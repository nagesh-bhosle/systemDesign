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
    @Published var history: [TranscriptEntry] = TranscriptHistory.shared.loadHistory()

    static var shared: AppState?

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
        case .transcribing, .enhancing:
            break
        }
    }

    private let speechRecognizer = SpeechRecognizerService()
    private let llmService = AbacusLLMService()
    private var rawTranscript: String = ""
    private var llmTimedOut: Bool = false

    private func startRecording() {
        errorMessage = ""
        liveTranscript = ""

        // Show floating window if not already visible
        if showFloatingWindow {
            FloatingWindowController.shared.showWindow(appState: self)
        }

        // Check speech recognition permission
        speechRecognizer.requestAuthorization { [weak self] granted in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard granted else {
                    self.status = .error
                    self.errorMessage = "Speech recognition permission denied. Grant it in System Settings → Privacy → Speech Recognition."
                    return
                }

                self.speechRecognizer.onPartialResult = { text in
                    DispatchQueue.main.async {
                        self.liveTranscript = text
                    }
                }

                self.speechRecognizer.startRecognition { result in
                    DispatchQueue.main.async {
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
                self.status = .recording
            }
        }
    }

    private func stopRecording() {
        status = .transcribing
        speechRecognizer.stopRecognition()
    }

    private func processTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            status = .idle
            errorMessage = "No speech detected."
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
        
        llmService.enhanceText(text: trimmed, apiKey: apiKey) { result in
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