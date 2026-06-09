import Foundation

/// Drops redundant in-memory payloads after load (e.g. thumbnail data when a file path exists).
enum ChatMessageMemorySanitizer {
    static func sanitizeSession(_ session: AgentSession) -> AgentSession {
        guard !session.messages.isEmpty else { return session }
        var changed = false
        let sanitized = session.messages.map { message -> ChatMessage in
            let next = sanitizeMessage(message, changed: &changed)
            return next
        }
        guard changed else { return session }
        var updated = session
        updated.messages = sanitized
        return updated
    }

    static func sanitizeMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return messages }
        var changed = false
        let sanitized = messages.map { message -> ChatMessage in
            sanitizeMessage(message, changed: &changed)
        }
        return changed ? sanitized : messages
    }

    private static func sanitizeMessage(_ message: ChatMessage, changed: inout Bool) -> ChatMessage {
        guard let attachments = message.imageAttachments, !attachments.isEmpty else { return message }
        var attachmentsChanged = false
        let sanitizedAttachments = attachments.map { attachment -> ImageAttachment in
            let next = sanitizeImageAttachment(attachment)
            if next.thumbnailData != attachment.thumbnailData {
                attachmentsChanged = true
            }
            return next
        }
        guard attachmentsChanged else { return message }
        changed = true
        var updated = message
        updated.imageAttachments = sanitizedAttachments
        return updated
    }

    private static func sanitizeImageAttachment(_ attachment: ImageAttachment) -> ImageAttachment {
        let path = attachment.filePath.path
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              attachment.thumbnailData != nil else {
            return attachment
        }

        return ImageAttachment(
            id: attachment.id,
            fileName: attachment.fileName,
            filePath: attachment.filePath,
            thumbnailData: nil,
            fileSize: attachment.fileSize
        )
    }
}
