import Foundation
import Combine

// MARK: - Session Manager
/// Manages agent session lifecycle: creation, persistence, loading, deletion, and date-based grouping.
class SessionManager: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var isLoading = false
    @Published var error: String?

    private let storage: FileStorageService
    private let maxSessions = 100

    init(storage: FileStorageService = FileStorageService()) {
        self.storage = storage
    }

    // MARK: - Load All Sessions
    func loadSessions() {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try storage.loadAllSessions()
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            self.error = "无法加载会话: \(error.localizedDescription)"
            sessions = []
        }
    }

    func clearConversationDisplay(sessionId: String) {
        do {
            try storage.clearConversationDisplay(sessionId)
        } catch {
            self.error = "无法清空对话展示缓存: \(error.localizedDescription)"
        }
    }

    // MARK: - Save Session
    private func saveSession(_ session: AgentSession) {
        do {
            try storage.saveSessionSync(session)
        } catch {
            self.error = "无法保存会话: \(error.localizedDescription)"
        }
    }

    private func saveSessions() {
        for session in sessions {
            saveSession(session)
        }
    }

    // MARK: - Create Session
    @discardableResult
    func createSession(title: String? = nil, workspace: String? = nil, workspaceName: String? = nil) -> AgentSession {
        let session = AgentSession(
            id: UUID().uuidString,
            title: title ?? "新对话",
            messages: [],
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0,
            activeWorkspace: workspace,
            workspaceName: workspaceName,
            plan: nil
        )
        sessions.insert(session, at: 0)
        deactivateOtherSessions(except: session.id)
        trimSessions()
        saveSession(session)
        return session
    }

    // MARK: - Activate Session
    func activateSession(_ sessionId: String) {
        deactivateOtherSessions(except: sessionId)
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].isActive = true
            sessions[idx].updatedAt = Date()
            saveSession(sessions[idx])
        }
    }

    private func deactivateOtherSessions(except sessionId: String) {
        for i in sessions.indices where sessions[i].id != sessionId {
            sessions[i].isActive = false
        }
    }

    // MARK: - Delete Session
    func deleteSession(_ sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        do {
            try storage.deleteSession(sessionId)
        } catch {
            self.error = "无法删除会话: \(error.localizedDescription)"
        }
    }

    // MARK: - Update Session
    func updateSession(_ sessionId: String, update: (inout AgentSession) -> Void) {
        updateSessionInMemory(sessionId, update: update)
        persistSession(sessionId)
    }

    /// Updates the in-memory session only (no disk I/O). Use during streaming UI updates.
    func updateSessionInMemory(_ sessionId: String, update: (inout AgentSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        update(&sessions[idx])
        sessions[idx].updatedAt = Date()
    }

    /// Writes the current in-memory session to disk.
    func persistSession(_ sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        saveSession(session)
    }

    // MARK: - Add Message to Session
    func addMessage(_ message: ChatMessage, to sessionId: String, persist: Bool = true) {
        upsertMessage(message, to: sessionId, persist: persist)
    }

    func upsertMessage(_ message: ChatMessage, to sessionId: String, persist: Bool = true) {
        let apply: (inout AgentSession) -> Void = { session in
            if let index = session.messages.firstIndex(where: { $0.id == message.id }) {
                session.messages[index] = message
            } else {
                session.messages.append(message)
            }
        }
        if persist {
            updateSession(sessionId, update: apply)
        } else {
            updateSessionInMemory(sessionId, update: apply)
        }
    }

    // MARK: - Update Plan
    func updatePlan(_ plan: AgentPlan?, for sessionId: String) {
        updateSession(sessionId) { session in
            session.plan = plan
        }
    }

    // MARK: - Set Running State
    func setRunning(_ running: Bool, for sessionId: String, persist: Bool = true) {
        if persist {
            updateSession(sessionId) { session in
                session.isRunning = running
            }
        } else {
            updateSessionInMemory(sessionId) { session in
                session.isRunning = running
            }
        }
    }

    // MARK: - Set Queued Turn Count
    func setQueuedTurnCount(_ count: Int, for sessionId: String, persist: Bool = true) {
        if persist {
            updateSession(sessionId) { session in
                session.queuedTurnCount = count
            }
        } else {
            updateSessionInMemory(sessionId) { session in
                session.queuedTurnCount = count
            }
        }
    }

    // MARK: - Export Session to Individual File
    func exportSession(_ sessionId: String) -> URL? {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return nil }
        let sessionDir = AppPathProvider.shared.sessionDirectory(sessionId)
        let fileURL = URL(fileURLWithPath: (sessionDir as NSString).appendingPathComponent("session.json"))
        do {
            try storage.saveSessionSync(session)
            return fileURL
        } catch {
            self.error = "导出失败: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Trim Old Sessions
    private func trimSessions() {
        if sessions.count > maxSessions {
            let toRemove = sessions.suffix(sessions.count - maxSessions)
            sessions = Array(sessions.prefix(maxSessions))
            for session in toRemove {
                try? storage.deleteSession(session.id)
            }
        }
    }

    // MARK: - Session Grouping (for sidebar display)
    enum SessionGroup: String, CaseIterable, Identifiable {
        case today = "今天"
        case yesterday = "昨天"
        case thisWeek = "本周"
        case older = "更早"

        var id: String { rawValue }
    }

    func groupedSessions() -> [(group: SessionGroup, sessions: [AgentSession])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday)!

        var groups: [(group: SessionGroup, sessions: [AgentSession])] = [
            (.today, []),
            (.yesterday, []),
            (.thisWeek, []),
            (.older, [])
        ]

        for session in sessions {
            let sessionDate = session.createdAt
            if sessionDate >= startOfToday {
                groups[0].sessions.append(session)
            } else if sessionDate >= startOfYesterday {
                groups[1].sessions.append(session)
            } else if sessionDate >= startOfWeek {
                groups[2].sessions.append(session)
            } else {
                groups[3].sessions.append(session)
            }
        }

        return groups.filter { !$0.sessions.isEmpty }
    }

    // MARK: - Search Sessions
    func searchSessions(query: String) -> [AgentSession] {
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(query) ||
            session.messages.contains { msg in
                msg.content.localizedCaseInsensitiveContains(query)
            }
        }
    }

    // MARK: - Get Session by ID
    func getSession(_ id: String) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Active Session
    var activeSession: AgentSession? {
        sessions.first { $0.isActive }
    }
}
