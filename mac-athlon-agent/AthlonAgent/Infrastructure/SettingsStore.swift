import Foundation

enum SettingsStore {
    private static let paths = AppPathProvider.shared

    static func load(credentialStore: CredentialStoring = CredentialStore()) -> AppSettings {
        paths.ensureCreated()
        ConfigSidecarMigration.runIfNeeded(paths: paths)

        var settings: AppSettings
        if FileManager.default.fileExists(atPath: paths.settingsFilePath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: paths.settingsFilePath)),
           let loaded = try? JsonCodec.decode(AppSettings.self, from: data) {
            settings = loaded
            migrateInlineApiKeyIfNeeded(&settings, credentialStore: credentialStore)
        } else {
            settings = AppSettings.default
        }

        let mcpServers = McpConfigFileService.loadServers(paths)
        if !mcpServers.isEmpty {
            settings.mcpServers = mcpServers
        }

        let skills = SkillConfigFileService.loadSkills(paths)
        if !skills.isEmpty {
            settings.skills = skills
        }

        if let storedKey = credentialStore.get(for: CredentialStore.apiKeyAccount), !storedKey.isEmpty {
            settings.model.apiKey = storedKey
        }

        return settings
    }

    @discardableResult
    static func save(
        _ settings: AppSettings,
        credentialStore: CredentialStoring = CredentialStore()
    ) throws -> AppSettings {
        paths.ensureCreated()

        if !settings.model.apiKey.isEmpty {
            try credentialStore.save(settings.model.apiKey, for: CredentialStore.apiKeyAccount)
        }

        var persisted = settings
        persisted.model.apiKey = ""
        let data = try JsonCodec.encode(persisted)
        try writeAtomic(path: paths.settingsFilePath, data: data)

        try McpConfigFileService.saveServers(settings.mcpServers, paths: paths)
        try SkillConfigFileService.saveSkills(settings.skills, paths: paths)

        var reloaded = settings
        if credentialStore.has(for: CredentialStore.apiKeyAccount) {
            reloaded.model.apiKey = ""
        }
        return reloaded
    }

    private static func migrateInlineApiKeyIfNeeded(
        _ settings: inout AppSettings,
        credentialStore: CredentialStoring
    ) {
        guard !settings.model.apiKey.isEmpty else { return }
        if !credentialStore.has(for: CredentialStore.apiKeyAccount) {
            try? credentialStore.save(settings.model.apiKey, for: CredentialStore.apiKeyAccount)
        }
        settings.model.apiKey = ""
        _ = try? save(settings, credentialStore: credentialStore)
    }

    private static func writeAtomic(path: String, data: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".settings.json.tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }
}
