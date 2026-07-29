import Foundation
import Testing
@testable import Athlon_work

struct SubAgentPathTests {
    @Test func spawnCreatesNestedDirectoryLayout() throws {
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("athlon-sub-\(UUID().uuidString)")
        defer { try? fm.removeItem(atPath: root) }

        let paths = SubTempPaths(root: root)
        try paths.ensureCreated()
        let storage = FileStorageService(paths: paths)

        let parent = AgentSession.create(title: "parent")
        try storage.saveSession(parent)

        let manager = SubAgentSessionManager(paths: paths, storage: storage)
        var settings = SubAgentSettings()
        settings.enabled = true
        let child = try manager.spawn(parentSessionId: parent.id, title: "child", settings: settings)

        let expected = SessionDirectoryLayout.subAgentDirectory(
            sessionsPath: paths.sessionsPath,
            parentSessionId: parent.id,
            subSessionId: child.id
        )
        #expect(fm.fileExists(atPath: (expected as NSString).appendingPathComponent("session.json")))

        let listed = try manager.list(parentSessionId: parent.id)
        #expect(listed.contains(where: { $0.id == child.id }))
    }
}

private struct SubTempPaths: AppPathProviding {
    let rootPath: String
    init(root: String) { rootPath = root }
    var configPath: String { (rootPath as NSString).appendingPathComponent("config") }
    var sessionsPath: String { (rootPath as NSString).appendingPathComponent("sessions") }
    var auditPath: String { (rootPath as NSString).appendingPathComponent("audit") }
    var logsPath: String { (rootPath as NSString).appendingPathComponent("logs") }
    var credentialsPath: String { (rootPath as NSString).appendingPathComponent("credentials") }
    var skillsPath: String { (rootPath as NSString).appendingPathComponent("skills") }
    var knowledgeBasePath: String { (rootPath as NSString).appendingPathComponent("knowledge-base") }
    var memoryPath: String { (rootPath as NSString).appendingPathComponent("memory") }
    var behaviorPath: String { (rootPath as NSString).appendingPathComponent("behavior") }
    func ensureCreated() throws {
        for p in [rootPath, configPath, sessionsPath, skillsPath, knowledgeBasePath, memoryPath] {
            try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        }
    }
    func resolveSkillPath(_ path: String) -> String {
        (path as NSString).isAbsolutePath ? path : (skillsPath as NSString).appendingPathComponent(path)
    }
}
