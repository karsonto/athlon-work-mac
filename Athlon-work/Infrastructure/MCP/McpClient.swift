import Foundation

// MARK: - Protocol

nonisolated protocol McpClient: Sendable {
    var serverName: String { get }
    func initialize() async throws
    func listTools() async throws -> [McpToolDescriptor]
    func callTool(name: String, argumentsJSON: String) async throws -> String
    func close() async
}

nonisolated struct McpToolDescriptor: Sendable, Hashable {
    var name: String
    var description: String
    var inputSchema: [String: Any]

    static func == (lhs: McpToolDescriptor, rhs: McpToolDescriptor) -> Bool {
        lhs.name == rhs.name && lhs.description == rhs.description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(description)
    }
}

nonisolated enum McpClientError: Error, LocalizedError {
    case notInitialized
    case processFailed(String)
    case invalidResponse(String)
    case toolError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "MCP client not initialized"
        case let .processFailed(d): return "MCP process failed: \(d)"
        case let .invalidResponse(d): return "Invalid MCP response: \(d)"
        case let .toolError(d): return d
        case .timeout: return "MCP request timed out"
        }
    }
}

// MARK: - Stdio client

/// Basic stdio MCP client: launches a process and speaks newline-delimited JSON-RPC over stdin/stdout.
nonisolated final class StdioMcpClient: McpClient, @unchecked Sendable {
    let serverName: String
    private let command: String
    private let args: [String]
    private let env: [String: String]
    private let workingDirectory: String
    private let timeoutSeconds: Int

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var nextId: Int = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private let lock = NSLock()
    private var readerTask: Task<Void, Never>?
    private var initialized = false
    private var buffer = Data()

    init(settings: McpServerSettings) {
        serverName = settings.name
        command = settings.command
        args = settings.args
        env = settings.env
        workingDirectory = settings.workingDirectory
        timeoutSeconds = max(5, settings.toolCallTimeoutSeconds)
    }

    func initialize() async throws {
        if initialized { return }
        try startProcess()
        let result = try await request(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "athlon-agent-macos", "version": "1.0"] as [String: Any],
            ]
        )
        _ = result
        try await notify(method: "notifications/initialized", params: [:])
        initialized = true
    }

    func listTools() async throws -> [McpToolDescriptor] {
        try await ensureInitialized()
        let result = try await request(method: "tools/list", params: [:])
        let toolsAny = result["tools"] as? [[String: Any]] ?? []
        return toolsAny.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let description = dict["description"] as? String ?? ""
            let schema = dict["inputSchema"] as? [String: Any]
                ?? ["type": "object", "properties": [:] as [String: Any]]
            return McpToolDescriptor(name: name, description: description, inputSchema: schema)
        }
    }

    func callTool(name: String, argumentsJSON: String) async throws -> String {
        try await ensureInitialized()
        let argsObj = (try? ToolJSON.object(from: argumentsJSON)) ?? [:]
        let result = try await request(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": argsObj,
            ]
        )
        if let isError = result["isError"] as? Bool, isError {
            throw McpClientError.toolError(stringifyContent(result["content"]))
        }
        return stringifyContent(result["content"])
    }

    func close() async {
        readerTask?.cancel()
        readerTask = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        initialized = false
        lock.lock()
        let waiters = pending
        pending.removeAll()
        lock.unlock()
        for (_, cont) in waiters {
            cont.resume(throwing: McpClientError.processFailed("closed"))
        }
    }

    // MARK: - Internals

    private func ensureInitialized() async throws {
        if !initialized { try await initialize() }
    }

    private func startProcess() throws {
        let proc = Process()
        let resolved = resolveLaunch(command: command, args: args)
        proc.executableURL = URL(fileURLWithPath: resolved.executable)
        proc.arguments = resolved.arguments
        if !workingDirectory.isEmpty {
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        proc.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            throw McpClientError.processFailed(error.localizedDescription)
        }

        process = proc
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading

        readerTask = Task { [weak self] in
            self?.readLoop(handle: stdoutPipe.fileHandleForReading)
        }
    }

    private func resolveLaunch(command: String, args: [String]) -> (executable: String, arguments: [String]) {
        if (command as NSString).isAbsolutePath || command.contains("/") {
            return (command, args)
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return (candidate, args)
            }
        }
        return ("/usr/bin/env", [command] + args)
    }

    private func readLoop(handle: FileHandle) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            lock.lock()
            buffer.append(chunk)
            while let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                lock.unlock()
                handleLine(lineData)
                lock.lock()
            }
            lock.unlock()
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let id = obj["id"] as? Int {
            lock.lock()
            let cont = pending.removeValue(forKey: id)
            lock.unlock()
            if let error = obj["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "MCP error"
                cont?.resume(throwing: McpClientError.invalidResponse(message))
            } else if let result = obj["result"] as? [String: Any] {
                cont?.resume(returning: result)
            } else {
                cont?.resume(returning: [:])
            }
        }
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id: Int
        lock.lock()
        id = nextId
        nextId += 1
        lock.unlock()

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if !params.isEmpty { payload["params"] = params }

        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            pending[id] = cont
            lock.unlock()
            do {
                try writeJSON(payload)
            } catch {
                lock.lock()
                pending.removeValue(forKey: id)
                lock.unlock()
                cont.resume(throwing: error)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                lock.lock()
                let timedOut = pending.removeValue(forKey: id)
                lock.unlock()
                timedOut?.resume(throwing: McpClientError.timeout)
            }
        }
    }

    private func notify(method: String, params: [String: Any]) async throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if !params.isEmpty { payload["params"] = params }
        try writeJSON(payload)
    }

    private func writeJSON(_ payload: [String: Any]) throws {
        guard let handle = stdinHandle else {
            throw McpClientError.processFailed("stdin closed")
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        var line = data
        line.append(0x0A)
        try handle.write(contentsOf: line)
    }

    private func stringifyContent(_ content: Any?) -> String {
        guard let content else { return "" }
        if let text = content as? String { return text }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { item -> String? in
                if let t = item["text"] as? String { return t }
                if let data = try? JSONSerialization.data(withJSONObject: item),
                   let s = String(data: data, encoding: .utf8) {
                    return s
                }
                return nil
            }.joined(separator: "\n")
        }
        if let data = try? JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return String(describing: content)
    }
}
