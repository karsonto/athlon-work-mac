import XCTest
@testable import AthlonAgent

final class ExecuteCommandAuditTests: XCTestCase {
    func testExecuteCommand_writesAuditJsonl() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let paths = AppPathProvider(rootPath: temp.path)
        let workspaceService = WorkspaceService()
        workspaceService.setWorkspaceRoot(temp.path)
        let guard_ = WorkspaceGuard(workspaceService: workspaceService, settings: .default)

        let tool = ExecuteCommandTool(
            permissions: ToolPermissionSettings(commandAllowList: ["echo"]),
            workspaceGuard: guard_,
            processRegistry: ExecuteCommandProcessRegistry(),
            auditPaths: paths
        )

        _ = try await tool.invoke(arguments: ["command": "echo audit-test-marker"])

        let auditDir = paths.auditPath
        let files = try FileManager.default.contentsOfDirectory(atPath: auditDir)
        let jsonl = files.first { $0.hasPrefix("audit-") && $0.hasSuffix(".jsonl") }
        XCTAssertNotNil(jsonl)

        let content = try String(contentsOfFile: (auditDir as NSString).appendingPathComponent(jsonl!), encoding: .utf8)
        XCTAssertTrue(content.contains("execute_command"))
        XCTAssertTrue(content.contains("audit-test-marker"))
        XCTAssertTrue(content.contains("\"cwd\""))
        XCTAssertTrue(content.contains("\"elapsedMs\""))
    }

    func testAuditLogService_write_matchesWpfShape() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-audit-shape-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPathProvider(rootPath: temp.path)

        AuditLogService.write(
            action: "execute_command",
            payload: ["command": "echo hi", "cwd": "/tmp", "exitCode": 0, "elapsedMs": 12],
            paths: paths
        )

        let files = try? FileManager.default.contentsOfDirectory(atPath: paths.auditPath)
        let jsonl = files?.first { $0.hasSuffix(".jsonl") }
        XCTAssertNotNil(jsonl)
        let line = try? String(contentsOfFile: (paths.auditPath as NSString).appendingPathComponent(jsonl!), encoding: .utf8)
        XCTAssertTrue(line?.contains("\"time\"") == true)
        XCTAssertTrue(line?.contains("\"payload\"") == true)
        XCTAssertTrue(line?.contains("\"exitCode\"") == true)
    }
}
