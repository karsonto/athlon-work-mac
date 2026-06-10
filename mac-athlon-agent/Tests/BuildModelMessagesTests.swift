import XCTest
@testable import AthlonAgent

final class BuildModelMessagesTests: XCTestCase {
    func testBuildModelMessages_toolHeavyHistory_completesQuickly() {
        let toolContent = String(repeating: "x", count: 8000)
        let toolCall = AgentToolCall(
            id: "tool1",
            name: "file_read",
            arguments: #"{"path":"Package.swift"}"#,
            argumentsStreaming: "",
            status: .succeeded
        )
        let formatted = AgentRuntimeToolFormatting.formatToolResult(
            toolCall,
            .success(summary: "ok", content: toolContent)
        )
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "analyze project"),
            ChatMessage(
                role: .assistant,
                content: "listing",
                toolCalls: [toolCall]
            ),
            ChatMessage(role: .tool, content: formatted, toolCallId: "tool1"),
            ChatMessage(
                role: .assistant,
                content: "reading",
                reasoningContent: "thinking",
                toolCalls: [
                    AgentToolCall(id: "t2", name: "file_read", arguments: "{}", argumentsStreaming: "", status: .succeeded),
                    AgentToolCall(id: "t3", name: "file_list", arguments: "{}", argumentsStreaming: "", status: .succeeded),
                    AgentToolCall(id: "t4", name: "file_read", arguments: "{}", argumentsStreaming: "", status: .succeeded),
                ]
            ),
            ChatMessage(role: .tool, content: formatted, toolCallId: "t2"),
            ChatMessage(role: .tool, content: formatted, toolCallId: "t3"),
            ChatMessage(role: .tool, content: formatted, toolCallId: "t4"),
        ]

        let started = Date()
        let built = AgentRuntime.buildModelMessages(
            environmentPrompt: String(repeating: "s", count: 5000),
            history: history,
            includeReasoningInModelContext: true
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(built.count, 4)
        XCTAssertLessThan(elapsed, 1.0, "buildModelMessages took \(elapsed)s")
    }
}
