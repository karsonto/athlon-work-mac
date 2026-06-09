import Foundation
import Combine

// MARK: - Skill Service
class SkillService: ObservableObject {
    @Published var skills: [SkillItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private let skillsDir: URL

    init(skillsDirectory: URL? = nil) {
        if let dir = skillsDirectory {
            self.skillsDir = dir
        } else {
            self.skillsDir = URL(fileURLWithPath: AppPathProvider.shared.skillsPath, isDirectory: true)
        }
        ensureDirectory()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    }

    func reload(savedSettings: [SkillSettings] = []) {
        isLoading = true
        defer { isLoading = false }

        let installed = SkillSettingsMerger.scanInstalled(skillsRootPath: skillsDir.path)
        let merged = SkillSettingsMerger.merge(
            skillsRootPath: skillsDir.path,
            installedSkills: installed,
            saved: savedSettings
        )

        skills = merged.compactMap { settings in
            let folder = (settings.path?.isEmpty == false) ? settings.path! : settings.name
            let skillFile = resolveSkillFile(folderName: folder)
            guard let skillFile else { return nil }
            let (description, _) = parseSkillMetadata(from: skillFile)
            let skillDirectory = skillsDir.appendingPathComponent(folder).path
            return SkillItem(
                id: settings.name,
                name: settings.name,
                description: description ?? "",
                isEnabled: settings.enabled,
                isInstalled: true,
                skillDirectory: FileManager.default.fileExists(atPath: skillDirectory) ? skillDirectory : nil
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func resolveSkillFile(folderName: String) -> URL? {
        let folder = skillsDir.appendingPathComponent(folderName)
        let upper = folder.appendingPathComponent("SKILL.md")
        let lower = folder.appendingPathComponent("skill.md")
        if FileManager.default.fileExists(atPath: upper.path) { return upper }
        if FileManager.default.fileExists(atPath: lower.path) { return lower }
        return nil
    }

    private func parseSkillMetadata(from fileURL: URL) -> (description: String?, version: String?) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (nil, nil)
        }
        var description: String?
        var version: String?
        for line in content.components(separatedBy: "\n").prefix(20) {
            if line.hasPrefix("description:") || line.hasPrefix("Description:") {
                description = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("version:") || line.hasPrefix("Version:") {
                version = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return (description, version)
    }

    func isSkillEnabled(_ name: String) -> Bool {
        skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.isEnabled ?? false
    }

    func addSkill(name: String, content: String) {
        let skillDir = skillsDir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let skillFile = skillDir.appendingPathComponent("SKILL.md")
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
        } catch {
            self.error = "创建技能失败: \(error.localizedDescription)"
        }
    }

    func deleteSkill(_ name: String) {
        let skillDir = skillsDir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: skillDir)
        skills.removeAll { $0.name == name }
    }

    var enabledSkills: [SkillItem] {
        skills.filter(\.isEnabled)
    }

    func skillContent(for name: String) -> String? {
        guard let file = resolveSkillFile(folderName: name) else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }
}
