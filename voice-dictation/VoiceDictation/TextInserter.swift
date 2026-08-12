//
//  TextInserter.swift
//  VoiceDictation
//
//  Inserts transcribed text at the cursor position.
//  Strategy:
//    1. Try Accessibility API (AXUIElement) to set value on focused text field.
//    2. Fallback: copy to clipboard + simulate Cmd+V paste.
//    3. Final fallback: copy to clipboard + show notification.
//

import Cocoa
import ApplicationServices
import UserNotifications

final class TextInserter {
    static let shared = TextInserter()

    private init() {}

    func insertOrCopy(_ text: String) {
        // Strategy 1: Try clipboard paste (most reliable across all apps)
        copyToClipboard(text)

        // Simulate Cmd+V to paste at cursor
        if simulatePaste() {
            print("✅ Text pasted via Cmd+V simulation")
            return
        }

        // Fallback: just copy to clipboard and notify
        print("📋 Text copied to clipboard (paste manually)")
        showNotification(text)
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ text: String) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // MARK: - Simulate Paste (Cmd+V)

    private func simulatePaste() -> Bool {
        // Check accessibility permission
        let trusted = AXIsProcessTrustedWithOptions(
            [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
        )

        guard trusted else {
            print("⚠️ Accessibility permission not granted")
            return false
        }

        let source = CGEventSource(stateID: CGEventSourceStateID.privateState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)  // Cmd
        cmdDown?.flags = CGEventFlags.maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)    // V
        vDown?.flags = CGEventFlags.maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = CGEventFlags.maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: CGEventTapLocation.cghidEventTap)
        vDown?.post(tap: CGEventTapLocation.cghidEventTap)
        vUp?.post(tap: CGEventTapLocation.cghidEventTap)
        cmdUp?.post(tap: CGEventTapLocation.cghidEventTap)

        return true
    }

    // MARK: - Notification

    private func showNotification(_ text: String) {
        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = "Voice Dictation"
                content.body = "Text copied to clipboard. Press Cmd+V to paste.\n\"\(String(text.prefix(100)))...\""
                let request = UNNotificationRequest(
                    identifier: "dictation-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
        }
    }
}