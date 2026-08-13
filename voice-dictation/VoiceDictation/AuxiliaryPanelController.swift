//
//  AuxiliaryPanelController.swift
//  VoiceDictation
//
//  Dedicated NSPanel host. Sheets on MenuBarExtra glitch when the extra closes.
//

import Cocoa
import SwiftUI

@MainActor
final class AuxiliaryPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private let title: String
    private let size: NSSize
    private let onClose: (() -> Void)?

    init(title: String, size: NSSize, onClose: (() -> Void)? = nil) {
        self.title = title
        self.size = size
        self.onClose = onClose
        super.init()
    }

    func show<Content: View>(_ content: Content) {
        let hosting = NSHostingController(rootView: AnyView(content))
        hostingController = hosting

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = title
            panel.isFloatingPanel = false
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.center()
            self.panel = panel
        }

        panel?.contentViewController = hosting
        panel?.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        onClose?()
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
enum AppPanels {
    static let history = AuxiliaryPanelController(
        title: "History",
        size: NSSize(width: 400, height: 480)
    )
    static let settings = AuxiliaryPanelController(
        title: "Settings",
        size: NSSize(width: 560, height: 600)
    )

    static func showHistory(appState: AppState) {
        history.show(
            HistoryView(onClose: { history.hide() })
                .environmentObject(appState)
        )
    }

    static func showSettings(appState: AppState) {
        settings.show(
            SettingsView()
                .environmentObject(appState)
        )
    }
}
