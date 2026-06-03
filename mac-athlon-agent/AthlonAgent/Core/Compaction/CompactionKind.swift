import Foundation

enum CompactionKind: String, Codable {
    case microcompact
    case autoCompact
    case conversationCompact
    case manualCompact
}
