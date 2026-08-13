//
//  HistoryView.swift
//  VoiceDictation
//
//  Searchable transcript history.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)? = nil
    @State private var searchText: String = ""
    @State private var showClearConfirmation = false
    @State private var copiedEntryID: UUID?

    var filteredHistory: [TranscriptEntry] {
        let base = appState.history
        if searchText.isEmpty {
            return base
        }
        return base.filter { entry in
            entry.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcripts", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search transcripts")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(Capsule(style: .continuous).stroke(AppTheme.hairlineBorder, lineWidth: 1))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if filteredHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredHistory) { entry in
                            HistoryRow(
                                entry: entry,
                                isCopied: copiedEntryID == entry.id,
                                onCopy: { copyEntry(entry) },
                                onPaste: { appState.pasteHistoryEntry(entry) },
                                onTogglePin: { appState.togglePinHistoryEntry(entry) },
                                onDelete: { appState.deleteHistoryEntry(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 440)
        .background(.ultraThinMaterial)
        .alert("Clear All History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all \(appState.history.count) transcript entries.")
        }
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Button("Done") { close() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.accent)
                .accessibilityLabel("Close history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(AppTheme.accent.opacity(0.7))
            Text(searchText.isEmpty ? "No transcripts yet" : "No results found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Your dictations will appear here")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(appState.history.count) total")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear All") {
                showClearConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.history.isEmpty)
            .accessibilityLabel("Clear all history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copyEntry(_ entry: TranscriptEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntryID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }
}

struct HistoryRow: View {
    let entry: TranscriptEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(AppTheme.accent)
                }
                Text(entry.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onPaste) {
                    Image(systemName: "text.cursor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Paste at cursor")
                .accessibilityLabel("Paste at cursor")

                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy transcript")

                Button(action: onTogglePin) {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isPinned ? "Unpin transcript" : "Pin transcript")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete transcript")
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            AppTheme.cardShape()
                .fill(AppTheme.cardBackground)
                .overlay(AppTheme.cardShape().stroke(AppTheme.hairlineBorder, lineWidth: 1))
        )
        .overlay(alignment: .leading) {
            if entry.isPinned {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.accent)
                    .frame(width: 2)
                    .padding(.vertical, 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .accessibilityLabel("Transcript from \(entry.relativeTime)")
    }
}
