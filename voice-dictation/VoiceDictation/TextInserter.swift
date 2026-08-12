//
//  TextInserter.swift
//  VoiceDictation
//
//  Inserts transcribed text at the cursor position.
//  Strategy:
//    1. Save existing clipboard contents.
//    2. Copy text to clipboard.
//    3. Check accessibility permission (without prompting if already granted).
//    4. Simulate Cmd+V to paste at cursor.
//    5. Restore previous clipboard contents after a short delay.
//    6. Fallback: keep text on clipboard + show notification.
//

import Cocoa
import ApplicationServices
import UserNotifications
import os

final class TextInserter {
    static let shared = TextInserter()

    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TextInserter")

    private let hasPromptedAccessibilityKey = "hasPromptedAccessibility"

    private init() {
        requestNotificationAuthorization()
    }

    // MARK: - Public

    /// Inserts text at cursor or copies to clipboard as fallback.
    /// Calls `completion` on the main thread with `true` if paste succeeded,
    /// `false` if only clipboard fallback was used.
    func insertOrCopy(_ text: String, completion: ((Bool) -> Void)? = nil) {
        // Save existing clipboard contents so we can restore after paste
        let previousClipboard = saveClipboardContents()

        copyToClipboardSync(text)

        if AXIsProcessTrusted() {
            // Small delay to ensure clipboard is set before simulating paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else {
                    completion?(false)
                    return
                }
                let pasteSucceeded = self.simulatePaste()
                if pasteSucceeded {
                    self.logger.info("Text pasted at cursor (\(text.count) chars)")
                    // Restore previous clipboard after paste has had time to execute
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.restoreClipboardContents(previousClipboard)
                    }
                    completion?(true)
                } else {
                    // Paste simulation failed — keep text on clipboard and notify
                    self.logger.warning("Paste simulation failed — text on clipboard (\(text.count) chars)")
                    self.showNotification(text)
                    completion?(false)
                }
            }
        } else {
            // No accessibility permission — prompt once, then fall back to notification
            if !hasPromptedAccessibility() {
                promptAccessibility()
                markPromptedAccessibility()
            }
            logger.warning("No accessibility permission — text on clipboard (\(text.count) chars)")
            showNotification(text)
            completion?(false)
        }
    }

    // MARK: - Clipboard

    private func copyToClipboardSync(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Clipboard Save/Restore

    private struct ClipboardContents {
        let stringData: String?
        let rtfData: Data?
        let pdfData: Data?
        let fileURLs: [URL]
    }

    private func saveClipboardContents() -> ClipboardContents {
        let pb = NSPasteboard.general
        let stringData = pb.string(forType: .string)
        let rtfData = pb.data(forType: .rtf)
        let pdfData = pb.data(forType: .pdf)
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        return ClipboardContents(
            stringData: stringData,
            rtfData: rtfData,
            pdfData: pdfData,
            fileURLs: fileURLs
        )
    }

    private func restoreClipboardContents(_ contents: ClipboardContents) {
        let pb = NSPasteboard.general
        pb.clearContents()

        var items: [NSPasteboardItem] = []

        if let stringData = contents.stringData {
            let item = NSPasteboardItem()
            item.setString(stringData, forType: .string)
            items.append(item)
        }
        if let rtfData = contents.rtfData {
            let item = NSPasteboardItem()
            item.setData(rtfData, forType: .rtf)
            items.append(item)
        }
        if let pdfData = contents.pdfData {
            let item = NSPasteboardItem()
            item.setData(pdfData, forType: .pdf)
            items.append(item)
        }
        if !contents.fileURLs.isEmpty {
            pb.writeObjects(contents.fileURLs as [NSPasteboardWriting])
        }

        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    // MARK: - Accessibility Permission

    private func hasPromptedAccessibility() -> Bool {
        UserDefaults.standard.bool(forKey: hasPromptedAccessibilityKey)
    }

    private func markPromptedAccessibility() {
        UserDefaults.standard.set(true, forKey: hasPromptedAccessibilityKey)
    }

    private func promptAccessibility() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Simulate Paste (Cmd+V)

    /// Simulates Cmd+V keypress. Returns true only if there is a focused app
    /// that can receive keyboard events.
    private func simulatePaste() -> Bool {
        // Check that there is a frontmost application that can receive key events
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("No frontmost application — cannot simulate paste")
            return false
        }

        // If the frontmost app is our own menu bar app, there's nowhere to paste
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            logger.warning("Frontmost app is VoiceDictation itself — nowhere to paste")
            return false
        }

        let source = CGEventSource(stateID: CGEventSourceStateID.privateState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = CGEventFlags.maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
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