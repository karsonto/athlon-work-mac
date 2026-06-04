import SwiftUI

// MARK: - Native Markdown (avoids WKWebView + CDN — empty bubble bug)
struct AssistantMarkdownTextView: View {
    let text: String
    let textColor: Color
    var fontSize: CGFloat = 14

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(.system(size: fontSize))
        .foregroundColor(textColor)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - User Message Bubble
struct UserMessageBubble: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                if let images = message.imageAttachments, !images.isEmpty {
                    imageAttachmentRow(images)
                }

                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(colors.userBubbleText)
                    .padding(.horizontal, LayoutMetrics.messageBubblePaddingH)
                    .padding(.vertical, LayoutMetrics.messageBubblePaddingV)
                    .background(
                        RoundedRectangle(cornerRadius: LayoutMetrics.messageBubbleCornerRadius)
                            .fill(colors.userBubble)
                            .overlay(
                                RoundedRectangle(cornerRadius: LayoutMetrics.messageBubbleCornerRadius)
                                    .stroke(colors.userBubbleBorder, lineWidth: 1)
                            )
                    )
                    .contextMenu {
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        }
                    }
            }
            .frame(maxWidth: LayoutMetrics.userBubbleMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .id(message.id)
    }

    @ViewBuilder
    private func imageAttachmentRow(_ images: [ImageAttachment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { img in
                    if let data = img.thumbnailData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 120, maxHeight: 80)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Assistant Message Bubble
struct AssistantMessageBubble: View {
    @EnvironmentObject var appState: AppState
    let messageId: String
    @State private var isReasoningExpanded: Bool = false

    /// Always read the live row from AppState so streaming updates re-render (ForEach snapshots go stale).
    private var message: ChatMessage {
        appState.messages.first(where: { $0.id == messageId })
            ?? ChatMessage(id: messageId, role: .assistant, content: "", createdAt: Date())
    }

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var shouldExpandReasoningByDefault: Bool {
        message.isReasoningStreaming
            || (message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.isStreaming && message.hasReasoning)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#7DD3FC"), colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Athlon")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.subtleText)
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(colors.disabledText)
                }

                if message.hasReasoning {
                    reasoningSection
                }

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { tc in
                        InlineToolCallRow(toolCall: tc, colors: colors)
                    }
                }

                // Only render the answer bubble when there is real body text.
                // `isStreaming` alone must not draw an empty chrome (the "air bubble" bug).
                if message.hasDisplayContent {
                    assistantAnswerBubble
                } else if message.isStreaming, !message.hasReasoning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("思考中…")
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
                    }
                } else if !message.isStreaming, message.hasReasoning {
                    Text("（模型未返回可见正文，仅包含推理过程。若使用 DeepSeek，请确认模型支持 content 流式输出，或改用 deepseek-chat / deepseek-reasoner。）")
                        .font(.system(size: 12))
                        .foregroundColor(colors.subtleText)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colors.panelAlt)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(colors.border.opacity(0.4), lineWidth: 1)
                                )
                        )
                }

                if message.isStreaming, message.hasDisplayContent || message.hasReasoning {
                    Text("▊")
                        .foregroundColor(colors.accent)
                }
            }
            .frame(maxWidth: LayoutMetrics.messageBubbleMaxWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(message.id)
        .onAppear {
            if shouldExpandReasoningByDefault {
                isReasoningExpanded = true
            }
        }
        .onValueChange(of: message.content) { newContent in
            if !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isReasoningExpanded = false
            }
        }
    }

    @ViewBuilder
    private var assistantAnswerBubble: some View {
        let text = message.displayContent
        if text.isEmpty, !message.isStreaming {
            EmptyView()
        } else {
            Group {
                if message.isStreaming {
                    // Native parser during streaming — avoids WebKit reload flicker / empty bubble.
                    AssistantMarkdownTextView(text: text, textColor: colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownContent(text: text, isDarkTheme: appState.theme == .dark)
                }
            }
            .frame(maxWidth: LayoutMetrics.messageBubbleMaxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, LayoutMetrics.messageBubblePaddingH)
            .padding(.vertical, LayoutMetrics.messageBubblePaddingV)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.messageBubbleCornerRadius)
                    .fill(colors.assistantBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: LayoutMetrics.messageBubbleCornerRadius)
                            .stroke(colors.border, lineWidth: 1)
                    )
            )
            .contextMenu {
                if text.contains("```mermaid") {
                    Button("查看 Mermaid 图表") {
                        MermaidPreviewWindow.show(markdown: text, isDark: appState.theme == .dark)
                    }
                }
                if text.localizedCaseInsensitiveContains("<html")
                    || text.localizedCaseInsensitiveContains("<!doctype html") {
                    Button("预览 HTML") {
                        HtmlPreviewWindow.show(html: text, isDark: appState.theme == .dark)
                    }
                }
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation { isReasoningExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                    Text("思考过程")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if message.isReasoningStreaming, !message.hasDisplayContent {
                        Text("思考中…")
                            .font(.system(size: 10))
                            .foregroundColor(colors.accent)
                    }
                }
                .foregroundColor(colors.toolThinkingText)
            }
            .buttonStyle(.plain)

            if isReasoningExpanded {
                AssistantMarkdownTextView(
                    text: message.reasoningContent,
                    textColor: colors.toolThinkingText,
                    fontSize: 12
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colors.toolThinkingBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(colors.toolThinkingBorder.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Inline Tool Call Row
struct InlineToolCallRow: View {
    let toolCall: AgentToolCall
    let colors: ThemeColors

    private var pathPreview: String? {
        let args = AssistantToolCallsCodec.parseArguments(toolCall.arguments)
        guard let path = args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path.count > 72 ? String(path.prefix(69)) + "…" : path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(toolCallColor)
                    .frame(width: 6, height: 6)
                Image(systemName: "hammer")
                    .font(.system(size: 10))
                    .foregroundColor(toolCallColor)
                Text(toolCall.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(toolCallColor)
                if toolCall.showStatusLabel {
                    Text(toolCall.status.statusLabel)
                        .font(.system(size: 10))
                        .foregroundColor(toolCallColor.opacity(0.8))
                }
            }
            if let pathPreview {
                Text("path: \(pathPreview)")
                    .font(.system(size: 10))
                    .foregroundColor(colors.disabledText)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(toolCallBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(toolCallColor.opacity(0.3), lineWidth: 1))
        )
    }

    private var toolCallColor: Color {
        switch toolCall.status {
        case .preparing, .running: return colors.toolThinkingText
        case .succeeded: return colors.toolSuccessText
        case .failed: return colors.toolFailureText
        default: return colors.subtleText
        }
    }

    private var toolCallBackground: Color {
        switch toolCall.status {
        case .preparing, .running: return colors.toolThinkingBg
        case .succeeded: return colors.toolSuccessBg
        case .failed: return colors.toolFailureBg
        default: return colors.panelAlt
        }
    }
}

// MARK: - Tool Call Card
struct CompactionMessageCard: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage
    @State private var isExpanded = false

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var audit: CompactionAuditDisplayInfo {
        CompactionAuditDisplay.parse(message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 14))
                .foregroundColor(colors.accent)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audit.cardTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colors.text)
                            if !audit.summary.isEmpty {
                                Text(audit.summary)
                                    .font(.system(size: 11))
                                    .foregroundColor(colors.subtleText)
                                    .lineLimit(isExpanded ? nil : 2)
                            }
                            Text(audit.strategySubtitle)
                                .font(.system(size: 10))
                                .foregroundColor(colors.subtleText.opacity(0.85))
                                .lineLimit(isExpanded ? nil : 1)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(colors.subtleText)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(audit.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(colors.subtleText)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.panelAlt)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border.opacity(0.5)))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(message.id)
    }
}

