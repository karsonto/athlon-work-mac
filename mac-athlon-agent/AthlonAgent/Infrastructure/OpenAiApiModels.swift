import Foundation

// MARK: - OpenAI Chat Completion API — Typed Codable Models
// Replaces ad-hoc [String: Any] dictionary parsing throughout the codebase.

// ── Helpers for encoding dynamic JSON ──────────────────────────────────

/// Recursive JSON value enum that enables `JSONEncoder` to work with
/// `[String: Any]` dictionaries containing arbitrary nesting.
indirect enum JsonValue: Codable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case null
    case array([JsonValue])
    case object([String: JsonValue])

    init(_ value: Any) {
        switch value {
        case let v as String:        self = .string(v)
        case let v as Int:           self = .integer(v)
        case let v as Double:        self = .number(v)
        case let v as Bool:          self = .bool(v)
        case let v as [Any]:         self = .array(v.map(JsonValue.init))
        case let v as [String: Any]: self = .object(v.mapValues(JsonValue.init))
        default:                     self = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode(Int.self) {
            self = .integer(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode([JsonValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JsonValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JsonValue: unsupported JSON value type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v):   try c.encode(v)
        case .number(let v):   try c.encode(v)
        case .integer(let v):  try c.encode(v)
        case .bool(let v):     try c.encode(v)
        case .null:            try c.encodeNil()
        case .array(let v):    try c.encode(v)
        case .object(let v):   try c.encode(v)
        }
    }
}

/// Wraps a `[String: Any]` dictionary so it can be embedded in a `Codable` struct
/// and encoded via `JSONEncoder`.  Uses `JsonValue` internally.
struct JsonObject: Codable {
    let value: [String: Any]

    init(_ value: [String: Any]) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as a JSON object then convert back to [String: Any]
        let data = try container.decode([String: JsonValue].self)
        self.value = data.mapValues(JsonObject.toAny)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JsonValue(value))
    }

    private static func toAny(_ v: JsonValue) -> Any {
        switch v {
        case .string(let v):  return v
        case .number(let v):  return v
        case .integer(let v): return v
        case .bool(let v):    return v
        case .null:           return NSNull()
        case .array(let a):   return a.map(toAny)
        case .object(let d):  return d.mapValues(toAny)
        }
    }
}

// ── Request (Encodable) ───────────────────────────────────────────────

struct OpenAiChatRequest: Encodable {
    let model: String
    let messages: [OpenAiRequestMessage]
    let stream: Bool
    let tools: [OpenAiRequestTool]?
    let toolChoice: String?
    let maxTokens: Int?
    let reasoningEffort: String?
    let thinking: OpenAiRequestThinking?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
        case thinking
    }
}

struct OpenAiRequestTool: Encodable {
    let type = "function"
    let function: OpenAiRequestFunction
}

struct OpenAiRequestFunction: Encodable {
    let name: String
    let description: String
    /// JSON Schema object describing the function parameters.  Stored as
    /// `JsonObject` so it survives `JSONEncoder` encoding.
    let parameters: JsonObject?

    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
}

struct OpenAiRequestThinking: Encodable {
    let type: String
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

struct OpenAiRequestMessage: Encodable {
    let role: String
    let content: OpenAiMessageContent
    let toolCallId: String?
    let toolCalls: [OpenAiRequestToolCall]?
    /// DeepSeek / reasoner models send reasoning content as a separate field.
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
    }
}

enum OpenAiMessageContent: Encodable {
    case text(String)
    case parts([OpenAiContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let v):    try container.encode(v)
        case .parts(let v):   try container.encode(v)
        }
    }
}

struct OpenAiContentPart: Encodable {
    let type: String
    let text: String?
    let imageUrl: OpenAiImageUrl?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}

struct OpenAiImageUrl: Encodable {
    let url: String
    let detail: String?
}

struct OpenAiRequestToolCall: Encodable {
    let id: String
    let type: String
    let function: OpenAiRequestToolCallFunction
}

struct OpenAiRequestToolCallFunction: Encodable {
    let name: String
    let arguments: String
}

// ── Non‑streaming response (Decodable) ─────────────────────────────────

struct OpenAiChatResponse: Decodable {
    let id: String?
    let choices: [OpenAiChoice]
    let usage: OpenAiUsage?
    let model: String?
}

struct OpenAiChoice: Decodable {
    let index: Int?
    let message: OpenAiResponseMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenAiResponseMessage: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAiResponseToolCall]?
    /// DeepSeek / reasoner models return reasoning content alongside the main content.
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
    }
}

struct OpenAiResponseToolCall: Decodable {
    let id: String
    let type: String?
    let function: OpenAiResponseFunction
}

struct OpenAiResponseFunction: Decodable {
    let name: String
    let arguments: String
}

struct OpenAiUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// ── Streaming response (SSE chunks) ────────────────────────────────────

struct OpenAiStreamChunk: Decodable {
    let choices: [OpenAiStreamChoice]?
}

struct OpenAiStreamChoice: Decodable {
    let index: Int?
    let delta: OpenAiDelta?
    /// Some providers send a full message object in the final chunk instead of a delta.
    let message: OpenAiResponseMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta, message
        case finishReason = "finish_reason"
    }
}

struct OpenAiDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAiDeltaToolCall]?
    let reasoningContent: String?
    /// Some providers (Qwen, etc.) use `reasoning` instead of `reasoning_content`.
    let reasoning: String?

    /// Alternative field name used by some providers (e.g. Anthropic-compatible endpoints).
    let text: String?
    /// Another alternative used by newer OpenAI models for `content`.
    let outputText: String?

    /// Returns the first non‑nil content field.
    var resolvedContent: String? { content ?? text ?? outputText }
    var resolvedReasoning: String? { reasoningContent ?? reasoning }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case reasoningContent = "reasoning_content"
        case reasoning
        case text
        case outputText = "output_text"
    }
}

struct OpenAiDeltaToolCall: Decodable {
    let index: Int
    let id: String?
    let type: String?
    let function: OpenAiDeltaFunction?
}

struct OpenAiDeltaFunction: Decodable {
    let name: String?
    let arguments: String?
}
