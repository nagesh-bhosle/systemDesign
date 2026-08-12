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

            // Panel starts tiny (36 — just mic icon) and expands to 340 on hover.
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
            panel?.contentViewController = hostingController

            // Panel can resize between tiny (36) and expanded (340)
            panel?.contentMinSize = NSSize(width: 36, height: 40)
            panel?.contentMaxSize = NSSize(width: 340, height: 40)
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

    /// Resize the panel between tiny (36 — just mic icon) and expanded (340) on hover.
    /// Also resizes based on recording/enhancing state.
    /// Keeps the top-center position fixed.
    /// Issue #27: The panel is the single source of truth for width.
    func resizePanel(isHovered: Bool) {
        guard let panel = panel else { return }
        let targetWidth: CGFloat = isHovered ? 340 : 36
        let currentFrame = panel.frame
        // Keep top-center fixed: recompute x so the center stays the same
        let centerX = currentFrame.midX
        let newX = centerX - targetWidth / 2
        let newY = currentFrame.maxY - 40
        let newFrame = NSRect(x: newX, y: newY, width: targetWidth, height: 40)
        if abs(currentFrame.width - targetWidth) > 0.5 {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    /// Issue #27: Resize panel based on app state (recording/enhancing needs
    /// more width to show live transcript).
    func resizePanelForState(width: CGFloat) {
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

    func toggleWindow(appState: AppState) {
        if isVisible {
            hideWindow()
        } else {
            showWindow(appState: appState)
        }
    }
}