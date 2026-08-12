//
//  HotkeyManager.swift
//  VoiceDictation
//
//  Registers a global hotkey (Option+Shift+Space) to toggle recording.
//  Uses the Carbon framework's RegisterEventHotKey API.
//

import Cocoa
import Carbon.HIToolbox

// Issue #29: Use a class-based box with a static singleton instead of a
// file-scope mutable variable. This is cleaner and more maintainable.
private final class HotkeyManagerBox {
    static let shared = HotkeyManagerBox()
    weak var manager: HotkeyManager?
    private init() {}
}

final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private static let hotkeyID: UInt32 = 1

    // Singleton so the Carbon callback can reach the shared AppState
    static let shared = HotkeyManager()

    private init() {}

    func registerHotkey() {
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]

        // Store self in the shared box so the C callback can reach us
        HotkeyManagerBox.shared.manager = self

        let handler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, _ in
            HotkeyManagerBox.shared.manager?.onHotkeyPressed()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            eventSpec,
            nil,
            &eventHandler
        )

        let modifiers: UInt32 = UInt32(optionKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_Space) // 49 = Space

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F4944) // "VOID"
        hotKeyID.id = HotkeyManager.hotkeyID

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        print("✅ Global hotkey registered: Option+Shift+Space")
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
    }

    private func onHotkeyPressed() {
        DispatchQueue.main.async {
            // Direct call to AppState — works regardless of which window is frontmost
            AppState.shared?.toggleRecording()
        }
    }
}

// Issue #29: Removed file-scope mutable variable — using HotkeyManagerBox
// singleton instead. Issue #37: Removed unused Notification.Name.toggleDictation.