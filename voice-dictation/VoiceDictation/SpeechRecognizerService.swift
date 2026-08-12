//
//  SpeechRecognizerService.swift
//  VoiceDictation
//
//  On-device speech recognition using Apple's SFSpeechRecognizer.
//  No API key needed — works entirely on-device.
//

import Foundation
import Speech
import AVFoundation

final class SpeechRecognizerService {
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var completion: ((Result<String, Error>) -> Void)?
    private var hasCompleted: Bool = false
    private var isRunning: Bool = false
    private var lastPartialText: String = ""
    var onPartialResult: ((String) -> Void)?

    init(locale: Locale = Locale(identifier: "en-US")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func startRecognition(completion: @escaping (Result<String, Error>) -> Void) {
        // Cancel any existing task first
        cancel()

        // Reset state
        hasCompleted = false
        self.completion = completion
        isRunning = true
        lastPartialText = ""

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            finish(with: .failure(NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create recognition request"])))
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.finish(with: .failure(error))
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finish(with: .success(text))
                } else {
                    // Save partial text for timeout fallback
                    self.lastPartialText = text
                    // Partial result — update floating window
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                    }
                }
            }
        }

        // Set up audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // Clean up tap on failure
            inputNode.removeTap(onBus: 0)
            finish(with: .failure(error))
        }
    }

    func stopRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRunning = false

        // If the recognition task doesn't call back within 3 seconds,
        // force-complete with whatever we have (or empty string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            if !self.hasCompleted {
                self.finish(with: .success(self.lastPartialText))
            }
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        // Don't call finish here — cancel means we don't want the result
        hasCompleted = true
        completion = nil
    }

    // MARK: - Private

    private func finish(with result: Result<String, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        isRunning = false
        let cb = completion
        completion = nil
        // Clean up audio resources
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionTask = nil
        recognitionRequest = nil
        DispatchQueue.main.async {
            cb?(result)
        }
    }
}