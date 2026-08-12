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
            // Stuck in transcribing — force reset so user can record again
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
    private var llmTimedOut: Bool = false

    private func startRecording() {
        errorMessage = ""
        liveTranscript = ""
        rawTranscript = ""

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
                        // Only process if we're still in transcribing/recording state
                        guard self.status == .transcribing || self.status == .recording else { return }

                        switch result {
                        case .success(let text):
                            self.rawTranscript = text
                            self.liveTranscript = ""
                            self.processTranscript(text)
                        case .failure(let error):
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
        // reset to idle so user can try again
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.status == .transcribing {
                print("⚠️ Transcription timed out — resetting to idle")
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
            saveToHistory(text: trimmed)
            TextInserter.shared.insertOrCopy(trimmed)
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
            self.saveToHistory(text: trimmed)
            TextInserter.shared.insertOrCopy(trimmed)
            self.status = .idle
            self.hideFloatingWindow()
            self.errorMessage = "LLM cleanup timed out (used raw text)"
        }
        
        llmService.enhanceText(text: trimmed, apiKey: apiKey, endpoint: llmEndpoint, model: llmModel) { result in
            DispatchQueue.main.async {
                // Skip if already timed out
                guard !self.llmTimedOut else { return }
                
                switch result {
                case .success(let enhanced):
                    self.lastTranscript = enhanced
                    self.saveToHistory(text: enhanced)
                    TextInserter.shared.insertOrCopy(enhanced)
                    self.status = .idle
                    self.hideFloatingWindow()
                case .failure(let error):
                    // Fallback: use raw transcript if LLM fails
                    print("⚠️ LLM enhancement failed: \(error.localizedDescription)")
                    self.lastTranscript = trimmed
                    self.saveToHistory(text: trimmed)
                    TextInserter.shared.insertOrCopy(trimmed)
                    self.status = .idle
                    self.hideFloatingWindow()
                    self.errorMessage = "LLM cleanup failed (using raw text): \(error.localizedDescription)"
                }
            }
        }
    }

    private func hideFloatingWindow() {
        // Window stays visible — user closes it via the X button
        // This is called after transcription completes; no auto-hide
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