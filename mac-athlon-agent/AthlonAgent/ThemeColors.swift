import SwiftUI

// MARK: - Color Theme
struct ThemeColors {
    // Backgrounds
    let appBackground: Color
    let chrome: Color
    let panel: Color
    let panelAlt: Color
    let chatBackground: Color

    // Bubbles
    let assistantBubble: Color
    let userBubble: Color

    // Composer
    let composer: Color

    // Tool call cards
    let toolThinkingBg: Color
    let toolThinkingBorder: Color
    let toolThinkingText: Color
    let toolSuccessBg: Color
    let toolSuccessBorder: Color
    let toolSuccessText: Color
    let toolFailureBg: Color
    let toolFailureBorder: Color
    let toolFailureText: Color

    // Text
    let text: Color
    let subtleText: Color
    let accent: Color
    let success: Color
    let danger: Color
    let border: Color

    // Badge
    let fileBadgeBg: Color
    let fileBadgeBorder: Color
    let fileBadgeText: Color
    let skillBadgeBg: Color
    let skillBadgeBorder: Color
    let skillBadgeText: Color

    // MARK: - Dark Theme
    static let dark = ThemeColors(
        appBackground: Color(hex: "#18181B"),
        chrome: Color(hex: "#27272A"),
        panel: Color(hex: "#1B1B1E"),
        panelAlt: Color(hex: "#222227"),
        chatBackground: Color(hex: "#18181B"),
        assistantBubble: Color(hex: "#1E1E24"),
        userBubble: Color(hex: "#1A3A5C"),
        composer: Color(hex: "#1E1E24"),
        toolThinkingBg: Color(hex: "#1A1825"),
        toolThinkingBorder: Color(hex: "#4C1D95"),
        toolThinkingText: Color(hex: "#C4B5FD"),
        toolSuccessBg: Color(hex: "#0B2818"),
        toolSuccessBorder: Color(hex: "#15803D"),
        toolSuccessText: Color(hex: "#86EFAC"),
        toolFailureBg: Color(hex: "#2D1B1B"),
        toolFailureBorder: Color(hex: "#991B1B"),
        toolFailureText: Color(hex: "#FCA5A5"),
        text: Color(hex: "#F4F4F5"),
        subtleText: Color(hex: "#A1A1AA"),
        accent: Color(hex: "#6366F1"),
        success: Color(hex: "#22C55E"),
        danger: Color(hex: "#EF4444"),
        border: Color(hex: "#3F3F46"),
        fileBadgeBg: Color(hex: "#1E293B"),
        fileBadgeBorder: Color(hex: "#334155"),
        fileBadgeText: Color(hex: "#93C5FD"),
        skillBadgeBg: Color(hex: "#1A1825"),
        skillBadgeBorder: Color(hex: "#4C1D95"),
        skillBadgeText: Color(hex: "#C4B5FD")
    )

    // MARK: - Light Theme
    static let light = ThemeColors(
        appBackground: Color(hex: "#FAFAFA"),
        chrome: Color(hex: "#F4F4F5"),
        panel: Color(hex: "#FFFFFF"),
        panelAlt: Color(hex: "#F4F4F5"),
        chatBackground: Color(hex: "#FAFAFA"),
        assistantBubble: Color(hex: "#FFFFFF"),
        userBubble: Color(hex: "#DBEAFE"),
        composer: Color(hex: "#FFFFFF"),
        toolThinkingBg: Color(hex: "#F5F3FF"),
        toolThinkingBorder: Color(hex: "#C4B5FD"),
        toolThinkingText: Color(hex: "#6D28D9"),
        toolSuccessBg: Color(hex: "#ECFDF5"),
        toolSuccessBorder: Color(hex: "#6EE7B7"),
        toolSuccessText: Color(hex: "#065F46"),
        toolFailureBg: Color(hex: "#FEF2F2"),
        toolFailureBorder: Color(hex: "#FCA5A5"),
        toolFailureText: Color(hex: "#991B1B"),
        text: Color(hex: "#18181B"),
        subtleText: Color(hex: "#71717A"),
        accent: Color(hex: "#6366F1"),
        success: Color(hex: "#22C55E"),
        danger: Color(hex: "#EF4444"),
        border: Color(hex: "#D4D4D8"),
        fileBadgeBg: Color(hex: "#DBEAFE"),
        fileBadgeBorder: Color(hex: "#93C5FD"),
        fileBadgeText: Color(hex: "#1E40AF"),
        skillBadgeBg: Color(hex: "#F5F3FF"),
        skillBadgeBorder: Color(hex: "#C4B5FD"),
        skillBadgeText: Color(hex: "#6D28D9")
    )
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Environment Key for theme colors
struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = .dark
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
