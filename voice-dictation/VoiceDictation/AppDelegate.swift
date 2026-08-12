//
//  AppDelegate.swift
//  VoiceDictation
//
//  Registers the global hotkey and manages app lifecycle.
//

import Cocoa
import Carbon.HIToolbox
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !HotkeyManager.shared.registerHotkey() {
            logger.error("Failed to register global hotkey — possible conflict with another app")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Hotkey Registration Failed"
                alert.informativeText = "Voice Dictation could not register ⌥⇧Space. Another app may be using this shortcut. You can still start and stop recording from the menu bar. Settings are also available from the menu bar icon."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppState.shared?.checkPermissionsAndShowOnboardingIfNeeded()
            if AppState.shared?.showOnboarding == true, let state = AppState.shared {
                state.presentOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }
}
