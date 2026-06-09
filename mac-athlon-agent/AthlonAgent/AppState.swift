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

    // MARK: - Services
    private(set) var themeManager: ThemeManager!
    private(set) var sessionManager: SessionManager!
    private(set) var agentRuntime: AgentRuntimeService!
    private(set) var mcpClientService: McpClientService!
    private(set) var skillService: SkillService!
    private(set) var workspaceService: WorkspaceService!
    private(set) var imageAttachmentService: ImageAttachmentService!
    private(set) var sessionTurnHost: SessionTurnHost!

    // MARK: - File System Watcher
    private var workspaceWatcher: WorkspaceFileWatcherService?
    private let executeCommandRegistry = ExecuteCommandProcessRegistry()

    // MARK: - Memory System
    private(set) var longTermMemory: ILongTermMemory!
    private(set) var memoryFlushService: MemoryFlushService!
    private(set) var memoryConsolidationService: MemoryConsolidationService!
    private(set) var postTurnMemoryProcessor: IPostTurnMemoryProcessor!

    // MARK: - Composer Commands
    private(set) var composerCommandRegistry: IComposerCommandRegistry!
    private(set) var composerCommandExecutor: ComposerCommandExecutor!
    private var uiControllers: [String: SessionTurnUiController] = [:]
    private let sessionUiCache = SessionUiCache()
    private var uiSettingsSaveWorkItem: DispatchWorkItem?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Logs
    var logsPath: String {
        AppPathProvider.shared.logsPath
    }

    // MARK: - ViewModels
    /// Lazily created FileEditorViewModel. Created on first access.
    lazy var fileEditorViewModel: FileEditorViewModel = {
        FileEditorViewModel(appState: self)
    }()

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
        mcpClientService = McpClientService()
        mcpClientService.syncFromSettings(settings.mcpServers)
        skillService = SkillService()
        skillService.reload(savedSettings: settings.skills)
        workspaceService = WorkspaceService(ignorePatterns: settings.workspaceIgnore.directoryNames)
        imageAttachmentService = ImageAttachmentService()

        // Initialize workspace file watcher — notifies FileEditorViewModel of external changes
        workspaceWatcher = WorkspaceFileWatcherService { [weak self] changedPath in
            guard let self else { return }
            self.fileEditorViewModel.handleExternalChange(changedPath)
        }
        configureMemorySystem()

        agentRuntime = AgentRuntimeService(
            settings: settings,
            workspaceService: workspaceService,
            skillService: skillService,
            sessionManager: sessionManager,
            mcpClientService: mcpClientService,
            executeCommandRegistry: executeCommandRegistry,
            longTermMemory: longTermMemory,
            postTurnMemoryProcessor: postTurnMemoryProcessor
        )

        // Initialize composer commands
        composerCommandRegistry = ComposerCommandRegistry()
        let compactionStorage = FileStorageService()
        let compactionModelClient = OpenAiChatModelClient(settings: settings)
        let compactionCompactor = ConversationCompactor(
            settings: settings.contextCompaction,
            modelClient: compactionModelClient,
            storage: compactionStorage
        )
        let compactionPipeline = PreCompletionPipeline(
            conversationCompactor: compactionCompactor,
            settings: settings.contextCompaction
        )
        var compactionContributors: [IPreReasoningPromptContributor] = []
        if let longTermMemory {
            compactionContributors.append(
                MemoryPromptContributor(longTermMemory: longTermMemory, settings: settings.memory)
            )
        }
        let compactionOrchestrator = SystemPromptOrchestrator(
            settings: settings,
            sections: EnvironmentPromptSections.makeAll(
                settings: settings,
                skillsProvider: { [weak skillService, weak self] in
                    guard let skillService, let self else { return [] }
                    return skillService.availableSkillInfos(settings: self.settings)
                }
            ),
            preReasoningContributors: compactionContributors
        )
        let compactionToolRouter = BuiltInTools.makeAll(
            workspaceService: workspaceService,
            settings: settings,
            skillService: skillService,
            sessionManager: sessionManager,
            mcpRegistry: mcpClientService.registryProvider,
            sessionWorkspacePath: workspaceRootPath,
            executeCommandRegistry: executeCommandRegistry,
            longTermMemory: longTermMemory
        ).router
        let sessionCompactionService = SessionCompactionService(
            preCompletionPipeline: compactionPipeline,
            toolRouter: compactionToolRouter,
            systemPromptOrchestrator: compactionOrchestrator,
            tokenEstimatorCalibrator: TokenEstimatorCalibrator(settings: settings),
            storage: compactionStorage,
            settings: settings,
            skillsProvider: { [weak skillService, weak self] in
                guard let skillService, let self else { return [] }
                return skillService.availableSkillInfos(settings: self.settings)
            }
        )
        composerCommandRegistry.register(CompactComposerCommand(compactionService: sessionCompactionService))
        composerCommandRegistry.register(HelpComposerCommand(registry: composerCommandRegistry))
        composerCommandExecutor = ComposerCommandExecutor(registry: composerCommandRegistry)

        // Optional startup consolidation (one-shot, not periodic)
        if settings.memory.enabled {
            Task { [weak self] in
                await self?.memoryConsolidationService?.consolidate()
            }
        }

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

        if let id = activeSessionId,
           let session = sessionManager.getSession(id) {
            applySessionWorkspace(for: session)
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
            // Save API Key to macOS Keychain for secure storage
            if !settings.model.apiKey.isEmpty {
                try? CredentialStore().save(settings.model.apiKey, for: CredentialStore.apiKeyAccount)
            }
            mcpClientService.syncFromSettings(settings.mcpServers)
            mcpClientService.refreshConnections(settings: settings.mcpServers, workspaceRoot: workspaceRootPath)
            skillService.reload(savedSettings: settings.skills)
            applyUiSettings()
        } catch {
            print("Failed to save settings: \(error)")
        }
        configureMemorySystem()
        agentRuntime?.stop()
        agentRuntime = AgentRuntimeService(
            settings: settings,
            workspaceService: workspaceService,
            skillService: skillService,
            sessionManager: sessionManager,
            mcpClientService: mcpClientService,
            executeCommandRegistry: executeCommandRegistry,
            longTermMemory: longTermMemory,
            postTurnMemoryProcessor: postTurnMemoryProcessor
        )
    }

    private func configureMemorySystem() {
        do {
            let memoryDir = (AppPathProvider.shared.rootPath as NSString)
                .appendingPathComponent(settings.memory.memoryDirName)
            let fileLongTermMemory = try FileLongTermMemory(memoryDir: memoryDir, settings: settings.memory)
            longTermMemory = fileLongTermMemory
            let modelClient = OpenAiChatModelClient(settings: settings)
            memoryFlushService = MemoryFlushService(
                longTermMemory: longTermMemory,
                modelClient: modelClient,
                settings: settings.memory
            )
            memoryConsolidationService = MemoryConsolidationService(
                longTermMemory: longTermMemory,
                modelClient: modelClient,
                settings: settings.memory
            )
            postTurnMemoryProcessor = PostTurnMemoryProcessor(
                flushService: memoryFlushService,
                consolidationService: memoryConsolidationService,
                settings: settings.memory
            )
        } catch {
            AgentFileLogger.log("Failed to initialize memory system: \(error.localizedDescription)", category: "Memory")
        }
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
            messages = ChatTimelineOrder.orderForDisplay(session.messages)
            applySessionWorkspace(for: session)
        }
        sessionGroups = buildSessionGroups()
        currentPage = .chat
    }

    func sendMessage(_ text: String) {
        guard let id = activeSessionId, let session = sessionManager.getSession(id) else { return }
        currentPage = .chat

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

        Task { @MainActor in
            let commandContext = ComposerCommandContext(
                userInput: text,
                session: session,
                workspaceRoot: self.workspaceRootPath
            )
            let cmdResult = await self.composerCommandExecutor.tryExecute(input: text, context: commandContext)
            if case .handled(let response) = cmdResult.outcome {
                self.appendSystemMessage(response, sessionId: id)
                self.sessionManager.setRunning(false, for: id)
                self.updateBusyState()
                return
            }
            self.startSessionTurn(
                sessionId: id,
                session: session,
                expanded: expanded,
                imageAttachments: images,
                ui: ui
            )
        }
    }

    private func startSessionTurn(
        sessionId: String,
        session: AgentSession,
        expanded: String,
        imageAttachments: [ImageAttachment],
        ui: SessionTurnUiController
    ) {
        ui.addUserMessage(expanded, imageAttachments: imageAttachments)
        sessionManager.updateSession(sessionId) { stored in
            stored.isRunning = true
            if let workspaceRootPath {
                stored.activeWorkspace = workspaceRootPath
                stored.workspaceName = activeWorkspaceName
            }
        }

        guard let session = sessionManager.getSession(sessionId) else { return }

        let request = SessionTurnRequest(
            sessionId: sessionId,
            session: session,
            userInput: expanded,
            imageAttachments: imageAttachments,
            ui: ui,
            isAutoContinue: false
        )

        if let error = sessionTurnHost.tryStart(request) {
            appendSystemMessage(error, sessionId: sessionId)
            sessionManager.setRunning(false, for: sessionId)
        }
        updateBusyState()
    }

    /// Public cancellation entry point expected by ComposerView stop button.
    /// Delegates to stopAgent() which performs full turn cancellation.
    func cancelActiveSession() {
        stopAgent()
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
            var updated = messages
            updated[index] = mergeToolMessage(existing: updated[index], incoming: message)
            messages = updated
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
            var updated = messages
            if let index = updated.firstIndex(where: { $0.id == message.id }) {
                updated[index] = message
            } else {
                updated.append(message)
            }
            messages = updated
        }
        sessionManager.upsertMessage(message, to: sessionId, persist: shouldPersist)
    }

    func removeMessage(sessionId: String, messageId: String) {
        if sessionId == activeSessionId {
            messages = messages.filter { $0.id != messageId }
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

        var ordered = ChatTimelineOrder.orderForDisplay(others + Array(toolByCallId.values))
        for index in ordered.indices {
            ordered[index].isStreaming = false
            ordered[index].isReasoningStreaming = false
        }
        messages = ordered
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

    /// Reassigns the active message row so `@Published` notifies SwiftUI (in-place struct mutation does not).
    private func mutateActiveMessage(
        messageId: String,
        sessionId: String,
        _ mutate: (inout ChatMessage) -> Void
    ) {
        guard sessionId == activeSessionId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var updated = messages
        mutate(&updated[index])
        messages = updated
    }

    /// Ends streaming on the pre-tool assistant bubble but keeps visible `content` (do not wipe the answer text).
    func sealAssistantBeforeTools(sessionId: String, messageId: String, reasoningContent: String) {
        mutateActiveMessage(messageId: messageId, sessionId: sessionId) { message in
            if !reasoningContent.isEmpty {
                message.reasoningContent = reasoningContent
            }
            message.toolCalls = nil
            message.isStreaming = false
            message.isReasoningStreaming = false
        }
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

    func isSessionTurnActive(_ sessionId: String) -> Bool {
        sessionTurnHost.isRunning(sessionId)
    }

    func updateMessageContent(
        sessionId: String,
        messageId: String,
        content: String,
        isStreaming: Bool = true
    ) {
        let effectiveStreaming = isStreaming && sessionTurnHost.isRunning(sessionId)
        mutateActiveMessage(messageId: messageId, sessionId: sessionId) { message in
            message.content = content
            message.isStreaming = effectiveStreaming
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.isReasoningStreaming = false
            }
            if !effectiveStreaming {
                message = message.withPromotedAnswer()
                message.isReasoningStreaming = false
            }
            if !content.isEmpty {
                AgentFileLogger.logUIAssistant(
                    sessionId: sessionId,
                    messageId: messageId,
                    contentLength: content.count,
                    reasoningLength: message.reasoningContent.count,
                    isStreaming: effectiveStreaming,
                    source: "updateMessageContent"
                )
            }
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            session.messages[index].content = content
            session.messages[index].isStreaming = effectiveStreaming
            if !effectiveStreaming {
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
        let effectiveReasoningStreaming = isReasoningStreaming && sessionTurnHost.isRunning(sessionId)
        mutateActiveMessage(messageId: messageId, sessionId: sessionId) { message in
            applyReasoningChannel(to: &message, incoming: content, isReasoningStreaming: effectiveReasoningStreaming)
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            guard let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            applyReasoningChannel(to: &session.messages[index], incoming: content, isReasoningStreaming: effectiveReasoningStreaming)
        }
    }

    /// Clears live streaming flags after a turn ends (prevents stale cursors / stop affordance).
    func clearStreamingFlags(sessionId: String) {
        let apply: (inout ChatMessage) -> Void = { message in
            if message.isStreaming || message.isReasoningStreaming {
                message.isStreaming = false
                message.isReasoningStreaming = false
                message = message.withPromotedAnswer()
            }
        }
        if sessionId == activeSessionId {
            var updated = messages
            for index in updated.indices {
                apply(&updated[index])
            }
            messages = updated
        }
        sessionManager.updateSessionInMemory(sessionId) { session in
            for index in session.messages.indices {
                apply(&session.messages[index])
            }
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
            var updated = messages
            updated[index] = merged
            messages = updated
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

        if session.messages.last(where: { $0.role == .user }) == nil {
            let userMessage = ChatMessage(
                id: UUID().uuidString,
                role: .user,
                content: request.userInput,
                createdAt: Date(),
                imageAttachments: request.imageAttachments.isEmpty ? nil : request.imageAttachments
            )
            sessionManager.upsertMessage(userMessage, to: sessionId, persist: false)
            if sessionId == activeSessionId, !messages.contains(where: { $0.id == userMessage.id }) {
                messages = messages + [userMessage]
            }
            if let latest = sessionManager.getSession(sessionId) {
                session = latest
            }
        }

        let assistantId = request.ui.reserveAssistantMessageId()

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
                if !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onReasoning(reasoning)
                }
            },
            onStreamEvent: { event in
                request.ui.processStreamEvent(event)
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

        if tryProcessNextQueuedTurn(event) { return }
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
            session.plan = nil
        }
        sessionManager.clearConversationDisplay(sessionId: id)
        sessionGroups = buildSessionGroups()
        updateBusyState()
    }

    func removeQueuedTurn(queueId: String) {
        guard let id = activeSessionId else { return }
        guard sessionTurnHost.removeQueued(sessionId: id, queueId: queueId) else { return }
        sessionManager.setQueuedTurnCount(sessionTurnHost.queueCount(sessionId: id), for: id)
        syncQueuedTurns(sessionId: id)
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
        activeWorkspace = path
        activeWorkspaceName = (path as NSString).lastPathComponent
        mcpClientService.refreshConnections(settings: settings.mcpServers, workspaceRoot: path)

        // Start/restart file system watcher for the new workspace root
        workspaceWatcher?.watchDirectory(path: path)
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

        shutdownStatusText = "正在关闭文件监听…"
        workspaceWatcher?.stop()

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
