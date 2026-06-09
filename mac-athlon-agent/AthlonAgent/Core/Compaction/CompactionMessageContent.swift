import Foundation

enum CompactionMessageContent {
    static let compressedTranscriptPrefix = "[Compressed. Transcript:"

    static func isCompressedPlaceholder(_ content: String) -> Bool {
        content.hasPrefix(compressedTranscriptPrefix)
    }

    static func createConversationCompact(
        tokensBefore: Int,
        tokensAfter: Int,
        originalMessageCount: Int,
        transcriptPath: String?,
        summaryPreview: String,
        strategy: CompactionStrategy = .conversationCompact,
        layers: [CompactionLayer]? = nil,
        pressureLevel: ContextPressureLevel? = nil,
        utilization: Double? = nil
    ) -> String {
        let summary: String
        if summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "已将 \(originalMessageCount) 条消息压缩为摘要并保留最近上下文。"
        } else {
            summary = summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return build(
            kind: .conversationCompact,
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            summary: summary,
            strategy: strategy,
            layers: layers,
            originalMessageCount: originalMessageCount,
            transcriptPath: transcriptPath,
            pressureLevel: pressureLevel,
            utilization: utilization
        )
    }

    static func isSummaryPlaceholder(_ content: String) -> Bool {
        content.hasPrefix(ConversationCompactionDefaults.summaryMessageMarker)
            || isCompressedPlaceholder(content)
    }

    static func createMicrocompact(
        tokensBefore: Int,
        tokensAfter: Int,
        clearedToolMessages: Int,
        keepToolMessages: Int
    ) -> String {
        let summary = "已清理 \(clearedToolMessages) 条较早的工具输出，保留最近 \(keepToolMessages) 条完整内容。"
        return build(
            kind: .microcompact,
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            summary: summary,
            clearedToolMessages: clearedToolMessages,
            keepToolMessages: keepToolMessages
        )
    }

    static func createAutoCompact(
        tokensBefore: Int,
        tokensAfter: Int,
        originalMessageCount: Int,
        transcriptPath: String,
        summaryPreview: String
    ) -> String {
        let summary: String
        if summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "已将 \(originalMessageCount) 条消息压缩为摘要。"
        } else {
            summary = summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return build(
            kind: .autoCompact,
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            summary: summary,
            originalMessageCount: originalMessageCount,
            transcriptPath: transcriptPath
        )
    }

    static func createManualCompact(
        tokensBefore: Int,
        tokensAfter: Int,
        originalMessageCount: Int,
        transcriptPath: String,
        summaryPreview: String,
        layers: [CompactionLayer]? = [.conversationCompact],
        pressureLevel: ContextPressureLevel? = nil,
        utilization: Double? = nil
    ) -> String {
        let summary: String
        if summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "已手动压缩 \(originalMessageCount) 条消息。"
        } else {
            summary = summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return build(
            kind: .manualCompact,
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
            summary: summary,
            strategy: .manualCompact,
            layers: layers,
            originalMessageCount: originalMessageCount,
            transcriptPath: transcriptPath,
            pressureLevel: pressureLevel,
            utilization: utilization
        )
    }

    static func createCompactionMessage(_ content: String, parentId: String? = nil) -> ChatMessage {
        ChatMessage(role: .compaction, content: content, parentMessageId: parentId)
    }

    private static func build(
        kind: CompactionKind,
        tokensBefore: Int,
        tokensAfter: Int,
        summary: String,
        strategy: CompactionStrategy? = nil,
        layers: [CompactionLayer]? = nil,
        clearedToolMessages: Int? = nil,
        keepToolMessages: Int? = nil,
        originalMessageCount: Int? = nil,
        transcriptPath: String? = nil,
        pressureLevel: ContextPressureLevel? = nil,
        utilization: Double? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("CompactionKind: \(kind.rawValue.lowercased())")
        if let strategy {
            lines.append("CompactionStrategy: \(CompactionAuditDisplay.formatStrategy(strategy))")
        }
        if let layers, !layers.isEmpty {
            lines.append("CompactionLayers: \(CompactionAuditDisplay.formatLayers(layers))")
        }
        lines.append("TokensBefore: \(tokensBefore)")
        lines.append("TokensAfter: \(tokensAfter)")

        if let clearedToolMessages {
            lines.append("ClearedToolMessages: \(clearedToolMessages)")
        }
        if let keepToolMessages {
            lines.append("KeepToolMessages: \(keepToolMessages)")
        }
        if let originalMessageCount {
            lines.append("OriginalMessageCount: \(originalMessageCount)")
        }
        if let transcriptPath, !transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("TranscriptPath: \(transcriptPath)")
        }
        if let pressureLevel {
            lines.append("ContextPressure: \(pressureLevel.rawValue)")
        }
        if let utilization {
            lines.append(String(format: "ContextUtilization: %.3f", utilization))
        }

        lines.append("")
        lines.append("Summary: \(summary)")
        return lines.joined(separator: "\n")
    }
}
