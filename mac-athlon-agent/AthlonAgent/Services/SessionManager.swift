import Foundation
import Combine

// MARK: - Session Manager
/// Manages agent session lifecycle: creation, persistence, loading, deletion, and date-based grouping.
class SessionManager: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var isLoading = false
    @Published var error: String?

    private let storageURL: URL
    private let maxSessions = 100
    private let sessionsFileName = "sessions.json"

    init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageURL = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageURL = appSupport.appendingPathComponent("AthlonAgent/Sessions")
        }
        ensureDirectory()
    }

    // MARK: - Directory Setup
    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    // MARK: - Load All Sessions
    func loadSessions() {
        isLoading = true
        defer { isLoading = false }

        let fileURL = storageURL.appendingPathComponent(sessionsFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([AgentSession].self, from: data)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            self.error = "无法加载会话: \(error.localizedDescription)"
            sessions = []
        }
    }

    // MARK: - Save All Sessions
    private func saveSessions() {
        ensureDirectory()
        let fileURL = storageURL.appendingPathComponent(sessionsFileName)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            self.error = "无法保存会话: \(error.localizedDescription)"
        }
    }

    // MARK: - Create Session
    @discardableResult
    func createSession(title: String? = nil, workspace: String? = nil, workspaceName: String? = nil) -> AgentSession {
        let session = AgentSession(
            id: UUID().uuidString,
            title: title ?? "新对话",
            messages: [],
            activeWorkspace: workspace,
            workspaceName: workspaceName,
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0,
            plan: nil
        )
        sessions.insert(session, at: 0)
        deactivateOtherSessions(except: session.id)
        trimSessions()
        saveSessions()
        return session
    }

    // MARK: - Activate Session
    func activateSession(_ sessionId: String) {
        deactivateOtherSessions(except: sessionId)
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].isActive = true
            sessions[idx].updatedAt = Date()
            saveSessions()
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
        saveSessions()
        // Also delete individual session file if exists
        let sessionFile = storageURL.appendingPathComponent("\(sessionId).json")
        try? FileManager.default.removeItem(at: sessionFile)
    }

    // MARK: - Update Session
    func updateSession(_ sessionId: String, update: (inout AgentSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        update(&sessions[idx])
        sessions[idx].updatedAt = Date()
        saveSessions()
    }

    // MARK: - Add Message to Session
    func addMessage(_ message: ChatMessage, to sessionId: String) {
        updateSession(sessionId) { session in
            session.messages.append(message)
        }
    }

    // MARK: - Update Plan
    func updatePlan(_ plan: AgentPlan?, for sessionId: String) {
        updateSession(sessionId) { session in
            session.plan = plan
        }
    }

    // MARK: - Set Running State
    func setRunning(_ running: Bool, for sessionId: String) {
        updateSession(sessionId) { session in
            session.isRunning = running
        }
    }

    // MARK: - Set Queued Turn Count
    func setQueuedTurnCount(_ count: Int, for sessionId: String) {
        updateSession(sessionId) { session in
            session.queuedTurnCount = count
        }
    }

    // MARK: - Export Session to Individual File
    func exportSession(_ sessionId: String) -> URL? {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return nil }
        let fileURL = storageURL.appendingPathComponent("\(sessionId).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
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
                let file = storageURL.appendingPathComponent("\(session.id).json")
                try? FileManager.default.removeItem(at: file)
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
