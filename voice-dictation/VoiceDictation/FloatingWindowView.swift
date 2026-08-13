//
//  FloatingWindowView.swift
//  VoiceDictation
//
//  Compact floating bar — idle orb, expands when active or hovered.
//

import SwiftUI

struct FloatingWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false
    @State private var showCopiedAnimation: Bool = false

    private var isExpanded: Bool {
        isHovered || appState.status == .recording || appState.status == .enhancing || appState.status == .transcribing
    }

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator

            if isExpanded {
                expandedContent
                if isHovered {
                    actionButtons
                }
            }
        }
        .padding(.horizontal, isExpanded ? 12 : 0)
        .padding(.vertical, isExpanded ? 8 : 0)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(AppTheme.hairlineBorder, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                isHovered = hovering
            }
            updatePanelSize()
        }
        .onChange(of: appState.status) { _, _ in
            updatePanelSize()
        }
        .onChange(of: isHovered) { _, _ in
            updatePanelSize()
        }
        .onAppear {
            updatePanelSize()
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var statusIndicator: some View {
        if appState.status == .recording {
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let floor: CGFloat = 0.25
                    let scale = reduceMotion
                        ? 0.6
                        : floor + CGFloat(appState.audioLevel) * (0.4 + CGFloat(index % 3) * 0.15)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 2.5, height: 10)
                        .scaleEffect(y: scale)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: appState.audioLevel)
                }
            }
            .frame(width: isExpanded ? nil : 36, height: 36)
        } else {
            Image(systemName: appState.statusIcon)
                .font(.system(size: 14))
                .foregroundColor(appState.status == .error ? .red : AppTheme.accent)
                .frame(width: 36, height: 36)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if appState.status == .recording {
            HStack(spacing: 8) {
                Text(appState.recordingDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if !appState.liveTranscript.isEmpty {
                    Text(appState.liveTranscript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !appState.liveTranscript.isEmpty {
            Text(appState.liveTranscript)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if appState.status == .enhancing {
            Text("Enhancing...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if appState.status == .transcribing {
            Text("Transcribing...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Voice Dictation")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: { appState.toggleRecording() }) {
                Image(systemName: appState.status == .recording ? "stop.fill" : "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(appState.status == .recording ? .red : AppTheme.accent)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(appState.status == .transcribing || appState.status == .enhancing)
            .accessibilityLabel(appState.status == .recording ? "Stop recording" : "Start recording")

            Button(action: {
                copyToClipboard(appState.lastTranscript)
                triggerCopiedAnimation()
            }) {
                Image(systemName: showCopiedAnimation ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(showCopiedAnimation ? .green : .primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(appState.lastTranscript.isEmpty)
            .accessibilityLabel("Copy last transcript")

            Button(action: { copyAndOpenNotes() }) {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(appState.lastTranscript.isEmpty)
            .help("Copy & Open Notes")
            .accessibilityLabel("Copy and open Notes")

            Button(action: closeFloatingBar) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close floating bar")
        }
    }

    // MARK: - Actions

    private func updatePanelSize() {
        let width: CGFloat = isExpanded ? 300 : 36
        FloatingWindowController.shared.resizePanel(width: width)
    }

    private func closeFloatingBar() {
        appState.saveShowFloatingWindow(false)
        FloatingWindowController.shared.hideWindow()
    }

    private func triggerCopiedAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCopiedAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCopiedAnimation = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAndOpenNotes() {
        guard !appState.lastTranscript.isEmpty else { return }
        copyToClipboard(appState.lastTranscript)
        if let url = URL(string: "mobilenotes://") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }
}
