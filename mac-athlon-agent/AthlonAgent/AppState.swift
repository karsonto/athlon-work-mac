import SwiftUI
import Combine

// MARK: - App Page Enum
enum AppPage: String, CaseIterable {
    case welcome = "Welcome"
    case chat = "Chat"
    case settings = "Settings"
    case fileEditor = "FileEditor"
}

// MARK: - Global App State
/// Equivalent to MainWindowViewModel in the WPF app.
final class AppState: ObservableObject {
    // MARK: - Navigation
    @Published var currentPage: AppPage = .welcome
    @Published var activeSessionId: String?
    @Published var sessions: [AgentSession] = []

    // MARK: - Theme
    @AppStorage("appTheme") var themeStorage: String = "dark"
    @Published var theme: AppTheme = .dark

    // MARK: - Workspace
    @Published var activeWorkspace: String?
    @Published var activeWorkspaceName: String = "No workspace"
    @Published var workspaceRootPath: String?

    // MARK: - Chat
    @Published var messages: [ChatMessage] = []
    @Published var isBusy: Bool = false
    @Published var streamingText: String = ""

    // MARK: - Sessions
    @Published var sessionGroups: [SessionHistoryGroup] = []
    @Published var hasAgentRecords: Bool = false

    // MARK: - Queued turns
    @Published var queuedTurns: [QueuedTurn] = []
    @Published var hasQueuedTurns: Bool = false

    // MARK: - Composer
    @Published var composerText: String = ""
    @Published var isAtCompletionOpen: Bool = false
    @Published var atCompletionItems: [AtCompletionItem] = []
    @Published var selectedAtCompletionIndex: Int = -1
    @Published var pendingImageAttachments: [ImageAttachment] = []

    // MARK: - Editor
    @Published var editingFilePath: String?
    @Published var hasOpenEditorTabs: Bool = false

    // MARK: - Copy notice
    @Published var copyNotice: String = ""
    @Published var isCopyNoticeVisible: Bool = false

    // MARK: - Shutdown
    @Published var shutdownStatusText: String = "Shutting down..."
    @Published var isShuttingDown: Bool = false

    // MARK: - Layout persistence
    @Published var navigationSidebarWidth: CGFloat = 220
    @Published var contextSidebarWidth: CGFloat = 300
    @Published var editorPaneWidth: CGFloat = 480
    @Published var composerHeight: CGFloat = 168

    // MARK: - Sidebar visibility
    @Published var isNavigationSidebarVisible: Bool = true
    @Published var isContextSidebarVisible: Bool = true

    // MARK: - Settings
    @Published var settings: AppSettings = AppSettings.default

    // MARK: - Services
    private(set) var themeManager: ThemeManager!
    private(set) var sessionManager: SessionManager!
    private(set) var agentRuntime: AgentRuntimeService!
    private(set) var mcpClientService: McpClientService!
    private(set) var skillService: SkillService!
    private(set) var workspaceService: WorkspaceService!
    private(set) var imageAttachmentService: ImageAttachmentService!
    private(set) var planViewModel: PlanViewModel?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Logs
    var logsPath: String {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs/AthlonAgent")
            .path ?? "~/Library/Logs/AthlonAgent"
    }

    // MARK: - Computed Properties
    var activeSessionTitle: String {
        guard let id = activeSessionId,
              let session = sessions.first(where: { $0.id == id }) else {
            return "新会话"
        }
        return session.title.isEmpty ? "新会话" : session.title
    }

    var activeSessionWorkspace: String? {
        guard let id = activeSessionId,
              let session = sessions.first(where: { $0.id == id }) else {
            return nil
        }
        return session.workspaceName
    }

    var activeMessageCount: Int { messages.count }

    var activeMessages: [ChatMessage] { messages }

    var isAgentRunning: Bool {
        agentRuntime?.isRunning ?? false
    }

    var plan: AgentPlan? {
        guard let id = activeSessionId,
              let session = sessions.first(where: { $0.id == id }) else {
            return nil
        }
        return session.plan
    }

