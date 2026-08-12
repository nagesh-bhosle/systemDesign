//
//  TextInserter.swift
//  VoiceDictation
//
//  Inserts transcribed text at the cursor of the app that was focused
//  when recording started (not Voice Dictation itself).
//

import Cocoa
import ApplicationServices
import UserNotifications
import os

enum InsertResult {
    case pasted
    case clipboardOnly
    case needsAccessibilityRefresh
}

final class TextInserter {
    static let shared = TextInserter()

    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TextInserter")

    var clipboardOnlyMode: Bool = false
    var restoreClipboardEnabled: Bool = true

    /// App that had keyboard focus when the user started dictating.
    private var insertionTarget: NSRunningApplication?

    private init() {
        requestNotificationAuthorization()
    }

    // MARK: - Target app

    /// Call when recording starts, before showing our own windows.
    func captureInsertionTarget() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.bundleIdentifier != Bundle.main.bundleIdentifier {
            insertionTarget = front
            logger.info("Insertion target: \(front.localizedName ?? "unknown", privacy: .public)")
        }
    }

    // MARK: - Public

    func insertOrCopy(_ text: String, completion: ((InsertResult) -> Void)? = nil) {
        let previousClipboard = saveClipboardContents()
        copyToClipboardSync(text)

        if clipboardOnlyMode {
            logger.info("Clipboard-only mode — text on clipboard (\(text.count) chars)")
            showNotification(text)
            completion?(.clipboardOnly)
            return
        }

        // Do not call AXIsProcessTrustedWithOptions(prompt). After a rebuild, System
        // Settings can still show Voice Dictation as enabled while this binary is
        // not trusted — Apple's dialog looks like permission is missing.
        guard AXIsProcessTrusted() else {
            logger.warning("This build is not Accessibility-trusted — text on clipboard")
            showAccessibilityRefreshNotification(text)
            completion?(.needsAccessibilityRefresh)
            return
        }

        guard let target = resolvedInsertionTarget() else {
            logger.warning("No target app for paste — text on clipboard")
            showNotification(text)
            completion?(.clipboardOnly)
            return
        }

        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target)
            _ = target.activate()
        } else {
            _ = target.activate(options: [.activateIgnoringOtherApps])
        }

        let pid = target.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else {
                completion?(.clipboardOnly)
                return
            }

            let pasteSucceeded = self.postCommandV(to: pid)
            if pasteSucceeded {
                self.logger.info("Posted Cmd+V to \(target.localizedName ?? "app", privacy: .public) (\(text.count) chars)")
                if self.restoreClipboardEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.restoreClipboardContents(previousClipboard)
                    }
                }
                completion?(.pasted)
            } else {
                self.logger.warning("Paste simulation failed — text on clipboard (\(text.count) chars)")
                self.showNotification(text)
                completion?(.clipboardOnly)
            }
        }
    }

    private func resolvedInsertionTarget() -> NSRunningApplication? {
        if let saved = insertionTarget, !saved.isTerminated,
           saved.bundleIdentifier != Bundle.main.bundleIdentifier {
            return saved
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return nil
    }

    // MARK: - Clipboard

    private func copyToClipboardSync(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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

    // MARK: - Simulate Paste (Cmd+V)

    /// Posts Cmd+V into the target process. `privateState` events are not delivered
    /// to other apps — use hidSystemState and postToPid.
    private func postCommandV(to pid: pid_t) -> Bool {
        guard pid > 0 else { return false }

        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.warning("Failed to create CGEvent for paste simulation")
            return false
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.postToPid(pid)
        vDown.postToPid(pid)
        vUp.postToPid(pid)
        cmdUp.postToPid(pid)

        return true
    }

    // MARK: - Notification

    private func requestNotificationAuthorization() {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func showNotification(_ text: String) {
        postNotification(
            title: "Voice Dictation",
            body: "Text copied to clipboard. Press Cmd+V to paste.\n\"\(String(text.prefix(100)))\""
        )
    }

    private func showAccessibilityRefreshNotification(_ text: String) {
        postNotification(
            title: "Toggle Accessibility for this build",
            body: "System Settings still lists Voice Dictation, but this rebuild is a new app. Uncheck it, check it again, then Cmd+V to paste.\n\"\(String(text.prefix(80)))\""
        )
    }

    private func postNotification(title: String, body: String) {
        DispatchQueue.main.async {
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: "dictation-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
