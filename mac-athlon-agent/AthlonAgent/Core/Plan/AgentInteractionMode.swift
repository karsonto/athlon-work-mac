import Foundation

enum AgentInteractionMode: String, Codable, CaseIterable {
    case agent
    case plan

    var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .plan: return "Plan"
        }
    }
}
