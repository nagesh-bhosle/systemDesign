//
//  AppDelegate.swift
//  VoiceDictation
//
//  Registers the global hotkey and manages floating window.
//

import Cocoa
import Carbon.HIToolbox
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Issue #13: Check registration result and log if it fails
        if !HotkeyManager.shared.registerHotkey() {
            logger.error("Failed to register global hotkey — possible conflict with another app")
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Hotkey Registration Failed"
                alert.informativeText = "Voice Dictation could not register ⌥⇧Space. Another app may be using this shortcut. Try quitting conflicting apps and restarting Voice Dictation."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }
}