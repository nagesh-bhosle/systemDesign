//
//  FloatingWindowController.swift
//  VoiceDictation
//
//  Manages the floating window that appears during recording.
//  Uses NSPanel so it floats above other windows without stealing focus.
//

import Cocoa
import SwiftUI

// Issue #53: Annotate with @MainActor since always accessed from main thread
@MainActor
final class FloatingWindowController: ObservableObject {
    static let shared = FloatingWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    @Published var isVisible = false

    // Issue #22: Persist window position
    private let positionKey = "floatingWindowPosition"

    private init() {}

    func showWindow(appState: AppState) {
        // Issue #20: Always recreate the hosting controller with current appState
        // so the panel references the correct instance
        let contentView = FloatingWindowView()
            .environmentObject(appState)

        let newHostingController = NSHostingController(rootView: AnyView(contentView))

        if panel == nil {
            let panelSize = NSSize(width: 36, height: 40)
            let panelFrame = NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height)

            panel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.borderless, .nonactivatingPanel, .resizable],
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
            panel?.becomesKeyOnlyIfNeeded = true
            panel?.worksWhenModal = true
            panel?.acceptsMouseMovedEvents = true
            panel?.contentMinSize = NSSize(width: 36, height: 40)
            panel?.contentMaxSize = NSSize(width: 340, height: 40)
            panel?.canBecomeVisibleWithoutLogin = true

            // Issue #22: Restore saved position or default to top-center
            if let savedPosition = UserDefaults.standard.array(forKey: positionKey) as? [CGFloat],
               savedPosition.count == 2 {
                panel?.setFrame(NSRect(x: savedPosition[0], y: savedPosition[1], width: panelSize.width, height: panelSize.height), display: true)
            } else if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - panelSize.width) / 2 + screenFrame.minX
                let y = screenFrame.maxY - panelSize.height - 10
                panel?.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
            }
        }

        // Issue #20: Update hosting controller with current appState
        panel?.contentViewController = newHostingController
        self.hostingController = newHostingController

        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hideWindow() {
        // Issue #22: Save position before hiding
        if let frame = panel?.frame {
            UserDefaults.standard.set([frame.origin.x, frame.origin.y], forKey: positionKey)
        }
        panel?.orderOut(nil)
        isVisible = false
    }

    // Issue #21: Consolidated resize method
    func resizePanel(width: CGFloat) {
        guard let panel = panel else { return }
        let currentFrame = panel.frame
        let centerX = currentFrame.midX
        let newX = centerX - width / 2
        let newY = currentFrame.maxY - 40
        let newFrame = NSRect(x: newX, y: newY, width: width, height: 40)
        if abs(currentFrame.width - width) > 0.5 {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    /// Convenience method for hover-based resize (tiny ↔ expanded)
    func resizePanel(isHovered: Bool) {
        resizePanel(width: isHovered ? 340 : 36)
    }

    /// Convenience method for state-based resize
    func resizePanelForState(width: CGFloat) {
        resizePanel(width: width)
    }

    func toggleWindow(appState: AppState) {
        if isVisible {
            hideWindow()
        } else {
            showWindow(appState: appState)
        }
    }
}