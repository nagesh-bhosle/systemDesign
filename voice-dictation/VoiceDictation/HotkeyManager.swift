//
//  HotkeyManager.swift
//  VoiceDictation
//
//  Registers a global hotkey (Option+Shift+Space) to toggle recording.
//  Uses the Carbon framework's RegisterEventHotKey API.
//

import Cocoa
import Carbon.HIToolbox

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

        // Store self in a global so the C callback can reach us
        HotkeyManagerCB.shared = self

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) in
                HotkeyManagerCB.shared?.onHotkeyPressed()
                return noErr
            },
            1,
            eventSpec,
            nil,
            &eventHandler
        )

        let modifiers: UInt32 = UInt32(optionKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_Space) // 49 = Space

        RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(id: HotkeyManager.hotkeyID, signature: OSType(0x564F4944)), // "VOID"
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
            RemoveEventHandler(GetApplicationEventTarget(), handler)
            eventHandler = nil
        }
    }

    private func onHotkeyPressed() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .toggleDictation, object: nil)
        }
    }
}

// Global holder for the Carbon callback (which is a C function pointer)
private var HotkeyManagerCB: HotkeyManagerBox = HotkeyManagerBox()

private final class HotkeyManagerBox {
    var shared: HotkeyManager?
}

extension Notification.Name {
    static let toggleDictation = Notification.Name("toggleDictation")
}