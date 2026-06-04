import Foundation

struct TruncateArgsService {
    func applyIfNeeded(session: AgentSession, settings: ContextCompactionSettings) -> AgentSession {
        let (updated, changed) = applyToMessages(session.messages, settings: settings)
        return changed ? session.withMessages(updated) : session
    }

    func applyToMessages(
        _ messages: [ChatMessage],
        settings: ContextCompactionSettings,
        keepTokenBudgetOverride: Int? = nil
    ) -> (messages: [ChatMessage], changed: Bool) {
        let truncateSettings = settings.truncateArgs
        if !truncateSettings.enabled || messages.isEmpty {
            return (messages, false)
        }

        let conversation = messages.filter { $0.role != .compaction }
        if conversation.isEmpty {
            return (messages, false)
        }

        let estimatedTokens = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        if keepTokenBudgetOverride == nil || keepTokenBudgetOverride! <= 0 {
            if !ConversationCutoffPlanner.shouldTruncateArgs(
                conversation,
                estimatedTokens: estimatedTokens,
                settings: truncateSettings
            ) {
                return (messages, false)
            }
        }

        let cutoff: Int
        if let keepTokenBudgetOverride, keepTokenBudgetOverride > 0 {
            cutoff = ConversationCutoffPlanner.determineTruncateArgsCutoffFromKeepBudget(
                conversation,
                keepTokenBudget: keepTokenBudgetOverride,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
        } else {
            cutoff = ConversationCutoffPlanner.determineTruncateArgsCutoff(
                conversation,
                settings: truncateSettings,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
        }
        if cutoff >= conversation.count {
            return (messages, false)
        }

        var changed = false
        var updatedConversation: [ChatMessage] = []
        updatedConversation.reserveCapacity(conversation.count)

        for (index, message) in conversation.enumerated() {
            var current = message
            if index < cutoff,
               current.role == .assistant,
               let calls = AssistantToolCallsCodec.deserializeToolCalls(from: current),
               !calls.isEmpty {
                let truncatedCalls = truncateToolCalls(
                    calls,
                    maxArgLength: truncateSettings.maxArgLength,
                    truncationText: truncateSettings.truncationText
                )
                if truncatedCalls != calls {
                    current = AssistantToolCallsCodec.apply(calls: truncatedCalls, to: current)
                    changed = true
                }
            }
            updatedConversation.append(current)
        }

        if !changed {
            return (messages, false)
        }

        return (Self.mergeCompactionAudits(original: messages, conversation: updatedConversation), true)
    }

    static func mergeCompactionAudits(
        original: [ChatMessage],
        conversation: [ChatMessage]
    ) -> [ChatMessage] {
        let audits = original.filter { $0.role == .compaction }
        return audits.isEmpty ? conversation : audits + conversation
    }

    private func truncateToolCalls(
        _ calls: [CompactionToolCallRecord],
        maxArgLength: Int,
        truncationText: String
    ) -> [CompactionToolCallRecord] {
        calls.map { call in
            CompactionToolCallRecord(
                id: call.id,
                name: call.name,
                arguments: truncateArguments(call.arguments, maxArgLength: maxArgLength, truncationText: truncationText)
            )
        }
    }

    private func truncateArguments(
        _ arguments: [String: String],
        maxArgLength: Int,
        truncationText: String
    ) -> [String: String] {
        guard !arguments.isEmpty else { return arguments }

        var changed = false
        var updated: [String: String] = [:]
        for (key, value) in arguments {
            let truncated = truncateArgumentValue(value, maxArgLength: maxArgLength, truncationText: truncationText)
            if truncated != value { changed = true }
            updated[key] = truncated
        }
        return changed ? updated : arguments
    }

    private func truncateArgumentValue(
        _ value: String,
        maxArgLength: Int,
        truncationText: String
    ) -> String {
        if value.count <= maxArgLength { return value }

        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = value.data(using: .utf8),
               var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               truncateJsonObject(&object, maxArgLength: maxArgLength, truncationText: truncationText),
               let updatedData = try? JSONSerialization.data(withJSONObject: object),
               let updated = String(data: updatedData, encoding: .utf8) {
                return updated
            }
        }

        return truncateStringArg(value, maxArgLength: maxArgLength, truncationText: truncationText)
    }

    private func truncateJsonObject(
        _ object: inout [String: Any],
        maxArgLength: Int,
        truncationText: String
    ) -> Bool {
        var changed = false
        for key in object.keys {
            guard let value = object[key] else { continue }
            if let text = value as? String {
                let truncated = truncateStringArg(text, maxArgLength: maxArgLength, truncationText: truncationText)
                if truncated != text {
                    object[key] = truncated
                    changed = true
                }
            } else if var nested = value as? [String: Any],
                      truncateJsonObject(&nested, maxArgLength: maxArgLength, truncationText: truncationText) {
                object[key] = nested
                changed = true
            }
        }
        return changed
    }

    private func truncateStringArg(
        _ value: String,
        maxArgLength: Int,
        truncationText: String
    ) -> String {
        if value.count <= maxArgLength { return value }
        let prefixLength = min(20, value.count)
        return String(value.prefix(prefixLength)) + truncationText
    }
}
