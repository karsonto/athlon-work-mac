import XCTest
@testable import AthlonAgent

final class SubAgentToolTests: XCTestCase {
    func testInvokeNewSessionRequiresRole() async {
        let context = DefaultActiveAgentSessionContext()
        context.setSession("parent-1")
        let tool = makeTool(context: context, executor: StubSubAgentExecutor())

        do {
            _ = try await tool.invoke(arguments: ["message": "do work"])
            XCTFail("Expected missing role error")
        } catch let error as ToolError {
            let detail = error.errorDescription ?? ""
            XCTAssertTrue(detail.localizedCaseInsensitiveContains("role"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvokeNewSessionReturnsSessionId() async throws {
        let context = DefaultActiveAgentSessionContext()
        context.setSession("parent-1")
        let executor = StubSubAgentExecutor()
        let tool = makeTool(context: context, executor: executor)

        let result = try await tool.invoke(arguments: [
            "role": "Searcher",
            "message": "find todos"
        ])

        XCTAssertTrue(result.localizedCaseInsensitiveContains("session_id:"))
        XCTAssertEqual(executor.sendCount, 1)
    }

    func testInvokeContinueReusesSavedRole() async throws {
        let store = InMemorySubAgentStore()
        let subId = "sub-continue"
        let session = AgentSession(
            id: subId,
            title: "Sub",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0
        )
        try await store.save(
            parentSessionId: "parent-1",
            subSessionId: subId,
            bundle: SubAgentSessionBundle(session: session, role: "Original role")
        )

        let context = DefaultActiveAgentSessionContext()
        context.setSession("parent-1")
        let executor = StubSubAgentExecutor()
        let tool = makeTool(context: context, executor: executor, store: store)

        _ = try await tool.invoke(arguments: [
            "session_id": subId,
            "message": "continue"
        ])

        let loaded = try await store.load(parentSessionId: "parent-1", subSessionId: subId)
        XCTAssertEqual(loaded?.role, "Original role")
    }

    func testInvokeContinueCanOverrideRole() async throws {
        let store = InMemorySubAgentStore()
        let subId = "sub-override"
        let session = AgentSession(
            id: subId,
            title: "Sub",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0
        )
        try await store.save(
            parentSessionId: "parent-1",
            subSessionId: subId,
            bundle: SubAgentSessionBundle(session: session, role: "Old")
        )

        let context = DefaultActiveAgentSessionContext()
        context.setSession("parent-1")
        let tool = makeTool(context: context, executor: StubSubAgentExecutor(), store: store)

        _ = try await tool.invoke(arguments: [
            "session_id": subId,
            "role": "New role",
            "message": "go"
        ])

        let loaded = try await store.load(parentSessionId: "parent-1", subSessionId: subId)
        XCTAssertEqual(loaded?.role, "New role")
    }

    func testInvokeExceedsNestingDepthFails() async {
        var settings = AppSettings.default
        settings.subAgent.maxNestingDepth = 1
        let context = DefaultActiveAgentSessionContext()
        context.setSession("parent-1")
        let tool = makeTool(context: context, executor: StubSubAgentExecutor(), settings: settings)

        do {
            try await SubAgentExecutionScope.withDepth {
                _ = try await tool.invoke(arguments: [
                    "role": "x",
                    "message": "y"
                ])
            }
            XCTFail("Expected nesting limit error")
        } catch let error as ToolError {
            let detail = error.errorDescription ?? ""
            XCTAssertTrue(detail.localizedCaseInsensitiveContains("depth"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeTool(
        context: DefaultActiveAgentSessionContext,
        executor: StubSubAgentExecutor,
        store: SubAgentSessionStore? = nil,
        settings: AppSettings = .default
    ) -> SubAgentTool {
        let storage = makeStorage(parentId: "parent-1")
        let childRouter = ChildAgentToolRouter(localTools: [], mcpRegistry: EmptyMcpRegistry())
        let prompt = SubAgentSystemPromptOrchestrator(settings: settings)
        let tool = SubAgentTool(
            settings: settings,
            storage: storage,
            sessionStore: store ?? InMemorySubAgentStore(),
            childToolRouter: childRouter,
            subAgentPromptOrchestrator: prompt,
            activeSessionContext: context,
            turnExecutor: executor
        )
        tool.bindTurnExecutor(executor)
        return tool
    }

    private func makeStorage(parentId: String) -> FileStorageService {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-subagent-test-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPathProvider(rootPath: root.path)
        let storage = FileStorageService(paths: paths)
        let parent = AgentSession(
            id: parentId,
            title: "Parent",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0,
            activeWorkspace: "/tmp/repo"
        )
        try? storage.saveSession(parent)
        return storage
    }
}

private final class StubSubAgentExecutor: SubAgentTurnExecuting {
    private(set) var sendCount = 0

    func executeSubTurn(session: AgentSession, userInput: String) async throws -> AgentSession {
        sendCount += 1
        let assistant = ChatMessage(
            role: .assistant,
            content: "done from sub",
            parentMessageId: session.messages.last?.id
        )
        return session.withMessage(assistant)
    }
}

private final class InMemorySubAgentStore: SubAgentSessionStore {
    private var bundles: [String: SubAgentSessionBundle] = [:]

    func load(parentSessionId: String, subSessionId: String) async throws -> SubAgentSessionBundle? {
        bundles[key(parentSessionId, subSessionId)]
    }

    func save(parentSessionId: String, subSessionId: String, bundle: SubAgentSessionBundle) async throws {
        bundles[key(parentSessionId, subSessionId)] = bundle
    }

    private func key(_ parent: String, _ sub: String) -> String { "\(parent):\(sub)" }
}

private final class EmptyMcpRegistry: McpRegistryProviding {
    func getStatuses() async -> [McpServerStatus] { [] }
    func listToolDefinitions() async -> [ToolDefinition] { [] }
    func refresh(servers: [McpServerSettings], workspaceRoot: String?) async {}
    func invoke(serverName: String, toolName: String, args: [String: String]) async -> ToolResult {
        .failure(summary: "none", error: "none")
    }
    func shutdownAll() async {}
}
