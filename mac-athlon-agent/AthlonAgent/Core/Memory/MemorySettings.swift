import Foundation

struct MemorySettings: Codable, Equatable {
    var enabled: Bool = true
    var summaryMaxTokens: Int = 4000
    var maxMemoryTokens: Int = 4000

    enum CodingKeys: String, CodingKey {
        case enabled
        case summaryMaxTokens = "summary_max_tokens"
        case maxMemoryTokens = "max_memory_tokens"
    }
}
