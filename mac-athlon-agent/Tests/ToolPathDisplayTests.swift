import XCTest
@testable import AthlonAgent

final class ToolPathDisplayTests: XCTestCase {
    func testBuildDisplayNotes_absolutePathResolvesUnderWorkspace() {
        let root = "/Users/test/workspace"
        let raw = ["path": "/Users/test/workspace/AthlonAgent"]
        var normalized = ToolPathNormalizer.normalizePathArguments(raw)
        if let path = normalized["path"] {
            normalized["path"] = ToolPathNormalizer.resolveRelativeToWorkspaceRoot(path, workspaceRoot: root)
        }
        let notes = ToolExecutionDisplayNotes.build(
            rawArguments: raw,
            normalizedArguments: normalized,
            workspaceRoot: root
        )
        XCTAssertNotNil(notes)
        XCTAssertEqual(notes?.normalizedArguments["path"], "AthlonAgent")
        XCTAssertEqual(
            notes?.resolvedFullPath,
            "/Users/test/workspace/AthlonAgent"
        )
    }

    func testResolveRelativeToWorkspaceRoot_stripsAbsolutePathUnderRoot() {
        let root = "/Users/test/workspace"
        let rel = ToolPathNormalizer.resolveRelativeToWorkspaceRoot(
            "/Users/test/workspace/AthlonAgent",
            workspaceRoot: root
        )
        XCTAssertEqual(rel, "AthlonAgent")
    }

    func testFormatToolResult_includesResolvedPathSection() {
        let call = AgentToolCall(
            id: "abc",
            name: "file_list",
            arguments: #"{"path":"/Users/test/workspace"}"#,
            argumentsStreaming: "",
            status: .succeeded
        )
        let notes = ToolExecutionDisplayNotes(
            normalizedArguments: ["path": "."],
            resolvedFullPath: "/Users/test/workspace"
        )
        let text = AgentRuntimeToolFormatting.formatToolResult(
            call,
            .success(summary: "ok", content: "listed"),
            displayNotes: notes
        )
        XCTAssertTrue(text.contains("Arguments (model):"))
        XCTAssertTrue(text.contains("Arguments (normalized):"))
        XCTAssertTrue(text.contains("Resolved path:"))
        XCTAssertTrue(text.contains("/Users/test/workspace"))
    }
}
