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

    private var hasPromptedAccessibility = false

    private init() {
        // Request notification authorization once at init (issue #15)
        requestNotificationAuthorization()
    }

    // MARK: - Public

    func insertOrCopy(_ text: String) {
        // Always copy to clipboard first as a safety net
        copyToClipboardSync(text)

        // Try to auto-paste if we have accessibility permission (issue #1)
        if AXIsProcessTrusted() {
            // Small delay to ensure clipboard is set before simulating paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if self?.simulatePaste() == true {
                    print("📋 Text pasted at cursor (\(text.count) chars)")
                } else {
                    self?.showNotification(text)
                    print("📋 Paste simulation failed — text copied to clipboard (\(text.count) chars)")
                }
            }
        } else {
            // No accessibility permission — prompt once, then fall back to notification
            if !hasPromptedAccessibility {
                promptAccessibility()
                hasPromptedAccessibility = true
            }
            showNotification(text)
            print("📋 Text copied to clipboard — grant Accessibility for auto-paste (\(text.count) chars)")
        }
    }

    // MARK: - Clipboard

    private func copyToClipboardSync(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Accessibility Permission

    private func promptAccessibility() {
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

    // Request authorization once at init instead of per-notification (issue #15)
    private func requestNotificationAuthorization() {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func showNotification(_ text: String) {
        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()
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