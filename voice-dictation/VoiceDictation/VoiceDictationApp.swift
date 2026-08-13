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
    @StateObject private var appState = AppState.createPrimary()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if appState.status == .recording {
                Image(systemName: "waveform")
                    .foregroundColor(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityLabel("Voice Dictation is recording")
            } else if appState.status == .enhancing {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityLabel("Voice Dictation is enhancing text")
            } else if appState.status == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .accessibilityLabel("Voice Dictation error")
            } else {
                MenuBarIdleIcon()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
