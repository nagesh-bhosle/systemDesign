//
//  PermissionHelper.swift
//  VoiceDictation
//
//  System Settings deep links and permission status checks.
//  Microphone status must use AVAudioApplication (same API as recording).
//  AVCaptureDevice.authorizationStatus(.audio) often stays .notDetermined on
//  macOS even when Microphone is already granted for this app.
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
            return "Optional — lets Voice Dictation paste text where your cursor is. Without it, text is copied to the clipboard. After a rebuild, you may need to toggle Voice Dictation off and on in Accessibility."
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
                ?? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
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
        if #available(macOS 14.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted {
                return true
            }
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func speechStatus() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var isMicrophoneDenied: Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .denied
        }
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

    /// Asks the same APIs the recorder uses. If TCC already granted this binary,
    /// the callbacks return true with no extra system dialog.
    static func probePermissions(completion: @escaping () -> Void) {
        requestMicrophone { _ in
            let speech = SFSpeechRecognizer.authorizationStatus()
            switch speech {
            case .authorized, .denied, .restricted:
                DispatchQueue.main.async { completion() }
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { _ in
                    DispatchQueue.main.async { completion() }
                }
            @unknown default:
                DispatchQueue.main.async { completion() }
            }
        }
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        if microphoneStatus() {
            DispatchQueue.main.async { completion(true) }
            return
        }
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    static func openSettings(for type: PermissionType) {
        if type == .accessibility {
            openAccessibilitySettings()
            return
        }
        if let url = type.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
