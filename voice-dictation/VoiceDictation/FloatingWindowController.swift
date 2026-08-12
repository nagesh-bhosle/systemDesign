//
//  FloatingWindowController.swift
//  VoiceDictation
//
//  Manages the floating window lifecycle.
//

import Cocoa
import SwiftUI

@MainActor
final class FloatingWindowController: ObservableObject {
    static let shared = FloatingWindowController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    @Published var isVisible = false

    private let positionKey = "floatingWindowPosition"
    private let idleWidth: CGFloat = 36
    private let activeWidth: CGFloat = 300
    private let panelHeight: CGFloat = 36

    private init() {}

    func showWindow(appState: AppState) {
        let contentView = FloatingWindowView()
            .environmentObject(appState)

        let newHostingController = NSHostingController(rootView: AnyView(contentView))

        if panel == nil {
            let panelSize = NSSize(width: idleWidth, height: panelHeight)
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
            panel?.contentMinSize = NSSize(width: idleWidth, height: panelHeight)
            panel?.contentMaxSize = NSSize(width: 340, height: panelHeight)
            panel?.canBecomeVisibleWithoutLogin = true

            if let savedPosition = UserDefaults.standard.array(forKey: positionKey) as? [CGFloat],
               savedPosition.count == 2 {
                panel?.setFrame(
                    NSRect(x: savedPosition[0], y: savedPosition[1], width: panelSize.width, height: panelSize.height),
                    display: true
                )
            } else if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - panelSize.width) / 2 + screenFrame.minX
                let y = screenFrame.maxY - panelSize.height - 10
                panel?.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
            }
        }

        panel?.contentViewController = newHostingController
        self.hostingController = newHostingController

        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hideWindow() {
        if let frame = panel?.frame {
            UserDefaults.standard.set([frame.origin.x, frame.origin.y], forKey: positionKey)
        }
        panel?.orderOut(nil)
        isVisible = false
    }

    func resizePanel(width: CGFloat) {
        guard let panel = panel else { return }
        let clampedWidth = min(max(width, idleWidth), 340)
        let currentFrame = panel.frame
        let centerX = currentFrame.midX
        let newX = centerX - clampedWidth / 2
        let newY = currentFrame.maxY - panelHeight
        let newFrame = NSRect(x: newX, y: newY, width: clampedWidth, height: panelHeight)
        if abs(currentFrame.width - clampedWidth) > 0.5 {
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
