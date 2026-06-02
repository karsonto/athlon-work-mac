import SwiftUI

// MARK: - Chat Page (Center Area)
struct ChatPageView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText: String = ""
    @State private var showAtCompletion: Bool = false
    @State private var attachedFiles: [String] = []

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Message list
            messageList

            // Composer
            composerBar
        }
    }

    // MARK: - Chat Header
    private var chatHeader: some View {
        HStack(spacing: 8) {
            // Session title
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.activeSessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.text)
                if let ws = appState.activeSessionWorkspace {
                    Text(ws)
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                }
            }

            Spacer()

            // Plan indicator
            if appState.plan != nil {
                PlanBadge()
            }

            // Resume button
            if appState.isAgentRunning {
                Button("停止") {
                    // Stop agent
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#EF4444"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#EF4444").opacity(0.1)))
            }

            // Context count badge
            Text("\(appState.activeMessageCount) 消息")
                .font(.system(size: 10))
                .foregroundColor(colors.subtleText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(colors.panelAlt))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: LayoutMetrics.splitPaneHeaderHeight)
        .background(colors.panel)
        .overlay(
            Rectangle().fill(colors.border).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Message List
    private var messageList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.activeMessages) { message in
                        if message.isUser {
                            UserMessageBubble(message: message)
                        } else if message.isTool || message.isCompaction {
                            ToolCallCard(message: message)
                        } else {
                            AssistantMessageBubble(message: message)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: appState.activeMessages.count) {
                withAnimation {
                    if let lastId = appState.activeMessages.last?.id {
                        scrollProxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Composer Bar
    private var composerBar: some View {
        VStack(spacing: 0) {
            // At-completion overlay (conditional)
            if showAtCompletion {
                AtCompletionPopup()
                    .transition(.opacity)
            }

            Divider()
                .foregroundColor(colors.border)

            VStack(spacing: 8) {
                // File attachments
                if !attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(attachedFiles, id: \.self) { file in
                                FileChip(name: file) {
                                    attachedFiles.removeAll { $0 == file }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Text input area
                HStack(alignment: .top, spacing: 8) {
                    // @ button
                    Button(action: { showAtCompletion.toggle() }) {
                        Text("@")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(Circle().fill(colors.accent.opacity(0.1)))
                    .help("输入 @ 选择文件或上下文")

                    // Text editor
                    TextEditor(text: $messageText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 48, maxHeight: LayoutMetrics.composerMaxHeight)
                        .background(colors.composer)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colors.border, lineWidth: 1)
                        )

                    // Send button
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(
                                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? colors.subtleText : colors.accent
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Bottom info bar
                HStack {
                    // Image attachment button
                    Button(action: {}) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(colors.subtleText)

                    Spacer()

                    Text("Enter 发送 · Shift+Enter 换行")
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .background(colors.panel)
        }
    }

    // MARK: - Actions
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appState.sendMessage(text)
        messageText = ""
        attachedFiles = []
    }
}

// MARK: - Plan Badge
struct PlanBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 9))
            Text("计划")
                .font(.system(size: 10))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(Color(hex: "#C4B5FD"))
        .background(Capsule().fill(Color(hex: "#4C1D95").opacity(0.2)))
    }
}

// MARK: - File Chip
struct FileChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
                .font(.system(size: 10))
            Text(name)
                .font(.system(size: 11))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(Color(hex: "#93C5FD"))
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "#1E293B"))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#334155"), lineWidth: 1)))
    }
}

// MARK: - At-Completion Stub
struct AtCompletionPopup: View {
    var body: some View {
        VStack {
            Text("@ 文件 · @ 上下文")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#A1A1AA"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "#1E1E24"))
        .overlay(Rectangle().fill(Color(hex: "#3F3F46")).frame(height: 1), alignment: .bottom)
    }
}
