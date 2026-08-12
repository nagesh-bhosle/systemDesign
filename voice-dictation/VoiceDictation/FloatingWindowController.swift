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

            let panelSize = NSSize(width: 360, height: 50)
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
            panel?.contentViewController = hostingController

            // Allow panel to resize width for hover expansion, but keep height fixed
            panel?.contentMinSize = NSSize(width: 160, height: 40)
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

    /// Resize the panel to fit its SwiftUI content.
    /// Called from FloatingWindowView via ViewSizeKey preference.
    /// Only width changes (hover expands buttons) — height stays fixed
    /// so the window shape doesn't change during recording.
    func resizePanel(to size: CGSize) {
        guard let panel = panel else { return }
        let currentFrame = panel.frame
        // Keep height fixed at the initial compact bar height
        let fixedHeight: CGFloat = 40
        // Only adjust width to match content, keep position and height stable
        let newWidth = currentFrame.width
        let newFrame = NSRect(x: currentFrame.minX, y: currentFrame.minY, width: newWidth, height: fixedHeight)
        // Only update if height is wrong (don't trigger unnecessary redraws)
        if abs(currentFrame.height - fixedHeight) > 1 {
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