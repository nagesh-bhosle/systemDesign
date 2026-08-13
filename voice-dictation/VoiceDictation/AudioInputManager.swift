//
//  AudioInputManager.swift
//  VoiceDictation
//
//  Lists Core Audio input devices and selects the system default input.
//  Dictation and the mic test share one AVAudioEngine in SpeechRecognizerService.
//

import Foundation
import CoreAudio
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

    /// Sets the Mac's default input so AVAudioEngine picks up the chosen mic.
    @discardableResult
    static func setDefaultInput(uid: String) -> Bool {
        guard !uid.isEmpty else { return false }
        guard let device = inputDevices().first(where: { $0.uid == uid }) else {
            logger.info("Preferred input UID not found: \(uid, privacy: .public)")
            return false
        }
        var id = device.deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        if status != noErr {
            logger.warning("Could not set default input \(device.name, privacy: .public): \(status)")
            return false
        }
        logger.info("Default input: \(device.name, privacy: .public)")
        return true
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
