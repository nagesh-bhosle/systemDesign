//
//  AudioRecorder.swift
//  VoiceDictation
//
//  Records audio from the default microphone using AVAudioEngine.
//  Saves to a temporary WAV file for Whisper API transcription.
//

import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func startRecording() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dictation-\(Int(Date().timeIntervalSince1970)).wav"
        let fileURL = tempDir.appendingPathComponent(filename)
        recordingURL = fileURL

        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: inputFormat.settings
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("❌ Write error: \(error)")
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        print("🎙️ Recording started → \(fileURL.path)")
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil
        print("🛑 Recording stopped")

        if let url = recordingURL {
            completion(url)
        } else {
            completion(nil)
        }
    }
}