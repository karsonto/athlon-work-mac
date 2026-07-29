import Foundation

nonisolated struct ExecuteCommandTool: AgentTool {
    let name = "execute_command"
    var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Run a shell command via /bin/zsh -lc in the workspace (UTF-8). Prefer non-interactive commands.",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string"] as [String: Any],
                    "timeout_seconds": ["type": "integer", "description": "Timeout in seconds (default 120)"] as [String: Any],
                ] as [String: Any],
                "required": ["command"],
            ]
        )
    }

    func invoke(arguments: String, context: AgentRunContext) async throws -> String {
        let args = try ToolJSON.object(from: arguments)
        guard let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("command is required")
        }
        let timeout = max(1, (args["timeout_seconds"] as? Int) ?? 120)
        let cwd = context.workspaceRoot.isEmpty ? FileManager.default.currentDirectoryPath : context.workspaceRoot

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var env = ProcessInfo.processInfo.environment
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let result: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                process.waitUntilExit()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? String(decoding: outData, as: UTF8.self)
                let err = String(data: errData, encoding: .utf8) ?? String(decoding: errData, as: UTF8.self)
                let code = process.terminationStatus
                var parts: [String] = []
                parts.append("exit_code: \(code)")
                if !out.isEmpty { parts.append("stdout:\n\(out)") }
                if !err.isEmpty { parts.append("stderr:\n\(err)") }
                if code != 0 {
                    parts.append("status: failed")
                }
                return parts.joined(separator: "\n")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                if process.isRunning {
                    process.terminate()
                    throw AgentToolError.executionFailed("Command timed out after \(timeout)s")
                }
                return ""
            }
            let first = try await group.next()!
            group.cancelAll()
            if process.isRunning {
                process.terminate()
            }
            return first
        }
        try Task.checkCancellation()
        return result
    }
}
