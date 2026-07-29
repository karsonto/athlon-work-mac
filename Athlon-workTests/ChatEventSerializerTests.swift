import Foundation
import Testing
@testable import Athlon_work

struct ChatEventSerializerTests {
    @Test func userMessageAndApprovalHelpers() {
        let user = ChatEventSerializer.serializeUserMessage(messageId: "u1", content: "hi")
        #expect(user.contains("USER_MESSAGE"))
        #expect(user.contains("\"content\":\"hi\""))

        let ask = ChatEventSerializer.serializeToolApprovalRequest(
            toolCallId: "c1",
            toolName: "execute_command",
            arguments: #"{"command":"ls"}"#
        )
        #expect(ask.contains("TOOL_APPROVAL_REQUEST"))
        #expect(ask.contains("execute_command"))

        let resolved = ChatEventSerializer.serializeToolApprovalResolved(toolCallId: "c1", approved: true)
        #expect(resolved.contains("TOOL_APPROVAL_RESOLVED"))
        #expect(resolved.contains("true"))
    }

    @Test func eventsArraySerialization() {
        let a = ChatEventSerializer.serialize(.runStarted(sessionId: "s", runId: "r"))
        let b = ChatEventSerializer.serialize(.runFinished(sessionId: "s", runId: "r"))
        let arr = ChatEventSerializer.serializeEventsToJsonArray([a, b])
        #expect(arr.hasPrefix("["))
        #expect(arr.contains("RUN_STARTED"))
        #expect(arr.contains("RUN_FINISHED"))
    }

    @Test func toolResultStatusParsing() {
        let failed = ChatEventSerializer.serialize(
            .toolCallResult(toolCallId: "t", content: "status: failed\nbad", messageId: "m")
        )
        #expect(failed.contains("\"status\":\"failed\""))

        let ok = ChatEventSerializer.serialize(
            .toolCallResult(toolCallId: "t", content: "ok", messageId: "m")
        )
        #expect(ok.contains("\"status\":\"succeeded\""))
    }

    @Test func streamingAssistantHtmlEvent() {
        let json = ChatEventSerializer.serializeStreamingAssistantHTML(
            messageId: "m1",
            markdown: "Hello **world**",
            streaming: true
        )
        #expect(json.contains("STATIC_ASSISTANT_HTML"))
        #expect(json.contains("\"streaming\":true"))
        #expect(json.contains("markdownB64"))
    }
}
