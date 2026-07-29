import AppKit
import SwiftUI

struct ChatPageView: View {
    @Environment(MainShellStore.self) private var store
    @State private var chatBridge = ChatWebViewBridge()

    private var isEmpty: Bool { store.messageCount == 0 }
    private var chrome: UiChromeColors { store.themeManager.chrome }

    private var sessionTitle: String {
        store.currentSession?.title ?? L10n.t("chat.newSession", language: store.language)
    }

    private var workspaceLabel: String {
        if let root = store.activeWorkspaceRoot, !root.isEmpty {
            if let ws = store.settings.workspaces.first(where: { $0.rootPath == root }), !ws.name.isEmpty {
                return ws.name
            }
            return (root as NSString).lastPathComponent
        }
        return L10n.t("chat.selectWorkspace", language: store.language)
    }

    var body: some View {
        HSplitView {
            if store.editorOpen {
                FileEditorView(
                    editor: store.fileEditorStore,
                    onClose: { store.closeEditor() },
                    onSave: { store.saveFile() }
                )
                .frame(
                    minWidth: UiLayoutConstraints.editorPaneMinWidth,
                    idealWidth: CGFloat(store.settings.ui.editorPaneWidth),
                    maxWidth: UiLayoutConstraints.editorPaneMaxWidth
                )
            }

            chatColumn
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(chrome.chatBackgroundTop.color)
        .onAppear {
            chatBridge.themeManager = store.themeManager
            store.chatBridge = chatBridge
            if let sessionId = store.currentSessionId, !store.turnHost.isRunning(sessionId) {
                store.hydrateCurrentSession()
            }
        }
        .onChange(of: store.messageCount) { _, count in
            if count > 0 {
                store.chatBridge = chatBridge
            }
        }
        .onChange(of: store.themeManager.kind) { _, _ in
            chatBridge.themeManager = store.themeManager
            chatBridge.applyThemeUpdate()
        }
        .onChange(of: store.currentSessionId) { _, _ in
            store.chatBridge = chatBridge
            store.hydrateCurrentSession()
        }
        .onChange(of: store.composerText) { _, _ in
            store.updateFileSuggestions()
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            if !isEmpty {
                topBar
            }

            ZStack {
                // Keep WebView mounted even in empty state so send/stream events are not dropped.
                ChatWebView(
                    bridge: chatBridge,
                    themeManager: store.themeManager,
                    onToolApproval: { toolCallId, approved in
                        store.handleToolApproval(toolCallId: toolCallId, approved: approved)
                    },
                    onLoadOlder: {
                        store.loadOlderMessages()
                    },
                    onOpenURL: { url in
                        NSWorkspace.shared.open(url)
                    }
                )
                .id("athlon-chat-webview")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isEmpty ? 0.001 : 1)
                .allowsHitTesting(!isEmpty)

                if isEmpty {
                    emptyStateBody
                }
            }

            if !isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    composerBlock(
                        height: CGFloat(store.settings.ui.composerHeight),
                        maxContentWidth: AppLayoutMetrics.composerMaxContentWidth,
                        style: .docked
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(chrome.chatBackgroundTop.color)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if !isEmpty {
                Text(sessionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chrome.text.color)
                    .lineLimit(1)
            }

            if !store.queuedTurnsForCurrentSession.isEmpty {
                Text("\(L10n.t("chat.queue", language: store.language)) \(store.queuedTurnsForCurrentSession.count)")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(chrome.accentSubtle.color))
                    .foregroundStyle(chrome.accent.color)
            }

            Spacer(minLength: 8)

            if let status = store.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(chrome.subtleText.color)
                    .lineLimit(1)
            }

            if store.editorOpen == false, store.activeWorkspaceRoot != nil {
                Button {
                    store.toggleContextVisible()
                } label: {
                    Label("IDE", systemImage: "arrow.up.forward")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(chrome.subtleText.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().strokeBorder(chrome.border.color.opacity(0.8), lineWidth: 1)
                )
                .help(L10n.t("chat.openIde", language: store.language))
            }

            Menu {
                Button(L10n.t("chat.toggleTheme", language: store.language)) {
                    store.toggleTheme()
                }
                Button(L10n.t("chat.replayFixture", language: store.language)) {
                    replayFixture()
                }
                Divider()
                Button(L10n.t("nav.settings", language: store.language)) {
                    store.selectPage(.settings)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chrome.subtleText.color)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    // MARK: - Empty hero

    private var emptyStateBody: some View {
        VStack(spacing: 0) {
            if let status = store.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(chrome.danger.color)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                contextSelectors

                composerBlock(
                    height: AppLayoutMetrics.composerEmptyHeroHeight,
                    maxContentWidth: AppLayoutMetrics.composerEmptyMaxContentWidth,
                    style: .hero
                )

                quickActions
            }
            .frame(maxWidth: AppLayoutMetrics.composerEmptyMaxContentWidth + 40)

            Spacer(minLength: 0)

            Text(L10n.t("chat.footerHint", language: store.language))
                .font(.system(size: 12))
                .foregroundStyle(chrome.disabledText.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var contextSelectors: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.settings.workspaces, id: \.id) { ws in
                    Button(ws.name.isEmpty ? (ws.rootPath as NSString).lastPathComponent : ws.name) {
                        store.selectWorkspace(path: ws.rootPath)
                    }
                }
                Divider()
                Button(L10n.t("nav.addWorkspace", language: store.language)) {
                    store.pickAndAddWorkspace()
                }
            } label: {
                contextChip(
                    icon: "folder",
                    title: workspaceLabel
                )
            }
            .menuStyle(.borderlessButton)

            contextChip(
                icon: "desktopcomputer",
                title: L10n.t("chat.thisMac", language: store.language)
            )
        }
    }

    private func contextChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.65)
        }
        .foregroundStyle(chrome.textSecondary.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(chrome.panel.color.opacity(0.9))
        )
        .overlay(
            Capsule().strokeBorder(chrome.border.color.opacity(0.7), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickPill(
                title: L10n.t("chat.planIdea", language: store.language),
                shortcut: "⇧Tab"
            ) {
                store.harnessMode = .plan
                if store.composerText.isEmpty {
                    store.composerText = L10n.t("chat.planIdeaPrompt", language: store.language)
                }
            }

            quickPill(
                title: L10n.t("chat.multitask", language: store.language),
                shortcut: nil
            ) {
                if store.composerText.isEmpty {
                    store.composerText = "/multitask "
                } else if !store.composerText.contains("/multitask") {
                    store.composerText = "/multitask " + store.composerText
                }
            }
        }
    }

    private func quickPill(title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(chrome.disabledText.color)
                }
            }
            .foregroundStyle(chrome.textSecondary.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(chrome.panel.color)
            )
            .overlay(
                Capsule().strokeBorder(chrome.border.color.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation (composer docked in chatColumn when !isEmpty)

    private func composerBlock(
        height: CGFloat,
        maxContentWidth: CGFloat,
        style: ComposerView.ComposerChromeStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.fileSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.fileSuggestions) { suggestion in
                            Button {
                                store.acceptFileSuggestion(suggestion)
                            } label: {
                                Text(suggestion.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(chrome.panelAlt.color)
                                    )
                                    .foregroundStyle(chrome.textSecondary.color)
                            }
                            .buttonStyle(.plain)
                            .help(suggestion.path)
                        }
                    }
                }
                .frame(maxWidth: maxContentWidth)
            }

            ComposerView(
                text: Bindable(store).composerText,
                isRunning: store.isRunning,
                height: height,
                maxContentWidth: maxContentWidth,
                placeholder: L10n.t("composer.placeholder", language: store.language),
                language: store.language,
                harnessMode: Bindable(store).harnessMode,
                attachments: store.composerAttachments,
                style: style,
                chrome: chrome,
                onSend: { store.sendComposerMessage() },
                onStop: { store.stopRunning() }
            )
        }
    }

    private func replayFixture() {
        do {
            let json = try ChatFixtureLoader.loadEventsJSONArray()
            store.messageCount = max(store.messageCount, 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                chatBridge.replayEventsJSON(json)
            }
        } catch {
            NSLog("[ChatPageView] fixture replay failed: %@", error.localizedDescription)
        }
    }
}

#Preview {
    ChatPageView()
        .environment(MainShellStore())
        .frame(width: 980, height: 720)
        .preferredColorScheme(.dark)
}
