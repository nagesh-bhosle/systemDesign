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
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }
}