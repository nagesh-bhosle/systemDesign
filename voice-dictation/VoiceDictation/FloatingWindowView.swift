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
        HStack(spacing: 8) {
            // Status indicator (always visible — the mic icon)
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

            // Status text or live transcript (only when hovered or recording)
            if isHovered || appState.status == .recording || appState.status == .enhancing {
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
                } else {
                    Text("Voice Dictation")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // ── Action buttons (visible on hover) ──
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
        .padding(.horizontal, isHovered || appState.status == .recording || appState.status == .enhancing ? 10 : 8)
        .padding(.vertical, 7)
        .frame(
            width: isHovered ? 340 : (appState.status == .recording || appState.status == .enhancing ? 200 : 36),
            height: 40
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .cornerRadius(14)
        .shadow(radius: 5)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            FloatingWindowController.shared.resizePanel(isHovered: hovering)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("📋 Copied to clipboard: \(text.prefix(50))...")
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