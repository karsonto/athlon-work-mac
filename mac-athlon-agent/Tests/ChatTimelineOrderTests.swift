import XCTest
@testable import AthlonAgent

final class ChatTimelineOrderTests: XCTestCase {
    func testOrderForDisplay_pinsStreamingAssistantToEnd() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let user = ChatMessage(
            id: "user",
            role: .user,
            content: "hi",
            createdAt: base
        )
        let assistant = ChatMessage(
            id: "assistant",
            role: .assistant,
            content: "thinking…",
            createdAt: base.addingTimeInterval(1),
            isStreaming: true
        )
        let tool = ChatMessage(
            id: "tool",
            role: .tool,
            content: "file_read",
            createdAt: base.addingTimeInterval(5),
            toolCalls: [
                AgentToolCall(
                    id: "tc1",
                    name: "file_read",
                    arguments: "{}",
                    argumentsStreaming: "",
                    status: .succeeded
                )
            ]
        )

        let ordered = ChatTimelineOrder.orderForDisplay(
            [user, assistant, tool],
            pinToEndMessageId: assistant.id
        )

        XCTAssertEqual(ordered.map { $0.id }, [user.id, tool.id, assistant.id])
    }

    func testOrderForDisplay_sortsByCreatedAtWhenNotPinned() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let early = ChatMessage(id: "a", role: .user, content: "1", createdAt: base)
        let late = ChatMessage(id: "b", role: .assistant, content: "2", createdAt: base.addingTimeInterval(10))

        let ordered = ChatTimelineOrder.orderForDisplay([late, early])
        XCTAssertEqual(ordered.map { $0.id }, ["a", "b"])
    }
}
