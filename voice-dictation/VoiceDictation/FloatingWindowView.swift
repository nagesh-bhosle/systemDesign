//
//  FloatingWindowView.swift
//  VoiceDictation
//
//  Small floating window that appears while recording.
//  Shows live transcript preview and recording status.
//

import SwiftUI

struct FloatingWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            // Header with animated waveform
            HStack(spacing: 8) {
                // Animated waveform bars
                if appState.status == .recording {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            WaveformBar()
                                .frame(width: 4, height: 20)
                                .animation(
                                    .easeInOut(duration: 0.4)
                                        .repeatForever()
                                        .delay(Double(i) * 0.1),
                                    value: appState.status == .recording
                                )
                        }
                    }
                } else {
                    Image(systemName: appState.statusIcon)
                        .font(.title3)
                        .foregroundColor(appState.status == .error ? .red : .accentColor)
                }

                Text(appState.status.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    appState.toggleRecording()
                }) {
                    Image(systemName: appState.status == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundColor(appState.status == .recording ? .red : .accentColor)
                }
                .buttonStyle(.plain)
            }

            // Live transcript preview
            if !appState.liveTranscript.isEmpty {
                Divider()
                ScrollView {
                    Text(appState.liveTranscript)
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            }

            // Error message
            if !appState.errorMessage.isEmpty {
                Divider()
                Text(appState.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Last transcript (when idle)
            if appState.status == .idle && !appState.lastTranscript.isEmpty && appState.liveTranscript.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcript")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.lastTranscript)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .onReceive(NotificationCenter.default.publisher(for: .toggleDictation)) { _ in
            appState.toggleRecording()
        }
    }
}

// MARK: - Animated Waveform Bar

struct WaveformBar: View {
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .scaleEffect(y: animate ? 1.0 : 0.3)
            .onAppear {
                animate = true
            }
            .animation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true),
                value: animate
            )
    }
}