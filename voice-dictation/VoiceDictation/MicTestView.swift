//
//  MicTestView.swift
//  VoiceDictation
//
//  Pick laptop vs headphone mic and confirm the level meter moves.
//  Audio starts only when the user clicks Start test.
//

import SwiftUI

struct MicTestView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speak at a normal volume after you start the test. The meter should move. If it stays still, pick a different input.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.audioInputs.isEmpty {
                Text("No microphones found. Check System Settings → Privacy & Security → Microphone.")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Picker("Input", selection: micSelection) {
                    ForEach(appState.audioInputs) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .accessibilityLabel("Microphone input")
            }

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
                .disabled(appState.audioInputs.isEmpty || appState.status == .recording || appState.status == .transcribing)
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Done") {
                    MicTestWindowController.shared.hide()
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            appState.refreshAudioInputs()
        }
    }

    private var micSelection: Binding<String> {
        Binding(
            get: { appState.resolvedInputUID },
            set: { appState.saveSelectedInput($0) }
        )
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
