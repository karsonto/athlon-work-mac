import Foundation
import Combine

// MARK: - Skill Service
/// Manages skill loading, parsing, and enable/disable state. Skills are loaded from a configurable directory.
class SkillService: ObservableObject {
    @Published var skills: [SkillItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private let skillsDir: URL
    private let configFile: URL

    init(skillsDirectory: URL? = nil) {
        if let dir = skillsDirectory {
            self.skillsDir = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.skillsDir = home.appendingPathComponent(".athlon-agent/skills")
        }
        self.configFile = skillsDir.appendingPathComponent("skills_config.json")
        ensureDirectory()
        loadSkills()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    }

    // MARK: - Load Skills
    func loadSkills() {
        isLoading = true
        defer { isLoading = false }

        // Load enable/disable state from config
        var enabledStates: [String: Bool] = [:]
        if FileManager.default.fileExists(atPath: configFile.path) {
            if let data = try? Data(contentsOf: configFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
                enabledStates = json
            }
        }

        // Scan skills directory
        var loadedSkills: [SkillItem] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in contents {
                // Each skill is a subdirectory with skill.md
                let skillFile = url.appendingPathComponent("skill.md")
                guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }

                let name = url.lastPathComponent
                let (description, version) = parseSkillMetadata(from: skillFile)

                let enabled = enabledStates[name] ?? true
                let skill = SkillItem(
                    id: name,
                    name: name,
                    description: description,
                    version: version,
                    path: url,
                    isEnabled: enabled
                )
                loadedSkills.append(skill)
            }
        }

        skills = loadedSkills.sorted { $0.name < $1.name }
    }

    // MARK: - Parse Skill Metadata
    private func parseSkillMetadata(from fileURL: URL) -> (description: String?, version: String?) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (nil, nil)
        }

        var description: String?
        var version: String?

        let lines = content.components(separatedBy: "\n")
        for line in lines.prefix(10) {
            if line.hasPrefix("description:") || line.hasPrefix("Description:") {
                description = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("version:") || line.hasPrefix("Version:") {
                version = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            }
        }

        return (description, version)
    }

    // MARK: - Toggle Skill
    func toggleSkill(_ name: String) {
        if let idx = skills.firstIndex(where: { $0.name == name }) {
            skills[idx].isEnabled.toggle()
            saveEnabledStates()
        }
    }

    func setSkillEnabled(_ name: String, enabled: Bool) {
        if let idx = skills.firstIndex(where: { $0.name == name }) {
            skills[idx].isEnabled = enabled
            saveEnabledStates()
        }
    }

    // MARK: - Add Skill
    func addSkill(name: String, content: String) {
        let skillDir = skillsDir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let skillFile = skillDir.appendingPathComponent("skill.md")
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
            loadSkills()
        } catch {
            self.error = "创建技能失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete Skill
    func deleteSkill(_ name: String) {
        let skillDir = skillsDir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: skillDir)
        skills.removeAll { $0.name == name }
        saveEnabledStates()
    }

    // MARK: - Save Enabled States
    private func saveEnabledStates() {
        var states: [String: Bool] = [:]
        for skill in skills {
            states[skill.name] = skill.isEnabled
        }
        if let data = try? JSONSerialization.data(withJSONObject: states, options: .prettyPrinted) {
            try? data.write(to: configFile, options: .atomic)
        }
    }

    // MARK: - Helpers
    var enabledSkills: [SkillItem] {
        skills.filter { $0.isEnabled }
    }

    var enabledSkillNames: [String] {
        enabledSkills.map { $0.name }
    }

    func skillContent(for name: String) -> String? {
        let skillFile = skillsDir.appendingPathComponent("\(name)/skill.md")
        return try? String(contentsOf: skillFile, encoding: .utf8)
    }

    // MARK: - Reload
    func reload() {
        loadSkills()
    }
}
