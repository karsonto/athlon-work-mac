import Foundation

// MARK: - Message role

nonisolated enum MessageRole: String, Codable, Sendable, CaseIterable, Hashable {
    case system = "System"
    case user = "User"
    case assistant = "Assistant"
    case tool = "Tool"
    case summary = "Summary"
    case compaction = "Compaction"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            switch intValue {
            case 0: self = .system
            case 1: self = .user
            case 2: self = .assistant
            case 3: self = .tool
            case 4: self = .summary
            case 5: self = .compaction
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown MessageRole raw value \(intValue)"
                )
            }
            return
        }
        let stringValue = try container.decode(String.self)
        if let role = MessageRole(rawValue: stringValue)
            ?? MessageRole(rawValue: stringValue.prefix(1).uppercased() + stringValue.dropFirst().lowercased())
            ?? MessageRole.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(stringValue) == .orderedSame })
        {
            self = role
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unknown MessageRole \(stringValue)"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Tool call

nonisolated struct ToolCall: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// Raw JSON object string for tool arguments (Windows `ToolCallArguments` compatible).
    var arguments: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
    }

    init(id: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
         name: String,
         arguments: String = "{}") {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .idPascal)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decode(String.self, forKey: .namePascal)
        if let raw = try container.decodeIfPresent(String.self, forKey: .arguments)
            ?? container.decodeIfPresent(String.self, forKey: .argumentsPascal) {
            arguments = raw
        } else if let dict = try container.decodeIfPresent([String: AthlonJSONValue].self, forKey: .arguments)
            ?? container.decodeIfPresent([String: AthlonJSONValue].self, forKey: .argumentsPascal) {
            let data = try JSONEncoder().encode(dict)
            arguments = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            arguments = "{}"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
    }

    private enum FlexibleCodingKeys: String, CodingKey {
        case id
        case idPascal = "Id"
        case name
        case namePascal = "Name"
        case arguments
        case argumentsPascal = "Arguments"
    }
}

// MARK: - Image attachment

nonisolated struct ImageAttachment: Codable, Hashable, Sendable {
    var fileName: String
    var mimeType: String
    var dataUrl: String?
    var localPath: String?

    enum CodingKeys: String, CodingKey {
        case fileName
        case mimeType
        case dataUrl
        case localPath
    }

    init(fileName: String, mimeType: String, dataUrl: String? = nil, localPath: String? = nil) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.dataUrl = dataUrl
        self.localPath = localPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
            ?? c.decode(String.self, forKey: .fileNamePascal)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
            ?? c.decode(String.self, forKey: .mimeTypePascal)
        dataUrl = try c.decodeIfPresent(String.self, forKey: .dataUrl)
            ?? c.decodeIfPresent(String.self, forKey: .dataUrlPascal)
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath)
            ?? c.decodeIfPresent(String.self, forKey: .localPathPascal)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encodeIfPresent(dataUrl, forKey: .dataUrl)
        try c.encodeIfPresent(localPath, forKey: .localPath)
    }

    private enum FlexibleCodingKeys: String, CodingKey {
        case fileName, mimeType, dataUrl, localPath
        case fileNamePascal = "FileName"
        case mimeTypePascal = "MimeType"
        case dataUrlPascal = "DataUrl"
        case localPathPascal = "LocalPath"
    }
}

// MARK: - Chat message