struct ToolCallCard: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage
    @State private var isExpanded = false

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var display: ToolCallDisplayInfo {
        ToolCallDisplay.from(message: message)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.isTool ? "hammer" : "arrow.triangle.merge")
                .font(.system(size: 14))
                .foregroundColor(statusColor)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colors.toolThinkingText)
                    }
                    .buttonStyle(.plain)

                    Text(message.isTool ? "工具" : "上下文压缩")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colors.toolThinkingText)
                    if display.status != .none {
                        Text(display.status.statusLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(statusColor)
                    }
                    Spacer()
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(colors.disabledText)
                }

                Text(display.header)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C4B5FD"))
                    .lineLimit(2)

                if display.hasArguments {
                    Text(display.argumentsText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.toolThinkingText)
                        .textSelection(.enabled)
                        .lineLimit(isExpanded ? nil : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !display.summary.isEmpty {
                    Text(display.summary)
                        .font(.system(size: 11))
                        .foregroundColor(colors.subtleText)
                        .lineLimit(isExpanded ? nil : 2)
                }

                if isExpanded, !detailPreview.isEmpty {
                    Text(detailPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(colors.subtleText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: LayoutMetrics.messageBubbleMaxWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(toolBackground)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(toolBorder.opacity(0.4), lineWidth: 1))
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(message.id)
    }

    private var detailPreview: String {
        let text = display.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("ToolCallId:") else { return text }
        // Hide persisted header block; show result body only when expanded.
        let parts = text.components(separatedBy: "\n\n")
        if let last = parts.last,
           !last.hasPrefix("ToolCallId:"),
           !last.hasPrefix("Tool `"),
           !last.hasPrefix("Arguments") {
            return last.count > 4_096 ? String(last.prefix(4_096)) + "\n…" : last
        }
        return ""
    }

    private var statusColor: Color {
        switch display.status {
        case .preparing, .running: return colors.toolThinkingText
        case .succeeded: return colors.toolSuccessText
        case .failed: return colors.toolFailureText
        case .cancelled: return colors.subtleText
        case .none: return colors.toolThinkingText
        }
    }

    private var toolBackground: Color {
        switch display.status {
        case .preparing, .running: return colors.toolThinkingBg
        case .succeeded: return colors.toolSuccessBg
        case .failed: return colors.toolFailureBg
        default: return colors.toolThinkingBg
        }
    }

    private var toolBorder: Color {
        switch display.status {
        case .succeeded: return colors.toolSuccessBorder
        case .failed: return colors.toolFailureBorder
        default: return colors.toolThinkingBorder
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
