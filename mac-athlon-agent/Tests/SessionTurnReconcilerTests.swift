import XCTest
@testable import AthlonAgent

final class SessionTurnReconcilerTests: XCTestCase {
    private func makeSession() -> AgentSession {
        AgentSession(
            id: "test",
            title: "",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: false,
            isRunning: false,
            queuedTurnCount: 0
        )
    }

    func testReconcile_cancelMidStream_persistsPartialAssistantAndNotice() {
        var session = makeSession()
        session = session.withMessage(ChatMessage(role: .user, content: "hello"))

        let snapshot = SessionTurnEndSnapshot(
            assistantContent: "partial reply",
            assistantReasoning: "thinking",
            incompleteToolCalls: [],
            wasCancelled: true,
            timedOut: false,
            errorMessage: nil
        )

        let result = SessionTurnReconciler.reconcile(session, snapshot: snapshot)

        XCTAssertEqual(result.session.messages.count, 3)
        XCTAssertEqual(result.persistedMessages.count, 2)
        XCTAssertEqual(result.session.messages[1].role, .assistant)
        XCTAssertEqual(result.session.messages[1].content, "partial reply")
        XCTAssertEqual(result.session.messages[1].reasoningContent, "thinking")
        XCTAssertEqual(result.session.messages[2].role, .system)
        XCTAssertTrue(result.session.messages[2].content.contains("生成已停止"))
    }

    func testReconcile_missingToolResult_persistsFailureToolMessage() {
        let callId = "call_missing"
        let toolCall = AgentToolCall(
            id: callId,
            name: "file_read",
            arguments: #"{"path":"a.txt"}"#,
            argumentsStreaming: "",
            status: .preparing
        )
        var session = makeSession()
        session = session.withMessage(ChatMessage(role: .user, content: "run"))
        session = session.withMessage(ChatMessage(role: .assistant, content: "", toolCalls: [toolCall]))

        let snapshot = SessionTurnEndSnapshot(
            assistantContent: nil,
            assistantReasoning: nil,
            incompleteToolCalls: [toolCall],
            wasCancelled: true,
            timedOut: false,
            errorMessage: nil
        )

        let result = SessionTurnReconciler.reconcile(session, snapshot: snapshot)

        XCTAssertEqual(result.session.messages.count, 4)
        XCTAssertTrue(result.persistedMessages.contains(where: { $0.role == MessageRole.tool }))
        XCTAssertTrue(result.session.messages.contains(where: {
            $0.role == MessageRole.tool && $0.content.contains("用户停止")
        }))
    }
}