nonisolated struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var role: MessageRole
    var content: String
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var reasoning: String?
    var createdAt: Date
    var parentId: String?
    var imageAttachments: [ImageAttachment]?

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCalls
        case toolCallId
        case reasoning = "reasoningContent"
        case createdAt
        case parentId
        case imageAttachments
        case toolCallsJson
    }

    init(
        id: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        reasoning: String? = nil,
        createdAt: Date = Date(),
        parentId: String? = nil,
        imageAttachments: [ImageAttachment]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.parentId = parentId
        self.imageAttachments = imageAttachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        id = try Self.decodeString(c, camel: .id, pascal: .idPascal)
        role = try c.decodeIfPresent(MessageRole.self, forKey: .role)
            ?? c.decode(MessageRole.self, forKey: .rolePascal)
        content = try Self.decodeString(c, camel: .content, pascal: .contentPascal)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
            ?? c.decodeIfPresent(String.self, forKey: .toolCallIdPascal)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
            ?? c.decodeIfPresent(String.self, forKey: .reasoningPascal)
            ?? c.decodeIfPresent(String.self, forKey: .reasoningContent)
            ?? c.decodeIfPresent(String.self, forKey: .reasoningContentPascal)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? c.decode(Date.self, forKey: .createdAtPascal)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
            ?? c.decodeIfPresent(String.self, forKey: .parentIdPascal)
        imageAttachments = try c.decodeIfPresent([ImageAttachment].self, forKey: .imageAttachments)
            ?? c.decodeIfPresent([ImageAttachment].self, forKey: .imageAttachmentsPascal)

        if let calls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            ?? c.decodeIfPresent([ToolCall].self, forKey: .toolCallsPascal) {
            toolCalls = calls
        } else if let json = try c.decodeIfPresent(String.self, forKey: .toolCallsJson)
            ?? c.decodeIfPresent(String.self, forKey: .toolCallsJsonPascal),
                  !json.isEmpty,
                  let data = json.data(using: .utf8) {
            toolCalls = try? JSONDecoder.athlon.decode([ToolCall].self, from: data)
        } else {
            toolCalls = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try c.encodeIfPresent(reasoning, forKey: .reasoning)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(imageAttachments, forKey: .imageAttachments)
        if let toolCalls {
            let data = try JSONEncoder.athlon.encode(toolCalls)
            let json = String(data: data, encoding: .utf8)
            try c.encodeIfPresent(json, forKey: .toolCallsJson)
            try c.encode(toolCalls, forKey: .toolCalls)
        }
    }

    private static func decodeString(
        _ c: KeyedDecodingContainer<FlexibleCodingKeys>,
        camel: FlexibleCodingKeys,
        pascal: FlexibleCodingKeys
    ) throws -> String {
        try c.decodeIfPresent(String.self, forKey: camel) ?? c.decode(String.self, forKey: pascal)
    }

    private enum FlexibleCodingKeys: String, CodingKey {
        case id, role, content, toolCalls, toolCallId, reasoning, createdAt, parentId, imageAttachments
        case reasoningContent, toolCallsJson
        case idPascal = "Id"
        case rolePascal = "Role"
        case contentPascal = "Content"
        case toolCallsPascal = "ToolCalls"
        case toolCallIdPascal = "ToolCallId"
        case reasoningPascal = "Reasoning"
        case reasoningContentPascal = "ReasoningContent"
        case createdAtPascal = "CreatedAt"
        case parentIdPascal = "ParentId"
        case imageAttachmentsPascal = "ImageAttachments"
        case toolCallsJsonPascal = "ToolCallsJson"
    }
}

// MARK: - Session

nonisolated struct AgentSession: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var activeWorkspaceId: String?
    var activeWorkspace: String?
    var activeSkill: String?
    var modelName: String?
    var messages: [ChatMessage]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case activeWorkspaceId
        case activeWorkspace
        case activeSkill
        case modelName
        case messages
    }

    init(
        id: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        title: String = "New chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activeWorkspaceId: String? = nil,
        activeWorkspace: String? = nil,
        activeSkill: String? = nil,
        modelName: String? = nil,
        messages: [ChatMessage]? = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeWorkspaceId = activeWorkspaceId
        self.activeWorkspace = activeWorkspace
        self.activeSkill = activeSkill
        self.modelName = modelName
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decode(String.self, forKey: .idPascal)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? c.decode(String.self, forKey: .titlePascal)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? c.decode(Date.self, forKey: .createdAtPascal)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c.decode(Date.self, forKey: .updatedAtPascal)
        activeWorkspaceId = try c.decodeIfPresent(String.self, forKey: .activeWorkspaceId)
            ?? c.decodeIfPresent(String.self, forKey: .activeWorkspaceIdPascal)
        activeWorkspace = try c.decodeIfPresent(String.self, forKey: .activeWorkspace)
            ?? c.decodeIfPresent(String.self, forKey: .activeWorkspacePascal)
        activeSkill = try c.decodeIfPresent(String.self, forKey: .activeSkill)
            ?? c.decodeIfPresent(String.self, forKey: .activeSkillPascal)
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
            ?? c.decodeIfPresent(String.self, forKey: .modelNamePascal)
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages)
            ?? c.decodeIfPresent([ChatMessage].self, forKey: .messagesPascal)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(activeWorkspaceId, forKey: .activeWorkspaceId)
        try c.encodeIfPresent(activeWorkspace, forKey: .activeWorkspace)
        try c.encodeIfPresent(activeSkill, forKey: .activeSkill)
        try c.encodeIfPresent(modelName, forKey: .modelName)
        try c.encodeIfPresent(messages, forKey: .messages)
    }

    static func create(title: String = "New chat") -> AgentSession {
        AgentSession(title: title)
    }

    private enum FlexibleCodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, activeWorkspaceId, activeWorkspace, activeSkill, modelName, messages
        case idPascal = "Id"
        case titlePascal = "Title"
        case createdAtPascal = "CreatedAt"
        case updatedAtPascal = "UpdatedAt"
        case activeWorkspaceIdPascal = "ActiveWorkspaceId"
        case activeWorkspacePascal = "ActiveWorkspace"
        case activeSkillPascal = "ActiveSkill"
        case modelNamePascal = "ModelName"
        case messagesPascal = "Messages"
    }
}

// MARK: - Session index / usage

