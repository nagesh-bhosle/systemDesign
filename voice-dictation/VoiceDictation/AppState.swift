//
//  AppState.swift
//  VoiceDictation
//
//  Central observable state for the app.
//  Flow: On-device speech recognition → Abacus LLM text cleanup → paste at cursor.
//

import Foundation
import SwiftUI
import Speech

enum DictationStatus: String {
    case idle = "Idle"
    case recording = "Listening"
    case transcribing = "Transcribing"
    case enhancing = "Enhancing"
    case error = "Error"
}

// Issue #30: Annotate with @MainActor so @Published properties are
// guaranteed to be updated on the main thread at compile time.
@MainActor
final class AppState: ObservableObject {
    @Published var status: DictationStatus = .idle
    @Published var lastTranscript: String = ""
    @Published var liveTranscript: String = ""
    @Published var errorMessage: String = ""
    @Published var apiKey: String = KeychainHelper.shared.loadAPIKey() ?? ""
    @Published var enhanceEnabled: Bool = true
    @Published var showFloatingWindow: Bool = true
    @Published var llmModel: String = UserDefaults.standard.string(forKey: "llmModel") ?? "gemini-3.5-flash-lite"
    @Published var llmEndpoint: String = UserDefaults.standard.string(forKey: "llmEndpoint") ?? "https://routellm.abacus.ai/v1/chat/completions"
    @Published var history: [TranscriptEntry] = TranscriptHistory.shared.loadHistory()

    func saveLLMModel(_ model: String) {
        llmModel = model
        UserDefaults.standard.set(model, forKey: "llmModel")
    }

    func saveLLMEndpoint(_ endpoint: String) {
        llmEndpoint = endpoint
        UserDefaults.standard.set(endpoint, forKey: "llmEndpoint")
    }

    static var shared: AppState?

    init() {
        // Set shared immediately so the hotkey callback (which fires before
        // MenuBarView.onAppear) can reach us.
        AppState.shared = self
    }

    // Issue #28: Track whether this is the "real" AppState to prevent
    // accidental overwrite from previews/tests.
    private var isPrimaryInstance = false

    static func createPrimary() -> AppState {
        let state = AppState()
        state.isPrimaryInstance = true
        AppState.shared = state
        return state
    }

