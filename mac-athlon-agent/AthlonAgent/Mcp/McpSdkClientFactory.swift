import Foundation
import MCP

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

enum McpSdkClientFactory {
    static func connect(
        name: String,
        server: McpServerSettings,
        workspaceRoot: String?,
        clientName: String? = nil
    ) async throws -> SdkMcpClient {
        if McpTransportKinds.isStreamableHttp(server.transportType) {
            return try await connectStreamableHttp(
                name: name,
                server: server,
                clientName: clientName
            )
        }
        return try await connectStdio(
            name: name,
            server: server,
            workspaceRoot: workspaceRoot,
            clientName: clientName
        )
    }

    private static func connectStreamableHttp(
        name: String,
        server: McpServerSettings,
        clientName: String?
    ) async throws -> SdkMcpClient {
        guard let endpoint = URL(string: server.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              !server.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Athlon.MCP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Streamable HTTP MCP requires a valid URL."
            ])
        }

        let headers = server.headers
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            requestModifier: { request in
                var modified = request
                for (key, value) in headers {
                    modified.setValue(value, forHTTPHeaderField: key)
                }
                return modified
            }
        )

        let client = Client(name: clientName ?? "AthlonAgent", version: "1.0.0")
        do {
            try await client.connect(transport: transport)
            return SdkMcpClient(name: name, transport: "streamable-http", client: client, process: nil)
        } catch {
            await transport.disconnect()
            throw error
        }
    }

    private static func connectStdio(
        name: String,
        server: McpServerSettings,
        workspaceRoot: String?,
        clientName: String?
    ) async throws -> SdkMcpClient {
        let command = server.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw NSError(domain: "Athlon.MCP", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Stdio MCP requires a command."
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = server.args

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in server.env ?? [:] {
            environment[key] = value
        }
        if let workspaceRoot,
           !workspaceRoot.isEmpty,
           environment["VISION_WORKSPACE"] == nil {
            environment["VISION_WORKSPACE"] = (workspaceRoot as NSString).standardizingPath
        }
        process.environment = environment

        let workingDirectory = resolveWorkingDirectory(server: server, workspaceRoot: workspaceRoot)
        if !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stderrCapture = StderrCapture()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                stderrCapture.lastLine = trimmed
            }
        }

        try process.run()

        let input = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let output = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: input, output: output)

        let client = Client(name: clientName ?? "AthlonAgent", version: "1.0.0")
        do {
            try await client.connect(transport: transport)
            return SdkMcpClient(
                name: name,
                transport: "stdio",
                client: client,
                process: process,
                getLastStderrLine: { stderrCapture.lastLine }
            )
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            await transport.disconnect()
            throw error
        }
    }

    private static func resolveWorkingDirectory(server: McpServerSettings, workspaceRoot: String?) -> String {
        if !server.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (server.workingDirectory as NSString).standardizingPath
        }
        if let workspaceRoot, !workspaceRoot.isEmpty {
            return (workspaceRoot as NSString).standardizingPath
        }
        return FileManager.default.currentDirectoryPath
    }
}

private final class StderrCapture: @unchecked Sendable {
    var lastLine: String?
}
