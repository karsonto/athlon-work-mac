import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MainShellStore {
    var settings: AppSettings
    var sessions: [AgentSession]
    var currentSessionId: String?
    var currentPage: AppPage = .chat
    var navVisible: Bool
    var contextVisible: Bool
    var themeManager: AppThemeManager
    var messageCount: Int = 0
    var composerText: String = ""
    var isRunning: Bool = false
    var contextTab: ContextSidebarTab = .files
    var harnessMode: ComposerHarnessMode = .agent
    var statusMessage: String?
    var pendingApprovals: [String] = []
    var fileSuggestions: [ComposerFileSuggestion] = []
    var apiKeyDraft: String = ""

    var skillInfos: [AvailableSkillInfo] = []
    var mcpStatuses: [McpServerStatus] = []

    /// Shared chat bridge injected from ChatPageView.
    var chatBridge: ChatWebViewBridge? {
        didSet {
            sessionUICache.sharedBridge = chatBridge
            if let id = currentSessionId {
                sessionUICache.setDisplayed(sessionId: id)
            }
        }
    }

    let turnHost = SessionTurnHost()
    let sessionUICache = SessionUICache()
    let queuedTurnPresenter: QueuedTurnPresenter
    let composerCoordinator = ComposerCoordinator()
    let workspaceTreeStore = WorkspaceTreeStore()
    let fileEditorStore = FileEditorStore()
    let composerAttachments = ComposerAttachmentStore()

    private let storage: FileStorageService
    private let keychain = KeychainCredentialStore()
    private(set) var agentBundle: AgentServices.Bundle?
    /// Bumped to cancel stale `hydrateCurrentSession` dispatches (e.g. onAppear race during streaming).
    private var hydrateGeneration = 0

    var agentRuntime: AgentRuntime? { agentBundle?.runtime }

    var currentSession: AgentSession? {
        guard let currentSessionId else { return nil }
        return sessions.first(where: { $0.id == currentSessionId })
    }

    var language: String { settings.ui.language }

    var activeWorkspaceRoot: String? {
        if let sessionRoot = currentSession?.activeWorkspace, !sessionRoot.isEmpty {
            return sessionRoot
        }
        if let id = currentSession?.activeWorkspaceId,
           let ws = settings.workspaces.first(where: { $0.id == id }) {
            return ws.rootPath
        }
        return settings.workspaces.first?.rootPath
    }

    var editorOpen: Bool { fileEditorStore.isOpen }

    var queuedTurnsForCurrentSession: [QueuedTurnItem] {
        guard let currentSessionId else { return [] }
        return queuedTurnPresenter.items(for: currentSessionId)
    }

    init(storage: FileStorageService = FileStorageService()) {
        self.storage = storage
        self.queuedTurnPresenter = QueuedTurnPresenter(turnHost: turnHost)
        try? storage.ensureDirectories()

        let loadedSettings = (try? storage.loadSettings()) ?? AppSettings()
        self.settings = loadedSettings
        self.navVisible = loadedSettings.ui.navigationSidebarVisible
        self.contextVisible = loadedSettings.ui.contextSidebarVisible
        self.themeManager = AppThemeManager(kind: ThemeKind.parse(loadedSettings.ui.theme))

        let index = (try? storage.listSessions()) ?? []
        if index.isEmpty {
            let session = AgentSession.create()
            try? storage.saveSession(session)
            self.sessions = [session]
            self.currentSessionId = session.id
            self.messageCount = session.messages?.count ?? 0
        } else {
            var loaded: [AgentSession] = []
            for entry in index {
                if let session = try? storage.loadSession(id: entry.id) {
                    loaded.append(session)
                }
            }
            if loaded.isEmpty {
                let session = AgentSession.create()
                try? storage.saveSession(session)
                loaded = [session]
            }
            self.sessions = loaded
            self.currentSessionId = loaded.first?.id
            self.messageCount = loaded.first?.messages?.count ?? 0
        }

        apiKeyDraft = (try? keychain.loadModelAPIKey()) ?? ""
        bootstrapAgentBundle()
        refreshCatalogs()
        refreshWorkspaceTree()
        Task { await connectMcp() }
    }

    // MARK: - Navigation

    func selectPage(_ page: AppPage) {
        currentPage = page
        if page == .settings {
            apiKeyDraft = (try? keychain.loadModelAPIKey()) ?? ""
        }
    }

    func selectSession(_ id: String) {
        currentSessionId = id
        currentPage = .chat
        sessionUICache.setDisplayed(sessionId: id)
        composerText = ""
        fileSuggestions = []
        refreshRunningState()
        hydrateCurrentSession()
        refreshPendingApprovals()
        refreshWorkspaceTree()
    }

    func createSession() {
        var session = AgentSession.create(title: L10n.t("chat.newSession", language: language))
        if let root = activeWorkspaceRoot {
            session.activeWorkspace = root
            if let ws = settings.workspaces.first(where: { $0.rootPath == root }) {
                session.activeWorkspaceId = ws.id
            }
        }
        try? storage.saveSession(session)
        sessions.insert(session, at: 0)
        selectSession(session.id)
    }

    func deleteSession(_ id: String) {
        turnHost.removeSession(id)
        queuedTurnPresenter.removeSession(id)
        sessionUICache.remove(sessionId: id)
        try? storage.deleteSession(id: id)
        sessions.removeAll { $0.id == id }

        if currentSessionId == id {
            if let next = sessions.first {
                selectSession(next.id)
            } else {
                createSession()
            }
        }
        reloadSessionsList()
    }

    func reloadSessionsList() {
        let index = (try? storage.listSessions()) ?? []
        var loaded: [AgentSession] = []
        for entry in index {
            if let session = try? storage.loadSession(id: entry.id) {
                loaded.append(session)
            }
        }
        if loaded.isEmpty, let current = currentSession {
            loaded = [current]
        }
        sessions = loaded
        if let id = currentSessionId,
           let refreshed = loaded.first(where: { $0.id == id }) {
            let visible = (refreshed.messages ?? []).filter { $0.role == .user || $0.role == .assistant }.count
            messageCount = max(messageCount, visible)
        }
    }

    // MARK: - Theme / chrome

    func toggleTheme() {
        let next: ThemeKind = themeManager.kind == .dark ? .light : .dark
        var ui: UiSettings? = settings.ui
        themeManager.setTheme(next, uiSettings: &ui)
        if let ui { settings.ui = ui }
        persistSettingsPublic()
    }

    func toggleNavVisible() {
        navVisible.toggle()
        settings.ui.navigationSidebarVisible = navVisible
        persistSettingsPublic()
    }

    func toggleContextVisible() {
        contextVisible.toggle()
        settings.ui.contextSidebarVisible = contextVisible
        persistSettingsPublic()
    }

    // MARK: - Composer / turns

    func sendComposerMessage() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = composerAttachments.toImageAttachments()
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        ensureCurrentSession()
        guard let sessionId = currentSessionId else { return }

        switch composerCoordinator.processBeforeSend(trimmed.isEmpty ? "/help" : trimmed) {
        case let .handled(status):
            composerText = ""
            fileSuggestions = []
            if status == "cleared" {
                clearCurrentTimelineDisplay()
                statusMessage = "已清空时间线显示"
            } else {
                injectLocalAssistantHelp(status)
                statusMessage = nil
            }
            return
        case let .send(text):
            composerText = ""
            fileSuggestions = []
            let modePrefix: String
            switch harnessMode {
            case .ask: modePrefix = "[ask] "
            case .plan: modePrefix = "[plan] "
            case .coding: modePrefix = "[coding] "
            case .agent: modePrefix = ""
            }
            let payloadText = modePrefix + (text.isEmpty && !images.isEmpty ? "(image)" : text)
            let pendingImages = images
            composerAttachments.clear()
            enqueueOrStartTurn(sessionId: sessionId, text: payloadText, images: pendingImages)
        }
    }

    func stopRunning() {
        guard let sessionId = currentSessionId else {
            isRunning = false
            return
        }
        turnHost.cancel(sessionId)
        refreshRunningState()
    }

    func handleToolApproval(toolCallId: String, approved: Bool) {
        if let sessionId = currentSessionId,
           let ui = sessionUICache.tryGet(sessionId: sessionId),
           ui.resolveToolApproval(toolCallId: toolCallId, approved: approved) {
            refreshPendingApprovals()
            return
        }
        for id in turnHost.runningSessionIds {
            if sessionUICache.tryGet(sessionId: id)?.resolveToolApproval(toolCallId: toolCallId, approved: approved) == true {
                refreshPendingApprovals()
                return
            }
        }
        NSLog("[MainShellStore] no pending approval for %@", toolCallId)
    }

    func loadOlderMessages() {
        NSLog("[MainShellStore] loadOlder requested")
    }

    func updateFileSuggestions() {
        fileSuggestions = composerCoordinator.fileSuggestions(
            for: composerText,
            workspaceRoot: activeWorkspaceRoot,
            ignorePatterns: combinedIgnorePatterns()
        )
    }

    func acceptFileSuggestion(_ suggestion: ComposerFileSuggestion) {
        composerText = composerCoordinator.acceptSuggestion(text: composerText, suggestion: suggestion)
        fileSuggestions = []
    }

    // MARK: - Hydration

    func hydrateCurrentSession(force: Bool = false) {
        guard let sessionId = currentSessionId else {
            messageCount = 0
            return
        }
        if !force, turnHost.isRunning(sessionId) {
            return
        }

        hydrateGeneration += 1
        let generation = hydrateGeneration

        let ui = sessionUICache.getOrCreate(sessionId: sessionId)
        ui.attach(bridge: chatBridge)
        ui.setDisplayed(true)

        let messages = loadMessagesForSession(sessionId)
        messageCount = max(
            messages.filter { $0.role == .user || $0.role == .assistant }.count,
            messages.isEmpty ? 0 : 1
        )
        ui.messageCount = messageCount

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard generation == self.hydrateGeneration else { return }
            guard self.currentSessionId == sessionId else { return }
            if !force, self.turnHost.isRunning(sessionId) { return }

            let latest = self.loadMessagesForSession(sessionId)
            ui.hydrate(messages: latest, showToolCalls: self.settings.ui.showToolCalls)
            self.messageCount = ui.messageCount
        }
    }

    // MARK: - Workspace / editor

    func pickAndAddWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("nav.addWorkspace", language: language)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addWorkspace(path: url.path)
        selectWorkspace(path: url.path)
    }

    func addWorkspace(path: String) {
        let standardized = (path as NSString).standardizingPath
        guard !standardized.isEmpty else { return }
        if settings.workspaces.contains(where: { $0.rootPath == standardized }) {
            selectWorkspace(path: standardized)
            return
        }
        let name = (standardized as NSString).lastPathComponent
        let ws = WorkspaceSettings(name: name, rootPath: standardized)
        settings.workspaces.append(ws)
        persistSettingsPublic()
        selectWorkspace(path: standardized)
    }

    func selectWorkspace(path: String) {
        let standardized = (path as NSString).standardizingPath
        guard var session = currentSession else {
            refreshWorkspaceTree()
            return
        }
        session.activeWorkspace = standardized
        if let ws = settings.workspaces.first(where: { $0.rootPath == standardized }) {
            session.activeWorkspaceId = ws.id
        }
        session.updatedAt = Date()
        try? storage.saveSession(session)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        refreshWorkspaceTree()
    }

    func openFile(path: String) {
        fileEditorStore.open(path: path, workspaceRoot: activeWorkspaceRoot)
    }

    func closeEditor() {
        fileEditorStore.close()
    }

    func saveFile() {
        _ = fileEditorStore.save()
    }

    func refreshWorkspaceTree() {
        workspaceTreeStore.load(
            rootPath: activeWorkspaceRoot,
            ignorePatterns: combinedIgnorePatterns()
        )
    }

    // MARK: - Settings

    func saveSettingsFromForm() {
        var ui: UiSettings? = settings.ui
        themeManager.setTheme(ThemeKind.parse(settings.ui.theme), uiSettings: &ui)
        if let ui { settings.ui = ui }
        persistSettingsPublic()
        let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedKey.isEmpty {
                try keychain.deleteModelAPIKey()
            } else {
                try keychain.saveModelAPIKey(trimmedKey)
            }
            statusMessage = "设置已保存"
        } catch {
            statusMessage = "设置已保存，但 API Key 写入失败: \(error.localizedDescription)"
        }
        bootstrapAgentBundle()
        refreshCatalogs()
        refreshWorkspaceTree()
        Task { await connectMcp() }
    }

    func persistSettingsPublic() {
        try? storage.saveSettings(settings)
    }

    func refreshCatalogs() {
        let catalog = agentBundle?.skillCatalog ?? SkillCatalog()
        skillInfos = catalog.listAvailableSkills(settings: settings)
        mcpStatuses = agentBundle?.mcpRegistry.serverStatuses ?? []
    }

    func connectMcp() async {
        guard let bundle = agentBundle else { return }
        await bundle.mcpRegistry.connect(settings: settings)
        mcpStatuses = bundle.mcpRegistry.serverStatuses
        refreshCatalogs()
    }

    // MARK: - Private turn helpers

    private func bootstrapAgentBundle() {
        if let bundle = try? AgentServices.make(paths: storage.pathsCompatible) {
            agentBundle = bundle
        } else {
            statusMessage = "Agent 服务初始化失败"
        }
    }

    private func enqueueOrStartTurn(sessionId: String, text: String, images: [ImageAttachment] = []) {
        let ui = sessionUICache.getOrCreate(sessionId: sessionId)
        ui.attach(bridge: chatBridge)
        ui.setDisplayed(currentSessionId == sessionId)

        if turnHost.isRunning(sessionId) {
            _ = queuedTurnPresenter.enqueue(sessionId: sessionId, text: text, images: images)
            statusMessage = "已加入队列（\(queuedTurnPresenter.count(for: sessionId))）"
            return
        }

        startTurn(sessionId: sessionId, text: text, images: images, ui: ui)
    }

    private func startTurn(sessionId: String, text: String, images: [ImageAttachment] = [], ui: SessionTurnUIController) {
        guard agentRuntime != nil else {
            statusMessage = "Agent Runtime 不可用"
            return
        }

        if currentSessionId == sessionId {
            messageCount = max(messageCount, 1)
        }
        ui.attach(bridge: chatBridge)
        ui.setDisplayed(currentSessionId == sessionId)
        ui.injectUserMessage(content: text, images: images)

        let apiKey = (try? keychain.loadModelAPIKey()) ?? ""
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = "请先在设置中配置 API Key 和模型 Endpoint"
            injectLocalAssistantHelp("尚未配置 API Key。请打开 **设置**，填写 OpenAI 兼容的 Endpoint、Model 和 API Key 后重试。")
            return
        }

        guard let runtime = agentRuntime else { return }

        ui.onPendingApprovalsChanged = { [weak self] in
            self?.refreshPendingApprovals()
        }

        let workspaceRoot = activeWorkspaceRoot
        hydrateGeneration += 1

        let error = turnHost.tryStart(sessionId: sessionId) { [weak self] in
            guard let self else { return }
            await self.executeTurn(
                sessionId: sessionId,
                text: text,
                images: images,
                workspaceRoot: workspaceRoot,
                ui: ui,
                runtime: runtime
            )
        } onFinished: { [weak self] in
            guard let self else { return }
            self.refreshRunningState()
            self.refreshPendingApprovals()
            self.processNextQueuedTurn(sessionId: sessionId)
        }
        if let error {
            statusMessage = error
            return
        }
        refreshRunningState()
        refreshPendingApprovals()
    }

    private func executeTurn(
        sessionId: String,
        text: String,
        images: [ImageAttachment] = [],
        workspaceRoot: String?,
        ui: SessionTurnUIController,
        runtime: AgentRuntime
    ) async {
        let callbacks = AgentTurnCallbacks(
            onStreamEvent: { event in
                Task { @MainActor in
                    ui.handleStreamEvent(event)
                }
            },
            onToolApprovalRequested: { call in
                await ui.requestToolApproval(call)
            }
        )

        do {
            let session = try await runtime.runTurn(
                sessionId: sessionId,
                userText: text,
                workspaceRoot: workspaceRoot,
                imageAttachments: images,
                callbacks: callbacks
            )
            await MainActor.run {
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[idx] = session
                }
                if self.currentSessionId == sessionId {
                    if let msgs = session.messages {
                        let visible = msgs.filter { $0.role == .user || $0.role == .assistant }.count
                        ui.messageCount = max(ui.messageCount, visible)
                        self.messageCount = max(self.messageCount, visible)
                    } else {
                        self.messageCount = max(self.messageCount, ui.messageCount)
                    }
                }
                self.reloadSessionsList()
                self.statusMessage = nil
            }
        } catch is CancellationError {
            await MainActor.run {
                self.statusMessage = "已停止"
            }
        } catch {
            let endpoint = settings.model.endpoint
            let message = ModelClientErrorFormatter.userFacingMessage(for: error, endpoint: endpoint)
            await MainActor.run {
                self.statusMessage = message
                self.injectLocalAssistantHelp("**请求失败**\n\n\(message)")
                NSLog("[MainShellStore] turn failed: %@", message)
            }
        }

    }

    private func processNextQueuedTurn(sessionId: String) {
        guard let payload = queuedTurnPresenter.dequeueNext(sessionId: sessionId) else { return }
        let ui = sessionUICache.getOrCreate(sessionId: sessionId)
        startTurn(sessionId: sessionId, text: payload.text, images: payload.images, ui: ui)
    }

    private func refreshRunningState() {
        if let id = currentSessionId {
            isRunning = turnHost.isRunning(id)
        } else {
            isRunning = false
        }
    }

    private func refreshPendingApprovals() {
        if let id = currentSessionId, let ui = sessionUICache.tryGet(sessionId: id) {
            pendingApprovals = ui.pendingApprovalIds
        } else {
            pendingApprovals = []
        }
    }

    private func clearCurrentTimelineDisplay() {
        guard let sessionId = currentSessionId else { return }
        let ui = sessionUICache.getOrCreate(sessionId: sessionId)
        ui.resetTimeline()
        messageCount = 0
    }

    private func injectLocalAssistantHelp(_ text: String) {
        guard let sessionId = currentSessionId else { return }
        messageCount = max(messageCount, 1)
        let ui = sessionUICache.getOrCreate(sessionId: sessionId)
        ui.attach(bridge: chatBridge)
        ui.setDisplayed(true)
        let messageId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let json = ChatEventSerializer.serializeStaticAssistantHTML(messageId: messageId, markdown: text)
        chatBridge?.dispatchJSON(json)
        ui.messageCount += 1
        messageCount = ui.messageCount
    }

    private func ensureCurrentSession() {
        if currentSessionId == nil {
            createSession()
        }
    }

    private func loadMessagesForSession(_ sessionId: String) -> [ChatMessage] {
        if let loaded = try? storage.loadConversationMessages(sessionId: sessionId) {
            return loaded
        }
        if currentSessionId == sessionId {
            return currentSession?.messages ?? []
        }
        return []
    }

    private func combinedIgnorePatterns() -> [String] {
        var patterns = settings.workspaceIgnore.directoryNames
        if let root = activeWorkspaceRoot,
           let ws = settings.workspaces.first(where: { $0.rootPath == root }) {
            patterns.append(contentsOf: ws.ignorePatterns)
        }
        return patterns
    }
}

enum ContextSidebarTab: String, CaseIterable, Identifiable, Hashable {
    case files
    case skills

    var id: String { rawValue }

    func title(language: String) -> String {
        switch self {
        case .files: return L10n.t("context.files", language: language)
        case .skills: return L10n.t("context.skills", language: language)
        }
    }
}

private extension FileStorageService {
    /// Expose path provider for AgentServices bootstrap without widening public API much.
    var pathsCompatible: AppPathProviding {
        AppPathProvider()
    }
}