    var statusIcon: String {
        switch status {
        case .idle:
            return "mic.fill"
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "waveform.circle.fill"
        case .enhancing:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    func toggleRecording() {
        switch status {
        case .idle, .error:
            startRecording()
        case .recording:
            stopRecording()
        case .transcribing:
            // Issue #13: Stuck in transcribing — force reset so user can record again.
            // cancel() marks hasCompleted=true so the pending 3s timeout in
            // SpeechRecognizerService won't fire a stale result.
            speechRecognizer.cancel()
            status = .idle
            errorMessage = ""
            liveTranscript = ""
        case .enhancing:
            // Stuck in enhancing — force reset
            llmTimedOut = true
            status = .idle
            errorMessage = ""
        }
    }

    private let speechRecognizer = SpeechRecognizerService()
    private let llmService = AbacusLLMService()
    private var rawTranscript: String = ""
    // Issue #5: llmTimedOut is now only accessed on the main thread (inside
    // DispatchQueue.main.async blocks), eliminating the data race.
    private var llmTimedOut: Bool = false
    // Issue #12: Track whether the transcription result has been processed
    // to prevent double-firing from the 3s and 5s timeouts.
    private var transcriptionProcessed: Bool = false

    private func startRecording() {
        errorMessage = ""
        liveTranscript = ""
        rawTranscript = ""
        transcriptionProcessed = false  // Issue #12: Reset for new session

        // Show floating window if not already visible
        if showFloatingWindow {
            FloatingWindowController.shared.showWindow(appState: self)
        }

        // Set status to recording immediately so UI reflects state
        status = .recording

        // Check speech recognition permission
        speechRecognizer.requestAuthorization { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard granted else {
                    self.status = .error
                    self.errorMessage = "Speech recognition permission denied. Grant it in System Settings → Privacy → Speech Recognition."
                    return
                }

                // Only proceed if we're still in recording state (user might have cancelled)
                guard self.status == .recording else { return }

                self.speechRecognizer.onPartialResult = { text in
                    DispatchQueue.main.async {
                        self.liveTranscript = text
                    }
                }

                self.speechRecognizer.startRecognition { result in
                    DispatchQueue.main.async {
                        // Issue #12: Skip if already processed (by timeout) or no longer in recording/transcribing state
                        guard !self.transcriptionProcessed else { return }
                        guard self.status == .transcribing || self.status == .recording else { return }

                        switch result {
                        case .success(let text):
                            self.transcriptionProcessed = true
                            self.rawTranscript = text
                            self.liveTranscript = ""
                            self.processTranscript(text)
                        case .failure(let error):
                            self.transcriptionProcessed = true
                            self.status = .error
                            self.errorMessage = "Recognition failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func stopRecording() {
        status = .transcribing
        liveTranscript = ""  // Clear the floating window text immediately
        speechRecognizer.stopRecognition()

        // Safety timeout: if recognition doesn't complete within 5 seconds,
        // reset to idle so user can try again.
        // Issue #12: Use transcriptionProcessed flag to avoid double-processing
        // with the 3s timeout in SpeechRecognizerService.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.status == .transcribing && !self.transcriptionProcessed {
                print("⚠️ Transcription timed out — resetting to idle")
                self.transcriptionProcessed = true
                self.speechRecognizer.cancel()
                self.status = .idle
                self.errorMessage = "No speech detected. Try again."
                self.liveTranscript = ""
            }
        }
    }

    private func processTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            status = .idle
            errorMessage = "No speech detected. Try again."
            liveTranscript = ""
            return
        }

        // If no API key or enhancement disabled, use raw transcript
        guard enhanceEnabled, !apiKey.isEmpty else {
            lastTranscript = trimmed
            TextInserter.shared.insertOrCopy(trimmed)
            // Issue #35: Save to history AFTER successful insertion
            saveToHistory(text: trimmed)
            status = .idle
            hideFloatingWindow()
            return
        }

        // Enhance text via Abacus LLM
        status = .enhancing
        llmTimedOut = false

        // Timeout: if LLM takes more than 12 seconds, use raw transcript
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self, self.status == .enhancing, !self.llmTimedOut else { return }
            print("⚠️ LLM enhancement timed out — using raw transcript")
            self.llmTimedOut = true
            self.lastTranscript = trimmed
            TextInserter.shared.insertOrCopy(trimmed)
            // Issue #35: Save to history AFTER successful insertion
            self.saveToHistory(text: trimmed)
            self.status = .idle
            self.hideFloatingWindow()
            self.errorMessage = "LLM cleanup timed out (used raw text)"
        }

        llmService.enhanceText(text: trimmed, apiKey: apiKey, endpoint: llmEndpoint, model: llmModel) { result in
            DispatchQueue.main.async {
                // Issue #5: llmTimedOut is now checked on the main thread,
                // eliminating the data race.
                guard !self.llmTimedOut else { return }

                switch result {
                case .success(let enhanced):
                    self.lastTranscript = enhanced
                    TextInserter.shared.insertOrCopy(enhanced)
                    // Issue #35: Save to history AFTER successful insertion
                    self.saveToHistory(text: enhanced)
                    self.status = .idle
                    self.hideFloatingWindow()
                case .failure(let error):
                    // Fallback: use raw transcript if LLM fails
                    print("⚠️ LLM enhancement failed: \(error.localizedDescription)")
                    self.lastTranscript = trimmed
                    TextInserter.shared.insertOrCopy(trimmed)
                    // Issue #35: Save to history AFTER successful insertion
                    self.saveToHistory(text: trimmed)
                    self.status = .idle
                    self.hideFloatingWindow()
                    self.errorMessage = "LLM cleanup failed (using raw text): \(error.localizedDescription)"
                }
            }
        }
    }

    // Issue #8: Actually hide the floating window after transcription completes.
    // The window will reappear on next recording start.
    private func hideFloatingWindow() {
        FloatingWindowController.shared.hideWindow()
    }

    private func saveToHistory(text: String) {
        let entry = TranscriptEntry(text: text, timestamp: Date())
        history.insert(entry, at: 0)
        if history.count > 100 {
            history.removeLast()
        }
        TranscriptHistory.shared.saveHistory(history)
    }
}