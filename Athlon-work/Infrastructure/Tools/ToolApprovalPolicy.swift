import Foundation

nonisolated enum ToolApprovalDecision: String, Sendable {
    case allow
    case deny
    case ask
}

nonisolated enum ToolApprovalPolicy {
    /// Evaluates command allow/deny lists. Deny wins over allow.
    static func decision(
        forCommand command: String,
        permissions: ToolPermissionSettings
    ) -> ToolApprovalDecision {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .ask }

        if matchesAny(normalized, patterns: permissions.commandDenyList) {
            return .deny
        }
        if matchesAny(normalized, patterns: permissions.commandAllowList) {
            if permissions.askBeforeEveryCommand {
                return .ask
            }
            return .allow
        }
        if permissions.approvalEnabled || permissions.askBeforeEveryCommand {
            return .ask
        }
        return .allow
    }

    static func requiresApproval(
        toolName: String,
        arguments: String,
        permissions: ToolPermissionSettings
    ) -> Bool {
        if toolName == "execute_command" {
            let command = extractCommand(from: arguments) ?? arguments
            switch decision(forCommand: command, permissions: permissions) {
            case .deny, .ask:
                return true
            case .allow:
                return permissions.askBeforeEveryCommand
            }
        }
        return permissions.approvalEnabled
    }

    static func isDenied(
        toolName: String,
        arguments: String,
        permissions: ToolPermissionSettings
    ) -> Bool {
        guard toolName == "execute_command" else { return false }
        let command = extractCommand(from: arguments) ?? arguments
        return decision(forCommand: command, permissions: permissions) == .deny
    }

    private static func extractCommand(from arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["command"] as? String ?? obj["Command"] as? String
    }

    private static func matchesAny(_ command: String, patterns: [String]) -> Bool {
        let lowered = command.lowercased()
        for pattern in patterns {
            let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !p.isEmpty else { continue }
            if lowered == p || lowered.hasPrefix(p + " ") || lowered.contains(" " + p + " ") || lowered.hasPrefix(p) {
                // Token / substring match: first token equals pattern, or pattern appears as prefix.
                let firstToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered
                if firstToken == p || lowered.hasPrefix(p) {
                    return true
                }
            }
        }
        return false
    }
}
