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
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var completion: ((Result<String, Error>) -> Void)?
    private var hasCompleted: Bool = false
    private var isRunning: Bool = false
    private var lastPartialText: String = ""
    var onPartialResult: ((String) -> Void)?

    init(locale: Locale = Locale(identifier: "en-US")) {
        // Issue #3/#39: Don't force-unwrap — handle nil gracefully
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            speechRecognizer = recognizer
        } else {
            speechRecognizer = SFSpeechRecognizer()
        }
    }

    deinit {
        // Issue #14: Clean up resources on deallocation
        cancel()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        // Issue #10: Request microphone permission in addition to speech recognition
        AVAudioApplication.requestRecordPermission { micGranted in
            guard micGranted else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        }
    }

    func startRecognition(completion: @escaping (Result<String, Error>) -> Void) {
        // Cancel any existing task first
        cancel()

        // Issue #39: Check if speech recognizer is available
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            completion(.failure(NSError(
                domain: "SpeechRecognizer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available on this device."]
            )))
            return
        }

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

        // Issue #4: Validate format before installing tap — prevents crash when
        // microphone permission not yet granted or format is invalid
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            finish(with: .failure(NSError(
                domain: "SpeechRecognizer",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Audio input format is invalid. Check microphone permission."]
            )))
            return
        }

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
        // Issue #11: Guard against calling stop when engine was never started
        guard isRunning else { return }

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
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
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
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
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        recognitionTask = nil
        recognitionRequest = nil
        DispatchQueue.main.async {
            cb?(result)
        }
    }
}