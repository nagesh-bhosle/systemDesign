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
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 12) {
            // Status with animated waveform
            HStack {
                if appState.status == .recording {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 3, height: 16)
                                .scaleEffect(y: appState.status == .recording ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.35)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.12),
                                    value: appState.status == .recording
                                )
                        }
                    }
                } else {
                    Image(systemName: appState.statusIcon)
                        .foregroundColor(appState.status == .error ? .red : .primary)
                        .font(.title2)
                }
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

            Button(action: {
                if FloatingWindowController.shared.isVisible {
                    FloatingWindowController.shared.hideWindow()
                } else {
                    FloatingWindowController.shared.showWindow(appState: appState)
                }
            }) {
                Label(FloatingWindowController.shared.isVisible ? "Hide Floating Bar" : "Show Floating Bar",
                      systemImage: "rectangle.topthird.inset.filled")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            // Settings, History & Quit
            HStack {
                Button("Settings") {
                    openSettings()
                }
                Button("History") {
                    showHistory = true
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Close the app completely")
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
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(appState)
        }
    }
}