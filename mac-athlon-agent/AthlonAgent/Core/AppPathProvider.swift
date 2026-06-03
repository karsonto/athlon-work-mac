import Foundation

/// Paths aligned with WPF `AppPathProvider` (~/.athlon-agent).
struct AppPathProvider {
    static let appDataFolderName = ".athlon-agent"
    static let skillsFolderName = "skills"

    let rootPath: String
    var configPath: String { (rootPath as NSString).appendingPathComponent("config") }
    var sessionsPath: String { (rootPath as NSString).appendingPathComponent("sessions") }
    var auditPath: String { (rootPath as NSString).appendingPathComponent("audit") }
    var logsPath: String { (rootPath as NSString).appendingPathComponent("logs") }
    var credentialsPath: String { (rootPath as NSString).appendingPathComponent("credentials") }
    var skillsPath: String { (rootPath as NSString).appendingPathComponent(Self.skillsFolderName) }

    static let shared = AppPathProvider()

    init(homeDirectory: String = NSHomeDirectory()) {
        rootPath = (homeDirectory as NSString).appendingPathComponent(Self.appDataFolderName)
    }

    /// Direct root (for tests or custom data dirs).
    init(rootPath: String) {
        self.rootPath = rootPath
    }

    func ensureCreated() {
        for path in [rootPath, configPath, sessionsPath, auditPath, logsPath, credentialsPath, skillsPath] {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    var settingsFilePath: String {
        (configPath as NSString).appendingPathComponent("settings.json")
    }

    func sessionDirectory(_ sessionId: String) -> String {
        (sessionsPath as NSString).appendingPathComponent(sessionId)
    }

    func resolveSkillPath(_ path: String) -> String {
        if path.isEmpty { return path }
        if path.hasPrefix("/") { return path }
        return (skillsPath as NSString).appendingPathComponent(path)
    }

    /// Legacy mac app storage before ~/.athlon-agent migration.
    static var legacyApplicationSupportPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AthlonAgent").path
    }
}
