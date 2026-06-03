import Foundation

enum PlanToolCatalog {
    static let createPlan = "create_plan"
    static let finishSubtask = "finish_subtask"
    static let getPlan = "get_plan"

    private static let planToolNames: Set<String> = [
        createPlan, finishSubtask, getPlan
    ]

    private static let mutatingNativeToolNames: Set<String> = [
        "file_write", "file_edit", "execute_command"
    ]

    static func isPlanTool(_ toolName: String) -> Bool {
        planToolNames.contains(toolName.lowercased())
    }

    static func isMutatingNativeTool(_ toolName: String) -> Bool {
        mutatingNativeToolNames.contains(toolName.lowercased())
    }

    static func filterForSession(
        _ tools: [ToolDefinition],
        mode: AgentInteractionMode,
        plan: AgentPlan?
    ) -> [ToolDefinition] {
        if mode == .plan {
            return tools.filter { tool in
                !isMutatingNativeTool(tool.name)
                    && tool.name.lowercased() != finishSubtask
            }
        }

        let filtered = tools.filter { !isPlanTool($0.name) }
        guard plan?.phase == .approved else {
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let executionTools = tools.filter { tool in
            tool.name.lowercased() == getPlan || tool.name.lowercased() == finishSubtask
        }
        return (filtered + executionTools)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
