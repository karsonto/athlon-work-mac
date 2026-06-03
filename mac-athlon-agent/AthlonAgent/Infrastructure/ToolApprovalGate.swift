import AppKit

@MainActor
enum ToolApprovalGate {
    static func requestApproval(
        toolName: String,
        arguments: [String: String],
        askBeforeEveryCommand: Bool
    ) -> Bool {
        guard askBeforeEveryCommand else { return true }

        let alert = NSAlert()
        alert.messageText = "确认执行工具？"
        alert.informativeText = "工具：\(toolName)\n参数：\(argumentsDescription(arguments))"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "允许")
        alert.addButton(withTitle: "拒绝")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func argumentsDescription(_ arguments: [String: String]) -> String {
        let text = arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        if text.count > 500 {
            return String(text.prefix(500)) + "…"
        }
        return text.isEmpty ? "(无)" : text
    }
}
