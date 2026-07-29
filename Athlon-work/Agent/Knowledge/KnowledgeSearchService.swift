import Foundation

nonisolated struct KnowledgeSearchHit: Sendable, Hashable {
    var documentId: String
    var title: String
    var sourcePath: String
    var score: Double
    var snippet: String
}

/// Keyword search over extracted knowledge text (parity-lite; no embeddings yet).
nonisolated final class KnowledgeSearchService: @unchecked Sendable {
    private let store: KnowledgeStore

    init(store: KnowledgeStore) {
        self.store = store
    }

    func search(query: String, settings: KnowledgeSearchSettings) throws -> [KnowledgeSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokens = trimmed.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        let index = try store.loadIndex()
        var hits: [KnowledgeSearchHit] = []

        for doc in index.documents {
            guard let text = try? store.loadExtractedText(documentId: doc.id) else { continue }
            let lower = text.lowercased()
            var score = 0.0
            for token in tokens {
                if lower.contains(token) {
                    score += 1.0
                    // Bonus for title match.
                    if doc.title.lowercased().contains(token) { score += 0.5 }
                }
            }
            let normalized = score / Double(tokens.count)
            guard normalized >= settings.minScore else { continue }
            let snippet = makeSnippet(text: text, tokens: tokens, maxChars: settings.maxContentCharsPerHit)
            hits.append(
                KnowledgeSearchHit(
                    documentId: doc.id,
                    title: doc.title,
                    sourcePath: doc.sourcePath,
                    score: normalized,
                    snippet: snippet
                )
            )
        }

        return Array(
            hits.sorted { $0.score > $1.score }.prefix(max(1, settings.topK))
        )
    }

    private func makeSnippet(text: String, tokens: [String], maxChars: Int) -> String {
        let lower = text.lowercased()
        var bestRange: Range<String.Index>?
        for token in tokens {
            if let r = lower.range(of: token) {
                bestRange = r
                break
            }
        }
        let start: String.Index
        if let r = bestRange {
            start = text.index(r.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        } else {
            start = text.startIndex
        }
        let end = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}
