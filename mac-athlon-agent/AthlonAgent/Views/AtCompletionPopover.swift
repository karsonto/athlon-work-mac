// AthlonAgent/Views/AtCompletionPopover.swift
import SwiftUI

/// Standalone reusable @-completion popover, extracted from ComposerView.
struct AtCompletionPopover: View {
    let items: [AtCompletionItem]
    let selectedIndex: Int
    let onSelect: (AtCompletionItem) -> Void
    let onDismiss: () -> Void
    let colors: ThemeColors

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button(action: { onSelect(item) }) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(colors.text)
                            Text(item.kindLabel)
                                .font(.system(size: 10))
                                .foregroundColor(colors.subtleText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(idx == selectedIndex ? colors.accent.opacity(0.15) : Color.clear)
                    .cornerRadius(DesignTokens.Radius.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < items.count - 1 {
                    Divider().background(colors.border)
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 220)
        .background(colors.panel)
        .cornerRadius(DesignTokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12)
    }
}

/// Item model for @ completion — matches existing ComposerView tuple structure
struct AtCompletionItem: Identifiable {
    let id = UUID()
    let displayName: String
    let detailText: String
    let iconName: String
    let kind: AtCompletionKind
    let fullPath: String

    var kindLabel: String {
        kind == .file ? "文件" : "技能"
    }
}

enum AtCompletionKind {
    case file
    case skill
}
