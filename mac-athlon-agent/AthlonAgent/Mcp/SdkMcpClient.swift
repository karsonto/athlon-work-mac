import Foundation
import MCP

#if canImport(System)
    import System
#else
    @preconcurrency import SystemPackage
#endif

/// Adapter over the official MCP Swift SDK `Client` (aligned with WPF `SdkMcpClient`).
final class SdkMcpClient: McpClientProtocol {
    let name: String
    private let transportLabel: String
    private let client: Client
    private let process: Process?
    private var statusValue: McpServerStatus
    private let getLastStderrLine: (() -> String?)?

    init(
        name: String,
        transport: String,
        client: Client,
        process: Process?,
        getLastStderrLine: (() -> String?)? = nil
    ) {
        self.name = name
        self.transportLabel = transport
        self.client = client
        self.process = process
        self.getLastStderrLine = getLastStderrLine
        self.statusValue = McpServerStatus(
            name: name,
            state: .connected,
            transport: transport,
            tools: [],
            lastError: nil
        )
    }

    var status: McpServerStatus { statusValue }

    func initialize(clientName: String?) async throws {
        _ = clientName
    }

    func listTools() async throws -> [McpTool] {
        do {
            var mapped: [McpTool] = []
            var cursor: String?
            repeat {
                let page = try await client.listTools(cursor: cursor)
                mapped.append(contentsOf: page.tools.map(Self.mapTool))
                cursor = page.nextCursor
            } while cursor != nil

            statusValue.state = .connected
            statusValue.tools = mapped
            statusValue.lastError = nil
            return mapped
        } catch {
            statusValue.state = .error
            statusValue.lastError = error.localizedDescription
            throw error
        }
    }

    func callTool(name: String, argumentsJson: String) async throws -> String {
        do {
            let arguments = McpArgumentsJson.parseValueDictionary(argumentsJson)
            let result = try await client.callTool(name: name, arguments: arguments)
            statusValue.state = .connected
            statusValue.lastError = getLastStderrLine?()

            let payload = CallTool.Result(content: result.content, isError: result.isError)
            let data = try JSONEncoder().encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            statusValue.state = .error
            statusValue.lastError = error.localizedDescription
            throw error
        }
    }

    func shutdown() {
        if let process, process.isRunning {
            process.terminate()
        }
        Task { await client.disconnect() }
    }

    private static func mapTool(_ tool: Tool) -> McpTool {
        McpTool(
            name: tool.name,
            description: tool.description ?? "",
            inputSchemaJson: McpValueJson.encodeToString(tool.inputSchema)
        )
    }
}
