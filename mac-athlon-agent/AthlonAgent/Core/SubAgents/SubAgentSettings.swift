import Foundation

struct SubAgentSettings: Codable, Equatable {
    var enabled: Bool = true
    var toolName: String = "call_assistant"
    var description: String =
        "Delegate a sub-task to a child assistant (role + message; session_id to continue). "
        + "Child has same file tools, skills, MCP, and compaction as parent; cannot spawn nested agents."
    var maxToolRounds: Int = 16
    var maxNestingDepth: Int = 2

    enum CodingKeys: String, CodingKey {
        case enabled
        case toolName = "tool_name"
        case description
        case maxToolRounds = "max_tool_rounds"
        case maxNestingDepth = "max_nesting_depth"
    }
}
