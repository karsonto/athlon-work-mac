import Foundation

// MARK: - Message Role
enum MessageRole: String, Codable {
    case user = "User"
    case assistant = "Assistant"
    case tool = "Tool"
    case compaction = "Compaction"
    case system = "System"

    var displayName: String {
        switch self {
        case .user: "您"
        case .assistant: "Athlon 助手"
        case .tool: "工具"
        case .compaction: "上下文"
        case .system: "系统"
        }
    }

    var assistantTone: Bool {
        self == .assistant || self == .compaction
    }

    var apiValue: String { rawValue.lowercased() }
}
