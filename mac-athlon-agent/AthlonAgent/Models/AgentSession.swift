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
        workspaceName: String? = nil
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
        // Legacy keys `plan` and `interactionMode` are ignored for forward compatibility.
    }
}
