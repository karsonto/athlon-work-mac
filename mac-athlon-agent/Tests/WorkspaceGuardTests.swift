import XCTest
@testable import AthlonAgent

final class WorkspaceGuardTests: XCTestCase {
    func testSessionRootPathOverridesEmptyWorkspaceService() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let workspaceService = WorkspaceService()
        let guard_ = WorkspaceGuard(workspaceService: workspaceService, settings: .default)
        guard_.sessionRootPath = temp.path

        XCTAssertEqual(try guard_.normalize("."), temp.path)
        XCTAssertTrue(guard_.isInsideWorkspace(temp.path))
    }

    func testFileListUsesSessionWorkspaceWhenServiceRootUnset() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try "hello".write(to: temp.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)

        let router = BuiltInTools.makeAll(
            workspaceService: WorkspaceService(),
            settings: .default,
            skillService: SkillService(),
            sessionContext: DefaultAgentSessionContext(),
            mcpRegistry: MockMcpRegistryForWorkspace(),
            sessionWorkspacePath: temp.path
        )

        let output = try await router.invoke(toolName: "file_list", arguments: [:])
        XCTAssertTrue(output.contains("sample.txt"))
    }
}

private final class MockMcpRegistryForWorkspace: McpRegistryProviding {
    func getStatuses() async -> [McpServerStatus] { [] }
    func listToolDefinitions() async -> [ToolDefinition] { [] }
    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async {}
    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult {
        .failure(summary: "unused", error: "unused")
    }
    func shutdownAll() async {}
}
