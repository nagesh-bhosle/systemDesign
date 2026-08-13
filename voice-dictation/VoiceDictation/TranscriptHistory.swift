//
//  TranscriptHistory.swift
//  VoiceDictation
//
//  Local persistence of past dictations (encrypted on disk).
//

import Foundation
import CryptoKit
import os

struct TranscriptEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    var isPinned: Bool

    init(text: String, timestamp: Date, isPinned: Bool = false) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let fileURL: URL
    private let appDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("VoiceDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.appDir = appDir
        self.fileURL = appDir.appendingPathComponent("history.json")
        excludeFromBackup(url: appDir)
        excludeFromBackup(url: fileURL)
    }

    func loadHistory(retentionDays: Int = 0) -> [TranscriptEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entries: [TranscriptEntry]

            if let plaintext = try? decoder.decode([TranscriptEntry].self, from: data) {
                entries = plaintext
                saveHistory(applyRetention(plaintext, retentionDays: retentionDays))
            } else {
                entries = try decryptEntries(from: data)
                let pruned = applyRetention(entries, retentionDays: retentionDays)
                if pruned.count != entries.count {
                    saveHistory(pruned)
                }
            }

            return sortEntries(applyRetention(entries, retentionDays: retentionDays))
        } catch {
            logger.warning("Failed to load history")
            return []
        }
    }

    func saveHistory(_ entries: [TranscriptEntry], retentionDays: Int = 0) {
        let sorted = sortEntries(applyRetention(entries, retentionDays: retentionDays))
        do {
            let plaintext = try encoder.encode(sorted)
            guard let key = KeychainHelper.shared.loadOrCreateHistoryKey() else {
                logger.warning("History encryption key unavailable — skipping save")
                return
            }
            let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
            guard let combined = sealed.combined else {
                logger.warning("Failed to seal history data")
                return
            }
            try combined.write(to: fileURL, options: .atomic)
            excludeFromBackup(url: fileURL)
        } catch {
            logger.warning("Failed to save history")
        }
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func applyRetention(_ entries: [TranscriptEntry], retentionDays: Int) -> [TranscriptEntry] {
        guard retentionDays > 0 else { return entries }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        return entries.filter { $0.isPinned || $0.timestamp >= cutoff }
    }

    func sortEntries(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    // MARK: - Private

    private func decryptEntries(from data: Data) throws -> [TranscriptEntry] {
        guard let key = KeychainHelper.shared.loadHistoryKey() else {
            throw NSError(domain: "TranscriptHistory", code: 1)
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
        return try decoder.decode([TranscriptEntry].self, from: plaintext)
    }

    private func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }
}
