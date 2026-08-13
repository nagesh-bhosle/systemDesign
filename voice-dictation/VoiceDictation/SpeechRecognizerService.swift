//
//  SpeechRecognizerService.swift
//  VoiceDictation
//
//  On-device speech recognition using Apple's SFSpeechRecognizer.
//

import Foundation
import Speech
import AVFoundation
import os

enum SpeechRecognizerError: LocalizedError {
    case recognizerUnavailable
    case couldNotCreateRequest
    case invalidAudioFormat
    case audioEngineStartFailed(Error)
    case recognitionFailed(Error)
    case cancelled
    case onDeviceUnavailable
    case microphoneBusy

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .couldNotCreateRequest:
            return "Could not create recognition request."
        case .invalidAudioFormat:
            return "Audio input format is invalid. Check microphone permission and the selected mic."
        case .audioEngineStartFailed(let error):
            return "Could not start the microphone: \(error.localizedDescription)"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        case .cancelled:
            return "Recognition was cancelled."
        case .onDeviceUnavailable:
            return "On-device speech recognition is not available. Using server-based recognition instead."
        case .microphoneBusy:
            return "The microphone is busy. Stop the mic test and try again."
        }
    }
}

final class SpeechRecognizerService: NSObject, SFSpeechRecognizerDelegate {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "SpeechRecognizer")
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false

    var preferredInputUID: String = ""

    private let stateQueue = DispatchQueue(label: "com.nagesh.voicedictation.speech-state")
    private var _completion: ((Result<String, Error>) -> Void)?
    private var _hasCompleted: Bool = false
    private var _isRunning: Bool = false
    private var _lastPartialText: String = ""

    private var localeIdentifier: String
    private var requiresOnDevice: Bool = true
    private(set) var onDeviceFallbackMessage: String?

    var onPartialResult: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    init(localeIdentifier: String = "en-US") {
        self.localeIdentifier = localeIdentifier
        super.init()
        configureRecognizer(localeIdentifier: localeIdentifier)
    }

    func updateConfiguration(localeIdentifier: String, requiresOnDevice: Bool) {
        self.localeIdentifier = localeIdentifier
        self.requiresOnDevice = requiresOnDevice
        configureRecognizer(localeIdentifier: localeIdentifier)
    }

    private func configureRecognizer(localeIdentifier: String) {
        let locale = Locale(identifier: localeIdentifier)
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            speechRecognizer = recognizer
        } else {
            speechRecognizer = SFSpeechRecognizer()
        }
        speechRecognizer?.delegate = self
    }

    deinit {
        cancel()
        stopCaptureGraph()
    }

    // MARK: - SFSpeechRecognizerDelegate

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

    private var lastPartialText: String {
        stateQueue.sync { _lastPartialText }
    }

    // MARK: - Permission

    func requestAuthorization(completion: @escaping (PermissionAuthResult) -> Void) {
        PermissionHelper.requestMicrophone { granted in
            guard granted else {
                completion(.microphoneDenied)
                return
            }
            self.requestSpeechAuthorization(completion: completion)
        }
    }

    private func requestSpeechAuthorization(completion: @escaping (PermissionAuthResult) -> Void) {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            DispatchQueue.main.async { completion(.granted) }
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized ? .granted : .speechDenied)
                }
            }
        default:
            DispatchQueue.main.async { completion(.speechDenied) }
        }
    }

    // MARK: - Start / Stop / Cancel

    func startRecognition(completion: @escaping (Result<String, Error>) -> Void) {
        cancelRecognitionIfNeeded(notify: true)
        stopCaptureGraph()
        onDeviceFallbackMessage = nil

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
        recognitionRequest.taskHint = .dictation
        recognitionRequest.addsPunctuation = true

        if requiresOnDevice {
            if speechRecognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            } else {
                logger.warning("On-device recognition not supported — falling back to server")
                onDeviceFallbackMessage = SpeechRecognizerError.onDeviceUnavailable.errorDescription
                recognitionRequest.requiresOnDeviceRecognition = false
            }
        } else {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        applyPreferredInputIfPossible()

        do {
            try beginInputTap(bufferSize: 1024, appendToRecognizer: true)
        } catch {
            stopCaptureGraph()
            finish(with: .failure(SpeechRecognizerError.audioEngineStartFailed(error)))
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finish(with: .success(text))
                    return
                }
                self.stateQueue.sync { self._lastPartialText = text }
                DispatchQueue.main.async {
                    self.onPartialResult?(text)
                }
            }

            if let error = error {
                self.handleRecognitionError(error)
            }
        }
    }

    func stopRecognition() {
        let running = stateQueue.sync { _isRunning }
        guard running else { return }

        recognitionRequest?.endAudio()
        stopCaptureGraph()
        stateQueue.sync { _isRunning = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let shouldFinish = self.stateQueue.sync { !self._hasCompleted }
            if shouldFinish {
                self.finish(with: .success(self.lastPartialText))
            }
        }
    }

    func cancel() {
        cancelRecognitionIfNeeded(notify: true)
        stopCaptureGraph()
    }

    func resetSession() {
        cancel()
    }

    // MARK: - Private

    private func applyPreferredInputIfPossible() {
        guard !preferredInputUID.isEmpty else { return }
        AudioInputManager.applyToInputNode(uid: preferredInputUID, inputNode: audioEngine.inputNode)
    }

    private func beginInputTap(bufferSize: AVAudioFrameCount, appendToRecognizer: Bool) throws {
        do {
            try ExceptionCatcher.run { errorPtr in
                if self.tapInstalled {
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.tapInstalled = false
                }
                self.applyPreferredInputIfPossible()
                self.audioEngine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
                    guard let self else { return }
                    if appendToRecognizer {
                        self.recognitionRequest?.append(buffer)
                    }
                    self.publishAudioLevel(from: buffer)
                }
                self.tapInstalled = true
                do {
                    try self.audioEngine.start()
                } catch {
                    errorPtr?.pointee = error as NSError
                }
            }
        } catch {
            stopCaptureGraph()
            throw error
        }

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate == 0 {
            stopCaptureGraph()
            throw SpeechRecognizerError.invalidAudioFormat
        }
    }

    private func cancelRecognitionIfNeeded(notify: Bool) {
        stateQueue.sync {
            let wasRunning = _isRunning && !_hasCompleted
            _hasCompleted = true
            _isRunning = false
            let cb = _completion
            _completion = nil
            if notify, wasRunning, let cb {
                DispatchQueue.main.async {
                    cb(.failure(SpeechRecognizerError.cancelled))
                }
            }
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    /// Stop the hardware graph without `reset()` or `prepare()`, which can abort.
    private func stopCaptureGraph() {
        do {
            try ExceptionCatcher.run { _ in
                if self.tapInstalled {
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                }
                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                }
            }
        } catch {
            logger.warning("Audio teardown: \(error.localizedDescription, privacy: .public)")
        }
        tapInstalled = false
    }

    private func publishAudioLevel(from buffer: AVAudioPCMBuffer) {
        let level = AudioLevel.rms(from: buffer)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(level)
        }
    }

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

        stopCaptureGraph()
        recognitionTask = nil
        recognitionRequest = nil

        DispatchQueue.main.async {
            cb?(result)
        }
    }

    private func handleRecognitionError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
            finish(with: .failure(SpeechRecognizerError.cancelled))
            return
        }

        let partial = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            logger.info("Recognition ended with error but partial text exists — using partial")
            finish(with: .success(partial))
            return
        }

        if isNoSpeechError(nsError) {
            logger.info("No speech detected (code \(nsError.code)) — treating as empty result")
            finish(with: .success(""))
            return
        }

        finish(with: .failure(SpeechRecognizerError.recognitionFailed(error)))
    }

    private func isNoSpeechError(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain" {
            return [1110, 1101, 1107, 203, 1700].contains(error.code)
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("no speech") || description.contains("no match")
    }
}
