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
    private var recordingStartedAt: Date?
    private(set) var lastRecordingDuration: TimeInterval = 0
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
        TempRecordingCleanup.purgeOrphanedFiles()
    }

    /// Apple's Speech framework drops tasks around one minute of audio, and
    /// long URL requests often report only the latest utterance. Short chunks
    /// plus overlap keep minutes of speech instead of the last line.
    private static let sttChunkSeconds: TimeInterval = 20
    private static let sttChunkOverlapSeconds: TimeInterval = 2
    private static let sttSecondsPerChunk: TimeInterval = 40

    /// Seconds to wait for URL transcription across all chunks.
    func recommendedTranscribeTimeout() -> TimeInterval {
        let step = max(1, Self.sttChunkSeconds - Self.sttChunkOverlapSeconds)
        let chunks = max(1, ceil(lastRecordingDuration / step))
        return min(900, chunks * Self.sttSecondsPerChunk + 20)
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

    /// Full joined transcript so far (never the current chunk alone).
    var currentTranscript: String {
        lastPartialText
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
        self.recordingStartedAt = Date()
        self.lastRecordingDuration = 0
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
        if let recorder {
            lastRecordingDuration = max(recorder.currentTime, 0)
            recorder.stop()
        } else if let recordingStartedAt {
            lastRecordingDuration = max(Date().timeIntervalSince(recordingStartedAt), 0)
        }
        recordingStartedAt = nil
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
        _ = speechRecognizer

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let headerOnly = fileSize < 256
        let accidentalClick = lastRecordingDuration > 0 && lastRecordingDuration < 0.08 && fileSize < 512
        if headerOnly || accidentalClick {
            logger.info("Recording empty (size=\(fileSize) duration=\(self.lastRecordingDuration)s) — treating as no speech")
            finish(with: .success(""), generation: generation)
            return
        }

        let chunks: [URL]
        do {
            chunks = try audioChunks(
                from: url,
                chunkSeconds: Self.sttChunkSeconds,
                overlapSeconds: Self.sttChunkOverlapSeconds
            )
        } catch {
            logger.warning("Could not split recording, transcribing whole file: \(error.localizedDescription, privacy: .public)")
            chunks = [url]
        }

        logger.info("Transcribing \(chunks.count, privacy: .public) chunk(s) for \(self.lastRecordingDuration, privacy: .public)s recording")
        transcribeChunks(
            chunks,
            index: 0,
            accumulated: "",
            generation: generation,
            originalsToDelete: chunks.filter { $0 != url }
        )
    }

    private func transcribeChunks(
        _ chunks: [URL],
        index: Int,
        accumulated: String,
        generation: UInt64,
        originalsToDelete: [URL]
    ) {
        guard isCurrentSession(generation) else {
            originalsToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
            return
        }

        if index >= chunks.count {
            originalsToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
            finish(with: .success(accumulated.trimmingCharacters(in: .whitespacesAndNewlines)), generation: generation)
            return
        }

        transcribeOneChunk(url: chunks[index], priorAccumulated: accumulated, generation: generation) { [weak self] chunkText in
            guard let self else { return }
            let next = Self.mergeGrowingTranscript(accumulated, chunkText)
            self.publishPartial(next)
            self.logger.info("Chunk \(index + 1)/\(chunks.count) joined to \(next.count, privacy: .public) chars")
            self.transcribeChunks(
                chunks,
                index: index + 1,
                accumulated: next,
                generation: generation,
                originalsToDelete: originalsToDelete
            )
        }
    }

    private func publishPartial(_ text: String) {
        stateQueue.sync { _lastPartialText = text }
        DispatchQueue.main.async { [weak self] in
            self?.onPartialResult?(text)
        }
    }

    /// Join chunk results and stitch Apple's rolling last-utterance window.
    private static func mergeGrowingTranscript(_ previous: String, _ incoming: String) -> String {
        let a = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if b == a { return a }
        if b.hasPrefix(a) { return b }
        if a.hasPrefix(b) { return a }
        if b.contains(a) { return b }
        if a.contains(b) { return a }
        if let stitched = stitchOverlap(a, b) { return stitched }
        return a + " " + b
    }

    private static func stitchOverlap(_ left: String, _ right: String) -> String? {
        let leftWords = left.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let rightWords = right.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let maxN = min(leftWords.count, rightWords.count)
        guard maxN > 0 else { return nil }
        for n in stride(from: maxN, through: 1, by: -1) {
            if leftWords.suffix(n) == rightWords.prefix(n) {
                return (leftWords + rightWords.dropFirst(n)).joined(separator: " ")
            }
        }
        return nil
    }

    private static func textFromTranscription(_ transcription: SFTranscription) -> String {
        let formatted = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        if transcription.segments.isEmpty { return formatted }
        let fromSegments = transcription.segments
            .map(\.substring)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fromSegments.count > formatted.count ? fromSegments : formatted
    }

    private func transcribeOneChunk(
        url: URL,
        priorAccumulated: String,
        generation: UInt64,
        completion: @escaping (String) -> Void
    ) {
        guard isCurrentSession(generation), let speechRecognizer else {
            completion("")
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

        var chunkMerged = ""
        var chunkFinished = false
        let finishChunk: (String) -> Void = { text in
            guard !chunkFinished else { return }
            chunkFinished = true
            completion(text)
        }

        let absorb: (String) -> Void = { [weak self] incoming in
            guard let self else { return }
            chunkMerged = Self.mergeGrowingTranscript(chunkMerged, incoming)
            self.publishPartial(Self.mergeGrowingTranscript(priorAccumulated, chunkMerged))
        }

        recognitionTask?.cancel()
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard self.isCurrentSession(generation) else { return }

            if let result = result {
                absorb(Self.textFromTranscription(result.bestTranscription))
                if result.isFinal {
                    finishChunk(chunkMerged)
                    return
                }
            }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    finishChunk(chunkMerged)
                    return
                }
                if !chunkMerged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finishChunk(chunkMerged)
                    return
                }
                if self.isNoSpeechError(nsError) {
                    finishChunk("")
                    return
                }
                self.logger.warning("Chunk transcription error: \(error.localizedDescription, privacy: .public)")
                finishChunk(chunkMerged)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sttSecondsPerChunk) { [weak self] in
            guard let self, !chunkFinished else { return }
            guard self.isCurrentSession(generation) else { return }
            self.logger.warning("Chunk transcription timed out — keeping \(chunkMerged.count, privacy: .public) merged chars")
            self.recognitionTask?.cancel()
            finishChunk(chunkMerged)
        }
    }

    /// Split a linear PCM recording into overlapping pieces under Apple's STT limit.
    private func audioChunks(from url: URL, chunkSeconds: TimeInterval, overlapSeconds: TimeInterval) throws -> [URL] {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let totalFrames = input.length
        let framesPerChunk = AVAudioFrameCount(max(1, format.sampleRate * chunkSeconds))
        let overlapFrames = AVAudioFramePosition(max(0, format.sampleRate * overlapSeconds))
        let stepFrames = max(1, AVAudioFramePosition(framesPerChunk) - overlapFrames)
        if totalFrames <= AVAudioFramePosition(framesPerChunk) {
            return [url]
        }

        var urls: [URL] = []
        var start: AVAudioFramePosition = 0
        var index = 0
        while start < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - start)
            let count = min(framesPerChunk, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
            input.framePosition = start
            try input.read(into: buffer, frameCount: count)
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voicedictation-chunk-\(UUID().uuidString)-\(index).caf")
            let output = try AVAudioFile(
                forWriting: chunkURL,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            )
            try output.write(from: buffer)
            urls.append(chunkURL)
            if remaining <= framesPerChunk { break }
            start += stepFrames
            index += 1
        }
        return urls.isEmpty ? [url] : urls
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
