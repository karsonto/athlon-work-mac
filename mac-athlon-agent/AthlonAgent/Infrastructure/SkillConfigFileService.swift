import Foundation

enum SkillConfigFileService {
    static let fileName = "skills.json"

    static func path(_ paths: AppPathProvider = .shared) -> String {
        (paths.configPath as NSString).appendingPathComponent(fileName)
    }

    static func loadSkills(_ paths: AppPathProvider = .shared) -> [SkillSettings] {
        let filePath = path(paths)
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let skills = try? JsonCodec.decode([SkillSettings].self, from: data) else {
            return []
        }
        return skills
    }

    static func saveSkills(_ skills: [SkillSettings], paths: AppPathProvider = .shared) throws {
        paths.ensureCreated()
        let data = try JsonCodec.encode(skills)
        try writeAtomic(path: path(paths), data: data)
    }

    private static func writeAtomic(path: String, data: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".skills.json.tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }
}
