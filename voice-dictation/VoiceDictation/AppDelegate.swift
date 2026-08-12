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

        // Issue #7: Don't show floating window on launch — it should only
        // appear when recording starts. The user can toggle it from the
        // menu bar if they want it visible.
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }
}