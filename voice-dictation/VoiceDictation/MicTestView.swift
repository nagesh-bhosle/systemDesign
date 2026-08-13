//
//  MicTestView.swift
//  VoiceDictation
//
//  Lets the user pick laptop vs headphone mic and confirm the level meter moves.
//

import SwiftUI

struct MicTestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check microphone")
                .font(.headline)

            Text("Speak at a normal volume. The meter should move. If it stays still, pick a different input (laptop mic vs headphones).")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Input", selection: Binding(
                get: { appState.selectedInputUID },
                set: { appState.saveSelectedInput($0) }
            )) {
                ForEach(appState.audioInputs) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .accessibilityLabel("Microphone input")

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.isMicTestRunning ? "Listening…" : "Meter idle")
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

                Spacer()

                Button("Done") {
                    appState.stopMicTest()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            appState.refreshAudioInputs()
            appState.startMicTest()
        }
        .onDisappear {
            appState.stopMicTest()
        }
    }

    private var meterColor: Color {
        if appState.micTestLevel < 0.08 {
            return .orange
        }
        if appState.micTestLevel < 0.7 {
            return .green
        }
        return .red
    }
}
