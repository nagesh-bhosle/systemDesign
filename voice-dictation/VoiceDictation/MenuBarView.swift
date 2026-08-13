//
//  MenuBarView.swift
//  VoiceDictation
//
//  Menu bar dropdown UI.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(spacing: 12) {
            header
            pasteAtCursorHelp
            primaryButton
            transcriptionHint
            transcriptCard
            messageArea
            secondaryRow
            footer
        }
        .padding(16)
        .frame(width: AppTheme.menuWidth)
        .background {
            ZStack {
                Color.black.opacity(0.18)
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .onAppear {
            appState.refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionState()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIconRenderer.makeTemplateImage())
                .renderingMode(.template)
                .foregroundColor(AppTheme.accent)
                .frame(width: 18, height: 18)
            Text("Voice Dictation")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            if appState.status == .recording && !reduceMotion {
                Circle()
                    .fill(AppTheme.recording)
                    .frame(width: 6, height: 6)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Circle()
                    .fill(chipColor)
                    .frame(width: 6, height: 6)
            }
            Text(appState.status.rawValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(chipColor.opacity(0.14))
                .overlay(Capsule().stroke(AppTheme.hairlineBorder, lineWidth: 1))
        )
        .accessibilityLabel("Status: \(appState.status.rawValue)")
    }

    private var chipColor: Color {
        switch appState.status {
        case .recording: return AppTheme.recording
        case .error: return AppTheme.recording
        case .enhancing, .transcribing: return AppTheme.accent
        default: return .secondary
        }
    }

    private var pasteAtCursorHelp: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.accessibilityGranted ? AppTheme.success : AppTheme.accent)
                .frame(width: 7, height: 7)
            Text(appState.accessibilityGranted ? "Paste at cursor ready" : "Accessibility needed to paste")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Fix") {
                PermissionHelper.openAccessibilitySettings()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundColor(AppTheme.accent)
            .accessibilityLabel("Open Accessibility Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(Capsule(style: .continuous).stroke(AppTheme.hairlineBorder, lineWidth: 1))
        )
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack(spacing: 8) {
                Image(systemName: primaryButtonSymbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(primaryButtonTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(appState.status == .recording ? AppTheme.recording : AppTheme.accent)
        )
        .foregroundColor(appState.status == .recording ? .white : .black.opacity(0.85))
        .accessibilityLabel(primaryButtonTitle)
    }

    @ViewBuilder
    private var transcriptionHint: some View {
        if appState.status == .recording {
            Text("Words appear after you press Stop.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if appState.status == .transcribing {
            Text("Transcribing after you stop… longer takes can take a minute.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    // MARK: - Transcript Card

    @ViewBuilder
    private var transcriptCard: some View {
        if !appState.lastTranscript.isEmpty {
            ThemeCard(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Last transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: copyTranscript) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(showCopiedFeedback ? AppTheme.success : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showCopiedFeedback ? "Copied" : "Copy transcript")
                    }
                    Text(appState.lastTranscript)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageArea: some View {
        if !appState.errorMessage.isEmpty {
            Text(appState.errorMessage)
                .font(.caption)
                .foregroundColor(AppTheme.recording)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !appState.statusMessage.isEmpty {
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            Button("Check mic") {
                MicTestWindowController.shared.show(appState: appState)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .disabled(appState.status == .recording || appState.status == .transcribing)
            .accessibilityLabel("Check microphone")

            Text("·")
                .foregroundColor(.secondary.opacity(0.5))

            Button("Undo paste") {
                appState.undoLastPaste()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .disabled(appState.status == .recording || appState.status == .transcribing || appState.status == .enhancing)
            .accessibilityLabel("Undo last paste")

            Spacer()

            Toggle(isOn: Binding(
                get: { appState.showFloatingWindow },
                set: { appState.saveShowFloatingWindow($0) }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel("Show floating bar")
            .help("Show floating bar")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            footerIconButton(symbol: "gearshape", label: "Open settings") {
                AppPanels.showSettings(appState: appState)
            }
            footerIconButton(symbol: "clock.arrow.circlepath", label: "Open history") {
                AppPanels.showHistory(appState: appState)
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
            .accessibilityLabel("Quit Voice Dictation")
        }
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.hairlineBorder)
                .frame(height: 1)
        }
    }

    private func footerIconButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
