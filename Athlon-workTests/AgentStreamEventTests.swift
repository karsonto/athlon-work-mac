import Foundation
import Testing
@testable import Athlon_work

struct AgentStreamEventTests {
    @Test func serializesRunStarted() {
        let json = ChatEventSerializer.serialize(.runStarted(sessionId: "s1", runId: "r1"))
        #expect(json.contains("\"type\":\"RUN_STARTED\""))
        #expect(json.contains("\"threadId\":\"s1\""))
        #expect(json.contains("\"runId\":\"r1\""))
    }

    @Test func serializesRunFinished() {
        let json = ChatEventSerializer.serialize(.runFinished(sessionId: "s1", runId: "r1"))
        #expect(json.contains("\"type\":\"RUN_FINISHED\""))
    }

    @Test func serializesTextAndToolEvents() {
        let start = ChatEventSerializer.serialize(.textMessageStart(messageId: "m1", role: "assistant"))
        #expect(start.contains("TEXT_MESSAGE_START"))
        let tool = ChatEventSerializer.serialize(.toolCallStart(toolCallId: "t1", toolName: "file_list", index: 0))
        #expect(tool.contains("TOOL_CALL_START"))
        #expect(tool.contains("file_list"))
        let output = ChatEventSerializer.serialize(.toolCallOutput(toolCallId: "t1", delta: "hello"))
        #expect(output.contains("TOOL_CALL_OUTPUT"))
    }
}
