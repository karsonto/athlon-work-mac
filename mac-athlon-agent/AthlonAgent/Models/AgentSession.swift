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
    var interactionMode: AgentInteractionMode

    var hasChatMessages: Bool { !messages.filter { $0.role != .system }.isEmpty }

    init(
        id: String,
        title: String,
        messages: [ChatMessage],
        createdAt: Date,
        updatedAt: Date,
        isActive: Bool,
        isRunning: Bool,
        queuedTurnCount: Int,
        activeWorkspace: String? = nil,
        workspaceName: String? = nil,
        plan: AgentPlan? = nil,
        interactionMode: AgentInteractionMode = .agent
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.activeWorkspace = activeWorkspace
        self.workspaceName = workspaceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.isRunning = isRunning
        self.queuedTurnCount = queuedTurnCount
        self.plan = plan
        self.interactionMode = interactionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        activeWorkspace = try container.decodeIfPresent(String.self, forKey: .activeWorkspace)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        queuedTurnCount = try container.decodeIfPresent(Int.self, forKey: .queuedTurnCount) ?? 0
        plan = try container.decodeIfPresent(AgentPlan.self, forKey: .plan)
        interactionMode = try container.decodeIfPresent(AgentInteractionMode.self, forKey: .interactionMode) ?? .agent
    }
}

// MARK: - Agent Plan
struct AgentPlan: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var expectedOutcome: String
    var overview: String
    var architecture: String
    var mermaid: String
    var testingStrategy: String
    var outOfScope: String
    var subtasks: [PlanSubtask]
    var phase: PlanPhase
    var createdAt: Date

    init(
        id: String,
        name: String,
        description: String,
        expectedOutcome: String,
        overview: String = "",
        architecture: String = "",
        mermaid: String = "",
        testingStrategy: String = "",
        outOfScope: String = "",
        subtasks: [PlanSubtask],
        phase: PlanPhase = .draft,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.expectedOutcome = expectedOutcome
        self.overview = overview.isEmpty ? description : overview
        self.architecture = architecture
        self.mermaid = mermaid
        self.testingStrategy = testingStrategy
        self.outOfScope = outOfScope
        self.subtasks = subtasks
        self.phase = phase
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        expectedOutcome = try container.decode(String.self, forKey: .expectedOutcome)
        overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? description
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture) ?? ""
        mermaid = try container.decodeIfPresent(String.self, forKey: .mermaid) ?? ""
        testingStrategy = try container.decodeIfPresent(String.self, forKey: .testingStrategy) ?? ""
        outOfScope = try container.decodeIfPresent(String.self, forKey: .outOfScope) ?? ""
        subtasks = try container.decode([PlanSubtask].self, forKey: .subtasks)
        phase = try container.decodeIfPresent(PlanPhase.self, forKey: .phase) ?? .draft
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Plan Subtask
struct PlanSubtask: Identifiable, Codable {
    let id: String
    let index: Int
    var name: String
    var description: String
    var expectedOutcome: String
    var files: [String]
    var status: PlanSubtaskStatus
    var outcome: String?

    init(
        id: String,
        index: Int,
        name: String,
        description: String,
        expectedOutcome: String,
        files: [String] = [],
        status: PlanSubtaskStatus,
        outcome: String? = nil
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.description = description
        self.expectedOutcome = expectedOutcome
        self.files = files
        self.status = status
        self.outcome = outcome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        expectedOutcome = try container.decode(String.self, forKey: .expectedOutcome)
        files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
        status = try container.decode(PlanSubtaskStatus.self, forKey: .status)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
    }
}

enum PlanSubtaskStatus: String, Codable {
    case pending = "Pending"
    case inProgress = "InProgress"
    case done = "Done"
    case abandoned = "Abandoned"
}
