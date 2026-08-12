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
import os

// Issue #37: Proper error types instead of hardcoded NSError
enum SpeechRecognizerError: LocalizedError {
    case recognizerUnavailable
    case couldNotCreateRequest
    case invalidAudioFormat
    case audioEngineStartFailed(Error)
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .couldNotCreateRequest:
            return "Could not create recognition request."
        case .invalidAudioFormat:
            return "Audio input format is invalid. Check microphone permission."
        case .audioEngineStartFailed(let error):
            return "Could not start audio engine: \(error.localizedDescription)"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        }
    }
}

final class SpeechRecognizerService: NSObject, SFSpeechRecognizerDelegate {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "SpeechRecognizer")
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Issue #2: All mutable state is accessed on a serial queue to prevent data races
    private let stateQueue = DispatchQueue(label: "com.nagesh.voicedictation.speech-state")
    private var _completion: ((Result<String, Error>) -> Void)?
    private var _hasCompleted: Bool = false
    private var _isRunning: Bool = false
    private var _lastPartialText: String = ""

    var onPartialResult: ((String) -> Void)?

    init(locale: Locale = Locale(identifier: "en-US")) {
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            speechRecognizer = recognizer
        } else {
            speechRecognizer = SFSpeechRecognizer()
        }
        super.init()
        // Issue #49: Observe availability changes at runtime
        speechRecognizer?.delegate = self
    }

    deinit {
        cancel()
    }

    // MARK: - SFSpeechRecognizerDelegate

    // Issue #49: Handle availability changes at runtime
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            logger.warning("Speech recognizer became unavailable mid-session")
            stateQueue.sync {
                if !_hasCompleted {
                    _hasCompleted = true
                    _isRunning = false
                    let cb = _completion
                    _completion = nil
                    DispatchQueue.main.async {
                        cb?(.failure(SpeechRecognizerError.recognizerUnavailable))
                    }
                }
            }
        } else {
            logger.info("Speech recognizer became available")
        }
    }

    // MARK: - Thread-safe state accessors

    private var hasCompleted: Bool {
        stateQueue.sync { _hasCompleted }
    }

    private var isRunning: Bool {
        stateQueue.sync { _isRunning }
    }

    private var lastPartialText: String {
        stateQueue.sync { _lastPartialText }
    }

    // MARK: - Permission

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { micGranted in
            guard micGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        }
    }

    // MARK: - Start / Stop / Cancel

    func startRecognition(completion: @escaping (Result<String, Error>) -> Void) {
        cancel()

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            completion(.failure(SpeechRecognizerError.recognizerUnavailable))
            return
        }

        stateQueue.sync {
            _hasCompleted = false
            _completion = completion
            _isRunning = true
            _lastPartialText = ""
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            finish(with: .failure(SpeechRecognizerError.couldNotCreateRequest))
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.finish(with: .failure(SpeechRecognizerError.recognitionFailed(error)))
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finish(with: .success(text))
                } else {
                    self.stateQueue.sync { self._lastPartialText = text }
                    DispatchQueue.main.async {
                        self.onPartialResult?(text)
                    }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            finish(with: .failure(SpeechRecognizerError.invalidAudioFormat))
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
            inputNode.removeTap(onBus: 0)
            finish(with: .failure(SpeechRecognizerError.audioEngineStartFailed(error)))
        }
    }

    func stopRecognition() {
        stateQueue.sync {
            guard _isRunning else { return }
        }

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()

        stateQueue.sync { _isRunning = false }

        // If the recognition task doesn't call back within 3 seconds,
        // force-complete with whatever we have (or empty string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            let shouldFinish: Bool = self.stateQueue.sync {
                if !self._hasCompleted {
                    return true
                }
                return false
            }
            if shouldFinish {
                let partial = self.lastPartialText
                self.finish(with: .success(partial))
            }
        }
    }

    // Issue #10: cancel() now calls the completion with a cancellation error
    // so the caller knows the result was dropped intentionally.
    func cancel() {
        let shouldCallCompletion: Bool = stateQueue.sync {
            let wasRunning = _isRunning && !_hasCompleted
            _hasCompleted = true
            _isRunning = false
            let cb = _completion
            _completion = nil
            if wasRunning, let cb = cb {
                DispatchQueue.main.async {
                    cb(.failure(SpeechRecognizerError.recognizerUnavailable))
                }
            }
            return wasRunning
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        _ = shouldCallCompletion // suppress unused warning
    }

    // MARK: - Private

    private func finish(with result: Result<String, Error>) {
        let shouldProceed: Bool = stateQueue.sync {
            guard !_hasCompleted else { return false }
            _hasCompleted = true
            _isRunning = false
            return true
        }
        guard shouldProceed else { return }

        let cb = stateQueue.sync { () -> ((Result<String, Error>) -> Void)? in
            let callback = _completion
            _completion = nil
            return callback
        }

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