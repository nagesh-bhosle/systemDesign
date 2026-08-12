//
//  FloatingWindowController.swift
//  VoiceDictation
//
//  Manages the floating window that appears during recording.
//  Uses NSPanel so it floats above other windows without stealing focus.
//

import Cocoa
import SwiftUI

final class FloatingWindowController: ObservableObject {
    static let shared = FloatingWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    @Published var isVisible = false

    private init() {}

    func showWindow(appState: AppState) {
        if panel == nil {
            let contentView = FloatingWindowView()
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: AnyView(contentView))
            self.hostingController = hostingController

            let panelSize = NSSize(width: 400, height: 60)
            let panelFrame = NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height)

            panel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel?.title = "Voice Dictation"
            panel?.isFloatingPanel = true
            panel?.level = .floating
            panel?.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel?.isOpaque = false
            panel?.backgroundColor = .clear
            panel?.isMovableByWindowBackground = true
            panel?.hidesOnDeactivate = false
            panel?.becomesKeyOnlyIfNeeded = false
            panel?.worksWhenModal = true
            panel?.contentViewController = hostingController

            // Make panel accept mouse events (critical for button clicks in nonactivating panel)
            panel?.styleMask = [.borderless, .nonactivatingPanel]
            panel?.canBecomeVisibleWithoutLogin = true

            // Position: top-center of screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - panelSize.width) / 2 + screenFrame.minX
                let y = screenFrame.maxY - panelSize.height - 10
                panel?.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
            }
        }

        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hideWindow() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggleWindow(appState: AppState) {
        if isVisible {
            hideWindow()
        } else {
            showWindow(appState: appState)
        }
    }
}