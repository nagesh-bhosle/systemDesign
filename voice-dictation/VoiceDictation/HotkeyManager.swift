//
//  HotkeyManager.swift
//  VoiceDictation
//
//  Registers a global hotkey (Option+Shift+Space) to toggle recording.
//  Uses the Carbon framework's RegisterEventHotKey API.
//

import Cocoa
import Carbon.HIToolbox
import os

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

    static let shared = HotkeyManager()

    private init() {}

    // Issue #13: Return success/failure so callers can report errors
    @discardableResult
    func registerHotkey() -> Bool {
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        HotkeyManagerBox.shared.manager = self

        let handler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, _ in
            HotkeyManagerBox.shared.manager?.onHotkeyPressed()
            return noErr
        }

        // Issue #13: Check InstallEventHandler result
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            eventSpec,
            nil,
            &eventHandler
        )

        guard installStatus == noErr else {
            logger.error("Failed to install event handler: \(installStatus)")
            return false
        }

        let modifiers: UInt32 = UInt32(optionKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_Space) // 49 = Space

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4944) // "VOID"
        hotKeyID.id = HotkeyManager.hotkeyID

        // Issue #13: Check RegisterEventHotKey result
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard registerStatus == noErr else {
            logger.error("Failed to register hotkey: \(registerStatus) — possible conflict with another app")
            return false
        }

        logger.info("Global hotkey registered: Option+Shift+Space")
        return true
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
            AppState.shared?.toggleRecording()
        }
    }
}