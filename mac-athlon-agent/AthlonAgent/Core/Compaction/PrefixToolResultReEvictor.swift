import Foundation

enum PrefixToolResultReEvictor {
    static func apply(
        messages: [ChatMessage],
        settings: ContextCompactionSettings,
        prefixCutoffExclusive: Int
    ) -> (messages: [ChatMessage], changed: Bool) {
        if prefixCutoffExclusive <= 0 {
            return (messages, false)
        }

        let previewChars = max(256, settings.toolResultEviction.previewChars / 2)
        var changed = false
        var updated: [ChatMessage] = []
        updated.reserveCapacity(messages.count)

        for (index, message) in messages.enumerated() {
            var current = message
            if index >= prefixCutoffExclusive
                || current.role != .tool
                || !isEvictedPlaceholder(current.content) {
                updated.append(current)
                continue
            }

            let tightened = tightenPreview(current.content, previewChars: previewChars)
            if tightened != current.content {
                current.content = tightened
                changed = true
            }
            updated.append(current)
        }

        return changed ? (updated, true) : (messages, false)
    }

    private static func isEvictedPlaceholder(_ content: String) -> Bool {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return content.localizedCaseInsensitiveContains("[Tool result evicted")
    }

    private static func tightenPreview(_ content: String, previewChars: Int) -> String {
        let marker = "Preview:"
        guard let range = content.range(of: marker, options: .caseInsensitive) else {
            if content.count <= previewChars * 3 { return content }
            return String(content.prefix(min(content.count, previewChars * 3))) + "\n...(preview tightened)"
        }

        let head = String(content[..<range.upperBound])
        var preview = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count <= previewChars * 2 { return content }

        let shortened = String(preview.prefix(previewChars)) + "\n...\n" + String(preview.suffix(previewChars))
        return head + "\n" + shortened
    }
}
