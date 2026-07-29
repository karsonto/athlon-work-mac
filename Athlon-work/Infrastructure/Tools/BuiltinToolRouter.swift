import Foundation

nonisolated final class BuiltinToolRouter: ToolRouter, @unchecked Sendable {
    let tools: [any AgentTool]

    init(tools: [any AgentTool]? = nil) {
        self.tools = tools ?? [
            FileListTool(),
            FileReadTool(),
            FileWriteTool(),
            FileEditTool(),
            GlobFilesTool(),
            GrepFilesTool(),
            ApplyPatchTool(),
            ExecuteCommandTool(),
        ]
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools.first { $0.name == name }
    }
}
