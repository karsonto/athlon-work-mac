import XCTest
@testable import AthlonAgent

final class AgentStreamAdapterTests: XCTestCase {
    private let sessionId = "session-1"
    private let runId = "run-1"
    private let messageId = "msg-1"

    func testCreateRunStarted_emitsRunStarted() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        let events = adapter.createRunStarted()
        XCTAssertEqual(events.count, 1)
        guard case .runStarted(let sid, let rid) = events[0] else {
            return XCTFail("Expected runStarted")
        }
        XCTAssertEqual(sid, sessionId)
        XCTAssertEqual(rid, runId)
    }

    func testTextDelta_opensSingleMessageAndAppends() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        let first = adapter.onTextDelta(messageId: messageId, delta: "hello ")
        let second = adapter.onTextDelta(messageId: messageId, delta: "world")

        XCTAssertEqual(first.filter { if case .textMessageStart = $0 { return true }; return false }.count, 1)
        let contentEvents = (first + second).filter { if case .textMessageContent = $0 { return true }; return false }
        XCTAssertEqual(contentEvents.count, 2)
        XCTAssertTrue(adapter.state.hasActiveTextMessage())
    }

    func testToolCallDelta_afterText_endsMessageAndStartsTool() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        _ = adapter.onTextDelta(messageId: messageId, delta: "before")

        let result = adapter.onToolCallDelta(
            messageId: messageId,
            delta: StreamingToolCallDelta(index: 0, id: "call-1", name: "read_file", argumentsJson: "{}")
        )

        XCTAssertTrue(result.contains { if case .textMessageEnd = $0 { return true }; return false })
        XCTAssertFalse(adapter.state.hasActiveTextMessage())
        XCTAssertTrue(result.contains { if case .toolCallStart = $0 { return true }; return false })
    }

    func testText_afterToolCallDelta_usesNewMessageId() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        _ = adapter.onTextDelta(messageId: messageId, delta: "first")
        _ = adapter.onToolCallDelta(
            messageId: messageId,
            delta: StreamingToolCallDelta(index: 0, id: "call-1", name: "read_file", argumentsJson: "{}")
        )

        let secondMessageId = "msg-2"
        let result = adapter.onTextDelta(messageId: secondMessageId, delta: "second")

        XCTAssertTrue(result.contains { if case .textMessageStart = $0 { return true }; return false })
        XCTAssertTrue(adapter.state.hasActiveTextMessage())
        XCTAssertEqual(adapter.state.currentTextMessageId, secondMessageId)
    }

    func testDuplicate_toolCallDelta_onlyStartsToolOnce() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        let delta = StreamingToolCallDelta(index: 0, id: "call-1", name: "read_file", argumentsJson: "{}")

        let first = adapter.onToolCallDelta(messageId: messageId, delta: delta)
        let second = adapter.onToolCallDelta(messageId: messageId, delta: delta)

        XCTAssertEqual(first.filter { if case .toolCallStart = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(second.filter { if case .toolCallStart = $0 { return true }; return false }.count, 0)
        let argsEvents = (first + second).filter { if case .toolCallArgs = $0 { return true }; return false }
        XCTAssertEqual(argsEvents.count, 2)
    }

    func testFinishRun_endsOpenTextMessageAndEmitsRunFinished() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        _ = adapter.onTextDelta(messageId: messageId, delta: "open")

        let result = adapter.finishRun()

        XCTAssertTrue(result.contains { if case .textMessageEnd = $0 { return true }; return false })
        XCTAssertTrue(result.contains { if case .runFinished = $0 { return true }; return false })
        XCTAssertFalse(adapter.state.hasActiveTextMessage())
        XCTAssertNil(adapter.state.activeAssistantMessageId)
    }

    func testReasoningDelta_beforeTool_isEndedAtToolBoundary() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        _ = adapter.onReasoningDelta(messageId: messageId, delta: "think")

        let result = adapter.onToolCallDelta(
            messageId: messageId,
            delta: StreamingToolCallDelta(index: 0, id: "call-1", name: "read_file", argumentsJson: "{}")
        )

        XCTAssertTrue(result.contains { if case .reasoningMessageEnd = $0 { return true }; return false })
        XCTAssertFalse(adapter.state.hasActiveReasoningMessage())
    }

    func testOnAssistantRoundCompleted_emitsToolStartAndEnd() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        let message = ChatMessage(
            id: messageId,
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call-1", name: "alpha", arguments: "{}", argumentsStreaming: "", status: .none)]
        )

        let result = adapter.onAssistantRoundCompleted(message)

        XCTAssertTrue(result.contains { if case .toolCallStart = $0 { return true }; return false })
        XCTAssertTrue(result.contains { if case .toolCallEnd = $0 { return true }; return false })
    }

    func testOnToolResult_emitsToolCallResult() {
        let adapter = AgentStreamAdapter(sessionId: sessionId, runId: runId)
        let toolCall = AgentToolCall(id: "call-1", name: "alpha", arguments: "{}", argumentsStreaming: "", status: .none)
        let toolMessage = ChatMessage(id: "tool-1", role: .tool, content: "ok", parentMessageId: messageId, toolCallId: "call-1")

        let result = adapter.onToolResult(toolMessage: toolMessage, toolCall: toolCall)

        XCTAssertTrue(result.contains { if case .toolCallResult = $0 { return true }; return false })
    }
}
