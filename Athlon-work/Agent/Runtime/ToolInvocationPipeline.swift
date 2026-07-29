import Foundation

nonisolated struct ToolInvocationResult: Sendable {
    var toolCallId: String
    var toolName: String
    var output: String
    var approved: Bool
}

nonisolated final class ToolInvocationPipeline: @unchecked Sendable {
    private let router: ToolRouter
    private let settingsProvider: @Sendable () -> AppSettings

    init(router: ToolRouter, settingsProvider: @escaping @Sendable () -> AppSettings) {
        self.router = router
        self.settingsProvider = settingsProvider
    }

    func invoke(
        call: ToolCall,
        context: AgentRunContext,
        callbacks: AgentTurnCallbacks
    ) async throws -> ToolInvocationResult {
        try Task.checkCancellation()
        try ToolJSON.validateObjectString(call.arguments)

        let permissions = settingsProvider().toolPermissions
        if ToolApprovalPolicy.isDenied(toolName: call.name, arguments: call.arguments, permissions: permissions) {
            let output = "status: approval_denied\nTool '\(call.name)' is denied by policy."
            callbacks.onStreamEvent(.toolCallOutput(toolCallId: call.id, delta: output))
            callbacks.onStreamEvent(.toolCallResult(toolCallId: call.id, content: output, messageId: UUID().uuidString.replacingOccurrences(of: "-", with: "")))
            return ToolInvocationResult(toolCallId: call.id, toolName: call.name, output: output, approved: false)
        }

        let needsAsk: Bool
        if call.name == "execute_command", permissions.askBeforeEveryCommand {
            needsAsk = true
        } else {
            needsAsk = ToolApprovalPolicy.requiresApproval(
                toolName: call.name,
                arguments: call.arguments,
                permissions: permissions
            )
        }

        if needsAsk {
            let approved = await callbacks.onToolApprovalRequested(call)
            if !approved {
                let output = "status: approval_denied\nUser denied tool '\(call.name)'."
                callbacks.onStreamEvent(.toolCallOutput(toolCallId: call.id, delta: output))
                callbacks.onStreamEvent(.toolCallResult(toolCallId: call.id, content: output, messageId: UUID().uuidString.replacingOccurrences(of: "-", with: "")))
                return ToolInvocationResult(toolCallId: call.id, toolName: call.name, output: output, approved: false)
            }
        }

        guard let tool = router.tool(named: call.name) else {
            throw AgentToolError.unknownTool(call.name)
        }

        do {
            let output = try await tool.invoke(arguments: call.arguments, context: context)
            callbacks.onStreamEvent(.toolCallOutput(toolCallId: call.id, delta: output))
            let messageId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            callbacks.onStreamEvent(.toolCallResult(toolCallId: call.id, content: output, messageId: messageId))
            return ToolInvocationResult(toolCallId: call.id, toolName: call.name, output: output, approved: true)
        } catch {
            let output = "status: failed\n\(error.localizedDescription)"
            callbacks.onStreamEvent(.toolCallOutput(toolCallId: call.id, delta: output))
            callbacks.onStreamEvent(.toolCallResult(toolCallId: call.id, content: output, messageId: UUID().uuidString.replacingOccurrences(of: "-", with: "")))
            return ToolInvocationResult(toolCallId: call.id, toolName: call.name, output: output, approved: true)
        }
    }
}
