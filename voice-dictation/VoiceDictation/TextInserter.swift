//
//  TextInserter.swift
//  VoiceDictation
//
//  Inserts transcribed text at the cursor position.
//

import Cocoa
import ApplicationServices
import UserNotifications
import os

final class TextInserter {
    static let shared = TextInserter()

    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TextInserter")

    private let hasPromptedAccessibilityKey = "hasPromptedAccessibility"

    var clipboardOnlyMode: Bool = false
    var restoreClipboardEnabled: Bool = true

    private init() {
        requestNotificationAuthorization()
    }

    // MARK: - Public

    func insertOrCopy(_ text: String, completion: ((Bool) -> Void)? = nil) {
        let previousClipboard = saveClipboardContents()
        copyToClipboardSync(text)

        if clipboardOnlyMode {
            logger.info("Clipboard-only mode — text on clipboard (\(text.count) chars)")
            showNotification(text)
            completion?(false)
            return
        }

        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else {
                    completion?(false)
                    return
                }
                let pasteSucceeded = self.simulatePaste()
                if pasteSucceeded {
                    self.logger.info("Text pasted at cursor (\(text.count) chars)")
                    if self.restoreClipboardEnabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.restoreClipboardContents(previousClipboard)
                        }
                    }
                    completion?(true)
                } else {
                    self.logger.warning("Paste simulation failed — text on clipboard (\(text.count) chars)")
                    self.showNotification(text)
                    completion?(false)
                }
            }
        } else {
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
        let htmlData: Data?
        let pdfData: Data?
        let tiffData: Data?
        let pngData: Data?
        let fileURLs: [URL]
    }

    private func saveClipboardContents() -> ClipboardContents {
        let pb = NSPasteboard.general
        return ClipboardContents(
            stringData: pb.string(forType: .string),
            rtfData: pb.data(forType: .rtf),
            htmlData: pb.data(forType: .html),
            pdfData: pb.data(forType: .pdf),
            tiffData: pb.data(forType: .tiff),
            pngData: pb.data(forType: .png),
            fileURLs: (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
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
        if let htmlData = contents.htmlData {
            let item = NSPasteboardItem()
            item.setData(htmlData, forType: .html)
            items.append(item)
        }
        if let pdfData = contents.pdfData {
            let item = NSPasteboardItem()
            item.setData(pdfData, forType: .pdf)
            items.append(item)
        }
        if let tiffData = contents.tiffData {
            let item = NSPasteboardItem()
            item.setData(tiffData, forType: .tiff)
            items.append(item)
        }
        if let pngData = contents.pngData {
            let item = NSPasteboardItem()
            item.setData(pngData, forType: .png)
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

    private func simulatePaste() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("No frontmost application — cannot simulate paste")
            return false
        }

        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            logger.warning("Frontmost app is VoiceDictation itself — nowhere to paste")
            return false
        }

        let source = CGEventSource(stateID: CGEventSourceStateID.privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.warning("Failed to create CGEvent for paste simulation")
            return false
        }

        cmdDown.flags = CGEventFlags.maskCommand
        vDown.flags = CGEventFlags.maskCommand
        vUp.flags = CGEventFlags.maskCommand

        cmdDown.post(tap: CGEventTapLocation.cghidEventTap)
        vDown.post(tap: CGEventTapLocation.cghidEventTap)
        vUp.post(tap: CGEventTapLocation.cghidEventTap)
        cmdUp.post(tap: CGEventTapLocation.cghidEventTap)

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
