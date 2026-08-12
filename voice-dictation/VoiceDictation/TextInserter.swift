//
//  TextInserter.swift
//  VoiceDictation
//
//  Inserts transcribed text at the cursor position.
//  Strategy:
//    1. Copy text to clipboard.
//    2. Check accessibility permission (without prompting if already granted).
//    3. Simulate Cmd+V to paste at cursor.
//    4. Fallback: copy to clipboard + show notification.
//

import Cocoa
import ApplicationServices
import UserNotifications

final class TextInserter {
    static let shared = TextInserter()

    private init() {}

    func insertOrCopy(_ text: String) {
        // Copy text to clipboard — user pastes manually with Cmd+V
        copyToClipboardSync(text)
        showNotification(text)
        print("📋 Text copied to clipboard (\(text.count) chars)")
    }

    // MARK: - Clipboard

    private func copyToClipboardSync(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyToClipboard(_ text: String) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // MARK: - Accessibility Permission

    private func promptAccessibility() {
        // Only prompt if not already trusted
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Simulate Paste (Cmd+V)

    private func simulatePaste() -> Bool {
        let source = CGEventSource(stateID: CGEventSourceStateID.privateState)

        // Key events for Cmd+V
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)   // Cmd down
        cmdDown?.flags = CGEventFlags.maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)      // V down
        vDown?.flags = CGEventFlags.maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)       // V up
        vUp?.flags = CGEventFlags.maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)     // Cmd up

        // Post events
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
                content.body = "Text copied to clipboard. Press Cmd+V to paste.\n\"\(String(text.prefix(100)))\""
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