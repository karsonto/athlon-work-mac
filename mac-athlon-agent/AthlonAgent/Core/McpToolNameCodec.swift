import Foundation

/// Encodes MCP tools as a single function name for OpenAI-compatible APIs.
/// Format: `mcp_{server}__{tool}` (separator `__`, escaped as `_2_`).
enum McpToolNameCodec {
    static let prefix = "mcp_"
    private static let separator = "__"
    private static let separatorEscape = "_2_"
    private static let apiNamePattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$")

    static func encode(serverName: String, toolName: String) throws -> String {
        let server = (serverName).trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = (toolName).trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = "\(prefix)\(escapeSegment(server))\(separator)\(escapeSegment(tool))"
        guard isApiCompatible(encoded) else {
            throw McpToolNameCodecError.invalidEncodedName(encoded)
        }
        return encoded
    }

    static func tryDecode(_ encoded: String?) -> (serverName: String, toolName: String)? {
        guard let value = encoded?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let current = tryDecodeCurrent(value) { return current }
        return tryDecodeLegacy(value)
    }

    private static func tryDecodeCurrent(_ value: String) -> (serverName: String, toolName: String)? {
        guard value.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let rest = String(value.dropFirst(prefix.count))
        guard let range = rest.range(of: separator) else { return nil }
        let serverPart = String(rest[..<range.lowerBound])
        let toolPart = String(rest[range.upperBound...])
        guard !serverPart.isEmpty, !toolPart.isEmpty else { return nil }
        return (unescapeSegment(serverPart), unescapeSegment(toolPart))
    }

    private static func tryDecodeLegacy(_ value: String) -> (serverName: String, toolName: String)? {
        let legacyPrefix = "mcp."
        guard value.lowercased().hasPrefix(legacyPrefix) else { return nil }
        let rest = String(value.dropFirst(legacyPrefix.count))
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        let server = String(rest[..<dot])
        let tool = String(rest[rest.index(after: dot)...])
        guard !server.isEmpty, !tool.isEmpty else { return nil }
        return (server, tool)
    }

    private static func escapeSegment(_ value: String) -> String {
        value.replacingOccurrences(of: separator, with: separatorEscape)
    }

    private static func unescapeSegment(_ value: String) -> String {
        value.replacingOccurrences(of: separatorEscape, with: separator)
    }

    private static func isApiCompatible(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return apiNamePattern.firstMatch(in: name, range: range) != nil
    }
}

enum McpToolNameCodecError: LocalizedError {
    case invalidEncodedName(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncodedName(let name):
            "Encoded MCP tool name '\(name)' is not API-compatible."
        }
    }
}
