//
//  OnboardingWindowController.swift
//  VoiceDictation
//
//  Dedicated setup panel so onboarding works for a menu-bar (LSUIElement) app
//  without requiring the extra menu to be open.
//

import Cocoa
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    private init() {}

    func show(appState: AppState) {
        let content = OnboardingView()
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: AnyView(content))
        hostingController = hosting

        if panel == nil {
            let size = NSSize(width: 460, height: 440)
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Voice Dictation Setup"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.center()
            self.panel = panel
        }

        panel?.contentViewController = hosting
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