nonisolated struct SessionIndexEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var path: String
    var updatedAt: Date
    var messageCount: Int?
    var activeWorkspace: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case path
        case updatedAt
        case messageCount
        case activeWorkspace
    }

    init(
        id: String,
        title: String,
        path: String,
        updatedAt: Date,
        messageCount: Int? = nil,
        activeWorkspace: String? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.activeWorkspace = activeWorkspace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decode(String.self, forKey: .idPascal)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? c.decode(String.self, forKey: .titlePascal)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? c.decode(String.self, forKey: .pathPascal)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c.decode(Date.self, forKey: .updatedAtPascal)
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount)
            ?? c.decodeIfPresent(Int.self, forKey: .messageCountPascal)
        activeWorkspace = try c.decodeIfPresent(String.self, forKey: .activeWorkspace)
            ?? c.decodeIfPresent(String.self, forKey: .activeWorkspacePascal)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(path, forKey: .path)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(messageCount, forKey: .messageCount)
        try c.encodeIfPresent(activeWorkspace, forKey: .activeWorkspace)
    }

    private enum FlexibleCodingKeys: String, CodingKey {
        case id, title, path, updatedAt, messageCount, activeWorkspace
        case idPascal = "Id"
        case titlePascal = "Title"
        case pathPascal = "Path"
        case updatedAtPascal = "UpdatedAt"
        case messageCountPascal = "MessageCount"
        case activeWorkspacePascal = "ActiveWorkspace"
    }
}

nonisolated enum PromptCacheAvailability: String, Codable, Sendable {
    case unknown = "Unknown"
    case hitMiss = "HitMiss"
    case readOnly = "ReadOnly"
}

nonisolated struct SessionUsageSnapshot: Codable, Hashable, Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    var cacheHitTokens: Int
    var cacheMissTokens: Int
    var cacheAvailability: PromptCacheAvailability
    var contextSavingsTokens: Int
    var hygieneSavingsTokens: Int
    var compactionSavingsTokens: Int
    var subAgentRollupPromptTokens: Int
    var subAgentRollupCompletionTokens: Int
    var turnCount: Int
    var lastUpdatedAt: Date
    var cacheReadTokens: Int
    var cacheCreationTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens
        case completionTokens
        case totalTokens
        case cacheHitTokens
        case cacheMissTokens
        case cacheAvailability
        case contextSavingsTokens
        case hygieneSavingsTokens
        case compactionSavingsTokens
        case subAgentRollupPromptTokens
        case subAgentRollupCompletionTokens
        case turnCount
        case lastUpdatedAt
        case cacheReadTokens
        case cacheCreationTokens
    }

    static let empty = SessionUsageSnapshot(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
        cacheHitTokens: 0,
        cacheMissTokens: 0,
        cacheAvailability: .unknown,
        contextSavingsTokens: 0,
        hygieneSavingsTokens: 0,
        compactionSavingsTokens: 0,
        subAgentRollupPromptTokens: 0,
        subAgentRollupCompletionTokens: 0,
        turnCount: 0,
        lastUpdatedAt: .distantPast,
        cacheReadTokens: 0,
        cacheCreationTokens: 0
    )

    var cacheHitRate: Double? {
        guard cacheAvailability == .hitMiss else { return nil }
        let denom = cacheHitTokens + cacheMissTokens
        guard denom > 0 else { return nil }
        return Double(cacheHitTokens) / Double(denom)
    }
}

// MARK: - JSON helpers

nonisolated enum AthlonJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AthlonJSONValue])
    case array([AthlonJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AthlonJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AthlonJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONEncoder {
    static let athlon: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Windows `JsonSerializerDefaults.Web` compatible (camelCase keys via CodingKeys).
    static let athlonCamelCase: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let athlonCamelCaseCompact: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

extension JSONDecoder {
    static let athlon: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .athlonFlexible
        return decoder
    }()

    static let athlonCamelCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .athlonFlexible
        return decoder
    }()
}

extension JSONDecoder.DateDecodingStrategy {
    /// Flexible ISO-8601 / epoch decoding. Must not call `decode(Date.self)` (would recurse).
    static let athlonFlexible = custom { decoder in
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            if let date = ISO8601DateFormatter.athlon.date(from: string)
                ?? ISO8601DateFormatter.athlonFractional.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(string)")
        }
        if let seconds = try? container.decode(Double.self) {
            // Heuristic: values that look like milliseconds since 1970.
            if seconds > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            if seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        if let seconds = try? container.decode(Int.self) {
            let value = Double(seconds)
            if value > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000)
            }
            if value > 1_000_000_000 {
                return Date(timeIntervalSince1970: value)
            }
            return Date(timeIntervalSinceReferenceDate: value)
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date value")
    }
}

extension ISO8601DateFormatter {
    static let athlon: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let athlonFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
