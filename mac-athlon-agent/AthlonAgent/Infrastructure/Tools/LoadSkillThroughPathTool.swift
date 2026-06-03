import Foundation

/// Loads skill resources from ~/.athlon-agent/skills (aligned with WPF `ISkillRuntime`).
final class SkillResourceLoader {
    private let skillService: SkillService
    private let skillsRoot: String

    init(skillService: SkillService, appPaths: AppPathProvider = .shared) {
        self.skillService = skillService
        self.skillsRoot = appPaths.skillsPath
    }

    func availableSkillIds() -> [String] {
        skillService.skills.filter(\.isEnabled).map(\.name)
    }

    func loadResource(skillId: String, path: String) throws -> String {
        let trimmedId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw ToolError.failed("Skill load failed", detail: "Missing or empty required parameter: skillId")
        }

        guard skillService.isSkillEnabled(trimmedId) else {
            throw ToolError.failed(
                "Skill load failed",
                detail: "Skill '\(trimmedId)' is disabled. Enable it in Settings > Skills before loading."
            )
        }

        let normalizedPath = try normalizeResourcePath(path)
        let skillDir = (skillsRoot as NSString).appendingPathComponent(trimmedId)
        guard FileManager.default.fileExists(atPath: skillDir) else {
            let available = availableSkillIds().joined(separator: ", ")
            throw ToolError.failed(
                "Skill load failed",
                detail: "Skill not found: '\(trimmedId)'. Available: \(available.isEmpty ? "(none)" : available)"
            )
        }

        if normalizedPath.caseInsensitiveCompare("SKILL.md") == .orderedSame
            || normalizedPath.caseInsensitiveCompare("skill.md") == .orderedSame {
            if let content = skillService.skillContent(for: trimmedId) {
                return content
            }
            let skillMd = (skillDir as NSString).appendingPathComponent("SKILL.md")
            let skillLower = (skillDir as NSString).appendingPathComponent("skill.md")
            if FileManager.default.fileExists(atPath: skillMd) {
                return try String(contentsOfFile: skillMd, encoding: .utf8)
            }
            if FileManager.default.fileExists(atPath: skillLower) {
                return try String(contentsOfFile: skillLower, encoding: .utf8)
            }
            throw ToolError.failed("Skill load failed", detail: "SKILL.md not found for skill '\(trimmedId)'")
        }

        let resourcePath = (skillDir as NSString).appendingPathComponent(normalizedPath)
        guard FileManager.default.fileExists(atPath: resourcePath) else {
            throw ToolError.failed(
                "Skill load failed",
                detail: "Resource not found: '\(normalizedPath)' in skill '\(trimmedId)'"
            )
        }
        return try String(contentsOfFile: resourcePath, encoding: .utf8)
    }

    private func normalizeResourcePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.failed("Skill load failed", detail: "Missing or empty required parameter: path")
        }
        if trimmed == "." || trimmed == "./" || trimmed.hasSuffix("/") || trimmed.hasPrefix("/") {
            throw ToolError.failed(
                "Skill load failed",
                detail: "Invalid path '\(path)'. Use 'SKILL.md' or a relative resource path such as 'references/guide.md'."
            )
        }
        return trimmed.replacingOccurrences(of: "\\", with: "/")
    }
}

struct LoadSkillThroughPathTool: AgentTool {
    private let loader: SkillResourceLoader

    var name: String { "load_skill_through_path" }

    var description: String {
        let skillIdList = loader.availableSkillIds()
        let listed = skillIdList.isEmpty
            ? "(none — install skills under the skills directory first)"
            : skillIdList.joined(separator: ", ")
        return """
        Load and activate a skill resource by name and resource path.

        **Functionality:**
        1. Activates the specified skill
        2. Returns the requested resource content

        **Path rules:**
        - Use path="SKILL.md" to load the skill's markdown documentation.
        - Use exact resource paths such as "references/guide.md".
        - Do not use '.', './', directories only, or absolute paths.

        **Available skill names:** \(listed)
        """
    }

    var parametersSchema: [String: String] = [
        "skillId": "The skill name from SKILL.md frontmatter (see Available skill names in the description).",
        "path": "Relative resource path within the skill. Use 'SKILL.md' for full instructions."
    ]

    init(loader: SkillResourceLoader) {
        self.loader = loader
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let skillId = try ToolArguments.required(arguments, name: "skillId", tool: name)
        let path = try ToolArguments.required(arguments, name: "path", tool: name)
        let content = try loader.loadResource(skillId: skillId, path: path)
        return ToolResultFormatter.success("Loaded skill resource from \(skillId)", content: content)
    }
}
