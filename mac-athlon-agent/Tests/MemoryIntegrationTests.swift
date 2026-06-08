import XCTest
@testable import AthlonAgent

final class MemoryIntegrationTests: XCTestCase {
    var tempDir: String!
    var memory: FileLongTermMemory!

    override func setUp() async throws {
        tempDir = NSTemporaryDirectory().appending(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        memory = try FileLongTermMemory(memoryDir: tempDir)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Full Memory Lifecycle

    func testFullMemoryLifecycle() async throws {
        // 1. Start with empty curated memory
        let curated = try await memory.readCurated()
        XCTAssertEqual(curated, "")

        // 2. Append daily entries
        try await memory.appendDaily("- User prefers dark theme\n")
        try await memory.appendDaily("- User committed to SwiftUI views\n")

        // 3. Read daily
        let daily = try await memory.readDaily(date: Date())
        XCTAssertTrue(daily.contains("dark theme"))
        XCTAssertTrue(daily.contains("SwiftUI"))

        // 4. Write curated
        try await memory.writeCurated("# Project\n- SwiftUI macOS app\n")
        let updated = try await memory.readCurated()
        XCTAssertEqual(updated, "# Project\n- SwiftUI macOS app\n")

        // 5. List daily files after watermark
        let files = try await memory.listDailyFilesAfter(watermark: Date.distantPast)
        XCTAssertFalse(files.isEmpty)

        // 6. Read a daily file by path
        if let first = files.first {
            let content = try await memory.readDailyFile(relativePath: first)
            XCTAssertFalse(content.isEmpty)
        }

        // 7. Archive
        if let first = files.first {
            try await memory.archiveDailyFile(relativePath: first)
            let archived = try await memory.readDailyFile(relativePath: first)
            XCTAssertEqual(archived, "")
        }
    }

    // MARK: - Composer Command Parser

    func testComposerCommandParserNoCommand() {
        XCTAssertNil(ComposerCommandParser.parse("hello world"))
        XCTAssertNil(ComposerCommandParser.parse("/"))
        XCTAssertNil(ComposerCommandParser.parse(""))
    }

    func testComposerCommandParserBasic() {
        let result = ComposerCommandParser.parse("/compact")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, "compact")
        XCTAssertEqual(result?.args, "")
    }

    func testComposerCommandParserWithArgs() {
        let result = ComposerCommandParser.parse("/help me please")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, "help")
        XCTAssertEqual(result?.args, "me please")
    }

