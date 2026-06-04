import SwiftUI

// MARK: - Chat Page (Center Area)
struct ChatPageView: View {
    @State private var messageText: String = ""
    @State private var attachedImages: [ImageAttachment] = []
    @State private var attachedFiles: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ChatMessagesArea()

            ChatComposerArea(
                messageText: $messageText,
                attachedImages: $attachedImages,
                attachedFiles: $attachedFiles
            )
        }
    }
}

// MARK: - Messages (observes AppState)
private struct ChatMessagesArea: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var hasMessages: Bool {
        !appState.activeMessages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasMessages {
                chatHeader
            }

            ZStack {
                if !hasMessages {
                    emptyState
                }

                messageList
                    .opacity(hasMessages ? 1 : 0)
                    .allowsHitTesting(hasMessages)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Session Toolbar
    private var chatHeader: some View {
        HStack(spacing: 12) {
            Text(appState.activeSessionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.text)
                .lineLimit(1)

            Spacer()

            Button("清空上下文") {
                appState.clearContext()
            }
            .disabled(appState.activeMessages.isEmpty || appState.isBusy)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(colors.subtleText)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colors.border, lineWidth: 1)
            )
            .help("清空当前对话在模型中的可见历史")

            Button(action: { appState.toggleContextSidebar() }) {
                RightSidebarToggleIcon(isPanelOpen: appState.isContextSidebarVisible)
            }
            .buttonStyle(.plain)
            .help(appState.isContextSidebarVisible ? "关闭右侧栏" : "打开右侧栏")
        }
        .padding(.horizontal, 20)
        .frame(height: LayoutMetrics.splitPaneHeaderHeight)
        .background(colors.chrome)
        .overlay(
            Rectangle().fill(colors.border.opacity(0.6)).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#7DD3FC"), colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Start chatting with Athlon")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(colors.text)

            Text("在下方输入问题，或使用技能与工具处理工作区文件。")
                .font(.system(size: 14))
                .foregroundColor(colors.subtleText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
    }

    // MARK: - Message List
    private var messageList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: LayoutMetrics.messageSpacing) {
                    ForEach(chatDisplayMessages) { message in
                        messageRow(for: message)
                    }
                }
                .padding(.horizontal, LayoutMetrics.chatScrollPaddingHorizontal)
                .padding(.top, LayoutMetrics.chatScrollPaddingTop)
                .padding(.bottom, LayoutMetrics.chatScrollPaddingBottom)
            }
            .onValueChange(of: appState.activeMessages.count) { _ in
                scrollToBottom(scrollProxy)
            }
            .onValueChange(of: appState.activeMessages.last?.content) { _ in
                scrollToBottom(scrollProxy)
            }
        }
    }

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        if message.isUser {
            UserMessageBubble(message: message)
                .environmentObject(appState)
        } else if message.isCompaction {
            CompactionMessageCard(message: message)
        } else if message.isTool {
            ToolCallCard(message: message)
                .environmentObject(appState)
        } else if shouldShowAssistantBubble(message) {
            AssistantMessageBubble(message: message)
                .environmentObject(appState)
        }
    }

    private var chatDisplayMessages: [ChatMessage] {
        let pinId = appState.isAgentRunning ? appState.pinnedAssistantMessageId : nil
        return ChatTimelineOrder.orderForDisplay(appState.activeMessages, pinToEndMessageId: pinId)
            .filter(\.shouldShowInChatTimeline)
    }

    private func shouldShowAssistantBubble(_ message: ChatMessage) -> Bool {
        message.shouldShowInChatTimeline
            && (message.isStreaming || message.hasReasoning || message.hasDisplayContent)
    }

    private func scrollToBottom(_ scrollProxy: ScrollViewProxy) {
        guard let lastId = chatDisplayMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

// MARK: - Composer host (stable identity — not tied to message stream updates)
private struct ChatComposerArea: View {
    @EnvironmentObject var appState: AppState
    @Binding var messageText: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [String]

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        ComposerView(
            messageText: $messageText,
            attachedImages: $attachedImages,
            attachedFiles: $attachedFiles
        )
        .environmentObject(appState)
        .id("chat-composer")
        .layoutPriority(1)
        .background(colors.chatBackgroundBottom)
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#1E3A5F").opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#2F5C8E"), lineWidth: 1))
        )
    }
}
