//
//  HistoryView.swift
//  VoiceDictation
//
//  Searchable transcript history accessible from menu bar.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var filteredHistory: [TranscriptEntry] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { entry in
            entry.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with Done button
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Close history")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcripts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search transcripts")
            }
            .padding(8)

            // History list
            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No transcripts yet" : "No results found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHistory) { entry in
                            HistoryRow(entry: entry) {
                                copyToClipboard(entry.text)
                            }
                            Divider()
                        }
                    }
                }
            }

            // Footer
            Divider()
            HStack {
                Text("\(appState.history.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear All") {
                    TranscriptHistory.shared.clearHistory()
                    appState.history = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Clear all history")
            }
            .padding(8)
        }
        .frame(width: 360, height: 400)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct HistoryRow: View {
    let entry: TranscriptEntry
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
                .accessibilityLabel("Copy transcript from \(entry.formattedTime)")
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
    }
}