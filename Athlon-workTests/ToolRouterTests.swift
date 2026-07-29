import Foundation
import Testing
@testable import Athlon_work

struct ToolRouterTests {
    @Test func fileListOnTempDirectory() async throws {
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("athlon-tool-router-\(UUID().uuidString)")
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }

        try "alpha".write(toFile: (root as NSString).appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: (root as NSString).appendingPathComponent("subdir"), withIntermediateDirectories: true)

        let router = BuiltinToolRouter()
        guard let tool = router.tool(named: "file_list") else {
            Issue.record("file_list tool missing")
            return
        }

        let context = AgentRunContext(
            sessionId: "test",
            workspaceRoot: root,
            ignorePatterns: [],
            settings: AppSettings()
        )
        let output = try await tool.invoke(arguments: #"{"path":"."}"#, context: context)
        #expect(output.contains("a.txt"))
        #expect(output.contains("subdir"))
    }

    @Test func workspaceGuardRejectsOutsidePaths() throws {
        let root = NSTemporaryDirectory()
        let guard_ = WorkspaceGuard(workspaceRoot: root)
        #expect(throws: WorkspaceGuardError.self) {
            _ = try guard_.resolve("/etc/passwd")
        }
    }
}
