import XCTest
@testable import AthlonAgent

final class SubAgentSessionStoreTests: XCTestCase {
    func testSaveAndLoadPersistsUnderParentSubagentsDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-subagent-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPathProvider(rootPath: root.path)
        let store = FileSubAgentSessionStore(paths: paths)
        let parentId = "parent-1"
        let subId = "sub-1"
        let session = AgentSession(
            id: subId,
            title: "Sub",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0,
            activeWorkspace: "/work"
        )
        let bundle = SubAgentSessionBundle(session: session, role: "Research assistant")

        try await store.save(parentSessionId: parentId, subSessionId: subId, bundle: bundle)

        let expectedDir = (paths.sessionsPath as NSString)
            .appendingPathComponent(parentId)
            .appending("/subagents/default/\(subId)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (expectedDir as NSString).appendingPathComponent("session.json")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (expectedDir as NSString).appendingPathComponent("meta.json")))

        let loaded = try await store.load(parentSessionId: parentId, subSessionId: subId)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.role, "Research assistant")
        XCTAssertEqual(loaded?.session.id, subId)
        XCTAssertEqual(loaded?.session.activeWorkspace, "/work")

        try? FileManager.default.removeItem(at: root)
    }
}
