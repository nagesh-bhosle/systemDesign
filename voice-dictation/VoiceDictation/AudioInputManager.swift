//
//  AudioInputManager.swift
//  VoiceDictation
//
//  Lists capture devices and applies a selected mic to an AVAudioInputNode
//  without changing the Mac's system-wide default input.
//

import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import CoreMedia
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

    static func applyToInputNode(uid: String, inputNode: AVAudioInputNode) {
        guard !uid.isEmpty else { return }
        guard let deviceID = coreAudioDeviceID(forUID: uid) else {
            logger.info("No Core Audio device for UID \(uid, privacy: .public)")
            return
        }
        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Input node has no audio unit yet")
            return
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            logger.warning("Could not set input device: \(status)")
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

    private static func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        coreAudioInputDevicesUnfiltered().first(where: { $0.uid == uid })?.deviceID
    }

    private static func coreAudioInputDevicesUnfiltered() -> [(uid: String, deviceID: AudioDeviceID)] {
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
            return (uid, id)
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

/// Level meter via AVCaptureSession so we never call AVAudioEngine.prepare().
final class MicrophoneTester: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.nagesh.voicedictation.mic-test")
    private var configured = false
    var onLevel: ((Float) -> Void)?

    func start(deviceUID: String?) throws {
        stop()

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.outputs.contains(output) {
            session.removeOutput(output)
        }

        let device: AVCaptureDevice
        if let deviceUID, !deviceUID.isEmpty, let match = AVCaptureDevice(uniqueID: deviceUID) {
            device = match
        } else if let fallback = AVCaptureDevice.default(for: .audio) {
            device = fallback
        } else {
            session.commitConfiguration()
            throw SpeechRecognizerError.invalidAudioFormat
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SpeechRecognizerError.microphoneBusy
        }
        session.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        configured = true

        queue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.outputs.contains(output) {
            session.removeOutput(output)
        }
        session.commitConfiguration()
        configured = false
        onLevel?(0)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let level = AudioLevel.rms(from: sampleBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
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

    static func rms(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, length > 1 else { return 0 }

        let asbd = CMSampleBufferGetFormatDescription(sampleBuffer)
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

        if let asbd, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = length / MemoryLayout<Float>.size
            return dataPointer.withMemoryRebound(to: Float.self, capacity: count) { ptr in
                normalizedRMS(samples: ptr, count: count, scale: 16)
            }
        }

        let count = length / MemoryLayout<Int16>.size
        return dataPointer.withMemoryRebound(to: Int16.self, capacity: count) { ptr in
            var sum: Float = 0
            for index in 0..<count {
                let sample = Float(ptr[index]) / Float(Int16.max)
                sum += sample * sample
            }
            return min(1, sqrt(sum / Float(max(count, 1))) * 16)
        }
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
