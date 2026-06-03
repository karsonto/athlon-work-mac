import Foundation

enum McpConnectionState: String {
    case disabled
    case connecting
    case connected
    case error
}

struct McpTool: Equatable {
    let name: String
    let description: String
    let inputSchemaJson: String
}

struct McpServerStatus: Equatable {
    let name: String
    var state: McpConnectionState
    let transport: String
    var tools: [McpTool]
    var lastError: String?
}

protocol McpClientProtocol: AnyObject {
    var name: String { get }
    var status: McpServerStatus { get }
    func initialize(clientName: String?) async throws
    func listTools() async throws -> [McpTool]
    func callTool(name: String, argumentsJson: String) async throws -> String
    func shutdown()
}

enum McpTransportKinds {
    static func isStdio(_ transportType: String?) -> Bool {
        let value = (transportType ?? "stdio").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty || value == "stdio"
    }

    static func isStreamableHttp(_ transportType: String?) -> Bool {
        let value = (transportType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "http" || value == "streamable-http" || value == "streamable_http"
    }
}
