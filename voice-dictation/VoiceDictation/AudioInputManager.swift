//
//  AudioInputManager.swift
//  VoiceDictation
//
//  Lists Core Audio input devices, applies the selected mic, and runs a live level test.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os

struct AudioInputDevice: Identifiable, Hashable {
    let uid: String
    let deviceID: AudioDeviceID
    let name: String
    var id: String { uid }
}

enum AudioInputManager {
    private static let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AudioInput")

    static func inputDevices() -> [AudioInputDevice] {
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

        return ids.compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "Microphone \(id)"
            return AudioInputDevice(uid: uid, deviceID: id, name: name)
        }
    }

    static func defaultInputDevice() -> AudioInputDevice? {
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
        let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
        let name = stringProperty(deviceID, kAudioObjectPropertyName) ?? "Built-in Microphone"
        return AudioInputDevice(uid: uid, deviceID: deviceID, name: name)
    }

    static func apply(uid: String, to inputNode: AVAudioInputNode) {
        guard !uid.isEmpty else { return }
        guard let device = inputDevices().first(where: { $0.uid == uid }) else {
            logger.info("Preferred input UID not found: \(uid, privacy: .public)")
            return
        }
        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Input node has no audio unit yet")
            return
        }
        var id = device.deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            logger.warning("Could not set input device \(device.name, privacy: .public): \(status)")
        } else {
            logger.info("Using input: \(device.name, privacy: .public)")
        }
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
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
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

final class MicrophoneTester {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "MicTest")
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    var onLevel: ((Float) -> Void)?

    func start(deviceUID: String?) throws {
        stop()

        let input = engine.inputNode
        engine.prepare()
        if let deviceUID, !deviceUID.isEmpty {
            AudioInputManager.apply(uid: deviceUID, to: input)
        }

        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw SpeechRecognizerError.invalidAudioFormat
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.publishLevel(from: buffer)
        }
        tapInstalled = true
        try engine.start()
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        onLevel?(0)
    }

    private func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let level = min(1.0, rms * 18)
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }
}
