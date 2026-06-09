// AthlonAgent/ViewModels/ChatMessageViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class ChatMessageViewModel: ObservableObject, Identifiable {
    let id: String
    let message: ChatMessage

    @Published var isReasoningExpanded: Bool = true
    @Published var isToolCardExpanded: Bool = false

    // MARK: - Computed properties
    var role: MessageRole { message.role }
    var content: String { message.content }
    var reasoningContent: String { message.reasoningContent }
    var hasReasoning: Bool { message.hasReasoning }
    var isUser: Bool { message.isUser }
    var isAssistant: Bool { message.role == .assistant }
    var isTool: Bool { message.isTool }

    var createdAt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.createdAt)
    }

    var reasoningChevronGlyph: String {
        isReasoningExpanded ? "▼" : "▶"
    }

    var toolCalls: [AgentToolCall] { message.toolCalls ?? [] }
    var hasToolCalls: Bool { !(message.toolCalls?.isEmpty ?? true) }
    var toolName: String? { message.toolCalls?.first?.name }
    var toolArgsText: String? { message.toolCalls?.first?.arguments }
    var toolStatusText: String {
        guard let first = message.toolCalls?.first else { return "" }
        return first.status.statusLabel
    }

    var attachmentPaths: [String] {
        message.imageAttachments?.map { $0.fileName } ?? []
    }
    var hasAttachments: Bool { !attachmentPaths.isEmpty }
    var attachmentSummary: String {
        guard hasAttachments else { return "" }
        return attachmentPaths.joined(separator: ", ")
    }

    var isStreaming: Bool { message.isStreaming }
    var isReasoningStreaming: Bool { message.isReasoningStreaming }

    init(message: ChatMessage) {
        self.id = message.id
        self.message = message
    }

    func toggleReasoning() {
        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
            isReasoningExpanded.toggle()
        }
    }

    func toggleToolCard() {
        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
            isToolCardExpanded.toggle()
        }
    }
}
