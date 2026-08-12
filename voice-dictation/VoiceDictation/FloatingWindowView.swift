//
//  FloatingWindowView.swift
//  VoiceDictation
//
//  WisprFlow-inspired compact floating bar.
//  Small pill by default, expands on hover with action buttons:
//  Record/Stop, Copy, Create Note, Close.
//

import SwiftUI

struct FloatingWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered: Bool = false
    @State private var showCopiedAnimation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact bar (always visible) ──
            HStack(spacing: 8) {
                // Status indicator
                if appState.status == .recording {
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 2.5, height: 12)
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
                        .font(.system(size: 12))
                        .foregroundColor(appState.status == .error ? .red : .accentColor)
                }

                // Status text or live transcript
                if !appState.liveTranscript.isEmpty {
                    Text(appState.liveTranscript)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if appState.status == .enhancing {
                    Text("Enhancing...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !appState.lastTranscript.isEmpty {
                    Text(appState.lastTranscript)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Voice Dictation")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Action buttons (only show on hover) ──
                if isHovered {
                    HStack(spacing: 4) {
                        // Record / Stop button
                        Button(action: {
                            appState.toggleRecording()
                        }) {
                            Image(systemName: appState.status == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 12))
                                .foregroundColor(appState.status == .recording ? .red : .accentColor)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help(appState.status == .recording ? "Stop & Transcribe" : "Start Recording")
                        .disabled(appState.status == .transcribing || appState.status == .enhancing)

                        // Copy button with animation
                        Button(action: {
                            copyToClipboard(appState.lastTranscript)
                            triggerCopiedAnimation()
                        }) {
                            Image(systemName: showCopiedAnimation ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(showCopiedAnimation ? .green : .primary)
                                .frame(width: 24, height: 24)
                                .scaleEffect(showCopiedAnimation ? 1.3 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showCopiedAnimation)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy last transcript")
                        .disabled(appState.lastTranscript.isEmpty)

                        // Create Note button
                        Button(action: {
                            createNote()
                        }) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Create Note in Apple Notes")
                        .disabled(appState.lastTranscript.isEmpty)

                        // Close button
                        Button(action: {
                            FloatingWindowController.shared.hideWindow()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Close floating bar")
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // ── Expanded section (only on hover, shows transcript) ──
            if isHovered && (appState.status == .recording || !appState.lastTranscript.isEmpty || !appState.errorMessage.isEmpty) {
                Divider()
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 8) {
                    // Live transcript preview
                    if !appState.liveTranscript.isEmpty {
                        Text("Live Transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ScrollView {
                            Text(appState.liveTranscript)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }

                    // Last transcript
                    if appState.status == .idle && !appState.lastTranscript.isEmpty {
                        Text("Last Transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ScrollView {
                            Text(appState.lastTranscript)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }

                    // Error message
                    if !appState.errorMessage.isEmpty {
                        Text(appState.errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: isHovered ? 340 : 160)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(radius: 5)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Actions

    private func triggerCopiedAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCopiedAnimation = true
        }
        // Reset after 1.2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopiedAnimation = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func createNote() {
        guard !appState.lastTranscript.isEmpty else { return }
        let text = appState.lastTranscript
        let url = URL(string: "shortcuts://run-shortcut?name=Create%20Note&input=text&text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        if let url = url {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: copy to clipboard and open Notes
            copyToClipboard(text)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }
}