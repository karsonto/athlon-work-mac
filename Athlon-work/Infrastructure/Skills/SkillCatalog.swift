import Foundation

nonisolated struct AvailableSkillInfo: Sendable, Hashable, Identifiable {
    var id: String { name.isEmpty ? directoryPath : name }
    var name: String
    var description: String
    var directoryPath: String
    var skillFilePath: String
    var enabled: Bool
}

/// Scans `~/.athlon-agent/skills/*/SKILL.md` (or `skill.md`) and parses YAML frontmatter.
nonisolated final class SkillCatalog: @unchecked Sendable {
    private let paths: AppPathProviding
    private let fileManager: FileManager

    init(paths: AppPathProviding = AppPathProvider(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func listAvailableSkills(settings: AppSettings? = nil) -> [AvailableSkillInfo] {
        try? paths.ensureCreated()
        var results: [AvailableSkillInfo] = []
        let root = paths.skillsPath
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else {
            return mergeConfiguredSkills([], settings: settings)
        }

        for name in entries.sorted() {
            let dir = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let skillFile = locateSkillFile(in: dir) else { continue }
            let parsed = parseFrontmatter(at: skillFile)
            let skillName = parsed.name.isEmpty ? name : parsed.name
            let enabled = settings?.skills.first(where: {
                $0.name.caseInsensitiveCompare(skillName) == .orderedSame
                    || paths.resolveSkillPath($0.path) == dir
            })?.enabled ?? true
            results.append(
                AvailableSkillInfo(
                    name: skillName,
                    description: parsed.description,
                    directoryPath: dir,
                    skillFilePath: skillFile,
                    enabled: enabled
                )
            )
        }

        return mergeConfiguredSkills(results, settings: settings)
    }

    func loadSkillBody(info: AvailableSkillInfo) -> String? {
        guard let text = try? String(contentsOfFile: info.skillFilePath, encoding: .utf8) else {
            return nil
        }
        return stripFrontmatter(text)
    }

    // MARK: - Private

    private func locateSkillFile(in directory: String) -> String? {
        let candidates = ["SKILL.md", "skill.md", "Skill.md"]
        for name in candidates {
            let path = (directory as NSString).appendingPathComponent(name)
            if fileManager.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func mergeConfiguredSkills(
        _ scanned: [AvailableSkillInfo],
        settings: AppSettings?
    ) -> [AvailableSkillInfo] {
        guard let settings else { return scanned }
        var byPath = Dictionary(uniqueKeysWithValues: scanned.map { ($0.directoryPath, $0) })
        for cfg in settings.skills where !cfg.path.isEmpty {
            let resolved = paths.resolveSkillPath(cfg.path)
            if byPath[resolved] != nil { continue }
            guard let skillFile = locateSkillFile(in: resolved) else { continue }
            let parsed = parseFrontmatter(at: skillFile)
            let name = cfg.name.isEmpty ? (parsed.name.isEmpty ? (resolved as NSString).lastPathComponent : parsed.name) : cfg.name
            byPath[resolved] = AvailableSkillInfo(
                name: name,
                description: parsed.description,
                directoryPath: resolved,
                skillFilePath: skillFile,
                enabled: cfg.enabled
            )
        }
        return byPath.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct Frontmatter {
        var name: String = ""
        var description: String = ""
    }

    private func parseFrontmatter(at path: String) -> Frontmatter {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return Frontmatter()
        }
        guard text.hasPrefix("---") else { return Frontmatter() }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.first == "---" else { return Frontmatter() }
        var end = 1
        while end < parts.count, parts[end] != "---" { end += 1 }
        guard end < parts.count else { return Frontmatter() }
        let yaml = parts[1..<end].joined(separator: "\n")
        var result = Frontmatter()
        for line in yaml.split(separator: "\n") {
            let raw = String(line)
            if let name = yamlScalar(raw, key: "name") { result.name = name }
            if let desc = yamlScalar(raw, key: "description") { result.description = desc }
        }
        return result
    }

    private func yamlScalar(_ line: String, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\(key):") else { return nil }
        var value = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.first == "---" else { return text }
        var end = 1
        while end < parts.count, parts[end] != "---" { end += 1 }
        guard end < parts.count else { return text }
        return parts[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
