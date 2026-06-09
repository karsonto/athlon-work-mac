import Foundation

enum SemanticMessageScorer {
    private static let preserveScoreThreshold = 3

    static func score(_ message: ChatMessage) -> Int {
        if SummaryMessageBuilder.isSummaryMessage(message) {
            return -5
        }

        var result: Int
        switch message.role {
        case .user:
            result = 3
        case .tool:
            result = scoreToolMessage(message)
        default:
            result = 0
        }

        result += scorePathSignals(message.content)
        if !message.reasoningContent.isEmpty {
            result += scorePathSignals(message.reasoningContent)
        }
        return result
    }

    static func shouldPreserveInSummary(_ message: ChatMessage) -> Bool {
        score(message) >= preserveScoreThreshold
    }

    private static func scoreToolMessage(_ message: ChatMessage) -> Int {
        let content = message.content
        if content.localizedCaseInsensitiveContains("evicted/")
            || content.localizedCaseInsensitiveContains("Archived at:") {
            return 1
        }
        if content.localizedCaseInsensitiveContains("file_write")
            || content.localizedCaseInsensitiveContains("file_edit")
            || content.localizedCaseInsensitiveContains("execute_command") {
            return 2
        }
        return 0
    }

    private static func scorePathSignals(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        if text.localizedCaseInsensitiveContains(".cs")
            || text.localizedCaseInsensitiveContains(".tsx")
            || text.localizedCaseInsensitiveContains(".json")
            || text.contains("\\")
            || text.contains("/") {
            return 2
        }
        return 0
    }
}
