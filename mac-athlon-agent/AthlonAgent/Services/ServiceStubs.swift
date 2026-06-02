import SwiftUI
import Foundation

// MARK: - Service stubs (to be implemented in later tasks)
// These minimal declarations prevent compile errors during incremental build

final class SessionManager {
    func loadSessions() -> [AgentSession] { [] }
    func createSession(title: String) -> AgentSession {
        AgentSession(id: UUID().uuidString, title: title, messages: [],
                     createdAt: Date(), updatedAt: Date(), isActive: true,
                     isRunning: false, queuedTurnCount: 0)
    }
}

final class SettingsManager: ObservableObject {
    @Published var settings = AppSettings.default
    func load() {}
    func save() {}
}

final class McpClientService {
    func loadServers() -> [McpServerItem] { [] }
}

final class SkillService {
    func loadSkills() -> [SkillItem] { [] }
}

final class WorkspaceService {
    func scanWorkspace(at path: String) -> [WorkspaceNode] { [] }
}

final class AgentRuntimeService {
    func send(message: String, session: AgentSession, images: [ImageAttachment]?,
              stream: @escaping (String) -> Void,
              completion: @escaping (Result<AgentSession, Error>) -> Void) {}
    func stop() {}
}

final class PlanTracker {
    var currentPlan: AgentPlan?
    func createPlan(name: String, description: String, expectedOutcome: String, subtasks: [PlanSubtask]) {}
}
