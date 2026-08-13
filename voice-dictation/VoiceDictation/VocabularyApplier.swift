//
//  VocabularyApplier.swift
//  VoiceDictation
//
//  Applies user vocabulary with word-aware matching. Escapes regex
//  metacharacters in both the pattern and the replacement template.
//

import Foundation

enum VocabularyApplier {
    static let maxItemLength = 80
    static let maxItems = 80
    static let minimumItemLength = 2

    static func apply(vocabulary: String, to text: String) -> String {
        let items = parse(vocabulary)
        guard !items.isEmpty else { return text }

        var result = text
        for item in items {
            result = replace(item, in: result)
        }
        return result
    }

    static func parse(_ vocabulary: String) -> [String] {
        var seen = Set<String>()
        var items: [String] = []

        for line in vocabulary.split(separator: "\n", omittingEmptySubsequences: true) {
            let item = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.count >= minimumItemLength, item.count <= maxItemLength else { continue }
            guard item.contains(where: { $0.isLetter || $0.isNumber }) else { continue }

            let key = item.lowercased()
            guard seen.insert(key).inserted else { continue }
            items.append(item)
            if items.count >= maxItems { break }
        }

        return items.sorted { $0.count > $1.count }
    }

    private static func replace(_ item: String, in text: String) -> String {
        var result = text
        let replacement = NSRegularExpression.escapedTemplate(for: item)

        for pattern in patterns(for: item) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    private static func patterns(for item: String) -> [String] {
        var patterns: [String] = []
        if let exact = boundedPattern(literal: item) {
            patterns.append(exact)
        }

        guard item.contains(where: { $0.isWhitespace }) else { return patterns }

        let escaped = NSRegularExpression.escapedPattern(for: item)
        let spaced = escaped.replacingOccurrences(of: "\\ ", with: "\\s+")
        if let spacedPattern = wrapBounds(spaced, raw: item) {
            patterns.append(spacedPattern)
        }

        let collapsed = item.filter { !$0.isWhitespace }
        if collapsed.count >= minimumItemLength, collapsed.lowercased() != item.lowercased(),
           let collapsedPattern = boundedPattern(literal: collapsed) {
            patterns.append(collapsedPattern)
        }

        return patterns
    }

    private static func boundedPattern(literal: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: literal)
        guard !escaped.isEmpty else { return nil }
        return wrapBounds(escaped, raw: literal)
    }

    /// Avoids `\b`, which fails on punctuation and many Unicode letters.
    private static func wrapBounds(_ escapedBody: String, raw: String) -> String? {
        guard let first = raw.first, let last = raw.last else { return nil }
        let prefix = (first.isLetter || first.isNumber) ? "(?<![\\p{L}\\p{N}])" : ""
        let suffix = (last.isLetter || last.isNumber) ? "(?![\\p{L}\\p{N}])" : ""
        return "(?i)\(prefix)\(escapedBody)\(suffix)"
    }
}
