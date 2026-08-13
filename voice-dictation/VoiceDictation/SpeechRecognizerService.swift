//
//  SpeechRecognizerService.swift
//  VoiceDictation
//
//  Records with AVAudioRecorder (same path as the working mic test) so Bluetooth
//  headsets stay connected, then transcribes the file with SFSpeechRecognizer.
//  AVAudioEngine input is not used: it switches BT headsets into HFP and goes silent.
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
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
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
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            logger.warning("Speech recognizer became unavailable mid-session")
            let generation = stateQueue.sync { sessionGeneration }
            finish(with: .failure(SpeechRecognizerError.recognizerUnavailable), generation: generation)
        }
    }

    private var lastPartialText: String {
        stateQueue.sync { _lastPartialText }
    }

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
        _ = speechRecognizer

        stateQueue.sync {
            _hasCompleted = false
            _completion = completion
            _isRunning = true
            _lastPartialText = ""
        }

        do {
            try startRecorder()
        } catch {
            finish(with: .failure(SpeechRecognizerError.audioEngineStartFailed(error)), generation: generation)
        }
    }

    func stopRecognition() {
        let running = stateQueue.sync { _isRunning }
        guard running else { return }

        let generation = stateQueue.sync { sessionGeneration }
        stopRecorderKeepingFile()
        stateQueue.sync { _isRunning = false }
        transcribeRecordingFile(generation: generation)
    }

    func cancel() {
        _ = beginNewSession(notifyPrevious: true)
        deleteRecordingFile()
    }

    func resetSession() {
        _ = beginNewSession(notifyPrevious: false)
        deleteRecordingFile()
        configureRecognizer(localeIdentifier: localeIdentifier)
    }

    // MARK: - Recorder (headset-safe)

    private func startRecorder() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedictation-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw SpeechRecognizerError.microphoneBusy
        }
        self.recorder = recorder
        self.recordingURL = url
        startMetering()
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0)
            let level = max(0, min(1, (db + 55) / 55))
            self.onAudioLevel?(level)
        }
        if let meterTimer {
            RunLoop.main.add(meterTimer, forMode: .common)
        }
    }

    private func stopRecorderKeepingFile() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(0)
        }
    }

    private func deleteRecordingFile() {
        stopRecorderKeepingFile()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func transcribeRecordingFile(generation: UInt64) {
        guard isCurrentSession(generation) else { return }
        guard let speechRecognizer, let url = recordingURL else {
            finish(with: .success(""), generation: generation)
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if fileSize < 2000 {
            logger.info("Recording too small (\(fileSize) bytes) — treating as no speech")
            finish(with: .success(""), generation: generation)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        if requiresOnDevice {
            if speechRecognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            } else {
                onDeviceFallbackMessage = SpeechRecognizerError.onDeviceUnavailable.errorDescription
                request.requiresOnDeviceRecognition = false
            }
        } else {
            request.requiresOnDeviceRecognition = false
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            let shouldFinish = self.stateQueue.sync { !self._hasCompleted && self.sessionGeneration == generation }
            if shouldFinish {
                self.finish(with: .success(self.lastPartialText), generation: generation)
            }
        }
    }

    // MARK: - Session

    private func isCurrentSession(_ generation: UInt64) -> Bool {
        stateQueue.sync { sessionGeneration == generation }
    }

    @discardableResult
    private func beginNewSession(notifyPrevious: Bool) -> UInt64 {
        cancelRecognitionIfNeeded(notify: notifyPrevious)
        stopRecorderKeepingFile()
        return stateQueue.sync { () -> UInt64 in
            sessionGeneration += 1
            return sessionGeneration
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
        task?.cancel()
        if shouldNotify, let callback {
            DispatchQueue.main.async {
                callback(.failure(SpeechRecognizerError.cancelled))
            }
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

        recognitionTask = nil
        stopRecorderKeepingFile()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil

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
            finish(with: .success(partial), generation: generation)
            return
        }

        if isNoSpeechError(nsError) {
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
