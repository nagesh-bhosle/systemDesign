//
//  TranscriptHistory.swift
//  VoiceDictation
//
//  Local persistence of past dictations.
//  Stores up to 100 entries as JSON in Application Support (not UserDefaults).
//

import Foundation
import os

struct TranscriptEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var formattedTime: String {
        Self.dateFormatter.string(from: timestamp)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

final class TranscriptHistory {
    static let shared = TranscriptHistory()

    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TranscriptHistory")

    // Issue #27: Static encoder/decoder instances
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Issue #18: Use file-based storage in Application Support instead of UserDefaults
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("VoiceDictation", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.fileURL = appDir.appendingPathComponent("history.json")
    }

    func loadHistory() -> [TranscriptEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([TranscriptEntry].self, from: data)
        } catch {
            logger.warning("Failed to load history: \(error.localizedDescription)")
            return []
        }
    }

    func saveHistory(_ entries: [TranscriptEntry]) {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("Failed to save history: \(error.localizedDescription)")
        }
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func deleteEntry(id: UUID, from entries: [TranscriptEntry]) -> [TranscriptEntry] {
        let updated = entries.filter { $0.id != id }
        saveHistory(updated)
        return updated
    }
}