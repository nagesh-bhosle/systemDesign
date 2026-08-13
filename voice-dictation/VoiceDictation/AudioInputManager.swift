//
//  AudioInputManager.swift
//  VoiceDictation
//
//  Lists input devices and the system default mic. Dictation never force-switches
//  the hardware device (that disconnects Bluetooth headsets).
//

import Foundation
import AVFoundation
import CoreAudio
import AppKit
import os

struct AudioInputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    var id: String { uid }
}

enum AudioInputManager {
    private static let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AudioInput")

    private static let excludedNameFragments = [
        "zoom", "teams", "webex", "discord", "slack", "aggregate",
        "multi-output", "soundflower", "blackhole", "loopback", "virtual"
    ]

    static func inputDevices() -> [AudioInputDevice] {
        let capture = captureDevices()
        if !capture.isEmpty {
            return capture
        }
        return coreAudioInputDevices()
    }

    static func defaultInputUID() -> String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
            ?? coreAudioDefaultUID()
    }

    static func openSoundSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - AVCapture listing

    private static func captureDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultUID = AVCaptureDevice.default(for: .audio)?.uniqueID
        return session.devices.compactMap { device in
            let name = device.localizedName
            if shouldExclude(name: name), device.uniqueID != defaultUID {
                return nil
            }
            return AudioInputDevice(uid: device.uniqueID, name: name)
        }
    }

    private static func shouldExclude(name: String) -> Bool {
        let lower = name.lowercased()
        return excludedNameFragments.contains { lower.contains($0) }
    }

    // MARK: - Core Audio fallback

    private static func coreAudioInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        let defaultUID = coreAudioDefaultUID()
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "Microphone \(id)"
            if shouldExclude(name: name), uid != defaultUID {
                return nil
            }
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    private static func coreAudioDefaultUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
    }

    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, raw) == noErr else {
            return 0
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfString)
        guard status == noErr, let cfString else { return nil }
        return cfString.takeUnretainedValue() as String
    }
}

/// Level meter using AVAudioRecorder on the system default input.
/// Does not steal Bluetooth headsets (no AVCaptureSession / no device switching).
final class MicrophoneTester {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?
    var onLevel: ((Float) -> Void)?
    private(set) var isActive = false

    func start() throws {
        stop()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedictation-mic-test-\(UUID().uuidString).caf")
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
        self.fileURL = url
        isActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0)
            let level = max(0, min(1, (db + 55) / 55))
            self.onLevel?(level)
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isActive = false
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        onLevel?(0)
    }
}

enum AudioLevel {
    static func rms(from buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        if let data = buffer.floatChannelData?[0] {
            return normalizedRMS(samples: data, count: frames, scale: 16)
        }
        if let data = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for index in 0..<frames {
                let sample = Float(data[index]) / Float(Int16.max)
                sum += sample * sample
            }
            return min(1, sqrt(sum / Float(frames)) * 16)
        }
        return 0
    }

    private static func normalizedRMS(samples: UnsafePointer<Float>, count: Int, scale: Float) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        return min(1, sqrt(sum / Float(count)) * scale)
    }
}
