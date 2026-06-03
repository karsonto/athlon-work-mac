import Foundation

enum SummaryMessageBuilder {
    static func createSummaryPlaceholder(summaryText: String, transcriptPath: String?) -> ChatMessage {
        ChatMessage(
            role: .user,
            content: buildSummaryContent(summaryText: summaryText, transcriptPath: transcriptPath)
        )
    }

    static func isSummaryMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .user else { return false }
        return message.content.contains(ConversationCompactionDefaults.summaryMessageMarker)
            || CompactionMessageContent.isCompressedPlaceholder(message.content)
    }

    static func filterSummaryMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { !isSummaryMessage($0) }
    }

    private static func buildSummaryContent(summaryText: String, transcriptPath: String?) -> String {
        let trimmedSummary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let transcriptPath, !transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            You are in the middle of a conversation that has been summarized.

            The full conversation history has been saved to \(transcriptPath) should you need to refer back to it for details.

            A condensed summary follows:

            <summary>
            \(trimmedSummary)
            </summary>

            \(ConversationCompactionDefaults.summaryMessageMarker)
            """
        }

        return """
        \(ConversationCompactionDefaults.summaryMessageMarker)
        Here is a summary of the conversation to date:

        \(trimmedSummary)
        """
    }
}
