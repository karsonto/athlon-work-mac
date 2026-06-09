import XCTest
@testable import AthlonAgent

final class WorkspacePromptLoaderTests: XCTestCase {
    func testAppendWorkspaceFilesInjectsAgentsMdWhenPresent() throws {
        let root = try createWorkspaceRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        try "# Agent Rules\nAlways run tests.".write(
            toFile: (root as NSString).appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        var builder = ""
        WorkspacePromptLoader.appendWorkspaceFiles(to: &builder, context: createContext(workspaceRoot: root))

        XCTAssertTrue(builder.contains("## AGENTS.md"))
        XCTAssertTrue(builder.contains("<loaded_context>"))
        XCTAssertTrue(builder.contains("# Agent Rules"))
        XCTAssertFalse(builder.contains("Honor AGENTS.md"))
    }

    func testAppendWorkspaceFilesTruncatesLargeAgentsMd() throws {
        let root = try createWorkspaceRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        try String(repeating: "A", count: 9000).write(
            toFile: (root as NSString).appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        var builder = ""
        WorkspacePromptLoader.appendWorkspaceFiles(
            to: &builder,
            context: createContext(
                workspaceRoot: root,
                promptSettings: PromptSettings(maxAgentsMdChars: 100)
            )
        )

        XCTAssertTrue(builder.localizedCaseInsensitiveContains("truncated"))
    }

    func testAppendWorkspaceFilesListsKnowledgeCatalogAndSkipsIgnoredDirs() throws {
        let root = try createWorkspaceRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let refsDir = (root as NSString).appendingPathComponent("knowledge/refs")
        try FileManager.default.createDirectory(atPath: refsDir, withIntermediateDirectories: true)
        try "# Guide".write(
            toFile: (refsDir as NSString).appendingPathComponent("guide.md"),
            atomically: true,
            encoding: .utf8
        )

        let binDir = (root as NSString).appendingPathComponent("knowledge/bin")
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try "x".write(
            toFile: (binDir as NSString).appendingPathComponent("skip.dll"),
            atomically: true,
            encoding: .utf8
        )

        var builder = ""
        WorkspacePromptLoader.appendWorkspaceFiles(
            to: &builder,
            context: createContext(
                workspaceRoot: root,
                ignorePatterns: [".git", "bin", "obj", "node_modules"]
            )
        )

        XCTAssertTrue(builder.contains("## Domain Knowledge"))
        XCTAssertTrue(builder.contains("knowledge/refs/guide.md"))
        XCTAssertFalse(builder.contains("knowledge/bin/"))
    }

    func testAppendWorkspaceFilesOmitsBlockWhenNoWorkspaceFiles() throws {
        let root = try createWorkspaceRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        var builder = ""
        WorkspacePromptLoader.appendWorkspaceFiles(to: &builder, context: createContext(workspaceRoot: root))
        XCTAssertEqual(builder, "")
    }

    private func createWorkspaceRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-workspace-prompt")
            .appendingPathComponent(UUID().uuidString)
            .path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    private func createContext(
        workspaceRoot: String,
        promptSettings: PromptSettings = PromptSettings(),
        ignorePatterns: [String] = [".git", "bin", "obj", "node_modules"]
    ) -> EnvironmentPromptContext {
        let now = Date()
        let session = AgentSession(
            id: "ws-test",
            title: "ws-test",
            messages: [],
            createdAt: now,
            updatedAt: now,
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0
        )
        return EnvironmentPromptContext(
            session: session,
            workspaceRoot: workspaceRoot,
            workspaceName: "test",
            ignorePatterns: ignorePatterns,
            tools: [],
            host: MacAgentHostEnvironment(skillsDirectory: "/tmp/skills"),
            promptSettings: promptSettings
        )
    }
}
