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
import os

enum DictationStatus: String {
    case idle = "Idle"
    case recording = "Listening"
    case transcribing = "Transcribing"
    case enhancing = "Enhancing"
    case error = "Error"
}

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AppState")

    @Published var status: DictationStatus = .idle
    @Published var lastTranscript: String = ""
    @Published var liveTranscript: String = ""
    @Published var errorMessage: String = ""
    @Published var apiKey: String = KeychainHelper.shared.loadAPIKey() ?? ""
    @Published var enhanceEnabled: Bool = false  // Issue #19: Default false when no key
    @Published var showFloatingWindow: Bool = true
    @Published var llmModel: String = UserDefaults.standard.string(forKey: "llmModel") ?? "meta-llama/Meta-Llama-3.1-8B-Instruct"  // Issue #16: Cheaper default
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

    // Issue #7: Only set shared in createPrimary, not in init
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
            speechRecognizer.cancel()
            status = .idle
            errorMessage = ""
            liveTranscript = ""
        case .enhancing:
            // Issue #5: Cancel in-flight LLM request
            llmService.cancel()
            llmTimedOut = true
            status = .idle
            errorMessage = ""
        }
    }

    // Issue #34: Dependencies are created with default implementations but can be injected for testing
    private let speechRecognizer: SpeechRecognizerService
    private let llmService: AbacusLLMService
    private var rawTranscript: String = ""

    // Issue #1: These flags are on a @MainActor class, so they are only
    // accessed on the main thread. Annotated for clarity.
    @MainActor private var llmTimedOut: Bool = false
    @MainActor private var transcriptionProcessed: Bool = false

    // Issue #34: Injectable init for testing
    init(speechRecognizer: SpeechRecognizerService = SpeechRecognizerService(),
         llmService: AbacusLLMService = AbacusLLMService()) {
        self.speechRecognizer = speechRecognizer
        self.llmService = llmService
    }

    // Issue #4: Guard against race condition between permission callback and hotkey toggle
    private var isStartingRecording: Bool = false

    private func startRecording() {
        // Issue #4: Prevent double-start if already starting
        guard !isStartingRecording else { return }
        isStartingRecording = true

        errorMessage = ""
        liveTranscript = ""
        rawTranscript = ""
        transcriptionProcessed = false

        if showFloatingWindow {
            FloatingWindowController.shared.showWindow(appState: self)
        }

        status = .recording

        speechRecognizer.requestAuthorization { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isStartingRecording = false

                guard granted else {
                    self.status = .error
                    self.errorMessage = "Speech recognition permission denied. Grant it in System Settings → Privacy → Speech Recognition."
                    return
                }

                // Issue #4: Only proceed if we're still in recording state
                // (user might have toggled while permission callback was pending)
                guard self.status == .recording else { return }

                self.speechRecognizer.onPartialResult = { text in
                    DispatchQueue.main.async {
                        self.liveTranscript = text
                    }
                }

                self.speechRecognizer.startRecognition { result in
                    DispatchQueue.main.async {
                        guard !self.transcriptionProcessed else { return }
                        guard self.status == .transcribing || self.status == .recording else { return }

                        switch result {
                        case .success(let text):
                            self.transcriptionProcessed = true
                            self.rawTranscript = text
                            self.liveTranscript = ""
                            self.processTranscript(text)
                        case .failure(let error):
                            // Issue #10: cancel() now calls back with an error —
                            // if we already reset via toggleRecording, ignore it
                            self.transcriptionProcessed = true
                            if self.status == .idle { return }
                            self.status = .error
                            self.errorMessage = "Recognition failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func stopRecording() {
        // Issue #4: If we're still waiting for permission (isStartingRecording),
        // reset to idle instead of going to transcribing
        if isStartingRecording {
            isStartingRecording = false
            status = .idle
            liveTranscript = ""
            return
        }

        status = .transcribing
        liveTranscript = ""
        speechRecognizer.stopRecognition()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.status == .transcribing && !self.transcriptionProcessed {
                self.logger.warning("Transcription timed out — resetting to idle")
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

        guard enhanceEnabled, !apiKey.isEmpty else {
            lastTranscript = trimmed
            // Issue #6: saveToHistory is called in the completion handler
            // after paste completes, not before
            TextInserter.shared.insertOrCopy(trimmed) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.saveToHistory(text: trimmed)
                }
            }
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
            self.logger.warning("LLM enhancement timed out — using raw transcript")
            self.llmTimedOut = true
            // Issue #5: Cancel the in-flight request
            self.llmService.cancel()
            self.lastTranscript = trimmed
            TextInserter.shared.insertOrCopy(trimmed) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.saveToHistory(text: trimmed)
                }
            }
            self.status = .idle
            self.hideFloatingWindow()
            self.errorMessage = "LLM cleanup timed out (used raw text)"
        }

        llmService.enhanceText(text: trimmed, apiKey: apiKey, endpoint: llmEndpoint, model: llmModel) { result in
            DispatchQueue.main.async {
                guard !self.llmTimedOut else { return }

                switch result {
                case .success(let enhanced):
                    self.lastTranscript = enhanced
                    // Issue #6: Save to history AFTER paste completes
                    TextInserter.shared.insertOrCopy(enhanced) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.saveToHistory(text: enhanced)
                        }
                    }
                    self.status = .idle
                    self.hideFloatingWindow()
                case .failure(let error):
                    // Issue #5: If cancelled by user, don't show error
                    if case AbacusLLMError.requestCancelled = error {
                        return
                    }
                    self.logger.warning("LLM enhancement failed: \(error.localizedDescription)")
                    self.lastTranscript = trimmed
                    TextInserter.shared.insertOrCopy(trimmed) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.saveToHistory(text: trimmed)
                        }
                    }
                    self.status = .idle
                    self.hideFloatingWindow()
                    self.errorMessage = "LLM cleanup failed (using raw text): \(error.localizedDescription)"
                }
            }
        }
    }

    private func hideFloatingWindow() {
        FloatingWindowController.shared.hideWindow()
    }

    // Issue #28: Deduplicate history entries
    private func saveToHistory(text: String) {
        // Don't save if identical to most recent entry
        if let first = history.first, first.text == text {
            return
        }
        let entry = TranscriptEntry(text: text, timestamp: Date())
        history.insert(entry, at: 0)
        if history.count > 100 {
            history.removeLast()
        }
        TranscriptHistory.shared.saveHistory(history)
    }
}