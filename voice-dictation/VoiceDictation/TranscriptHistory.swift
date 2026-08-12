//
//  TranscriptHistory.swift
//  VoiceDictation
//
//  Local persistence of past dictations.
//  Stores up to 100 entries in UserDefaults as JSON.
//

import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
    }

    // Issue #26: Use a static formatter instead of creating one per access
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var formattedTime: String {
        Self.dateFormatter.string(from: timestamp)
    }
}

final class TranscriptHistory {
    static let shared = TranscriptHistory()
    private let key = "voiceDictation.history"

    private init() {}

    func loadHistory() -> [TranscriptEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([TranscriptEntry].self, from: data)
        } catch {
            print("⚠️ Failed to load history: \(error)")
            return []
        }
    }

    func saveHistory(_ entries: [TranscriptEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("⚠️ Failed to save history: \(error)")
        }
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}