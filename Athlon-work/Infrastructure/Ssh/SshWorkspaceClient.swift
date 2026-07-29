import Foundation

nonisolated protocol SshWorkspaceClient: Sendable {
    func listDirectory(_ remotePath: String) async throws -> [String]
    func readFile(_ remotePath: String, maxBytes: Int) async throws -> String
}

nonisolated enum SshWorkspaceClientError: Error, LocalizedError {
    case notConfigured
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "SSH workspace is not configured"
        case let .commandFailed(d): return d
        }
    }
}

/// Basic SSH via `/usr/bin/ssh` for list/read. Falls back to local FS when host is empty.
nonisolated struct ProcessSshWorkspaceClient: SshWorkspaceClient {
    let settings: SshWorkspaceSettings
    let localFallbackRoot: String

    init(settings: SshWorkspaceSettings?, localFallbackRoot: String = "") {
        self.settings = settings ?? SshWorkspaceSettings()
        self.localFallbackRoot = localFallbackRoot
    }

    var isRemoteConfigured: Bool {
        !settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func listDirectory(_ remotePath: String) async throws -> [String] {
        if !isRemoteConfigured {
            return try localList(remotePath)
        }
        let path = remotePath.isEmpty ? "." : remotePath
        let output = try await runRemote("ls -1 \(shellEscape(path))")
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func readFile(_ remotePath: String, maxBytes: Int = 256_000) async throws -> String {
        if !isRemoteConfigured {
            return try localRead(remotePath, maxBytes: maxBytes)
        }
        let output = try await runRemote("head -c \(max(1, maxBytes)) \(shellEscape(remotePath))")
        return output
    }

    // MARK: - Local fallback

    private func localList(_ path: String) throws -> [String] {
        let root = localFallbackRoot.isEmpty ? FileManager.default.currentDirectoryPath : localFallbackRoot
        let full = path.isEmpty || path == "." ? root : ((path as NSString).isAbsolutePath ? path : (root as NSString).appendingPathComponent(path))
        return try FileManager.default.contentsOfDirectory(atPath: full).sorted()
    }

    private func localRead(_ path: String, maxBytes: Int) throws -> String {
        let root = localFallbackRoot.isEmpty ? FileManager.default.currentDirectoryPath : localFallbackRoot
        let full = (path as NSString).isAbsolutePath ? path : (root as NSString).appendingPathComponent(path)
        let data = try Data(contentsOf: URL(fileURLWithPath: full))
        let sliced = data.prefix(maxBytes)
        return String(data: sliced, encoding: .utf8) ?? ""
    }

    // MARK: - ssh process

    private func runRemote(_ remoteCommand: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runSSH(
                        settings: settings,
                        remoteCommand: remoteCommand
                    )
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func runSSH(settings: SshWorkspaceSettings, remoteCommand: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args: [String] = [
            "-p", "\(settings.port)",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let key = settings.privateKeyPath, !key.isEmpty {
            args += ["-i", key]
        }
        args.append("\(settings.username)@\(settings.host)")
        args.append(remoteCommand)
        proc.arguments = args

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw SshWorkspaceClientError.commandFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
