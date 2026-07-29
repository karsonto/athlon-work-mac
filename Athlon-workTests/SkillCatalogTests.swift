import Foundation
import Testing
@testable import Athlon_work

struct SkillCatalogTests {
    @Test func scansSkillMarkdownFrontmatter() throws {
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("athlon-skills-\(UUID().uuidString)")
        defer { try? fm.removeItem(atPath: root) }

        let skillDir = (root as NSString).appendingPathComponent("demo-skill")
        try fm.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
        let body = """
        ---
        name: demo-skill
        description: A demo skill for tests
        ---
        # Demo
        Do the thing.
        """
        try body.write(
            toFile: (skillDir as NSString).appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let paths = TempPathProvider(root: root)
        let catalog = SkillCatalog(paths: paths)
        let skills = catalog.listAvailableSkills()
        #expect(skills.count == 1)
        #expect(skills[0].name == "demo-skill")
        #expect(skills[0].description.contains("demo skill"))

        let rendered = SkillPromptRenderer.renderFromCatalog(catalog: catalog, settings: AppSettings())
        #expect(rendered.contains("<available_skills>"))
        #expect(rendered.contains("demo-skill"))
        #expect(rendered.contains("Do the thing."))
    }
}

private struct TempPathProvider: AppPathProviding {
    let rootPath: String
    init(root: String) { rootPath = root }
    var configPath: String { (rootPath as NSString).appendingPathComponent("config") }
    var sessionsPath: String { (rootPath as NSString).appendingPathComponent("sessions") }
    var auditPath: String { (rootPath as NSString).appendingPathComponent("audit") }
    var logsPath: String { (rootPath as NSString).appendingPathComponent("logs") }
    var credentialsPath: String { (rootPath as NSString).appendingPathComponent("credentials") }
    var skillsPath: String { rootPath }
    var knowledgeBasePath: String { (rootPath as NSString).appendingPathComponent("knowledge-base") }
    var memoryPath: String { (rootPath as NSString).appendingPathComponent("memory") }
    var behaviorPath: String { (rootPath as NSString).appendingPathComponent("behavior") }
    func ensureCreated() throws {
        try FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
    }
    func resolveSkillPath(_ path: String) -> String {
        if (path as NSString).isAbsolutePath { return path }
        return (skillsPath as NSString).appendingPathComponent(path)
    }
}
