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

enum InsertResult: Equatable {
    case pasted
    case clipboardOnly
    case needsAccessibilityRefresh
}

@MainActor
final class TextInserter {
    static let shared = TextInserter()

    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TextInserter")

    var clipboardOnlyMode: Bool = false
    var restoreClipboardEnabled: Bool = true

    private var insertionTarget: NSRunningApplication?
    private(set) var lastInsertResult: InsertResult?
    private(set) var lastTargetPID: pid_t = 0
    /// Bumped on each insert so a late clipboard restore cannot overwrite a newer take.
    private var restoreGeneration: UInt64 = 0

    private init() {
        requestNotificationAuthorization()
    }

    // MARK: - Target app

    func captureInsertionTarget() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.bundleIdentifier != Bundle.main.bundleIdentifier {
            insertionTarget = front
            logger.info("Insertion target: \(front.localizedName ?? "unknown", privacy: .public)")
        }
    }

    var targetBundleIdentifier: String? {
        resolvedInsertionTarget()?.bundleIdentifier
    }

    // MARK: - Public

    func insertOrCopy(_ text: String, completion: ((InsertResult) -> Void)? = nil) {
        restoreGeneration += 1
        let generation = restoreGeneration
        let fieldBefore = focusedElementString()
        let previousClipboard = saveClipboardContents()
        copyToClipboardSync(text)

        if clipboardOnlyMode {
            logger.info("Clipboard-only mode — text on clipboard (\(text.count) chars)")
            lastInsertResult = .clipboardOnly
            lastTargetPID = 0
            showNotification(text)
            completion?(.clipboardOnly)
            return
        }

        // Clicking our pill/menu can steal key focus. Drop it before inserting
        // so the caret stays in Notepad / Safari / the search field.
        FloatingWindowController.shared.resignKey()

        let finish: (InsertResult, PasteMechanism) -> Void = { result, mechanism in
            self.lastInsertResult = result
            if result == .pasted, self.restoreClipboardEnabled {
                self.scheduleClipboardRestore(
                    previous: previousClipboard,
                    transcript: text,
                    mechanism: mechanism,
                    generation: generation,
                    fieldBefore: fieldBefore
                )
            }
            if result == .needsAccessibilityRefresh {
                self.showAccessibilityRefreshNotification(text)
            } else if result != .pasted {
                self.showNotification(text)
            }
            completion?(result)
        }

        attemptInsert(
            text: text,
            allowActivateTarget: true,
            fieldBefore: fieldBefore,
            completion: finish
        )
    }

    private enum PasteMechanism {
        /// AX set the field value; the clipboard was never consumed.
        case accessibility
        /// Cmd+V; wait until the target app reads the pasteboard.
        case commandV
    }

    private func attemptInsert(
        text: String,
        allowActivateTarget: Bool,
        fieldBefore: String?,
        completion: @escaping (InsertResult, PasteMechanism) -> Void
    ) {
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let focused = focusedAXElement()
        let focusedPID = focused.map { axPid($0) } ?? 0
        let focusedIsOtherApp = focusedPID != 0 && focusedPID != ourPID

        if focusedIsOtherApp, let element = focused {
            if insertTextViaAccessibility(text, into: element),
               fieldConfirmsInsert(transcript: text, before: fieldBefore) {
                lastTargetPID = focusedPID
                logger.info("Inserted via Accessibility into focused field")
                completion(.pasted, .accessibility)
                return
            }
            logger.info("Accessibility set did not change the field — falling through to Cmd+V")
        }

        // Our menu/pill stole focus — put the original app back, then insert.
        if allowActivateTarget, (!focusedIsOtherApp),
           let target = resolvedInsertionTarget(),
           target.processIdentifier != ourPID {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: target)
                _ = target.activate()
            } else {
                _ = target.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.attemptInsert(
                    text: text,
                    allowActivateTarget: false,
                    fieldBefore: fieldBefore,
                    completion: completion
                )
            }
            return
        }

        if AXIsProcessTrusted(), postCommandVToSession() {
            lastTargetPID = focusedIsOtherApp ? focusedPID : (resolvedInsertionTarget()?.processIdentifier ?? 0)
            logger.info("Posted session Cmd+V for focused cursor")
            completion(.pasted, .commandV)
            return
        }

        lastTargetPID = 0
        if !AXIsProcessTrusted() {
            completion(.needsAccessibilityRefresh, .commandV)
        } else {
            completion(.clipboardOnly, .commandV)
        }
    }

    // MARK: - Accessibility insert (the actual caret)

    private func focusedAXElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard status == .success, let focused else { return nil }
        return (focused as! AXUIElement)
    }

    private func axPid(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private func insertTextViaAccessibility(_ text: String, into element: AXUIElement) -> Bool {
        let selectedStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedStatus == .success {
            return true
        }

        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard valueStatus == .success, rangeStatus == .success,
              let current = valueRef as? String,
              let rangeRef else {
            return false
        }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return false }

        let ns = current as NSString
        let location = max(0, min(Int(cfRange.location), ns.length))
        let length = max(0, min(Int(cfRange.length), ns.length - location))
        let updated = ns.replacingCharacters(in: NSRange(location: location, length: length), with: text)
        let setStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updated as CFTypeRef
        )
        guard setStatus == .success else { return false }

        var caret = CFRange(location: location + (text as NSString).length, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caretValue)
        }
        return true
    }

    // MARK: - Session-wide Cmd+V (reaches the app that owns the caret)

    private func postCommandVToSession() -> Bool {
        postSessionChord(keyCode: 0x09)
    }

    private func postSessionChord(keyCode: UInt16) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.warning("Failed to create CGEvent for session shortcut")
            return false
        }

        cmdDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)

        return true
    }

    enum UndoResult {
        case undone
        case nothingToUndo
        case failed
    }

    func undoLastPaste() -> UndoResult {
        guard lastInsertResult == .pasted, lastTargetPID > 0 else {
            return .nothingToUndo
        }

        guard AXIsProcessTrusted() else {
            return .failed
        }

        if postSessionChord(keyCode: 0x06) {
            logger.info("Posted Cmd+Z to undo last paste")
            lastInsertResult = nil
            lastTargetPID = 0
            return .undone
        }
        return .failed
    }

    func pasteHistoryEntry(_ text: String, completion: ((InsertResult) -> Void)? = nil) {
        captureInsertionTarget()
        insertOrCopy(text, completion: completion)
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

    private func scheduleClipboardRestore(
        previous: ClipboardContents,
        transcript: String,
        mechanism: PasteMechanism,
        generation: UInt64,
        fieldBefore: String?
    ) {
        switch mechanism {
        case .accessibility:
            restoreIfSafe(
                transcript: transcript,
                previous: previous,
                generation: generation
            )
        case .commandV:
            waitForConfirmedPasteThenRestore(
                transcript: transcript,
                previous: previous,
                generation: generation,
                fieldBefore: fieldBefore
            )
        }
    }

    /// Restore only if this is still the latest insert and the pasteboard still holds our transcript.
    private func restoreIfSafe(transcript: String, previous: ClipboardContents, generation: UInt64) {
        guard generation == restoreGeneration else { return }
        let current = NSPasteboard.general.string(forType: .string)
        guard current == transcript else { return }
        restoreClipboardContents(previous)
    }

    private func waitForConfirmedPasteThenRestore(
        transcript: String,
        previous: ClipboardContents,
        generation: UInt64,
        fieldBefore: String?
    ) {
        let deadline = Date().addingTimeInterval(2.5)
        func tick() {
            guard generation == restoreGeneration else { return }
            if fieldConfirmsInsert(transcript: transcript, before: fieldBefore) {
                restoreIfSafe(transcript: transcript, previous: previous, generation: generation)
                return
            }
            // Timed out: keep the current transcript on the clipboard.
            // Restoring here races Cmd+V and pastes the previous take.
            if Date() >= deadline {
                logger.info("Paste not confirmed in time — leaving current transcript on the clipboard")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                tick()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            tick()
        }
    }

    /// True only if the focused field changed and now contains this take.
    private func fieldConfirmsInsert(transcript: String, before: String?) -> Bool {
        let needle = String(transcript.prefix(80))
        guard !needle.isEmpty, let after = focusedElementString() else { return false }
        guard after.contains(needle) else { return false }
        if let before, after == before {
            return false
        }
        return true
    }

    private func focusedElementString() -> String? {
        guard let element = focusedAXElement() else { return nil }
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String {
            return value
        }
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let selected = selectedRef as? String {
            return selected
        }
        return nil
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
