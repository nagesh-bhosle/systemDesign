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
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completion(.failure(NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create recognition request"])))
            return
        }
        recognitionRequest.shouldReportPartialResults = false

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let result = result, result.isFinal {
                let text = result.bestTranscription.formattedString
                completion(.success(text))
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
            completion(.failure(error))
        }
    }

    func stopRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}