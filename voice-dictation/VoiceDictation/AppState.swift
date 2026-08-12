//
//  AppState.swift
//  VoiceDictation
//
//  Central observable state for the app.
//

import Foundation
import SwiftUI

enum DictationStatus: String {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"
    case error = "Error"
}

final class AppState: ObservableObject {
    @Published var status: DictationStatus = .idle
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String = ""
    @Published var apiKey: String = KeychainHelper.shared.loadAPIKey() ?? ""

    var statusIcon: String {
        switch status {
        case .idle:
            return "mic.fill"
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "waveform.circle.fill"
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
            break
        }
    }

    private let recorder = AudioRecorder()
    private let whisper = WhisperService()

    private func startRecording() {
        errorMessage = ""
        do {
            try recorder.startRecording()
            status = .recording
        } catch {
            status = .error
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        status = .transcribing
        recorder.stopRecording { [weak self] audioURL in
            guard let self = self else { return }
            guard let url = audioURL else {
                DispatchQueue.main.async {
                    self.status = .error
                    self.errorMessage = "No audio captured."
                }
                return
            }

            // If no API key, copy raw audio path and show error
            guard !self.apiKey.isEmpty else {
                DispatchQueue.main.async {
                    self.status = .error
                    self.errorMessage = "No API key set. Open Settings to add your OpenAI API key."
                }
                return
            }

            self.whisper.transcribe(audioURL: url, apiKey: self.apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        self.lastTranscript = text
                        TextInserter.shared.insertOrCopy(text)
                        self.status = .idle
                    case .failure(let error):
                        self.status = .error
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}