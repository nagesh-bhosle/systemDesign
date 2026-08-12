//
//  AppDelegate.swift
//  VoiceDictation
//
//  Registers the global hotkey and manages floating window.
//

import Cocoa
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.registerHotkey()

        // Show floating bar on launch (delayed so AppState is ready)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let appState = AppState.shared {
                FloatingWindowController.shared.showWindow(appState: appState)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }
}