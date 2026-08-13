//
//  MenuBarView.swift
//  VoiceDictation
//
//  Menu bar dropdown UI.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @State private var showCopiedFeedback = false
    @State private var showMicTest = false

    var body: some View {
        VStack(spacing: 14) {
            header
            pasteAtCursorHelp
            micCheckButton
            primaryButton
            undoButton
            transcriptCard
            messageArea
            floatingToggle
            footer
        }
        .padding(14)
        .frame(width: 290)
        .background(.ultraThinMaterial)
        .onAppear {
            appState.refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionState()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showMicTest, onDismiss: {
            appState.stopMicTest()
        }) {
            MicTestView()
                .environmentObject(appState)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Voice Dictation")
                .font(.headline)
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            if appState.status == .recording && !reduceMotion {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Circle()
                    .fill(chipColor)
                    .frame(width: 6, height: 6)
            }
            Text(appState.status.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(chipColor.opacity(0.12))
                .overlay(Capsule().stroke(AppTheme.hairlineBorder, lineWidth: 1))
        )
        .accessibilityLabel("Status: \(appState.status.rawValue)")
    }

    private var chipColor: Color {
        switch appState.status {
        case .recording: return .red
        case .error: return .red
        case .enhancing: return AppTheme.accent
        default: return .secondary
        }
    }

    private var pasteAtCursorHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.accessibilityGranted ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(appState.accessibilityGranted ? "Paste at cursor is ready" : "Paste at cursor needs Accessibility")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Open Accessibility Settings") {
                PermissionHelper.openAccessibilitySettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open Accessibility Settings")
            if !appState.accessibilityGranted {
                Text("Turn Voice Dictation off, then on, in that list.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Primary Button

    private var micCheckButton: some View {
        Button("Check microphone") {
            showMicTest = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.status == .recording || appState.status == .transcribing)
        .accessibilityLabel("Check microphone")
    }

    private var primaryButton: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack(spacing: 6) {
                Image(systemName: primaryButtonSymbol)
                Text(primaryButtonTitle)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(appState.status == .recording ? Color.red : AppTheme.accent)
        )
        .foregroundColor(appState.status == .recording ? .white : .black.opacity(0.85))
        .accessibilityLabel(primaryButtonTitle)
    }

    private var primaryButtonTitle: String {
        switch appState.status {
        case .recording: return "Stop"
        case .transcribing, .enhancing: return "Cancel"
        default: return "Start"
        }
    }

    private var primaryButtonSymbol: String {
        switch appState.status {
        case .recording: return "stop.fill"
        case .transcribing, .enhancing: return "xmark"
        default: return "waveform"
        }
    }

    private var undoButton: some View {
        Button("Undo last paste") {
            appState.undoLastPaste()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.status == .recording || appState.status == .transcribing || appState.status == .enhancing)
        .accessibilityLabel("Undo last paste")
    }

    // MARK: - Transcript Card

    @ViewBuilder
    private var transcriptCard: some View {
        if !appState.lastTranscript.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last transcript")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: copyTranscript) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(showCopiedFeedback ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showCopiedFeedback ? "Copied" : "Copy transcript")
                }
                Text(appState.lastTranscript)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.hairlineBorder, lineWidth: 1))
            )
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageArea: some View {
        if !appState.errorMessage.isEmpty {
            Text(appState.errorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !appState.statusMessage.isEmpty {
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Floating Toggle

    private var floatingToggle: some View {
        Toggle(isOn: Binding(
            get: { appState.showFloatingWindow },
            set: { newValue in
                appState.saveShowFloatingWindow(newValue)
            }
        )) {
            Text("Show floating bar")
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel("Show floating bar")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: openSettingsWithActivation) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")

            Button(action: { showHistory = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open history")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
            .accessibilityLabel("Quit Voice Dictation")
        }
    }

    // MARK: - Actions

    private func openSettingsWithActivation() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }
}
