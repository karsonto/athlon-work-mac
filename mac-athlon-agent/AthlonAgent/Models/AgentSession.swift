import Foundation

// MARK: - Agent Session
struct AgentSession: Identifiable, Codable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var activeWorkspace: String?
    var workspaceName: String?
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var isRunning: Bool
    var queuedTurnCount: Int
    var plan: AgentPlan?

    var hasChatMessages: Bool { !messages.filter { $0.role != .system }.isEmpty }
}

// MARK: - Agent Plan
struct AgentPlan: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var expectedOutcome: String
    var subtasks: [PlanSubtask]
    var createdAt: Date
}

// MARK: - Plan Subtask
struct PlanSubtask: Identifiable, Codable {
    let id: String
    let index: Int
    var name: String
    var description: String
    var expectedOutcome: String
    var status: PlanSubtaskStatus
    var outcome: String?
}

enum PlanSubtaskStatus: String, Codable {
    case pending = "Pending"
    case inProgress = "InProgress"
    case done = "Done"
    case abandoned = "Abandoned"
}
