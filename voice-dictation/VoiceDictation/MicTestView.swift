//
//  MicTestView.swift
//  VoiceDictation
//
//  Confirms the system default mic (headset or laptop) without switching devices.
//

import SwiftUI

struct MicTestView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This uses whatever microphone macOS currently has selected, so your headset will not disconnect. Speak after Start test — the meter should move.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Current input")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(appState.currentInputName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Button("Open Sound Settings to change mic") {
                AudioInputManager.openSoundSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.isMicTestRunning ? "Listening…" : "Meter idle — press Start test")
                    .font(.caption)
                    .foregroundColor(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(meterColor)
                            .frame(width: max(8, geo.size.width * CGFloat(appState.micTestLevel)))
                    }
                }
                .frame(height: 10)
            }

            HStack {
                Button(appState.isMicTestRunning ? "Stop test" : "Start test") {
                    if appState.isMicTestRunning {
                        appState.stopMicTest()
                    } else {
                        appState.startMicTest()
                    }
                }
                .disabled(appState.status == .recording || appState.status == .transcribing)
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Done") {
                    MicTestWindowController.shared.hide()
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            appState.refreshAudioInputs()
        }
    }

    private var meterColor: Color {
        if !appState.isMicTestRunning || appState.micTestLevel < 0.08 {
            return .orange
        }
        if appState.micTestLevel < 0.7 {
            return .green
        }
        return .red
    }
}
