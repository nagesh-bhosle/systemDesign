//
//  TempRecordingCleanup.swift
//  VoiceDictation
//
//  Removes leftover voicedictation-*.caf files from NSTemporaryDirectory.
//

import Foundation
import os

enum TempRecordingCleanup {
    private static let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "TempCleanup")

    static func purgeOrphanedFiles() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in items {
            let name = url.lastPathComponent
            guard url.pathExtension.lowercased() == "caf",
                  name.hasPrefix("voicedictation") else { continue }
            do {
                try fm.removeItem(at: url)
            } catch {
                logger.debug("Could not delete temp recording \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
