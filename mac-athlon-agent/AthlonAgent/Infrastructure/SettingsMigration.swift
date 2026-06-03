import Foundation

enum SettingsMigration {
    static func runIfNeeded() {
        guard isNewPathEmpty() else { return }

        let legacyRoot = AppPathProvider.legacyApplicationSupportPath
        let paths = AppPathProvider.shared

        migrateSettings(from: legacyRoot, to: paths)
        migrateSessions(from: legacyRoot, to: paths)
    }

    private static func isNewPathEmpty() -> Bool {
        let paths = AppPathProvider.shared
        if FileManager.default.fileExists(atPath: paths.settingsFilePath) {
            return false
        }

        guard FileManager.default.fileExists(atPath: paths.sessionsPath) else {
            return true
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: paths.sessionsPath) else {
            return true
        }

        for entry in entries where !entry.hasPrefix(".") {
            if entry == "index.json" { continue }
            var isDir: ObjCBool = false
            let fullPath = (paths.sessionsPath as NSString).appendingPathComponent(entry)
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                return false
            }
        }

        return true
    }

    private static func migrateSettings(from legacyRoot: String, to paths: AppPathProvider) {
        let legacySettings = (legacyRoot as NSString).appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: legacySettings) else { return }

        do {
            try FileManager.default.createDirectory(
                atPath: paths.configPath,
                withIntermediateDirectories: true
            )
            let destination = paths.settingsFilePath
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.copyItem(atPath: legacySettings, toPath: destination)
        } catch {
            print("Settings migration failed: \(error)")
        }
    }

    private static func migrateSessions(from legacyRoot: String, to paths: AppPathProvider) {
        let legacySessionsDir = (legacyRoot as NSString).appendingPathComponent("Sessions")
        guard FileManager.default.fileExists(atPath: legacySessionsDir) else { return }

        let legacyBundle = (legacySessionsDir as NSString).appendingPathComponent("sessions.json")
        if FileManager.default.fileExists(atPath: legacyBundle) {
            migrateLegacySessionsBundle(at: legacyBundle, storage: FileStorageService(paths: paths))
            return
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: legacySessionsDir) else {
            return
        }

        for entry in entries where !entry.hasPrefix(".") {
            let source = (legacySessionsDir as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let destination = paths.sessionDirectory(entry)
            copyDirectory(from: source, to: destination)
        }
    }

    private static func migrateLegacySessionsBundle(at path: String, storage: FileStorageService) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let sessions = try? JsonCodec.decode([AgentSession].self, from: data) else {
            return
        }

        for session in sessions {
            try? storage.saveSessionSync(session)
        }
    }

    private static func copyDirectory(from source: String, to destination: String) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination) else { return }

        do {
            try fileManager.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(atPath: source, toPath: destination)
        } catch {
            print("Session directory migration failed (\(source)): \(error)")
        }
    }
}
