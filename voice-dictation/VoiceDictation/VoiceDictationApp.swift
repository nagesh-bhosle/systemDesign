//
//  VoiceDictationApp.swift
//  VoiceDictation
//
//  Created on 2026-08-12.
//

import SwiftUI

@main
struct VoiceDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if appState.status == .recording {
                Image(systemName: "waveform")
                    .foregroundColor(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else if appState.status == .enhancing {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating)
            } else if appState.status == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "mic.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}