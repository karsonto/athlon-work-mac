import Foundation

/// Resolves `~/.athlon-agent` layout used by Windows and macOS builds.
nonisolated protocol AppPathProviding: Sendable {
    var rootPath: String { get }
    var configPath: String { get }
    var sessionsPath: String { get }
    var auditPath: String { get }
    var logsPath: String { get }
    var credentialsPath: String { get }
    var skillsPath: String { get }
    var knowledgeBasePath: String { get }
    var memoryPath: String { get }
    var behaviorPath: String { get }

    func ensureCreated() throws
    func resolveSkillPath(_ path: String) -> String
}

nonisolated struct AppPathProvider: AppPathProviding {
    static let appDataFolderName = ".athlon-agent"
    static let skillsFolderName = "skills"
    static let knowledgeBaseFolderName = "knowledge-base"
    static let memoryFolderName = "memory"
    static let behaviorFolderName = "behavior"

    let rootPath: String

    init(homeDirectory: String = NSHomeDirectory()) {
        rootPath = (homeDirectory as NSString).appendingPathComponent(Self.appDataFolderName)
    }

    var configPath: String { (rootPath as NSString).appendingPathComponent("config") }
    var sessionsPath: String { (rootPath as NSString).appendingPathComponent(SessionDirectoryLayout.sessionsFolderName) }
    var auditPath: String { (rootPath as NSString).appendingPathComponent("audit") }
    var logsPath: String { (rootPath as NSString).appendingPathComponent("logs") }
    var credentialsPath: String { (rootPath as NSString).appendingPathComponent("credentials") }
    var skillsPath: String { (rootPath as NSString).appendingPathComponent(Self.skillsFolderName) }
    var knowledgeBasePath: String { (rootPath as NSString).appendingPathComponent(Self.knowledgeBaseFolderName) }
    var memoryPath: String { (rootPath as NSString).appendingPathComponent(Self.memoryFolderName) }
    var behaviorPath: String { (rootPath as NSString).appendingPathComponent(Self.behaviorFolderName) }

    func ensureCreated() throws {
        let fm = FileManager.default
        let paths = [
            rootPath, configPath, sessionsPath, auditPath, logsPath,
            credentialsPath, skillsPath, knowledgeBasePath, memoryPath, behaviorPath,
        ]
        for path in paths {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    func resolveSkillPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if (trimmed as NSString).isAbsolutePath {
            return trimmed
        }
        return (skillsPath as NSString).appendingPathComponent(trimmed)
    }
}
