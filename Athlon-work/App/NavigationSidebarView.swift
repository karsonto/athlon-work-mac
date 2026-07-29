import SwiftUI

struct NavigationSidebarView: View {
    @Environment(MainShellStore.self) private var store
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false

    private var chrome: UiChromeColors { store.themeManager.chrome }

    private var filteredSessions: [AgentSession] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.sessions }
        return store.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.activeWorkspace ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topActions
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if isSearching {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    repositoriesHeader
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    LazyVStack(spacing: 2) {
                        ForEach(filteredSessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .frame(minWidth: UiLayoutConstraints.navigationSidebarMinWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.panel.color)
    }

    // MARK: - Top

    private var topActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.createSession()
                store.selectPage(.chat)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("nav.newAgent", language: store.language))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(chrome.text.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(chrome.panelAlt.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(chrome.border.color.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            sidebarLink(
                title: L10n.t("nav.search", language: store.language),
                systemImage: "magnifyingglass",
                selected: isSearching
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearching.toggle()
                    if !isSearching { searchText = "" }
                }
            }

            sidebarLink(
                title: L10n.t("nav.automations", language: store.language),
                systemImage: "bolt",
                selected: store.currentPage == .schedule
            ) {
                store.selectPage(.schedule)
            }

            sidebarLink(
                title: L10n.t("nav.customize", language: store.language),
                systemImage: "slider.horizontal.3",
                selected: store.currentPage == .settings
            ) {
                store.selectPage(.settings)
            }

            sidebarLink(
                title: L10n.t("nav.knowledge", language: store.language),
                systemImage: "books.vertical",
                selected: store.currentPage == .knowledge
            ) {
                store.selectPage(.knowledge)
            }
        }
    }

    private func sidebarLink(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? chrome.text.color : chrome.subtleText.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? chrome.panelAlt.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(chrome.subtleText.color)
            TextField(L10n.t("nav.searchPlaceholder", language: store.language), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chrome.appBackground.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(chrome.border.color.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Repositories

    private var repositoriesHeader: some View {
        HStack(spacing: 6) {
            Text(L10n.t("nav.repositories", language: store.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(chrome.subtleText.color)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer(minLength: 0)
            Button {
                store.pickAndAddWorkspace()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.subtleText.color)
            }
            .buttonStyle(.plain)
            .help(L10n.t("nav.addWorkspace", language: store.language))
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        let selected = session.id == store.currentSessionId && store.currentPage == .chat
        let queueCount = store.queuedTurnPresenter.count(for: session.id)
        let running = store.turnHost.isRunning(session.id)
        let subtitle = sessionSubtitle(session)

        Button {
            store.selectSession(session.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(chrome.subtleText.color)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.title.isEmpty ? L10n.t("chat.newSession", language: store.language) : session.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(chrome.text.color)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if running {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text(RelativeTimeFormatting.string(from: session.updatedAt))
                                .font(.system(size: 11))
                                .foregroundStyle(chrome.disabledText.color)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(chrome.subtleText.color)
                            .lineLimit(1)
                    }

                    if selected, !store.queuedTurnsForCurrentSession.isEmpty {
                        ForEach(store.queuedTurnsForCurrentSession) { item in
                            HStack(spacing: 4) {
                                Image(systemName: "tray")
                                    .font(.system(size: 10))
                                Text(item.preview)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    store.queuedTurnPresenter.remove(sessionId: item.sessionId, queueId: item.queueId)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(chrome.subtleText.color)
                        }
                    }
                }

                if queueCount > 0 && !running {
                    Text("\(queueCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(chrome.accentSubtle.color))
                        .foregroundStyle(chrome.accent.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? chrome.panelAlt.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.t("nav.deleteSession", language: store.language), role: .destructive) {
                store.deleteSession(session.id)
            }
        }
    }

    private func sessionSubtitle(_ session: AgentSession) -> String {
        if let root = session.activeWorkspace, !root.isEmpty {
            return (root as NSString).lastPathComponent
        }
        if let id = session.activeWorkspaceId,
           let ws = store.settings.workspaces.first(where: { $0.id == id }) {
            return ws.name.isEmpty ? (ws.rootPath as NSString).lastPathComponent : ws.name
        }
        return L10n.t("nav.noWorkspace", language: store.language)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(chrome.accent.color.opacity(0.85))
                .frame(width: 22, height: 22)
                .overlay(
                    Text(String(NSFullUserName().prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(chrome.text.color)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                store.selectPage(.settings)
            } label: {
                Text(L10n.t("nav.update", language: store.language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chrome.subtleText.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().strokeBorder(chrome.border.color, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.t("nav.openSettings", language: store.language))

            Button {
                store.selectPage(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(chrome.subtleText.color)
            }
            .buttonStyle(.plain)
            .help(L10n.t("nav.settings", language: store.language))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(chrome.panel.color)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(chrome.border.color.opacity(0.55))
                .frame(height: 1)
        }
    }
}

enum RelativeTimeFormatting {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        if seconds < 864_000 { return "\(seconds / 86_400)d" }
        return "\(seconds / 604_800)w"
    }
}

#Preview {
    NavigationSidebarView()
        .environment(MainShellStore())
        .frame(width: 280, height: 700)
        .preferredColorScheme(.dark)
}
