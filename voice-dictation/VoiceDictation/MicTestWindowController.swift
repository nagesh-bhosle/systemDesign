//
//  MicTestWindowController.swift
//  VoiceDictation
//
//  Dedicated panel for the mic check. Sheets on MenuBarExtra crash on macOS.
//

import Cocoa
import SwiftUI

@MainActor
final class MicTestWindowController: NSObject, NSWindowDelegate {
    static let shared = MicTestWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    private override init() {
        super.init()
    }

    func show(appState: AppState) {
        appState.refreshAudioInputs()
        appState.stopMicTest()

        let content = MicTestView()
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: AnyView(content))
        hostingController = hosting

        if panel == nil {
            let size = NSSize(width: 400, height: 280)
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Check microphone"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.center()
            self.panel = panel
        }

        panel?.contentViewController = hosting
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        AppState.shared?.stopMicTest()
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppState.shared?.stopMicTest()
    }
}
