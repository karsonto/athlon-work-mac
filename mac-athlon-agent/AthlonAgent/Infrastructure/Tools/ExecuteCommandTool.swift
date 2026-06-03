import Foundation

struct ExecuteCommandTool: AgentTool {
    static let defaultTimeoutSeconds = 3600
    static let maxTimeoutSeconds = 3600

    let name = "execute_command"
    let description =
        "Execute a shell command in the workspace. Uses zsh on macOS. "
        + "Default timeout \(defaultTimeoutSeconds)s (max \(maxTimeoutSeconds)s); timeout ends only this tool, not the agent turn."
    let parametersSchema: [String: String] = [
        "command": "Command line",
        "cwd": "Optional working directory",
        "timeout": "Optional timeout in seconds (default \(defaultTimeoutSeconds), max \(maxTimeoutSeconds))"
    ]
    private let permissions: ToolPermissionSettings
    private let workspaceGuard: WorkspaceGuard
    private let processRegistry: ExecuteCommandProcessRegistry?
    private let auditPaths: AppPathProvider

    init(
        permissions: ToolPermissionSettings,
        workspaceGuard: WorkspaceGuard,
        processRegistry: ExecuteCommandProcessRegistry? = nil,
        auditPaths: AppPathProvider = .shared
    ) {
        self.permissions = permissions
        self.workspaceGuard = workspaceGuard
        self.processRegistry = processRegistry
        self.auditPaths = auditPaths
    }

    func invoke(arguments: [String: String]) async throws -> String {
        let command = try ToolArguments.required(arguments, name: "command", tool: name)
        if !permissions.commandAllowList.isEmpty {
            let allowed = permissions.commandAllowList.contains { prefix in
                let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !p.isEmpty else { return false }
                return command.lowercased().hasPrefix(p)
                    || command.lowercased().contains(" \(p) ")
                    || command.lowercased().contains("/\(p)")
            }
            if !allowed {
                throw ToolError.denied(
                    "Command not in allow list. Allowed prefixes: \(permissions.commandAllowList.joined(separator: ", "))"
                )
            }
        }

        let cwd: String
        if let requested = arguments["cwd"], !requested.isEmpty {
            cwd = URL(fileURLWithPath: requested).standardizedFileURL.path
        } else if let root = workspaceGuard.tryGetWorkspaceRoot() {
            cwd = root
        } else {
            cwd = FileManager.default.currentDirectoryPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError.failed("Invalid working directory", detail: "Working directory does not exist: \(cwd)")
        }

        let timeoutSeconds = min(
            max(ToolArguments.int32(arguments, name: "timeout", defaultValue: Self.defaultTimeoutSeconds), 1),
            Self.maxTimeoutSeconds
        )

        let start = Date()
        let result = try await runShell(command: command, cwd: cwd, timeoutSeconds: timeoutSeconds)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

        if result.timedOut {
            let partial = formatOutput(stdout: result.stdout, stderr: result.stderr)
            let timeoutMessage = "Command exceeded \(timeoutSeconds)s timeout."
            AuditLogService.write(
                action: name,
                payload: [
                    "command": command,
                    "cwd": cwd,
                    "timedOut": true,
                    "elapsedMs": elapsedMs
                ],
                paths: auditPaths
            )
            throw ToolError.failed(
                "Command timed out",
                detail: partial.isEmpty ? timeoutMessage : timeoutMessage + "\n" + partial
            )
        }

        let content = formatOutput(stdout: result.stdout, stderr: result.stderr)
        var payload: [String: Any] = [
            "command": command,
            "cwd": cwd,
            "elapsedMs": elapsedMs
        ]
        if let exitCode = result.exitCode {
            payload["exitCode"] = exitCode
        }
        AuditLogService.write(action: name, payload: payload, paths: auditPaths)

        if result.exitCode == 0 {
            return ToolResultFormatter.success("Command exited 0 in \(elapsedMs)ms", content: content)
        }
        throw ToolError.failed("Command failed", detail: content.isEmpty ? "Exit code \(result.exitCode ?? -1)" : content)
    }

    private struct ProcessRunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32?
        let timedOut: Bool
    }

    private func runShell(command: String, cwd: String, timeoutSeconds: Int) async throws -> ProcessRunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            final class FinishState: @unchecked Sendable {
                private let lock = NSLock()
                private var finished = false
                func finishOnce(_ action: () -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !finished else { return }
                    finished = true
                    action()
                }
            }

            let state = FinishState()

            process.terminationHandler = { [weak processRegistry] proc in
                if let processRegistry {
                    processRegistry.unregister(proc)
                }
                state.finishOnce {
                    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessRunResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: proc.terminationStatus,
                        timedOut: false
                    ))
                }
            }

            do {
                try process.run()
                processRegistry?.register(process)
            } catch {
                continuation.resume(throwing: ToolError.failed("Failed to start process", detail: error.localizedDescription))
                return
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) { [weak processRegistry] in
                guard process.isRunning else { return }
                process.terminate()
                processRegistry?.unregister(process)
                state.finishOnce {
                    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessRunResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: nil,
                        timedOut: true
                    ))
                }
            }
        }
    }

    private func formatOutput(stdout: String, stderr: String) -> String {
        if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stdout
        }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }
}
