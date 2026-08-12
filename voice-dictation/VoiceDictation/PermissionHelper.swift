//
//  PermissionHelper.swift
//  VoiceDictation
//
//  System Settings deep links and permission status checks.
//

import AppKit
import AVFoundation
import ApplicationServices
import Speech

enum PermissionType: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .accessibility: return "Accessibility"
        }
    }

    var description: String {
        switch self {
        case .microphone:
            return "Required to hear your voice."
        case .speechRecognition:
            return "Required to convert speech to text on your Mac."
        case .accessibility:
            return "Optional — lets Voice Dictation paste text where your cursor is. Without it, text is copied to the clipboard."
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

enum PermissionAuthResult {
    case granted
    case microphoneDenied
    case speechDenied

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .granted:
            return nil
        case .microphoneDenied:
            return "Microphone access denied. Open System Settings → Privacy & Security → Microphone and enable Voice Dictation."
        case .speechDenied:
            return "Speech recognition denied. Open System Settings → Privacy & Security → Speech Recognition and enable Voice Dictation."
        }
    }
}

enum PermissionHelper {
    static func microphoneStatus() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func speechStatus() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var isMicrophoneDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    static var isSpeechDenied: Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return true
        default: return false
        }
    }

    static func accessibilityStatus() -> Bool {
        AXIsProcessTrusted()
    }

    static func isGranted(_ type: PermissionType) -> Bool {
        switch type {
        case .microphone: return microphoneStatus()
        case .speechRecognition: return speechStatus()
        case .accessibility: return accessibilityStatus()
        }
    }

    static func openSettings(for type: PermissionType) {
        if let url = type.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
