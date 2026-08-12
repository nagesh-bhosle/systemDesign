//
//  MenuBarView.swift
//  VoiceDictation
//
//  Menu bar dropdown UI — shows status, last transcript, and actions.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            // Status
            HStack {
                Image(systemName: appState.statusIcon)
                    .foregroundColor(appState.status == .recording ? .red : .primary)
                    .font(.title2)
                Text(appState.status.rawValue)
                    .font(.headline)
                Spacer()
            }

            // Toggle button
            Button(action: {
                appState.toggleRecording()
            }) {
                Text(appState.status == .recording ? "Stop & Transcribe" : "Start Recording")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.status == .transcribing)

            // Last transcript
            if !appState.lastTranscript.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcript")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.lastTranscript)
                        .font(.body)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Copy Again") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Error
            if !appState.errorMessage.isEmpty {
                Divider()
                Text(appState.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Settings & Quit
            HStack {
                Button("Settings") {
                    openSettings()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            HotkeyManager.shared.registerHotkey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDictation)) { _ in
            appState.toggleRecording()
        }
    }
}