import SwiftUI

// MARK: - Navigation Sidebar (Left Panel)
struct NavigationSidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var isWorkspaceExpanded: Bool = true
    @State private var isHistoryExpanded: Bool = true
    @State private var isQueuedExpanded: Bool = true

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace info panel
            workspaceInfoPanel

            Divider()
                .foregroundColor(colors.border)

            // Queued turns
            if appState.hasQueuedTurns {
                queuedTurnsSection
                Divider()
                    .foregroundColor(colors.border)
            }

            // Session history
            sessionHistorySection

            Divider()
                .foregroundColor(colors.border)

            // Bottom action buttons
            bottomActions
        }
        .background(colors.panelAlt)
    }

    // MARK: - Workspace Info Panel
    private var workspaceInfoPanel: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isWorkspaceExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#F59E0B"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("当前工作区")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.text)
                        if let ws = appState.activeWorkspace {
                            Text(ws)
                                .font(.system(size: 9))
                                .foregroundColor(colors.subtleText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: isWorkspaceExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(colors.subtleText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isWorkspaceExpanded {
                VStack(spacing: 2) {
                    if let path = appState.workspaceRootPath {
                        workspaceInfoRow(icon: "link", label: path)
                    }
                    workspaceInfoRow(icon: "doc.on.doc", label: "\(appState.workspaceFiles.count) 个文件")
                    workspaceInfoRow(icon: "clock", label: "最后更新：\(timeAgo())")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Queued Turns Section
    private var queuedTurnsSection: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isQueuedExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#F59E0B"))
                    Text("排队消息")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.text)
                    Spacer()
                    Text("\(appState.queuedTurns.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(colors.accent.opacity(0.15)))
                    Image(systemName: isQueuedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(colors.subtleText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isQueuedExpanded {
                VStack(spacing: 2) {
                    ForEach(appState.queuedTurns) { turn in
                        QueuedTurnRow(turn: turn)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Session History
    private var sessionHistorySection: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isHistoryExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(colors.subtleText)
                    Text("历史会话")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.text)
                    Spacer()
                    Text("\(appState.sessions.count)")
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                    Image(systemName: isHistoryExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(colors.subtleText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isHistoryExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedSessions, id: \.id) { group in
                            sessionGroupView(group)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
        }
    }

    // MARK: - Bottom Actions
    private var bottomActions: some View {
        VStack(spacing: 2) {
            sidebarActionButton(
                icon: "plus.bubble.fill",
                label: "新会话",
                shortcut: "⌘N"
            ) {
                appState.createNewSession()
            }

            sidebarActionButton(
                icon: "gearshape",
                label: "设置",
                shortcut: "⌘,"
            ) {
                appState.currentPage = .settings
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    // MARK: - Grouped Sessions
    private var groupedSessions: [SessionHistoryGroup] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        var todaySessions: [AgentSession] = []
        var yesterdaySessions: [AgentSession] = []
        var thisWeekSessions: [AgentSession] = []
        var olderSessions: [AgentSession] = []

        for session in appState.sessions {
            let date = session.updatedAt
            if date >= startOfToday {
                todaySessions.append(session)
            } else if date >= startOfYesterday {
                yesterdaySessions.append(session)
            } else if date >= startOfWeek {
                thisWeekSessions.append(session)
            } else {
                olderSessions.append(session)
            }
        }

        var groups: [SessionHistoryGroup] = []
        if !todaySessions.isEmpty {
            groups.append(SessionHistoryGroup(
                id: "today",
                title: "今天",
                items: todaySessions.map { SessionHistoryItem(id: $0.id, title: $0.title.isEmpty ? "新会话" : $0.title,
                    updatedAtText: shortTime(from: $0.updatedAt), isActive: appState.activeSessionId == $0.id,
                    isRunning: $0.isRunning) }
            ))
        }
        if !yesterdaySessions.isEmpty {
            groups.append(SessionHistoryGroup(
                id: "yesterday",
                title: "昨天",
                items: yesterdaySessions.map { SessionHistoryItem(id: $0.id, title: $0.title.isEmpty ? "新会话" : $0.title,
                    updatedAtText: shortTime(from: $0.updatedAt), isActive: appState.activeSessionId == $0.id,
                    isRunning: $0.isRunning) }
            ))
        }
        if !thisWeekSessions.isEmpty {
            groups.append(SessionHistoryGroup(
                id: "thisweek",
                title: "本周",
                items: thisWeekSessions.map { SessionHistoryItem(id: $0.id, title: $0.title.isEmpty ? "新会话" : $0.title,
                    updatedAtText: shortTime(from: $0.updatedAt), isActive: appState.activeSessionId == $0.id,
                    isRunning: $0.isRunning) }
            ))
        }
        if !olderSessions.isEmpty {
            groups.append(SessionHistoryGroup(
                id: "older",
                title: "更早",
                items: olderSessions.map { SessionHistoryItem(id: $0.id, title: $0.title.isEmpty ? "新会话" : $0.title,
                    updatedAtText: shortTime(from: $0.updatedAt), isActive: appState.activeSessionId == $0.id,
                    isRunning: $0.isRunning) }
            ))
        }
        return groups
    }

    // MARK: - Session Group View
    private func sessionGroupView(_ group: SessionHistoryGroup) -> some View {
        VStack(spacing: 0) {
            // Group header
            HStack {
                Text(group.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colors.subtleText)
                    .padding(.leading, 12)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.top, 4)

            // Group items
            ForEach(group.items) { item in
                SessionRow(sessionId: item.id, title: item.title, workspace: nil,
                           updatedAt: item.updatedAtText, isActive: item.isActive, isRunning: item.isRunning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.activeSessionId = item.id
                        appState.currentPage = .chat
                    }
            }
        }
    }

    // MARK: - Helpers
    private func workspaceInfoRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(colors.subtleText)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(colors.subtleText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func sidebarActionButton(icon: String, label: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundColor(colors.accent)
                Text(label)
                    .foregroundColor(colors.text)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 10))
                    .foregroundColor(colors.subtleText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    private func shortTime(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func timeAgo() -> String {
        "刚刚"
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let sessionId: String
    let title: String
    let workspace: String?
    let updatedAt: String
    let isActive: Bool
    let isRunning: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Running indicator
            Circle()
                .fill(isRunning ? Color(hex: "#6366F1") : Color.clear)
                .frame(width: 6, height: 6)

            Image(systemName: isRunning ? "circle.dotted" : "bubble.left")
                .font(.system(size: 12))
                .foregroundColor(isActive ? Color(hex: "#6366F1") : Color(hex: "#A1A1AA"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundColor(isActive ? .white : Color(hex: "#D4D4D8"))
                if let ws = workspace, !ws.isEmpty {
                    Text(ws)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#71717A"))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(updatedAt)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#52525B"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                    ? Color(hex: "#6366F1").opacity(0.2)
                    : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .onHover { h in isHovered = h }
        .contextMenu {
            Button("激活会话") {
                // handled by parent
            }
            Divider()
            Button("删除会话", role: .destructive) {
                // delete action
            }
        }
    }
}

// MARK: - Queued Turn Row
struct QueuedTurnRow: View {
    let turn: QueuedTurn

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#F59E0B"))
            Text(turn.previewText)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#D4D4D8"))
                .lineLimit(1)
            Spacer()
            if !turn.imageItems.isEmpty {
                Text("📎\(turn.imageItems.count)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#A1A1AA"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "#F59E0B").opacity(0.08))
        )
    }
}
