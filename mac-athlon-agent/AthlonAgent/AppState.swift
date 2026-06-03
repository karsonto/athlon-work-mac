import AppKit
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
@MainActor
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
    /// Live assistant bubble for the active turn — pinned to the bottom of the chat timeline while running.
    @Published var pinnedAssistantMessageId: String?

    // MARK: - Sessions
    @Published var sessionGroups: [SessionHistoryGroup] = []
    @Published var hasAgentRecords: Bool = false

    // MARK: - Queued turns
    @Published var queuedTurns: [QueuedTurn] = []
    @Published var hasQueuedTurns: Bool = false

    // MARK: - Composer
    @Published var composerText: String = ""
    /// Transient hint (e.g. message queued while a turn is still running).
    @Published var composerStatusMessage: String = ""
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

    // MARK: - Interaction mode (aligned with WPF Plan/Agent toggle)
    @Published var interactionMode: AgentInteractionMode = .agent

    // MARK: - Services
    private(set) var themeManager: ThemeManager!
    private(set) var sessionManager: SessionManager!
    private(set) var agentRuntime: AgentRuntimeService!
    private(set) var mcpClientService: McpClientService!
    private(set) var skillService: SkillService!
    private(set) var workspaceService: WorkspaceService!
    private(set) var imageAttachmentService: ImageAttachmentService!
    private(set) var planViewModel: PlanViewModel?
    private(set) var sessionTurnHost: SessionTurnHost!
    private var planWorkspaceGuard: WorkspaceGuard!
    private(set) var planNotebook: PlanNotebook!
    private let executeCommandRegistry = ExecuteCommandProcessRegistry()
    private let planAutoContinueTracker = PlanAutoContinueTracker()
    private var uiControllers: [String: SessionTurnUiController] = [:]
    private let sessionUiCache = SessionUiCache()
    private var uiSettingsSaveWorkItem: DispatchWorkItem?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Logs
    var logsPath: String {
        AppPathProvider.shared.logsPath
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

    /// Matches `SessionTurnHost` occupancy (same signal as `isBusy`), not `agentRuntime` alone.
    var isAgentRunning: Bool {
        guard let id = activeSessionId else { return false }
        return sessionTurnHost.isRunning(id)
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
        AppPathProvider.shared.ensureCreated()
        SettingsMigration.runIfNeeded()

        // Load theme
        theme = themeStorage == "light" ? .light : .dark

        // Initialize theme manager
        themeManager = ThemeManager()
        themeManager.saveTheme(theme)

        // Load settings
        settings = SettingsStore.load()
        applyUiSettings()

        // Initialize services
        sessionManager = SessionManager()
        agentRuntime = AgentRuntimeService(settings: settings)
        mcpClientService = McpClientService()
        mcpClientService.syncFromSettings(settings.mcpServers)
        skillService = SkillService()
        skillService.reload(savedSettings: settings.skills)
        workspaceService = WorkspaceService(ignorePatterns: settings.workspaceIgnore.directoryNames)
        imageAttachmentService = ImageAttachmentService()
        planWorkspaceGuard = WorkspaceGuard(workspaceService: workspaceService, settings: settings)
        planNotebook = PlanNotebook(
            settings: settings.plan,
            workspaceGuard: planWorkspaceGuard,
            sessionManager: sessionManager
        )
        agentRuntime.configureDependencies(
            workspaceService: workspaceService,
            skillService: skillService,
            sessionManager: sessionManager,
            mcpClientService: mcpClientService,
            executeCommandRegistry: executeCommandRegistry,
            planNotebook: planNotebook
        )

        sessionManager.loadSessions()
        if let existing = sessionManager.sessions.first {
            sessions = sessionManager.sessions
            activeSessionId = existing.id
            messages = existing.messages
        } else {
            let initialSession = sessionManager.createSession(title: "")
            sessions = sessionManager.sessions
            activeSessionId = initialSession.id
        }

        if let id = activeSessionId {
            planViewModel = PlanViewModel(sessionManager: sessionManager, sessionId: id)
            if let session = sessionManager.getSession(id) {
                interactionMode = session.interactionMode
                applySessionWorkspace(for: session)
            }
        }

        sessionTurnHost = SessionTurnHost(
            settingsProvider: { [weak self] in self?.settings.agentTurn ?? AgentTurnSettings() },
            executor: { [weak self] request, onChunk, onToolCall, onReasoning, completion in
                self?.executeTurn(request, onChunk: onChunk, onToolCall: onToolCall, onReasoning: onReasoning, completion: completion)
            }
        )
        sessionTurnHost.onTurnStateChanged = { [weak self] sessionId in
            DispatchQueue.main.async { self?.handleTurnStateChanged(sessionId) }
        }
        sessionTurnHost.onTurnCompleted = { [weak self] event in
            DispatchQueue.main.async { self?.handleTurnCompleted(event) }
        }
        sessionTurnHost.onReconcileTurn = { [weak self] request, session, cancelled, timedOut, errorMessage in
            guard let self else {
                return (session, [])
            }
            return self.reconcileInterruptedTurn(
                request: request,
                session: session,
                cancelled: cancelled,
                timedOut: timedOut,
                errorMessage: errorMessage
            )
        }

        mcpClientService.refreshConnections(settings: settings.mcpServers, workspaceRoot: workspaceRootPath)
        currentPage = .chat

        syncSessionState()
        updateBusyState()
    }

    // MARK: - Settings Persistence
    func loadSettings() {
        settings = SettingsStore.load()
        mcpClientService.syncFromSettings(settings.mcpServers)
        applyUiSettings()
    }

    func saveSkillSettings() {
        let installed = SkillSettingsMerger.scanInstalled(skillsRootPath: AppPathProvider.shared.skillsPath)
        settings.skills = SkillSettingsMerger.merge(
            skillsRootPath: AppPathProvider.shared.skillsPath,
            installedSkills: installed,
            saved: settings.skills
        )
        saveSettings()
    }

    func saveSettings() {
        do {
            settings = try SettingsStore.save(settings)
            settings = SettingsStore.load()
            mcpClientService.syncFromSettings(settings.mcpServers)
            mcpClientService.refreshConnections(settings: settings.mcpServers, workspaceRoot: workspaceRootPath)
            skillService.reload(savedSettings: settings.skills)
            applyUiSettings()
        } catch {
            print("Failed to save settings: \(error)")
        }
        agentRuntime = AgentRuntimeService(settings: settings)
        agentRuntime.configureDependencies(
            workspaceService: workspaceService,
            skillService: skillService,
            sessionManager: sessionManager,
            mcpClientService: mcpClientService,
            executeCommandRegistry: executeCommandRegistry,
            planNotebook: planNotebook
        )
    }

    var canBuildPlan: Bool {
        !isBusy && interactionMode == .plan && plan?.phase == .draft
    }

    var planFilePathForEditor: String? {
        planFilePath()
    }

    func setInteractionMode(_ mode: AgentInteractionMode) {
        interactionMode = mode
        guard let id = activeSessionId else { return }
        sessionManager.updateSession(id) { $0.interactionMode = mode }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].interactionMode = mode
        }
    }

    func togglePlanMode() {
        setInteractionMode(interactionMode == .plan ? .agent : .plan)
    }

    func buildPlan() {
        guard let id = activeSessionId else { return }
        guard canBuildPlan else { return }
        let result = planNotebook.approvePlan(sessionId: id)
        if !result.success {
            appendSystemMessage(result.message, sessionId: id)
            return
        }
        setInteractionMode(.agent)
        planViewModel?.loadPlan()
        if let path = planFilePath() {
            openFileEditor(path: path)
        }
        sendMessage(PlanExecuteDefaults.executeUserMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func planFilePath() -> String? {
        guard let root = workspaceRootPath?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else {
            return nil
        }
        let fileName = settings.plan.planFileName.isEmpty ? "plan.md" : settings.plan.planFileName
        return (root as NSString).appendingPathComponent(fileName)
    }

    private func applyUiSettings() {
        navigationSidebarWidth = CGFloat(settings.ui.navigationSidebarWidth)
        contextSidebarWidth = CGFloat(settings.ui.contextSidebarWidth)
        editorPaneWidth = CGFloat(settings.ui.editorPaneWidth)
        composerHeight = CGFloat(settings.ui.composerHeight)
        isContextSidebarVisible = settings.ui.contextSidebarVisible
    }

    // MARK: - Session Sync
    func syncSessionState() {
        sessions = sessionManager.sessions
        if let id = activeSessionId, let session = sessionManager.getSession(id) {
            mergeMessagesFromSession(session.messages)
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

    func deleteSession(_ sessionId: String) {
        guard sessionManager.getSession(sessionId) != nil else { return }

        if let id = activeSessionId, id == sessionId {
            sessionManager.updateSession(id) { session in
                session.messages = messages
                session.isRunning = false
            }
        }

        sessionTurnHost.dropSession(sessionId)
        planAutoContinueTracker.reset(sessionId)
        uiControllers.removeValue(forKey: sessionId)

        let wasActive = activeSessionId == sessionId
        sessionManager.deleteSession(sessionId)
        sessions = sessionManager.sessions

        if wasActive {
            activeSessionId = nil
            messages = []
            hasQueuedTurns = false
            queuedTurns = []
            if let next = sessions.first {
                activateSession(next.id)
            } else {
                createNewSession()
            }
        } else {
            sessionGroups = buildSessionGroups()
        }
    }

    func activateSession(_ sessionId: String) {
        guard sessionId != activeSessionId else { return }

        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.messages = messages
            }
            sessionUiCache.set(id, state: SessionUiState())
        }

        activeSessionId = sessionId
        _ = sessionUiCache.get(sessionId)
        sessionManager.activateSession(sessionId)
        if let session = sessionManager.getSession(sessionId) {
            messages = session.messages
            interactionMode = session.interactionMode
            applySessionWorkspace(for: session)
        }
        planViewModel = PlanViewModel(sessionManager: sessionManager, sessionId: sessionId)
        sessionGroups = buildSessionGroups()
        currentPage = .chat
    }

    func sendMessage(_ text: String) {
        guard let id = activeSessionId, var session = sessionManager.getSession(id) else { return }
        currentPage = .chat
        planAutoContinueTracker.reset(id)

        let ui = uiController(for: id)
        let images = pendingImageAttachments
        pendingImageAttachments = []

        if sessionTurnHost.isRunning(id) {
            let queueId = UUID().uuidString
            sessionTurnHost.enqueue(QueuedTurnPayload(
                queueId: queueId,
                sessionId: id,
                userInput: text,
                imageAttachments: images,
                ui: ui
            ))
            syncQueuedTurns(sessionId: id)
            composerStatusMessage = "已加入排队，当前回合结束后将自动发送。"
            return
        }

        composerStatusMessage = ""
        let expanded = SkillComposerExpander.expand(
            text,
            availableSkills: skillService.availableSkillInfos(settings: settings)
        )
        ui.addUserMessage(expanded, imageAttachments: images)
        session.isRunning = true
        session.interactionMode = interactionMode
        if let workspaceRootPath {
            session.activeWorkspace = workspaceRootPath
            session.workspaceName = activeWorkspaceName
        }
        sessionManager.updateSession(id) { $0 = session }

        if let latest = sessionManager.getSession(id) {
            session = latest
        }

        let request = SessionTurnRequest(
            sessionId: id,
            session: session,
            userInput: expanded,
            imageAttachments: images,
            ui: ui,
            isAutoContinue: false
        )

        if let error = sessionTurnHost.tryStart(request) {
            appendSystemMessage(error, sessionId: id)
            sessionManager.setRunning(false, for: id)
        }
        updateBusyState()
    }

    func stopAgent() {
        guard let id = activeSessionId else { return }
        sessionTurnHost.cancel(sessionId: id)
        executeCommandRegistry.killAll()
        agentRuntime.stop()
        uiController(for: id).markTurnCancelled()
        sessionTurnHost.clearQueue(sessionId: id)
        syncQueuedTurns(sessionId: id)
        composerStatusMessage = ""
        pinnedAssistantMessageId = nil

        if let request = sessionTurnHost.abortTurn(sessionId: id) {
            finalizeAbortedTurn(sessionId: id, request: request)
        } else {
            sessionManager.setRunning(false, for: id)
            updateBusyState()
        }
    }

    /// Ends a cancelled turn immediately so the next `sendMessage` does not enqueue (aligned with WPF `StopSession`).
    private func finalizeAbortedTurn(sessionId: String, request: SessionTurnRequest) {
        var session = sessionManager.getSession(sessionId) ?? request.session
        var reconciled: [ChatMessage] = []
        if let outcome = sessionTurnHost.onReconcileTurn?(request, session, true, false, nil) {
            session = outcome.session
            reconciled = outcome.persistedMessages
            sessionManager.updateSession(sessionId) { $0 = session }
            if sessionId == activeSessionId {
                mergeMessagesFromSession(session.messages)
            }
        }
        request.ui.finalizeTurn(
            fullText: "",
            cancelled: true,
            timedOut: false,
            errorMessage: nil,
            reconciledMessages: reconciled
        )
        sessionManager.setRunning(false, for: sessionId)
        updateBusyState()
        sessionGroups = buildSessionGroups()
    }

    // MARK: - Session turn integration

    private func uiController(for sessionId: String) -> SessionTurnUiController {
        if let existing = uiControllers[sessionId] {
            return existing
        }
        let controller = SessionTurnUiController(sessionId: sessionId, appState: self)
        uiControllers[sessionId] = controller
        return controller
    }

    func upsertToolMessage(_ message: ChatMessage, sessionId: String) {
        if sessionId == activeSessionId,
           let toolCallId = message.toolCallId,
           let index = messages.firstIndex(where: { $0.toolCallId == toolCallId }) {
            messages[index] = mergeToolMessage(existing: messages[index], incoming: message)
        } else {
            appendMessage(message, sessionId: sessionId, persist: false)
            return
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            if let toolCallId = message.toolCallId,
               let index = session.messages.firstIndex(where: { $0.toolCallId == toolCallId }) {
                session.messages[index] = self.mergeToolMessage(existing: session.messages[index], incoming: message)
            } else if !session.messages.contains(where: { $0.id == message.id }) {
                session.messages.append(message)
            }
        }
    }

    /// Merges persisted tool output into the live UI row (same `toolCallId`, often different `message.id`).
    private func mergeToolMessage(existing: ChatMessage, incoming: ChatMessage) -> ChatMessage {
        var merged = existing
        if incoming.content.count > existing.content.count {
            merged.content = incoming.content
        } else if existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.content = incoming.content
        }
        if let toolCalls = incoming.toolCalls, !toolCalls.isEmpty {
            merged.toolCalls = toolCalls
        }
        applyToolResultStatus(to: &merged, content: merged.content)
        return merged
    }

    private func applyToolResultStatus(to message: inout ChatMessage, content: String) {
        guard message.isTool, var calls = message.toolCalls, !calls.isEmpty else { return }
        let lower = content.lowercased()
        let status: ToolCallDisplayStatus = {
            if lower.contains(" failed") || lower.contains(" failed.") { return .failed }
            if lower.contains(" succeeded") { return .succeeded }
            return calls[0].status
        }()
        for idx in calls.indices {
            calls[idx].status = status
            if status == .succeeded {
                calls[idx].resultSummary = "已完成 ✓"
            } else if status == .failed {
                calls[idx].resultSummary = "失败 ✗"
            }
        }
        message.toolCalls = calls
    }

    func appendMessage(_ message: ChatMessage, sessionId: String, persist: Bool? = nil) {
        let shouldPersist = persist ?? !sessionTurnHost.isRunning(sessionId)
        if sessionId == activeSessionId {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
        }
        sessionManager.upsertMessage(message, to: sessionId, persist: shouldPersist)
    }

    func removeMessage(sessionId: String, messageId: String) {
        if sessionId == activeSessionId {
            messages.removeAll { $0.id == messageId }
        }
        sessionManager.updateSession(sessionId) { session in
            session.messages.removeAll { $0.id == messageId }
        }
    }

    func mergeMessagesFromSession(_ sessionMessages: [ChatMessage]) {
        var mergedById: [String: ChatMessage] = [:]
        for message in sessionMessages {
            mergeMessagePreferringRicher(&mergedById, message)
        }
        for message in messages {
            mergeMessagePreferringRicher(&mergedById, message)
        }

        var toolByCallId: [String: ChatMessage] = [:]
        var others: [ChatMessage] = []
        for message in mergedById.values {
            if message.isTool, let toolCallId = message.toolCallId, !toolCallId.isEmpty {
                if let existing = toolByCallId[toolCallId] {
                    toolByCallId[toolCallId] = mergeToolMessage(existing: existing, incoming: message)
                } else {
                    toolByCallId[toolCallId] = message
                }
            } else {
                others.append(message)
            }
        }

        messages = (others + toolByCallId.values).sorted { $0.createdAt < $1.createdAt }
    }

    private func mergeMessagePreferringRicher(_ mergedById: inout [String: ChatMessage], _ message: ChatMessage) {
        let normalized = message.withPromotedAnswer()
        guard let existing = mergedById[normalized.id] else {
            mergedById[normalized.id] = normalized
            return
        }
        let existingScore = existing.content.trimmingCharacters(in: .whitespacesAndNewlines).count
            + existing.reasoningContent.count
        let incomingScore = normalized.content.trimmingCharacters(in: .whitespacesAndNewlines).count
            + normalized.reasoningContent.count
        if incomingScore >= existingScore {
            mergedById[normalized.id] = normalized
        }
    }

    /// Ends streaming on the pre-tool assistant bubble but keeps visible `content` (do not wipe the answer text).
    func sealAssistantBeforeTools(sessionId: String, messageId: String, reasoningContent: String) {
        guard sessionId == activeSessionId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        if !reasoningContent.isEmpty {
            messages[index].reasoningContent = reasoningContent
        }
        messages[index].toolCalls = nil
        messages[index].isStreaming = false
        messages[index].isReasoningStreaming = false
        sessionManager.updateSessionInMemory(sessionId) { session in
            guard let idx = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            if !reasoningContent.isEmpty {
                session.messages[idx].reasoningContent = reasoningContent
            }
            session.messages[idx].toolCalls = nil
            session.messages[idx].isStreaming = false
            session.messages[idx].isReasoningStreaming = false
        }
    }

    func updateMessageContent(
        sessionId: String,
        messageId: String,
        content: String,
        isStreaming: Bool = true
    ) {
        if sessionId == activeSessionId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].content = content
            messages[index].isStreaming = isStreaming
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].isReasoningStreaming = false
            }
            if !isStreaming {
                messages[index] = messages[index].withPromotedAnswer()
                messages[index].isReasoningStreaming = false
            }
            if !content.isEmpty {
                let reasoningLen = messages[index].reasoningContent.count
                AgentFileLogger.logUIAssistant(
                    sessionId: sessionId,
                    messageId: messageId,
                    contentLength: content.count,
                    reasoningLength: reasoningLen,
                    isStreaming: isStreaming,
                    source: "updateMessageContent"
                )
            }
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            session.messages[index].content = content
            session.messages[index].isStreaming = isStreaming
            if !isStreaming {
                session.messages[index] = session.messages[index].withPromotedAnswer()
            }
        }
    }

    func appendReasoning(sessionId: String, messageId: String, chunk: String) {
        setReasoningContent(sessionId: sessionId, messageId: messageId, content: chunk)
    }

    func setReasoningContent(
        sessionId: String,
        messageId: String,
        content: String,
        isReasoningStreaming: Bool = true
    ) {
        if sessionId == activeSessionId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            applyReasoningChannel(to: &messages[index], incoming: content, isReasoningStreaming: isReasoningStreaming)
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            applyReasoningChannel(to: &session.messages[index], incoming: content, isReasoningStreaming: isReasoningStreaming)
        }
    }

    /// Routes reasoning tokens into `reasoningContent` while streaming; promotes to `content` when the turn ends (WPF split).
    private func applyReasoningChannel(
        to message: inout ChatMessage,
        incoming: String,
        isReasoningStreaming: Bool
    ) {
        message.isReasoningStreaming = isReasoningStreaming
        guard !incoming.isEmpty else { return }

        if isReasoningStreaming {
            message.reasoningContent = incoming
            return
        }

        message.reasoningContent = incoming
        message = message.withPromotedAnswer()
    }

    func syncAssistantMessage(sessionId: String, message: ChatMessage) {
        var merged = mergeAssistantMessagePreservingStreamedFields(message)
        if !merged.isStreaming {
            merged = merged.withPromotedAnswer()
        }
        if sessionId == activeSessionId,
           let index = messages.firstIndex(where: { $0.id == merged.id }) {
            messages[index] = merged
            AgentFileLogger.logUIAssistant(
                sessionId: sessionId,
                messageId: merged.id,
                contentLength: merged.content.count,
                reasoningLength: merged.reasoningContent.count,
                isStreaming: merged.isStreaming,
                source: "syncAssistantMessage"
            )
        }
        let persist = !sessionTurnHost.isRunning(sessionId)
        if persist {
            sessionManager.updateSession(sessionId) { session in
                guard let index = session.messages.firstIndex(where: { $0.id == merged.id }) else { return }
                session.messages[index] = merged
            }
        } else {
            sessionManager.updateSessionInMemory(sessionId) { session in
                guard let index = session.messages.firstIndex(where: { $0.id == merged.id }) else { return }
                session.messages[index] = merged
            }
        }
    }

    private func mergeAssistantMessagePreservingStreamedFields(_ incoming: ChatMessage) -> ChatMessage {
        guard let existing = messages.first(where: { $0.id == incoming.id }) else { return incoming }
        var merged = incoming
        if merged.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.content = existing.content
        }
        if merged.reasoningContent.isEmpty {
            merged.reasoningContent = existing.reasoningContent
        }
        return merged
    }

    func finishTurnUI(sessionId: String) {
        sessionManager.setRunning(false, for: sessionId, persist: false)
        sessionManager.setQueuedTurnCount(sessionTurnHost.queueCount(sessionId: sessionId), for: sessionId, persist: false)
        if sessionId == activeSessionId {
            sessionManager.updateSessionInMemory(sessionId) { session in
                session.messages = self.messages
            }
        }
        sessionManager.persistSession(sessionId)
        if sessionId == activeSessionId {
            pinnedAssistantMessageId = nil
            composerStatusMessage = ""
            syncSessionState()
        } else {
            sessions = sessionManager.sessions
        }
        updateBusyState()
        sessionGroups = buildSessionGroups()
    }

    private func appendSystemMessage(_ text: String, sessionId: String) {
        appendMessage(ChatMessage(id: UUID().uuidString, role: .system, content: text, createdAt: Date()), sessionId: sessionId)
    }

    private func executeTurn(
        _ request: SessionTurnRequest,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (AgentToolCall) -> Void,
        onReasoning: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let sessionId = request.sessionId
        guard var session = sessionManager.getSession(sessionId) else {
            completion(.failure(NSError(domain: "Athlon", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "会话不存在"
            ])))
            return
        }

        let assistantId = request.ui.reserveAssistantMessageId()
        if sessionId == activeSessionId {
            pinnedAssistantMessageId = assistantId
        }

        if let latest = sessionManager.getSession(sessionId) {
            session = latest
        }

        agentRuntime.sendTurn(
            session: session,
            streamingAssistantId: assistantId,
            onSessionUpdated: { updated in
                session = updated
            },
            onMessage: { message in
                if message.role == .tool {
                    self.upsertToolMessage(message, sessionId: sessionId)
                } else if message.role == .compaction {
                    self.appendMessage(message, sessionId: sessionId)
                } else if message.role == .assistant {
                    var assistant = message.withPromotedAnswer()
                    assistant.isStreaming = false
                    assistant.isReasoningStreaming = false
                    // Tool cards are separate rows; keep API history on session only.
                    assistant.toolCalls = nil
                    if assistant.isAssistantToolCallsOnly {
                        // Tool cards are driven by onToolCall; hide tool_calls-only assistant rows (WPF).
                    } else if self.messages.contains(where: { $0.id == assistant.id }) {
                        self.syncAssistantMessage(sessionId: sessionId, message: assistant)
                    } else if !assistant.content.isEmpty || assistant.hasReasoning {
                        self.appendMessage(assistant, sessionId: sessionId)
                    }
                }
                if let toolCalls = message.toolCalls {
                    for call in toolCalls { onToolCall(call) }
                }
            },
            onToolStarted: { toolCall in
                onToolCall(toolCall)
            },
            onStreamingAssistantTarget: { id in
                request.ui.adoptAssistantMessageId(id)
            },
            onStreamingAssistantUpdate: { _, content, reasoning in
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onChunk(content)
                }
                if !reasoning.isEmpty {
                    onReasoning(reasoning)
                }
            },
            completion: { result in
                switch result {
                case .success(let updated):
                    self.sessionManager.updateSessionInMemory(sessionId) { $0 = updated }
                    if sessionId == self.activeSessionId {
                        self.mergeMessagesFromSession(updated.messages)
                    }
                    self.sessionManager.persistSession(sessionId)
                    let assistant = updated.messages.last(where: {
                        $0.role == .assistant
                            && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }) ?? updated.messages.last(where: { $0.role == .assistant })
                    let persistedAnswer = assistant?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let uiAnswer = assistant.flatMap { msg in
                        self.messages.first(where: { $0.id == msg.id })?.displayContent
                    }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let answer = !persistedAnswer.isEmpty ? (assistant?.content ?? "") : uiAnswer
                    completion(.success(answer))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }

    private func handleTurnStateChanged(_ sessionId: String) {
        let persist = !sessionTurnHost.isRunning(sessionId)
        sessionManager.setQueuedTurnCount(
            sessionTurnHost.queueCount(sessionId: sessionId),
            for: sessionId,
            persist: persist
        )
        if sessionId == activeSessionId {
            syncQueuedTurns(sessionId: sessionId)
            updateBusyState()
        }
    }

    @MainActor
    private func reconcileInterruptedTurn(
        request: SessionTurnRequest,
        session: AgentSession,
        cancelled: Bool,
        timedOut: Bool,
        errorMessage: String?
    ) -> (session: AgentSession, persistedMessages: [ChatMessage]) {
        var working = sessionManager.getSession(request.sessionId) ?? session
        let snapshot = request.ui.captureEndSnapshot(
            session: working,
            wasCancelled: cancelled,
            timedOut: timedOut,
            errorMessage: errorMessage
        )
        let result = SessionTurnReconciler.reconcile(working, snapshot: snapshot)
        guard !result.persistedMessages.isEmpty else {
            return (working, [])
        }

        sessionManager.updateSession(request.sessionId) { $0 = result.session }
        working = result.session
        if request.sessionId == activeSessionId {
            mergeMessagesFromSession(working.messages)
        }
        return (working, result.persistedMessages)
    }

    private func handleTurnCompleted(_ event: SessionTurnCompletedEvent) {
        if let updated = sessionManager.getSession(event.sessionId) {
            if event.sessionId == activeSessionId {
                mergeMessagesFromSession(updated.messages)
            }
        }
        sessionManager.persistSession(event.sessionId)

        if event.sessionId == activeSessionId {
            planViewModel?.loadPlan()
            if let session = sessionManager.getSession(event.sessionId) {
                interactionMode = session.interactionMode
            }
        }

        if tryProcessNextQueuedTurn(event) { return }
        trySchedulePlanAutoContinue(event)
        syncQueuedTurns(sessionId: event.sessionId)
        updateBusyState()
        sessionGroups = buildSessionGroups()
    }

    private func tryProcessNextQueuedTurn(_ event: SessionTurnCompletedEvent) -> Bool {
        guard let payload = sessionTurnHost.tryDequeue(sessionId: event.sessionId) else { return false }

        syncQueuedTurns(sessionId: event.sessionId)
        payload.ui.addUserMessage(payload.userInput, imageAttachments: payload.imageAttachments)

        var session = event.session
        if let latest = sessionManager.getSession(event.sessionId) {
            session = latest
        }

        let request = SessionTurnRequest(
            sessionId: event.sessionId,
            session: session,
            userInput: payload.userInput,
            imageAttachments: payload.imageAttachments,
            ui: payload.ui,
            isAutoContinue: false
        )

        if let error = sessionTurnHost.tryStart(request) {
            sessionTurnHost.requeueFront(payload)
            syncQueuedTurns(sessionId: event.sessionId)
            if event.sessionId == activeSessionId {
                appendSystemMessage(error, sessionId: event.sessionId)
            }
        } else {
            sessionManager.setRunning(true, for: event.sessionId)
        }
        updateBusyState()
        return true
    }

    private func trySchedulePlanAutoContinue(_ event: SessionTurnCompletedEvent) {
        guard !sessionTurnHost.hasQueuedTurns(sessionId: event.sessionId) else { return }

        let planSettings = settings.plan
        let plan = sessionManager.getSession(event.sessionId)?.plan
        let completedRounds = planAutoContinueTracker.get(event.sessionId)

        guard PlanAutoContinuePolicy.shouldScheduleContinue(
            autoContinueEnabled: planSettings.autoContinueEnabled,
            completedAutoContinueRounds: completedRounds,
            maxRounds: planSettings.maxAutoContinueRounds,
            cancelled: event.cancelled,
            timedOut: event.timedOut,
            error: event.error,
            plan: plan
        ) else { return }

        let ui = uiController(for: event.sessionId)
        let input = PlanAutoContinueDefaults.continueUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.addUserMessage(input)

        var session = event.session
        if let latest = sessionManager.getSession(event.sessionId) {
            session = latest
        }

        let request = SessionTurnRequest(
            sessionId: event.sessionId,
            session: session,
            userInput: input,
            imageAttachments: [],
            ui: ui,
            isAutoContinue: true
        )

        if sessionTurnHost.tryStart(request) == nil {
            planAutoContinueTracker.increment(event.sessionId)
            sessionManager.setRunning(true, for: event.sessionId)
            updateBusyState()
        }
    }

    private func syncQueuedTurns(sessionId: String) {
        let payloads = sessionTurnHost.queuedPayloads(sessionId: sessionId)
        hasQueuedTurns = sessionId == activeSessionId && !payloads.isEmpty
        queuedTurns = payloads.map { payload in
            let preview = payload.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = preview.isEmpty ? "(附件消息)" : String(preview.prefix(120))
            let images = payload.imageAttachments.map {
                QueuedTurnImage(id: $0.id, fileName: $0.fileName, thumbnail: $0.thumbnailData)
            }
            return QueuedTurn(id: payload.queueId, previewText: text, imageItems: images)
        }
    }

    private func updateBusyState() {
        guard let id = activeSessionId else {
            isBusy = false
            return
        }
        isBusy = sessionTurnHost.isRunning(id)
    }

    func persistUiSettingsDebounced() {
        uiSettingsSaveWorkItem?.cancel()
        settings.ui.navigationSidebarWidth = Double(navigationSidebarWidth)
        settings.ui.contextSidebarWidth = Double(contextSidebarWidth)
        settings.ui.editorPaneWidth = Double(editorPaneWidth)
        settings.ui.composerHeight = Double(composerHeight)
        settings.ui.contextSidebarVisible = isContextSidebarVisible

        let work = DispatchWorkItem { [weak self] in
            self?.saveSettings()
        }
        uiSettingsSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func clearContext() {
        guard let id = activeSessionId else { return }
        guard !messages.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "清空上下文"
        alert.informativeText = """
        将清空当前对话在模型中的全部可见历史（用户、助手、工具与压缩记录）。

        会话 ID、工作区与标题会保留；磁盘上的 transcript 归档不会删除。

        同时将清除内存中的计划并删除工作区 plan.md（若存在）。

        下次发送消息时会重新构建系统提示（工作区、工具、技能等）。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if sessionTurnHost.isRunning(id) {
            sessionTurnHost.cancel(sessionId: id)
            executeCommandRegistry.killAll()
            agentRuntime.stop()
            uiController(for: id).markTurnCancelled()
            if let request = sessionTurnHost.abortTurn(sessionId: id) {
                finalizeAbortedTurn(sessionId: id, request: request)
            } else {
                sessionManager.setRunning(false, for: id)
            }
        }
        sessionTurnHost.clearQueue(sessionId: id)
        syncQueuedTurns(sessionId: id)
        composerStatusMessage = ""

        messages = []
        streamingText = ""
        pendingImageAttachments = []
        sessionManager.updateSession(id) { session in
            session.messages = []
            session.isRunning = false
        }
        sessionManager.clearConversationDisplay(sessionId: id)
        planViewModel?.clearPlan()
        deleteWorkspacePlanFileIfPresent()
        sessionGroups = buildSessionGroups()
        updateBusyState()
    }

    func removeQueuedTurn(queueId: String) {
        guard let id = activeSessionId else { return }
        guard sessionTurnHost.removeQueued(sessionId: id, queueId: queueId) else { return }
        sessionManager.setQueuedTurnCount(sessionTurnHost.queueCount(sessionId: id), for: id)
        syncQueuedTurns(sessionId: id)
    }

    private func deleteWorkspacePlanFileIfPresent() {
        guard let root = workspaceRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty else { return }
        let fileName = settings.plan.planFileName.isEmpty ? "plan.md" : settings.plan.planFileName
        let path = (root as NSString).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func toggleContextSidebar() {
        isContextSidebarVisible.toggle()
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

    /// Aligns global workspace state with the active session (WPF `ApplySessionWorkspace` / `SyncWorkspaceContext`).
    func applySessionWorkspace(for session: AgentSession) {
        if let path = session.activeWorkspace?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            if workspaceRootPath != path {
                setWorkspaceRoot(path)
            } else {
                activeWorkspace = path
                activeWorkspaceName = (path as NSString).lastPathComponent
            }
            return
        }

        if let current = workspaceRootPath,
           FileManager.default.fileExists(atPath: current) {
            return
        }

        if let configured = settings.workspaces.first(where: {
            !$0.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && FileManager.default.fileExists(atPath: $0.rootPath)
        }) {
            setWorkspaceRoot(configured.rootPath)
        }
    }

    func setWorkspaceRoot(_ path: String) {
        workspaceRootPath = path
        workspaceService.setWorkspaceRoot(path)
        workspaceService.startMonitoring()
        planWorkspaceGuard.sessionRootPath = path
        activeWorkspace = path
        activeWorkspaceName = (path as NSString).lastPathComponent
        mcpClientService.refreshConnections(settings: settings.mcpServers, workspaceRoot: path)
        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.activeWorkspace = path
                session.workspaceName = activeWorkspaceName
            }
        }
    }

    func refreshWorkspace() {
        workspaceService.scanWorkspace()
    }

    // MARK: - Plan Operations
    func updatePlanSubtask(subtaskId: String, status: PlanSubtaskStatus, outcome: String?) {
        planViewModel?.updateSubtaskStatus(subtaskId, to: status, outcome: outcome)
    }

    // MARK: - Cleanup

    /// Graceful shutdown aligned with WPF `ApplicationShutdownService`.
    func shutdownAsync() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        shutdownStatusText = "正在停止生成任务…"

        if let id = activeSessionId {
            sessionManager.updateSession(id) { session in
                session.messages = messages
                session.isRunning = false
            }
        }

        shutdownStatusText = "正在等待回合结束…"
        await sessionTurnHost.shutdownAsync(timeout: 15)

        shutdownStatusText = "正在结束命令行进程…"
        executeCommandRegistry.killAll()
        agentRuntime.stop()

        shutdownStatusText = "正在保存设置…"
        saveSettings()
        persistUiSettingsDebounced()

        shutdownStatusText = "正在关闭 MCP 连接…"
        workspaceService.stopMonitoring()
        await mcpClientService.registryProvider.shutdownAll()

        shutdownStatusText = "完成"
    }

    func prepareForShutdown() {
        let group = DispatchGroup()
        group.enter()
        Task { @MainActor in
            await shutdownAsync()
            group.leave()
        }
        group.wait()
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
