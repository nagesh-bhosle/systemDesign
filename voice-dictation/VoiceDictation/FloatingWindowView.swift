//
//  FloatingWindowView.swift
//  VoiceDictation
//
//  WisprFlow-inspired compact floating bar.
//  Transparent pill that floats above all windows with action buttons:
//  Record/Stop, Copy, Create Note, Expand, Close.
//

import SwiftUI

struct FloatingWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Compact bar (always visible) ──
            HStack(spacing: 10) {
                // Status indicator
                if appState.status == .recording {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 3, height: 14)
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
                        .font(.system(size: 14))
                        .foregroundColor(appState.status == .error ? .red : .accentColor)
                }

                // Status text or live transcript
                if !appState.liveTranscript.isEmpty {
                    Text(appState.liveTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if appState.status == .enhancing {
                    Text("Enhancing...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !appState.lastTranscript.isEmpty {
                    Text(appState.lastTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Voice Dictation")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Action buttons ──
                HStack(spacing: 6) {
                    // Record / Stop button
                    Button(action: {
                        appState.toggleRecording()
                    }) {
                        Image(systemName: appState.status == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(appState.status == .recording ? .red : .accentColor)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(appState.status == .recording ? "Stop & Transcribe" : "Start Recording")
                    .disabled(appState.status == .transcribing || appState.status == .enhancing)

                    // Copy button
                    Button(action: {
                        copyToClipboard(appState.lastTranscript)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy last transcript")
                    .disabled(appState.lastTranscript.isEmpty)

                    // Create Note button
                    Button(action: {
                        createNote()
                    }) {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Create Note in Apple Notes")
                    .disabled(appState.lastTranscript.isEmpty)

                    // Expand/collapse button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Hide details" : "Show details")

                    // Close button
                    Button(action: {
                        FloatingWindowController.shared.hideWindow()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Close floating bar")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── Expanded section ──
            if isExpanded {
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

                        // Action row
                        HStack(spacing: 8) {
                            Button(action: {
                                copyToClipboard(appState.lastTranscript)
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(action: {
                                createNote()
                            }) {
                                Label("Note", systemImage: "note.text")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(action: {
                                appState.toggleRecording()
                            }) {
                                Label("Record", systemImage: "mic.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()
                        }
                    }

                    // Error message
                    if !appState.errorMessage.isEmpty {
                        Text(appState.errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 6)
        .onReceive(NotificationCenter.default.publisher(for: .toggleDictation)) { _ in
            appState.toggleRecording()
        }
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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