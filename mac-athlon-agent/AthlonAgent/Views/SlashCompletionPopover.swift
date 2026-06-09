// AthlonAgent/Views/SlashCompletionPopover.swift
import SwiftUI

/// Standalone /-command completion popover.
struct SlashCompletionPopover: View {
    let items: [SlashCompletionItem]
    let selectedIndex: Int
    let onSelect: (SlashCompletionItem) -> Void
    let colors: ThemeColors

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button(action: { onSelect(item) }) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text("/\(item.name)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.accent)
                        Text(item.description)
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
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
        .frame(width: 320)
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

struct SlashCompletionItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}
