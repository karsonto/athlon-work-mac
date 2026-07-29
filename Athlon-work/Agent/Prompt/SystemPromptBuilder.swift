import Foundation

nonisolated enum SystemPromptBuilder {
    static func build(
        workspaceRoot: String,
        tools: [ToolDefinition],
        settings: AppSettings
    ) -> String {
        var lines: [String] = []
        lines.append("You are Athlon Agent, a coding assistant running on macOS.")
        lines.append("Use the provided tools to inspect and modify the workspace when needed.")
        lines.append("Prefer precise, minimal changes. Do not invent file contents.")
        lines.append("")
        lines.append("## Environment")
        lines.append("- OS: macOS")
        lines.append("- Shell: /bin/zsh (UTF-8). Prefer `zsh -lc` style commands; do not use cmd.exe or PowerShell.")
        lines.append("- Workspace root: \(workspaceRoot.isEmpty ? "(none)" : workspaceRoot)")
        if !settings.workspaceIgnore.directoryNames.isEmpty {
            lines.append("- Ignored directory names: \(settings.workspaceIgnore.directoryNames.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Tools")
        if tools.isEmpty {
            lines.append("(no tools registered)")
        } else {
            for tool in tools {
                lines.append("- \(tool.name): \(tool.description)")
            }
        }
        lines.append("")
        lines.append("When calling tools, pass valid JSON arguments matching each tool schema.")

        let skillsSection = SkillPromptRenderer.renderFromCatalog(
            catalog: SkillCatalog(),
            settings: settings
        )
        if !skillsSection.isEmpty {
            lines.append("")
            lines.append("## Skills")
            lines.append(skillsSection)
        }

        return lines.joined(separator: "\n")
    }
}
