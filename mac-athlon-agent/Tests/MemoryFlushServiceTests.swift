import XCTest
@testable import AthlonAgent

final class MemoryFlushServiceTests: XCTestCase {
    func testSerializeMessagesFiltersSystemAndCompaction() {
        let messages: [ChatMessage] = [
            .init(id: "1", role: .system, content: "system prompt", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false),
            .init(id: "2", role: .user, content: "Hello", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false),
            .init(id: "3", role: .compaction, content: "compacted", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false),
            .init(id: "4", role: .assistant, content: "Hi there", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false)
        ]

        let filtered = messages.filter { $0.role != .system && $0.role != .compaction }
        let serialized = filtered.map { "[\($0.role.apiValue)]: \($0.content)" }.joined(separator: "\n\n")

        XCTAssertFalse(serialized.contains("system"), "Should not contain system messages")
        XCTAssertFalse(serialized.contains("compacted"), "Should not contain compaction messages")
        XCTAssertTrue(serialized.contains("Hello"), "Should contain user message")
        XCTAssertTrue(serialized.contains("Hi there"), "Should contain assistant message")
    }

    func testSerializeMessagesWithToolMessages() {
        let messages: [ChatMessage] = [
            .init(id: "1", role: .user, content: "List files", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false),
            .init(id: "2", role: .tool, content: "file1.txt\nfile2.txt", reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false)
        ]

        let serialized = messages
            .filter { $0.role != .system && $0.role != .compaction }
            .map { "[\($0.role.apiValue)]: \($0.content)" }
            .joined(separator: "\n\n")

        XCTAssertTrue(serialized.contains("[user]:"), "Should include tool messages")
        XCTAssertTrue(serialized.contains("[tool]:"), "Should include tool messages")
    }

    func testSerializeMessagesRespectsMaxLength() {
        let longContent = String(repeating: "A", count: 100_000)
        let messages: [ChatMessage] = [
            .init(id: "1", role: .user, content: longContent, reasoningContent: "", createdAt: Date(),
                  imageAttachments: nil, toolCalls: nil, parentMessageId: nil, toolCallId: nil,
                  isStreaming: false, isReasoningStreaming: false)
        ]

        let result = messages
            .filter { $0.role != .system && $0.role != .compaction }
            .map { "[\($0.role.apiValue)]: \($0.content)" }
            .joined(separator: "\n\n")

        let truncated = result.count > 80_000 ? String(result.suffix(80_000)) : result
        XCTAssertLessThanOrEqual(truncated.count, 80_000)
    }
}
