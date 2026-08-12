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
    @State private var showCopiedFeedback = false
    @ObservedObject private var floatingController = FloatingWindowController.shared

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
            // Issue #24: Also disable during enhancing
            .disabled(appState.status == .transcribing || appState.status == .enhancing)
            .accessibilityLabel(appState.status == .recording ? "Stop and transcribe" : "Start recording")

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

                    // Issue #47: Add copy feedback
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
                        showCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedFeedback = false
                        }
                    } label: {
                        Text(showCopiedFeedback ? "✅ Copied!" : "Copy Again")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Copy last transcript to clipboard")
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
                if floatingController.isVisible {
                    floatingController.hideWindow()
                } else {
                    floatingController.showWindow(appState: appState)
                }
            }) {
                Label(floatingController.isVisible ? "Hide Floating Bar" : "Show Floating Bar",
                      systemImage: "rectangle.topthird.inset.filled")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(floatingController.isVisible ? "Hide floating bar" : "Show floating bar")

            Divider()

            // Settings, History & Quit
            HStack {
                Button("Settings") {
                    openSettings()
                }
                .accessibilityLabel("Open settings")
                Button("History") {
                    showHistory = true
                }
                .accessibilityLabel("Open transcript history")
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Close the app completely")
                .accessibilityLabel("Quit Voice Dictation")
            }
        }
        .padding()
        .frame(width: 320)
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(appState)
        }
    }
}