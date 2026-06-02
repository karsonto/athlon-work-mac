import SwiftUI

// MARK: - User Message Bubble
struct UserMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                // Image attachments
                if let images = message.imageAttachments, !images.isEmpty {
                    imageAttachmentRow(images)
                }

                // Text bubble
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#F4F4F5"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1A3A5C"))
                    )
                    .contextMenu {
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        }
                    }

                // Timestamp
                Text(formatTime(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#71717A"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: LayoutMetrics.userBubbleMaxWidth, alignment: .trailing)
        .id(message.id)
    }

    @ViewBuilder
    private func imageAttachmentRow(_ images: [ImageAttachment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { img in
                    VStack(spacing: 4) {
                        if let data = img.thumbnailData,
                           let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 120, maxHeight: 80)
                                .cornerRadius(6)
                        } else {
                            Image(systemName: "photo")
                                .frame(width: 80, height: 60)
                                .background(Color(hex: "#27272A"))
                                .cornerRadius(6)
                        }
                        Text(img.fileName)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#A1A1AA"))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Assistant Message Bubble
struct AssistantMessageBubble: View {
    let message: ChatMessage
    @State private var isReasoningExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Role label
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6366F1"))
                Text("Athlon 助手")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#A1A1AA"))
                Text(formatTime(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#52525B"))
            }

            // Reasoning content (collapsible)
            if message.hasReasoning {
                reasoningSection
            }

            // Tool calls (if any)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                ForEach(toolCalls) { tc in
                    InlineToolCallRow(toolCall: tc)
                }
                .padding(.bottom, 4)
            }

            // Main content
            Text(message.content)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#F4F4F5"))
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    }
                }

            // Streaming cursor
            if message.isStreaming {
                Text("▊")
                    .foregroundColor(Color(hex: "#6366F1"))
                    .opacity(message.isStreaming ? 1 : 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: LayoutMetrics.messageBubbleMaxWidth, alignment: .leading)
        .id(message.id)
    }

    // MARK: - Reasoning Section
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isReasoningExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                    Text("推理过程")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if message.isReasoningStreaming {
                        Text("思考中…")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6366F1"))
                    }
                }
                .foregroundColor(Color(hex: "#C4B5FD"))
            }
            .buttonStyle(.plain)

            if isReasoningExpanded {
                Text(message.reasoningContent)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#C4B5FD"))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "#1A1825"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "#4C1D95").opacity(0.3), lineWidth: 1)
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

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(toolCallColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(toolCallColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var toolCallColor: Color {
        switch toolCall.status {
        case .preparing, .running:
            return Color(hex: "#C4B5FD")
        case .succeeded:
            return Color(hex: "#86EFAC")
        case .failed:
            return Color(hex: "#FCA5A5")
        default:
            return Color(hex: "#A1A1AA")
        }
    }
}

// MARK: - Tool Call Card (Standalone tool/compaction message)
struct ToolCallCard: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: message.isTool ? "hammer" : "arrow.triangle.merge")
                    .font(.system(size: 11))
                Text(message.isTool ? "工具" : "上下文压缩")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(formatTime(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#52525B"))
            }
            .foregroundColor(Color(hex: "#A1A1AA"))

            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#A1A1AA"))
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: LayoutMetrics.messageBubbleMaxWidth, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .id(message.id)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
