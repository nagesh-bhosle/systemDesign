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
        case .cancelled:
            return "Recognition was cancelled."
        case .onDeviceUnavailable:
            return "On-device speech recognition is not available. Using server-based recognition instead."
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
    /// Soft gain so quiet laptop mics still reach the recognizer. Clipped to [-1, 1].
    private let inputGain: Float = 4.0

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
        cancel()
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

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

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

        let inputNode = audioEngine.inputNode
        audioEngine.prepare()
        if !preferredInputUID.isEmpty {
            AudioInputManager.apply(uid: preferredInputUID, to: inputNode)
        }
        enableVoiceProcessingIfPossible(on: inputNode)

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            teardownEngine()
            finish(with: .failure(SpeechRecognizerError.invalidAudioFormat))
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let boosted = self.boostedBuffer(buffer, gain: self.inputGain)
            self.recognitionRequest?.append(boosted)
            self.publishAudioLevel(from: boosted)
        }
        tapInstalled = true

        do {
            try audioEngine.start()
        } catch {
            teardownEngine()
            finish(with: .failure(SpeechRecognizerError.audioEngineStartFailed(error)))
        }
    }

    func stopRecognition() {
        stateQueue.sync {
            guard _isRunning else { return }
        }

        recognitionRequest?.endAudio()
        teardownEngine()

        stateQueue.sync { _isRunning = false }

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

    func cancel() {
        stateQueue.sync {
            let wasRunning = _isRunning && !_hasCompleted
            _hasCompleted = true
            _isRunning = false
            let cb = _completion
            _completion = nil
            if wasRunning, let cb = cb {
                DispatchQueue.main.async {
                    cb(.failure(SpeechRecognizerError.cancelled))
                }
            }
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        teardownEngine()
    }

    /// Tear down the audio graph so the next recording can start even after a failed session.
    func resetSession() {
        cancel()
        teardownEngine()
    }

    // MARK: - Private

    private func publishAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let level = min(1.0, rms * 8)
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

        teardownEngine()
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
            // 1110 no speech, 203 retry/timeout, 1101/1107 recognition failure with silence
            return [1110, 1101, 1107, 203, 1700].contains(error.code)
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("no speech") || description.contains("no match")
    }

    private func teardownEngine() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
    }

    private func enableVoiceProcessingIfPossible(on inputNode: AVAudioInputNode) {
        do {
            if !inputNode.isVoiceProcessingEnabled {
                try inputNode.setVoiceProcessingEnabled(true)
            }
        } catch {
            logger.info("Voice processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func boostedBuffer(_ buffer: AVAudioPCMBuffer, gain: Float) -> AVAudioPCMBuffer {
        guard gain != 1, buffer.format.commonFormat == .pcmFormatFloat32 else { return buffer }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return buffer
        }
        copy.frameLength = buffer.frameLength
        guard let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return buffer }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        for channel in 0..<channels {
            for frame in 0..<frames {
                dst[channel][frame] = max(-1, min(1, src[channel][frame] * gain))
            }
        }
        return copy
    }
}
