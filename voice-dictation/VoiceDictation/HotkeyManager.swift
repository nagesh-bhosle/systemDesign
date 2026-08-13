//
//  HotkeyManager.swift
//  VoiceDictation
//
//  Registers a global hotkey to toggle or push-to-talk record.
//

import Cocoa
import Carbon.HIToolbox
import os

enum HotkeyPreferences {
    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"
    static let pushToTalkKey = "pushToTalkEnabled"

    static let defaultKeyCode: UInt32 = UInt32(kVK_Space)
    static let defaultModifiers: UInt32 = UInt32(optionKey | shiftKey)

    static func loadKeyCode() -> UInt32 {
        guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else {
            return defaultKeyCode
        }
        return UInt32(UserDefaults.standard.integer(forKey: keyCodeKey))
    }

    static func loadModifiers() -> UInt32 {
        guard UserDefaults.standard.object(forKey: modifiersKey) != nil else {
            return defaultModifiers
        }
        return UInt32(UserDefaults.standard.integer(forKey: modifiersKey))
    }

    static func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey)
    }

    static func loadPushToTalk() -> Bool {
        UserDefaults.standard.bool(forKey: pushToTalkKey)
    }

    static func savePushToTalk(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: pushToTalkKey)
    }
}

enum HotkeyDisplay {
    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        let parts = modifierLabels(modifiers) + [keyLabel(keyCode)]
        return parts.joined(separator: " ")
    }

    static func modifierLabels(_ modifiers: UInt32) -> [String] {
        var labels: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { labels.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { labels.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { labels.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { labels.append("⇧") }
        return labels
    }

    static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_A...kVK_ANSI_Z:
            let letter = Character(UnicodeScalar(Int(keyCode) - kVK_ANSI_A + 65)!)
            return String(letter)
        case kVK_ANSI_0...kVK_ANSI_9:
            return String(Int(keyCode) - kVK_ANSI_0)
        default:
            return "Key \(keyCode)"
        }
    }
}

private final class HotkeyManagerBox {
    static let shared = HotkeyManagerBox()
    weak var manager: HotkeyManager?
    private init() {}
}

final class HotkeyManager {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "HotkeyManager")
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private static let hotkeyID: UInt32 = 1

    private(set) var keyCode: UInt32
    private(set) var modifiers: UInt32
    var pushToTalkEnabled: Bool

    static let shared = HotkeyManager()

    private init() {
        keyCode = HotkeyPreferences.loadKeyCode()
        modifiers = HotkeyPreferences.loadModifiers()
        pushToTalkEnabled = HotkeyPreferences.loadPushToTalk()
    }

    func updateConfiguration(keyCode: UInt32, modifiers: UInt32, pushToTalk: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.pushToTalkEnabled = pushToTalk
    }

    /// Attempt registration without installing a permanent handler (conflict check).
    static func canRegister(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4944)
        hotKeyID.id = 99

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            UnregisterEventHotKey(ref)
            return true
        }
        return false
    }

    @discardableResult
    func registerHotkey() -> Bool {
        unregisterHotkey()

        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        HotkeyManagerBox.shared.manager = self

        let handler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr, hotKeyID.id == HotkeyManager.hotkeyID else { return noErr }

            let kind = GetEventKind(event)
            if kind == UInt32(kEventHotKeyPressed) {
                HotkeyManagerBox.shared.manager?.onHotkeyPressed()
            } else if kind == UInt32(kEventHotKeyReleased) {
                HotkeyManagerBox.shared.manager?.onHotkeyReleased()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            2,
            eventSpec,
            nil,
            &eventHandler
        )

        guard installStatus == noErr else {
            logger.error("Failed to install event handler: \(installStatus)")
            return false
        }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4944)
        hotKeyID.id = HotkeyManager.hotkeyID

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard registerStatus == noErr else {
            logger.error("Failed to register hotkey: \(registerStatus)")
            if let handler = eventHandler {
                RemoveEventHandler(handler)
                eventHandler = nil
            }
            return false
        }

        logger.info("Global hotkey registered: \(HotkeyDisplay.label(keyCode: self.keyCode, modifiers: self.modifiers), privacy: .public)")
        return true
    }

    @discardableResult
    func reregister() -> Bool {
        keyCode = HotkeyPreferences.loadKeyCode()
        modifiers = HotkeyPreferences.loadModifiers()
        pushToTalkEnabled = HotkeyPreferences.loadPushToTalk()
        return registerHotkey()
    }

    func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        logger.info("Global hotkey unregistered")
    }

    private func onHotkeyPressed() {
        DispatchQueue.main.async {
            guard let appState = AppState.shared else { return }
            if self.pushToTalkEnabled {
                appState.handleHotkeyDown()
            } else {
                appState.toggleRecording()
            }
        }
    }

    private func onHotkeyReleased() {
        DispatchQueue.main.async {
            guard self.pushToTalkEnabled else { return }
            AppState.shared?.handleHotkeyUp()
        }
    }
}
