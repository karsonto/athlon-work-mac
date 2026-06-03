import Foundation

struct FrozenSystemPrompt: Equatable {
    let text: String
}

struct EnvironmentPromptContext {
    let session: AgentSession
    let workspaceRoot: String?
    let workspaceName: String?
    let ignorePatterns: [String]
    let tools: [ToolDefinition]
    let skillsDirectory: String
    let interactionMode: AgentInteractionMode
    let planAutoContinueEnabled: Bool
    let planMaxSubtasks: Int

    var hasWorkspace: Bool {
        guard let workspaceRoot else { return false }
        return !workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Builds system prompts aligned with WPF `SystemPromptOrchestrator`.
struct SystemPromptOrchestrator {
    let settings: AppSettings
    let skillsDirectory: String

    init(settings: AppSettings, skillsDirectory: String = AppPathProvider.shared.skillsPath) {
        self.settings = settings
        self.skillsDirectory = skillsDirectory
    }

    func prepareForTurn(session: AgentSession, tools: [ToolDefinition], skills: [AvailableSkillInfo]) -> FrozenSystemPrompt {
        let context = makeContext(session: session, tools: tools)
        var builder = ""
        appendBasePersona(&builder)
        appendHostEnvironment(&builder)
        appendWorkspacePolicy(&builder, context: context)
        appendPlanModePolicy(&builder, context: context)
        appendPlanExecutionPolicy(&builder, context: context)
        appendFileToolsPolicy(&builder)
        appendToolsPolicy(&builder, context: context)
        appendSkillsList(&builder, skills: skills)
        appendProductGuidance(&builder)
        return FrozenSystemPrompt(text: formatPrompt(builder))
    }

    func buildForReasoningIteration(
        frozen: FrozenSystemPrompt,
        session: AgentSession,
        tools: [ToolDefinition]
    ) -> String {
        frozen.text
    }

    private func makeContext(session: AgentSession, tools: [ToolDefinition]) -> EnvironmentPromptContext {
        let workspace = resolveWorkspace(session)
        return EnvironmentPromptContext(
            session: session,
            workspaceRoot: workspace?.rootPath,
            workspaceName: workspace?.name,
            ignorePatterns: workspace?.ignorePatterns ?? settings.workspaceIgnore.directoryNames,
            tools: tools,
            skillsDirectory: skillsDirectory,
            interactionMode: session.interactionMode,
            planAutoContinueEnabled: settings.plan.autoContinueEnabled,
            planMaxSubtasks: settings.plan.maxSubtasks
        )
    }

    private struct ResolvedWorkspace {
        let name: String
        let rootPath: String
        let ignorePatterns: [String]
    }

    private func resolveWorkspace(_ session: AgentSession) -> ResolvedWorkspace? {
        if let active = session.activeWorkspace, !active.isEmpty {
            let rootPath = URL(fileURLWithPath: active).standardizedFileURL.path
            let name = (rootPath as NSString).lastPathComponent
            let match = settings.workspaces.first {
                !$0.rootPath.isEmpty
                    && URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == rootPath
            }
            let patterns = match?.ignorePatterns ?? settings.workspaceIgnore.directoryNames
            return ResolvedWorkspace(name: name, rootPath: rootPath, ignorePatterns: patterns)
        }
        guard let configured = settings.workspaces.first(where: { !$0.rootPath.isEmpty }) else { return nil }
        let rootPath = URL(fileURLWithPath: configured.rootPath).standardizedFileURL.path
        return ResolvedWorkspace(
            name: configured.name,
            rootPath: rootPath,
            ignorePatterns: configured.ignorePatterns ?? settings.workspaceIgnore.directoryNames
        )
    }

    private func appendBasePersona(_ builder: inout String) {
        builder += "You are Athlon Agent, a macOS desktop coding agent.\n"
        builder += "Use the provided function tools when you need to inspect or modify workspace files. Do not guess file contents.\n"
        builder += "Think through the user's goal, constraints, and risks before calling tools or making changes. Share concise reasoning when it helps the user follow your approach.\n"
        builder += "\n"
    }

    private func appendHostEnvironment(_ builder: inout String) {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        let tz = TimeZone.current.identifier
        let user = NSFullUserName()
        let cwd = FileManager.default.currentDirectoryPath
        builder += "Host: macOS \(version) | \(formatter.string(from: now)) \(tz) | \(user) | cwd=\(cwd) | skills=\(skillsDirectory)\n"
        builder += "\n"
    }

    private func appendWorkspacePolicy(_ builder: inout String, context: EnvironmentPromptContext) {
        guard context.hasWorkspace else {
            builder += "当前工作区尚未设定。文件工具可使用绝对路径或相对于当前进程工作目录的路径。\n"
            builder += "\n"
            return
        }

        builder += "All relative file paths are resolved from the active workspace. Use absolute paths for files outside the workspace.\n"
        builder += "In file tool arguments (path), always use forward slashes (/), e.g. src/foo.swift.\n"
        builder += "Paths are relative to Workspace root below — not cwd, not a parent directory, and not an absolute path.\n"
        builder += "Correct: src/foo.swift. Wrong: \(context.workspaceName ?? "workspace")/src/foo.swift or the full Workspace root path in path.\n"
        builder += "Active workspace label: \(context.workspaceName ?? "workspace") (not a path prefix — do not include in file tool path).\n"
        builder += "Workspace root: \(context.workspaceRoot ?? "")\n"
        if let agentsMd = loadAgentsMarkdown(workspaceRoot: context.workspaceRoot) {
            builder += "\n## AGENTS.md\n\(agentsMd)\n"
        }
        if let knowledge = loadKnowledgeSnippet(workspaceRoot: context.workspaceRoot) {
            builder += "\n## Knowledge\n\(knowledge)\n"
        }
        builder += "Workspace contents are intentionally not embedded in this prompt because they change often.\n"
        builder += "Use file_list to fetch a live directory listing when needed.\n"
        if context.interactionMode == .agent {
            appendPlanningGuidance(&builder, context: context)
        }
        builder += "\n"
    }

    private func appendPlanModePolicy(_ builder: inout String, context: EnvironmentPromptContext) {
        guard context.interactionMode == .plan else { return }
        builder += "Plan mode (spec-first workflow):\n"
        builder += "- You are in Plan mode: research and specify before implementation. Do not write files, edit files, or run commands.\n"
        builder += "- Separate what to build from building it. The user approves the plan via the Build button before any execution.\n"
        builder += "\nWhen to create a plan:\n"
        builder += "- Complex features with multiple approaches; tasks touching many files or systems; unclear requirements; architectural decisions.\n"
        builder += "- For small, obvious one-file fixes, a full plan is optional — still answer concisely.\n"
        builder += "\nWorkflow:\n"
        builder += "- Research first: use file_list, file_read, grep_files, glob_files; do not guess file contents.\n"
        builder += "- Clarify when needed: ask focused questions before locking the plan.\n"
        builder += "- Create a detailed plan: call create_plan with ordered subtasks (up to \(context.planMaxSubtasks)). "
        builder += "Provide overview (Markdown), optional architecture/mermaid/testing/out_of_scope, and subtasks with concrete repo-relative files and measurable expected_outcome.\n"
        builder += "- Do not hand-write plan.md with file_write; plan tools sync it automatically.\n"
        builder += "- Use get_plan to review the current draft plan and subtask states.\n"
        builder += "- Do not call finish_subtask in Plan mode. Tell the user to review plan.md and click Build to execute.\n"
        builder += "\ncreate_plan document shape (Cursor-style):\n"
        builder += "- overview: background, goals, constraints, key decisions (required, substantive Markdown).\n"
        builder += "- architecture / mermaid: use for multi-step or cross-cutting work.\n"
        builder += "- Each subtask: name, description, expected_outcome (verifiable), files[] (paths you will touch).\n"
        builder += "\nAfter the plan is ready:\n"
        builder += "- Summarize briefly and ask the user to review plan.md and click Build when ready.\n"
        builder += "\n"
    }

    private func appendPlanExecutionPolicy(_ builder: inout String, context: EnvironmentPromptContext) {
        guard context.interactionMode == .agent,
              context.session.plan?.phase == .approved else { return }
        builder += "Approved plan execution:\n"
        builder += "- Call get_plan first. Work subtasks in order; call finish_subtask with concrete measurable outcomes.\n"
        builder += "- Only get_plan and finish_subtask are available for plan management during execution.\n"
        builder += "\n"
    }

    private func appendPlanningGuidance(_ builder: inout String, context: EnvironmentPromptContext) {
        builder += "Planning for multi-step or long-running tasks:\n"
        builder += "- For requests that span multiple turns, many files, or roughly more than 30 minutes of work, call create_plan first; do not attempt the entire scope in one turn.\n"
        builder += "- Split work into granular subtasks (up to \(context.planMaxSubtasks)): each subtask must be a smallest verifiable unit completable in one focused turn (e.g. add API + unit test), not vague goals like \"finish the module\".\n"
        builder += "- Name each subtask and fill description / expectedOutcome with concrete, measurable details (paths, types, commands, acceptance criteria); avoid vague phrases like \"improve code\" or \"polish feature\".\n"
        builder += "- Prefer more short subtasks over a few large ones; use create_plan to replace the plan if scope changes.\n"
        builder += "- Use create_plan to define the plan and ordered subtasks (do not hand-write plan.md with file_write).\n"
        builder += "- Execute one in-progress subtask at a time; after each step, call finish_subtask with a specific measurable outcome.\n"
        builder += "- Use get_plan when you need the full current plan and subtask states.\n"
        builder += "- plan.md is synced automatically by plan tools; do not edit checkboxes in plan.md with file_edit unless the user explicitly asks.\n"
        if context.planAutoContinueEnabled {
            builder += "- While a subtask is in progress, the client may auto-send a continue instruction when a turn ends; do not claim the overall task is complete until every subtask is done or abandoned.\n"
            builder += "- If the current subtask is still too large for one turn, split remaining work into smaller subtasks via create_plan before continuing.\n"
        }
    }

    private func appendFileToolsPolicy(_ builder: inout String) {
        builder += "File tools:\n"
        builder += "- For large files, use grep_files or glob_files to locate content before file_read.\n"
        builder += "- Use file_read with offset and limit to read in chunks; do not assume a single read covers the whole file.\n"
        builder += "- When file_read returns truncated: true or a next_offset in the meta footer, continue with that offset.\n"
        builder += "- file_read line output uses N| prefixes for display only; file_edit old_text must match disk content without those prefixes.\n"
        builder += "\n"
    }

    private func appendToolsPolicy(_ builder: inout String, context: EnvironmentPromptContext) {
        builder += "Tools:\n"
        if context.interactionMode == .plan {
            builder += "Plan mode: read-only file tools plus create_plan and get_plan. No file_write, file_edit, or execute_command.\n"
        } else if context.session.plan?.phase == .approved {
            builder += "Agent mode with approved plan: use get_plan and finish_subtask; other native tools per schema.\n"
        } else {
            builder += "Native tools via function calling; long tasks use create_plan with granular subtasks. Use each tool's schema.\n"
        }
        builder += "Do not guess file contents.\n"
        builder += "\n"

        let mcpTools = context.tools.filter { $0.source?.lowercased() == "mcp" }
        if !mcpTools.isEmpty {
            builder += "Available MCP tools:\n"
            for tool in mcpTools {
                builder += "- \(tool.name): \(tool.description)\n"
            }
            builder += "\n"
        }

        builder += "For write operations, explain your intent before calling file_write or file_edit.\n"
        builder += "macOS: use bash/zsh via execute_command; avoid Windows-only shell assumptions.\n"
        builder += "\n"
    }

    private func appendSkillsList(_ builder: inout String, skills: [AvailableSkillInfo]) {
        guard !skills.isEmpty else { return }
        builder += "\n"
        builder += "## Available Skills\n"
        builder += "\n"
        builder += "<usage>\n"
        builder += "Skills provide specialized capabilities. Use them when they match the current task.\n"
        builder += "Load skill: load_skill_through_path(skillId=\"<skill-name>\", path=\"SKILL.md\")\n"
        builder += "Load resources with the same tool and a relative path (e.g. references/guide.md).\n"
        builder += "Do not use '.', './', absolute paths, or the skills directory root as path.\n"
        builder += "</usage>\n"
        builder += "\n"
        builder += "<available_skills>\n"
        for skill in skills {
            builder += "<skill>\n"
            builder += "  <name>\(escapeXml(skill.name))</name>\n"
            if !skill.description.isEmpty {
                builder += "  <description>\(escapeXml(skill.description))</description>\n"
            }
            builder += "  <skill-id>\(escapeXml(skill.skillId))</skill-id>\n"
            builder += "</skill>\n"
            builder += "\n"
        }
        builder += "</available_skills>\n"
        builder += "\n"
    }

    private func appendProductGuidance(_ builder: inout String) {
        builder += "When context grows large, history is auto-compressed; full transcripts are kept under the session transcripts folder.\n"
        builder += "\n"
        builder += "Mermaid diagrams in chat:\n"
        builder += "- When a diagram clarifies the answer better than prose alone, include one or more fenced ```mermaid code blocks (e.g. flowchart, sequenceDiagram, stateDiagram-v2, classDiagram, erDiagram, gantt).\n"
        builder += "- Prefer Mermaid for: request/API flows, multi-step processes, component or deployment topology, state transitions, timelines, and decision branches.\n"
        builder += "- Skip diagrams for simple factual answers, short lists, or when the user only wants code/text.\n"
        builder += "- Keep each diagram focused; use multiple small diagrams instead of one huge chart.\n"
        builder += "- In Athlon Agent the chat shows Mermaid as source code, not inline graphics. Tell the user they can right-click the message and choose \"查看 Mermaid 图表\" for an offline rendered preview.\n"
        builder += "- Do not claim an inline image is visible unless you also describe the structure in text.\n"
    }

    private func loadAgentsMarkdown(workspaceRoot: String?) -> String? {
        guard let workspaceRoot, !workspaceRoot.isEmpty else { return nil }
        let path = (workspaceRoot as NSString).appendingPathComponent("AGENTS.md")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = settings.prompt.maxAgentsMdChars
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }

    private func loadKnowledgeSnippet(workspaceRoot: String?) -> String? {
        guard let workspaceRoot, !workspaceRoot.isEmpty else { return nil }
        let knowledgeDir = (workspaceRoot as NSString).appendingPathComponent("knowledge")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: knowledgeDir) else { return nil }
        let maxEntries = settings.prompt.maxKnowledgeCatalogEntries
        let perFileLimit = settings.prompt.maxKnowledgeMdChars
        var parts: [String] = []
        for file in files.sorted().prefix(maxEntries) where file.hasSuffix(".md") {
            let path = (knowledgeDir as NSString).appendingPathComponent(file)
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append("### \(file)\n\(String(trimmed.prefix(perFileLimit)))")
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private func formatPrompt(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func escapeXml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
