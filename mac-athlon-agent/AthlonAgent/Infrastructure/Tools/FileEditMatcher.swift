import Foundation

enum FileEditMatcher {
    enum MatchStatus {
        case found
        case notFound
        case notUnique
    }

    enum CandidateKind {
        case exact
        case strippedLinePrefixes
        case crlfNormalized
        case strippedLinePrefixesCrlf
    }

    struct MatchResult {
        let status: MatchStatus
        let matchedOldText: String
        let originalOldText: String
        let kind: CandidateKind
        let occurrences: Int
    }

    static func tryMatch(content: String, oldText: String, replaceAll: Bool) -> MatchResult {
        for candidate in enumerateOldTextCandidates(content: content, oldText: oldText) {
            let occurrences = countOccurrences(in: content, of: candidate.text)
            if occurrences == 0 { continue }
            if !replaceAll && occurrences != 1 {
                return MatchResult(
                    status: .notUnique,
                    matchedOldText: candidate.text,
                    originalOldText: oldText,
                    kind: candidate.kind,
                    occurrences: occurrences
                )
            }
            return MatchResult(
                status: .found,
                matchedOldText: candidate.text,
                originalOldText: oldText,
                kind: candidate.kind,
                occurrences: occurrences
            )
        }
        return MatchResult(status: .notFound, matchedOldText: oldText, originalOldText: oldText, kind: .exact, occurrences: 0)
    }

    static func applyReplace(content: String, matchedOldText: String, newText: String, replaceAll: Bool) -> String {
        if replaceAll {
            return content.replacingOccurrences(of: matchedOldText, with: newText)
        }
        guard let range = content.range(of: matchedOldText) else { return content }
        return content.replacingCharacters(in: range, with: newText)
    }

    static func resolveNewText(originalOldText: String, originalNewText: String, match: MatchResult) -> String {
        switch match.kind {
        case .exact: return originalNewText
        case .strippedLinePrefixes: return stripFileReadLinePrefixes(originalNewText)
        case .crlfNormalized: return toCRLF(originalNewText)
        case .strippedLinePrefixesCrlf: return toCRLF(stripFileReadLinePrefixes(originalNewText))
        }
    }

    static func buildNotFoundMessage(_ oldText: String) -> String {
        var message = "old_text did not match the file on disk."
        if oldText.range(of: #"^\d+\|"#, options: .regularExpression, range: nil, locale: nil) != nil {
            message += " Remove file_read line-number prefixes (N|) from old_text."
        } else {
            message += " Copy exact text from the file (not from file_read's N|line format or grep path:line: output)."
        }
        message += " Check whitespace, indentation, and line endings (CRLF vs LF)."
        return message
    }

    private struct Candidate {
        let text: String
        let kind: CandidateKind
    }

    private static func enumerateOldTextCandidates(content: String, oldText: String) -> [Candidate] {
        var results: [Candidate] = [Candidate(text: oldText, kind: .exact)]
        let stripped = stripFileReadLinePrefixes(oldText)
        if stripped != oldText {
            results.append(Candidate(text: stripped, kind: .strippedLinePrefixes))
        }
        guard content.contains("\r") else { return results }

        let crlf = toCRLF(oldText)
        if crlf != oldText {
            results.append(Candidate(text: crlf, kind: .crlfNormalized))
        }
        if stripped != oldText {
            let strippedCrlf = toCRLF(stripped)
            if strippedCrlf != stripped && strippedCrlf != crlf {
                results.append(Candidate(text: strippedCrlf, kind: .strippedLinePrefixesCrlf))
            }
        }
        return results
    }

    static func stripFileReadLinePrefixes(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var changed = false
        for index in lines.indices {
            if let range = lines[index].range(of: #"^\d+\|"#, options: .regularExpression) {
                lines[index] = String(lines[index][range.upperBound...])
                changed = true
            }
        }
        guard changed else { return text }
        let joined = lines.joined(separator: "\n")
        return text.contains("\r\n") ? joined.replacingOccurrences(of: "\n", with: "\r\n") : joined
    }

    private static func toCRLF(_ text: String) -> String {
        text.contains("\r\n") ? text : text.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private static func countOccurrences(in content: String, of needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<content.endIndex
        }
        return count
    }
}

enum AtomicFile {
    static func backupIfExists(_ path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        try? fm.copyItem(atPath: path, toPath: path + ".bak")
    }

    static func writeText(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = path + ".tmp"
        try content.write(toFile: temp, atomically: true, encoding: .utf8)
        backupIfExists(path)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.moveItem(atPath: temp, toPath: path)
    }
}
