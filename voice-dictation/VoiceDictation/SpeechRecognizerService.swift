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
    private var audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var sessionGeneration: UInt64 = 0

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
        let generation = beginNewSession(notifyPrevious: true)
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
            finish(with: .failure(SpeechRecognizerError.couldNotCreateRequest), generation: generation)
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

        do {
            try beginInputTap(bufferSize: 1024, appendToRecognizer: true)
        } catch {
            rebuildEngine()
            finish(with: .failure(SpeechRecognizerError.audioEngineStartFailed(error)), generation: generation)
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            guard self.isCurrentSession(generation) else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finish(with: .success(text), generation: generation)
                    return
                }
                self.stateQueue.sync { self._lastPartialText = text }
                DispatchQueue.main.async {
                    self.onPartialResult?(text)
                }
            }

            if let error = error {
                self.handleRecognitionError(error, generation: generation)
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
            let generation = self.stateQueue.sync { self.sessionGeneration }
            let shouldFinish = self.stateQueue.sync { !self._hasCompleted }
            if shouldFinish {
                self.finish(with: .success(self.lastPartialText), generation: generation)
            }
        }
    }

    func cancel() {
        _ = beginNewSession(notifyPrevious: true)
        rebuildEngine()
    }

    func resetSession() {
        _ = beginNewSession(notifyPrevious: false)
        rebuildEngine()
        configureRecognizer(localeIdentifier: localeIdentifier)
    }

    // MARK: - Private

    private func isCurrentSession(_ generation: UInt64) -> Bool {
        stateQueue.sync { sessionGeneration == generation }
    }

    @discardableResult
    private func beginNewSession(notifyPrevious: Bool) -> UInt64 {
        cancelRecognitionIfNeeded(notify: notifyPrevious)
        stopCaptureGraph()
        return stateQueue.sync { () -> UInt64 in
            sessionGeneration += 1
            return sessionGeneration
        }
    }

    private func rebuildEngine() {
        stopCaptureGraph()
        audioEngine = AVAudioEngine()
        tapInstalled = false
    }

    private func beginInputTap(bufferSize: AVAudioFrameCount, appendToRecognizer: Bool) throws {
        do {
            try ExceptionCatcher.run { errorPtr in
                if self.tapInstalled {
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.tapInstalled = false
                }
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
        var callback: ((Result<String, Error>) -> Void)?
        var shouldNotify = false
        stateQueue.sync {
            shouldNotify = notify && _isRunning && !_hasCompleted
            _hasCompleted = true
            _isRunning = false
            callback = _completion
            _completion = nil
        }
        let task = recognitionTask
        recognitionTask = nil
        recognitionRequest = nil
        task?.cancel()
        if shouldNotify, let callback {
            DispatchQueue.main.async {
                callback(.failure(SpeechRecognizerError.cancelled))
            }
        }
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

    private func finish(with result: Result<String, Error>, generation: UInt64) {
        let shouldProceed: Bool = stateQueue.sync {
            guard sessionGeneration == generation else { return false }
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

    private func handleRecognitionError(_ error: Error, generation: UInt64) {
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
            finish(with: .failure(SpeechRecognizerError.cancelled), generation: generation)
            return
        }

        let partial = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            logger.info("Recognition ended with error but partial text exists — using partial")
            finish(with: .success(partial), generation: generation)
            return
        }

        if isNoSpeechError(nsError) {
            logger.info("No speech detected (code \(nsError.code)) — treating as empty result")
            finish(with: .success(""), generation: generation)
            return
        }

        finish(with: .failure(SpeechRecognizerError.recognitionFailed(error)), generation: generation)
    }

    private func isNoSpeechError(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain" {
            return [1110, 1101, 1107, 203, 1700].contains(error.code)
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("no speech") || description.contains("no match")
    }
}
