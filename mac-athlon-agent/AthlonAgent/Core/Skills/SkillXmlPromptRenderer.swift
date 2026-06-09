import Foundation

enum SkillXmlPromptRenderer {
    private static let xmlTagNamePattern = try! NSRegularExpression(
        pattern: "^[A-Za-z_][A-Za-z0-9_.-]*$",
        options: []
    )

    static func appendSkillPrompt(to builder: inout String, skills: [AvailableSkillInfo]) {
        guard !skills.isEmpty else { return }

        builder += "## Available Skills\n"
        builder += "\n"
        builder += "<usage>\n"
        builder += "Skills provide specialized capabilities. Use them when they match the current task.\n"
        builder += "Load skill: load_skill_through_path(skillId=\"<skill-name>\", path=\"SKILL.md\")\n"
        builder += "Load resources with the same tool and a skill-internal relative path (e.g. references/guide.md).\n"
        builder += "For load_skill_through_path, use only paths inside the skill — not '.', './', absolute paths, or the shared skills install directory.\n"
        builder += "Each <skill> may include <files-root> with the absolute path for shell-executing that skill's scripts.\n"
        builder += "</usage>\n"
        builder += "\n"
        builder += "<available_skills>\n"

        var hasFilesRoot = false
        for skill in skills {
            if appendSkill(to: &builder, skill: skill) {
                hasFilesRoot = true
            }
        }

        builder += "</available_skills>\n"
        builder += "\n"

        if hasFilesRoot {
            appendCodeExecutionSection(to: &builder)
        }
    }

    @discardableResult
    private static func appendSkill(to builder: inout String, skill: AvailableSkillInfo) -> Bool {
        builder += "<skill>\n"
        appendXmlNode(to: &builder, key: "name", value: skill.name, indentLevel: 1)
        appendXmlNode(to: &builder, key: "description", value: skill.description, indentLevel: 1)
        appendXmlNode(to: &builder, key: "skill-id", value: skill.skillId, indentLevel: 1)

        let filesRoot = SkillPathFormatter.formatFilesRoot(skill: skill)
        if let filesRoot {
            appendXmlNode(to: &builder, key: "files-root", value: filesRoot, indentLevel: 1)
        }

        builder += "</skill>\n"
        builder += "\n"
        return filesRoot != nil
    }

    private static func appendCodeExecutionSection(to builder: inout String) {
        builder += "## Code Execution\n"
        builder += "\n"
        builder += "<code_execution>\n"
        builder += "You have access to execute_command. Each skill in <available_skills> includes a <files-root> element giving the absolute path to that skill's files.\n"
        builder += "Workflow:\n"
        builder += "1. After loading a skill, look at its <files-root> in <available_skills> or the Files root line in the load response.\n"
        builder += "2. List its files:    dir \"<files-root>\"\n"
        builder += "3. Run scripts:       python \"<files-root>/scripts/<script-name>\"\n"
        builder += "4. Always use absolute paths derived from <files-root>; never invent paths.\n"
        builder += "5. execute_command cwd still defaults to the workspace root; run skill scripts via absolute paths in the command, not by switching cwd.\n"
        builder += "6. Quote paths that contain spaces or non-ASCII characters.\n"
        builder += "</code_execution>\n"
        builder += "\n"
    }

    private static func appendXmlNode(to builder: inout String, key: String, value: String?, indentLevel: Int) {
        guard let value, !value.isEmpty else { return }
        let indent = String(repeating: " ", count: indentLevel * 2)
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        let isValidTag = xmlTagNamePattern.firstMatch(in: key, range: range) != nil
        let openTag = isValidTag ? "<\(key)>" : "<entry key=\"\(escapeXml(key))\">"
        let closeTag = isValidTag ? "</\(key)>" : "</entry>"
        builder += indent + openTag + escapeXml(value) + closeTag + "\n"
    }

    private static func escapeXml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
