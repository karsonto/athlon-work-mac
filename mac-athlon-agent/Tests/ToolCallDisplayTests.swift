import XCTest
@testable import AthlonAgent

final class ToolCallDisplayTests: XCTestCase {
    func testFromToolCall_showsArguments() {
        let call = AgentToolCall(
            id: "tc1",
            name: "file_read",
            arguments: #"{"path":"src/AppModels.swift"}"#,
            argumentsStreaming: "",
            status: .running,
            resultSummary: "执行中…"
        )
        let message = ChatMessage(
            id: "m1",
            role: .tool,
            content: ToolCallDisplay.headerLine(toolName: "file_read", status: .running),
            toolCalls: [call],
            toolCallId: "tc1"
        )
        let display = ToolCallDisplay.from(message: message)
        XCTAssertTrue(display.hasArguments)
        XCTAssertTrue(display.argumentsText.contains("path"))
        XCTAssertTrue(display.argumentsText.contains("AppModels.swift"))
    }

    func testFromPersistedContent_readsArgumentsModelBlock() {
        let content = """
        ToolCallId: abc
        Tool `file_read` succeeded.

        Arguments (model):
        path=src/Foo.swift

        Summary: Read 10 lines
        line one
        """
        let message = ChatMessage(id: "m2", role: .tool, content: content, toolCallId: "abc")
        let display = ToolCallDisplay.from(message: message)
        XCTAssertEqual(display.toolName, "file_read")
        XCTAssertTrue(display.argumentsText.contains("path"))
        XCTAssertEqual(display.summary, "Read 10 lines")
    }
}