    // Convenience: workspace files from workspace service
    var workspaceFiles: [WorkspaceNode] {
        workspaceService?.files ?? []
    }

    var mcpServers: [McpServerItem] {
        mcpClientService?.servers ?? []
    }

    var skills: [SkillItem] {
        skillService?.skills ?? []
    }

    // MARK: - Init
    init() {
        // Load theme
        theme = themeStorage == "light" ? .light : .dark

        // Initialize theme manager
        themeManager = ThemeManager()
        themeManager.saveTheme(theme)

        // Load settings
        loadSettings()

        // Initialize services
        sessionManager = SessionManager()
        agentRuntime = AgentRuntimeService(settings: settings)
        mcpClientService = McpClientService()
        skillService = SkillService()
        workspaceService = WorkspaceService(ignorePatterns: settings.workspaceIgnore.directoryNames)
        imageAttachmentService = ImageAttachmentService()

        // Create initial session
        let initialSession = sessionManager.createSession(title: "")
        sessions = [initialSession]
        activeSessionId = initialSession.id
        planViewModel = PlanViewModel(sessionManager: sessionManager, sessionId: initialSession.id)
        currentPage = .welcome

        // Sync session state
        syncSessionState()
    }

    // MARK: - Settings Persistence
    private let settingsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("AthlonAgent/settings.json")
    }()

    func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            settings = AppSettings.default
            return
        }
        settings = loaded
    }

    func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
        // Reconfigure services
        agentRuntime = AgentRuntimeService(settings: settings)
    }

    // MARK: - Session Sync
    func syncSessionState() {
        sessions = sessionManager.sessions
        if let id = activeSessionId, let session = sessionManager.getSession(id) {
            messages = session.messages
        }
        sessionGroups = buildSessionGroups()
    }

    private func buildSessionGroups() -> [SessionHistoryGroup] {
        let grouped = sessionManager.groupedSessions()
        var result: [SessionHistoryGroup] = []

        for (group, list) in grouped {
            let items = list.map { session in
                SessionHistoryItem(
                    id: session.id,
                    title: session.title.isEmpty ? "新会话" : session.title,
                    updatedAtText: shortTime(from: session.updatedAt),
                    isActive: activeSessionId == session.id,
                    isRunning: session.isRunning
                )
            }
            result.append(SessionHistoryGroup(
                id: group.id,
                title: group.rawValue,
                items: items,
                isExpanded: group == .today
            ))
        }
        return result
    }

    private func shortTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'昨天' HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    // MARK: - Actions
    func createNewSession() {
        // Deactivate current
        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.isRunning = false
                session.messages = messages
            }
        }

        let session = sessionManager.createSession(title: "")
        sessions = sessionManager.sessions
        activeSessionId = session.id
        messages = []
        planViewModel = PlanViewModel(sessionManager: sessionManager, sessionId: session.id)
        sessionGroups = buildSessionGroups()
        currentPage = .chat
    }

    func activateSession(_ sessionId: String) {
        guard sessionId != activeSessionId else { return }

        // Save current session state
        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.messages = messages
            }
        }

        activeSessionId = sessionId
        sessionManager.activateSession(sessionId)
        if let session = sessionManager.getSession(sessionId) {
            messages = session.messages
        }
        planViewModel = PlanViewModel(sessionManager: sessionManager, sessionId: sessionId)
        sessionGroups = buildSessionGroups()
        currentPage = .chat
    }

    func sendMessage(_ text: String) {
        guard let id = activeSessionId else { return }
        currentPage = .chat

        // Build user message
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            createdAt: Date()
        )
        messages.append(userMsg)

        // Persist
        sessionManager.updateSession(id) { session in
            session.messages.append(userMsg)
            session.isRunning = true
        }

        // Start streaming assistant placeholder
        let assistantMsg = ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: "",
            createdAt: Date()
        )
        messages.append(assistantMsg)

        // Set up system prompt
        let systemPrompt = SystemPromptBuilder.build(
            workspaceRoot: workspaceRootPath,
            files: workspaceService.flatFilePaths,
            mcpTools: mcpClientService.allAvailableTools,
            skills: skillService.enabledSkillNames,
            date: Date()
        )

        // Build tools from MCP
        let tools = buildToolDefinitions()

        // Send to agent runtime
        agentRuntime.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            onChunk: { [weak self] chunk in
                // Update streaming assistant message
                DispatchQueue.main.async {
                    guard let self = self, let idx = self.messages.firstIndex(where: { $0.id == assistantMsg.id }) else { return }
                    self.messages[idx].content += chunk
                }
            },
            onToolCall: { [weak self] toolCall in
                // Handle tool call - add to messages
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let tcMsg = ChatMessage(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: "",
                        createdAt: Date(),
                        toolCalls: [toolCall]
                    )
                    self.messages.append(tcMsg)
                    self.sessionManager.addMessage(tcMsg, to: id)
                }
            },
            onReasoningChunk: { [weak self] reasoning in
                DispatchQueue.main.async {
                    guard let self = self, let idx = self.messages.firstIndex(where: { $0.id == assistantMsg.id }) else { return }
                    self.messages[idx].reasoningContent += reasoning
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.sessionManager.updateSession(id) { session in
                        session.isRunning = false
                        session.messages = self.messages
                        session.updatedAt = Date()
                    }

                    switch result {
                    case .success(let fullText):
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                            self.messages[idx].content = fullText
                        }
                    case .failure(let error):
                        self.messages.append(ChatMessage(
                            id: UUID().uuidString,
                            role: .system,
                            content: "错误: \(error.localizedDescription)",
                            createdAt: Date()
                        ))
                    }
                    self.sessionGroups = self.buildSessionGroups()
                }
            }
        )
    }

    private func buildToolDefinitions() -> [ToolDefinition] {
        // Gather tools from MCP servers
        var tools: [ToolDefinition] = []
        for server in mcpClientService.servers where server.isEnabled {
            for toolName in server.toolNames {
                tools.append(ToolDefinition(
                    name: toolName,
                    description: "Tool from MCP server: \(server.name)",
                    parameters: [
                        "type": "object",
                        "properties": [:],
                        "required": []
                    ]
                ))
            }
        }
        return tools
    }

    func stopAgent() {
        agentRuntime?.stop()
    }

    func openFileEditor(path: String) {
        editingFilePath = path
        currentPage = .fileEditor
    }

    func toggleTheme() {
        theme = theme == .dark ? .light : .dark
        themeStorage = theme.rawValue.lowercased()
        themeManager?.saveTheme(theme)
    }

    // MARK: - Workspace Operations
    func setWorkspaceRoot(_ path: String) {
        workspaceRootPath = path
        workspaceService.setWorkspaceRoot(path)
        activeWorkspace = path
        activeWorkspaceName = (path as NSString).lastPathComponent
    }

    func refreshWorkspace() {
        workspaceService.scanWorkspace()
    }

    // MARK: - Plan Operations
    func updatePlanSubtask(subtaskId: String, status: PlanSubtaskStatus, outcome: String?) {
        planViewModel?.updateSubtaskStatus(subtaskId, to: status, outcome: outcome)
    }

    // MARK: - Cleanup
    func prepareForShutdown() {
        // Save active session
        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.messages = messages
                session.isRunning = false
            }
        }
        workspaceService.stopMonitoring()
    }
}

// MARK: - Session History Group
struct SessionHistoryGroup: Identifiable {
    let id: String
    let title: String
    let items: [SessionHistoryItem]
    var isExpanded: Bool = true
}

struct SessionHistoryItem: Identifiable {
    let id: String
    let title: String
    let updatedAtText: String
    let isActive: Bool
    let isRunning: Bool
}

// MARK: - Queued Turn
struct QueuedTurn: Identifiable {
    let id: String
    let previewText: String
    let imageItems: [QueuedTurnImage]
}

struct QueuedTurnImage: Identifiable {
    let id: String
    let fileName: String
    let thumbnail: Data?
}

// MARK: - At Completion
struct AtCompletionItem: Identifiable {
    let id: String
    let type: String // "文件" or "技能"
    let primaryText: String
    let secondaryText: String
}