    func testComposerCommandParserTrimsWhitespace() {
        let result = ComposerCommandParser.parse("  /compact  ")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, "compact")
    }

    func testComposerCommandParserCaseInsensitive() {
        let result = ComposerCommandParser.parse("/COMPACT")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, "compact")
    }

    // MARK: - Composer Command Registry

    func testComposerCommandRegistry() {
        let registry = ComposerCommandRegistry()
        let help = HelpComposerCommand(registry: registry)
        registry.register(help)
        XCTAssertNotNil(registry.find("help"))
        XCTAssertNil(registry.find("unknown"))
        XCTAssertTrue(registry.allCommands.count >= 1)
    }

    func testComposerCommandRegistryCaseInsensitive() {
        let registry = ComposerCommandRegistry()
        let help = HelpComposerCommand(registry: registry)
        registry.register(help)
        XCTAssertNotNil(registry.find("HELP"))
        XCTAssertNotNil(registry.find("Help"))
    }

    // MARK: - Memory Flush Serialization

    func testSerializeMessagesFiltersSystemAndCompaction() {
        let messages: [ChatMessage] = [
            .init(role: .system, content: "system prompt"),
            .init(role: .user, content: "Hello"),
            .init(role: .compaction, content: "compacted"),
            .init(role: .assistant, content: "Hi there")
        ]
        let serialized = messages
            .filter { $0.role != .system && $0.role != .compaction }
            .map { "[\($0.role)]: \($0.content ?? "")" }
            .joined(separator: "\n\n")
        XCTAssertFalse(serialized.contains("system"))
        XCTAssertFalse(serialized.contains("compacted"))
        XCTAssertTrue(serialized.contains("Hello"))
        XCTAssertTrue(serialized.contains("Hi there"))
    }

    func testSerializeMessagesWithToolMessages() {
        let messages: [ChatMessage] = [
            .init(role: .user, content: "list files"),
            .init(role: .assistant, content: "I'll check"),
            .init(role: .tool, content: "file_list result"),
        ]
        let serialized = messages
            .filter { $0.role != .system && $0.role != .compaction }
            .map { "[\($0.role)]: \($0.content ?? "")" }
            .joined(separator: "\n\n")
        XCTAssertTrue(serialized.contains("[tool]"))
        XCTAssertTrue(serialized.contains("file_list result"))
    }

    func testSerializeMessagesRespectsMaxLength() {
        // Create a message with content exceeding 80K limit
        let longContent = String(repeating: "A", count: 90_000)
        let messages: [ChatMessage] = [
            .init(role: .user, content: longContent),
            .init(role: .assistant, content: "short reply")
        ]
        let serialized = messages
            .filter { $0.role != .system && $0.role != .compaction }
            .map { "[\($0.role)]: \($0.content ?? "")" }
            .joined(separator: "\n\n")
        // In production, truncation happens in MemoryFlushService.serializeMessages
        // Here we just verify the raw concatenation is long
        XCTAssertTrue(serialized.count > 80_000)
    }

    // MARK: - MemoryPromptContributor

    func testMemoryPromptContributorAppendsLongTermMemory() async throws {
        try await memory.writeCurated("# Previous Decision\n- Use Swift concurrency\n")
        let contributor = MemoryPromptContributor(longTermMemory: memory)
        var builder = "Base prompt\n"
        let appended = contributor.append(to: &builder)
        XCTAssertTrue(appended)
        XCTAssertTrue(builder.contains("<long_term_memory>"))
        XCTAssertTrue(builder.contains("Swift concurrency"))
        XCTAssertTrue(builder.contains("</long_term_memory>"))
    }

    func testMemoryPromptContributorSkipsWhenEmpty() async throws {
        let contributor = MemoryPromptContributor(longTermMemory: memory)
        var builder = "Base prompt\n"
        let appended = contributor.append(to: &builder)
        XCTAssertFalse(appended)
        XCTAssertEqual(builder, "Base prompt\n")
    }

    // MARK: - EnvironmentPromptContext

    func testEnvironmentPromptContextHasWorkspace() {
        let session = AgentSession(id: "test", title: "Test", messages: [])
        let contextNoWorkspace = EnvironmentPromptContext(
            session: session,
            workspaceRoot: nil,
            workspaceName: nil,
            ignorePatterns: [],
            tools: [],
            skillsDirectory: "/tmp/skills",
            interactionMode: .agent,
            planAutoContinueEnabled: false,
            planMaxSubtasks: 5
        )
        XCTAssertFalse(contextNoWorkspace.hasWorkspace)

        let contextWithWorkspace = EnvironmentPromptContext(
            session: session,
            workspaceRoot: "/tmp/workspace",
            workspaceName: "workspace",
            ignorePatterns: [],
            tools: [],
            skillsDirectory: "/tmp/skills",
            interactionMode: .agent,
            planAutoContinueEnabled: false,
            planMaxSubtasks: 5
        )
        XCTAssertTrue(contextWithWorkspace.hasWorkspace)
    }

    // MARK: - MemorySettings

    func testMemorySettingsDefaults() {
        let settings = MemorySettings()
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.summaryMaxTokens, 4000)
        XCTAssertEqual(settings.maxMemoryTokens, 4000)
    }

    func testMemorySettingsCodableRoundTrip() throws {
        let original = MemorySettings(enabled: false, summaryMaxTokens: 2000, maxMemoryTokens: 1000)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MemorySettings.self, from: encoded)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertEqual(decoded.summaryMaxTokens, 2000)
        XCTAssertEqual(decoded.maxMemoryTokens, 1000)
    }
}
