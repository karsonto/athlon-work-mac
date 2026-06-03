import Foundation

/// One-time migration of legacy MCP/skills config paths into `~/.athlon-agent/config/`.
enum ConfigSidecarMigration {
    private static let mcpMigrationFlag = "athlon.mcpSidecarMigrated"
    private static let skillsMigrationFlag = "athlon.skillsSidecarMigrated"

    static func runIfNeeded(paths: AppPathProvider = .shared) {
        migrateLegacyMcpServersIfNeeded(paths: paths)
        migrateLegacySkillsConfigIfNeeded(paths: paths)
    }

    private static func migrateLegacyMcpServersIfNeeded(paths: AppPathProvider) {
        let target = McpConfigFileService.path(paths)
        guard !FileManager.default.fileExists(atPath: target) else { return }
        guard !UserDefaults.standard.bool(forKey: mcpMigrationFlag) else { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let legacy = appSupport.appendingPathComponent("AthlonAgent/MCP/mcp_servers.json")
        guard FileManager.default.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let items = try? JSONDecoder().decode([McpServerItem].self, from: data) else {
            return
        }

        let servers = items.map { item in
            McpServerSettings(
                id: item.id,
                name: item.name,
                command: "",
                args: [],
                enabled: item.isEnabled
            )
        }

        if !servers.isEmpty {
            try? McpConfigFileService.saveServers(servers, paths: paths)
        }
        UserDefaults.standard.set(true, forKey: mcpMigrationFlag)
    }

    private static func migrateLegacySkillsConfigIfNeeded(paths: AppPathProvider) {
        let target = SkillConfigFileService.path(paths)
        guard !FileManager.default.fileExists(atPath: target) else { return }
        guard !UserDefaults.standard.bool(forKey: skillsMigrationFlag) else { return }

        let legacy = (paths.skillsPath as NSString).appendingPathComponent("skills_config.json")
        guard FileManager.default.fileExists(atPath: legacy),
              let data = try? Data(contentsOf: URL(fileURLWithPath: legacy)),
              let states = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            return
        }

        let skills = states.map { name, enabled in
            SkillSettings(name: name, enabled: enabled, path: name)
        }.sorted { $0.name < $1.name }

        if !skills.isEmpty {
            try? SkillConfigFileService.saveSkills(skills, paths: paths)
        }
        UserDefaults.standard.set(true, forKey: skillsMigrationFlag)
    }
}
