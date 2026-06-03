import SwiftUI

// MARK: - Color Theme
/// Semantic colors aligned with WPF DarkAppThemePalette / LightAppThemePalette.
struct ThemeColors {
    let appBackground: Color
    let chrome: Color
    let panel: Color
    let panelAlt: Color
    let chatBackgroundTop: Color
    let chatBackgroundBottom: Color

    let assistantBubble: Color
    let userBubble: Color
    let userBubbleBorder: Color
    let userBubbleText: Color

    let composer: Color

    let toolThinkingBg: Color
    let toolThinkingBorder: Color
    let toolThinkingText: Color
    let toolSuccessBg: Color
    let toolSuccessBorder: Color
    let toolSuccessText: Color
    let toolFailureBg: Color
    let toolFailureBorder: Color
    let toolFailureText: Color

    let text: Color
    let subtleText: Color
    let disabledText: Color
    let accent: Color
    let accentHover: Color
    let success: Color
    let danger: Color
    let border: Color

    let navActiveBg: Color
    let navActiveText: Color
    let hoverNeutral: Color
    let selectionBorder: Color

    let fileBadgeBg: Color
    let fileBadgeBorder: Color
    let fileBadgeText: Color
    let skillBadgeBg: Color
    let skillBadgeBorder: Color
    let skillBadgeText: Color

    var chatBackground: LinearGradient {
        LinearGradient(
            colors: [chatBackgroundTop, chatBackgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Dark Theme
    static let dark = ThemeColors(
        appBackground: Color(hex: "#101012"),
        chrome: Color(hex: "#18181B"),
        panel: Color(hex: "#262628"),
        panelAlt: Color(hex: "#2A2A2D"),
        chatBackgroundTop: Color(hex: "#141416"),
        chatBackgroundBottom: Color(hex: "#101012"),
        assistantBubble: Color(hex: "#262628"),
        userBubble: Color(hex: "#1E3A5F").opacity(0.86),
        userBubbleBorder: Color(hex: "#2F5C8E"),
        userBubbleText: Color(hex: "#DBEAFE"),
        composer: Color(hex: "#2A2A2D"),
        toolThinkingBg: Color(hex: "#1E1B2E"),
        toolThinkingBorder: Color(hex: "#6D28D9"),
        toolThinkingText: Color(hex: "#DDD6FE"),
        toolSuccessBg: Color(hex: "#142A22"),
        toolSuccessBorder: Color(hex: "#059669"),
        toolSuccessText: Color(hex: "#6EE7B7"),
        toolFailureBg: Color(hex: "#2A1418"),
        toolFailureBorder: Color(hex: "#E11D48"),
        toolFailureText: Color(hex: "#FDA4AF"),
        text: Color(hex: "#F4F4F5"),
        subtleText: Color(hex: "#A1A1AA"),
        disabledText: Color(hex: "#71717A"),
        accent: Color(hex: "#2563EB"),
        accentHover: Color(hex: "#1D4ED8"),
        success: Color(hex: "#10B981"),
        danger: Color(hex: "#E11D48"),
        border: Color(hex: "#3F3F46"),
        navActiveBg: Color(hex: "#1E3A5F"),
        navActiveText: Color(hex: "#93C5FD"),
        hoverNeutral: Color(hex: "#27272A"),
        selectionBorder: Color(hex: "#3B82F6"),
        fileBadgeBg: Color(hex: "#2A2A2D"),
        fileBadgeBorder: Color(hex: "#3F3F46"),
        fileBadgeText: Color(hex: "#A1A1AA"),
        skillBadgeBg: Color(hex: "#1E1B2E"),
        skillBadgeBorder: Color(hex: "#6D28D9"),
        skillBadgeText: Color(hex: "#DDD6FE")
    )

    // MARK: - Light Theme
    static let light = ThemeColors(
        appBackground: Color(hex: "#F1F5F9"),
        chrome: Color(hex: "#FFFFFF"),
        panel: Color(hex: "#FFFFFF"),
        panelAlt: Color(hex: "#F8FAFC"),
        chatBackgroundTop: Color(hex: "#F8FBFF"),
        chatBackgroundBottom: Color(hex: "#F1F5F9"),
        assistantBubble: Color(hex: "#FFFFFF"),
        userBubble: Color(hex: "#0284C7"),
        userBubbleBorder: Color(hex: "#0284C7"),
        userBubbleText: Color(hex: "#FFFFFF"),
        composer: Color(hex: "#FFFFFF"),
        toolThinkingBg: Color(hex: "#F5F3FF"),
        toolThinkingBorder: Color(hex: "#DDD6FE"),
        toolThinkingText: Color(hex: "#4C1D95"),
        toolSuccessBg: Color(hex: "#ECFDF5"),
        toolSuccessBorder: Color(hex: "#059669"),
        toolSuccessText: Color(hex: "#047857"),
        toolFailureBg: Color(hex: "#FFF1F2"),
        toolFailureBorder: Color(hex: "#E11D48"),
        toolFailureText: Color(hex: "#BE123C"),
        text: Color(hex: "#0F172A"),
        subtleText: Color(hex: "#64748B"),
        disabledText: Color(hex: "#94A3B8"),
        accent: Color(hex: "#0284C7"),
        accentHover: Color(hex: "#0369A1"),
        success: Color(hex: "#059669"),
        danger: Color(hex: "#E11D48"),
        border: Color(hex: "#E2E8F0"),
        navActiveBg: Color(hex: "#F0F9FF"),
        navActiveText: Color(hex: "#0369A1"),
        hoverNeutral: Color(hex: "#F8FAFC"),
        selectionBorder: Color(hex: "#BAE6FD"),
        fileBadgeBg: Color(hex: "#F8FAFC"),
        fileBadgeBorder: Color(hex: "#E2E8F0"),
        fileBadgeText: Color(hex: "#64748B"),
        skillBadgeBg: Color(hex: "#F5F3FF"),
        skillBadgeBorder: Color(hex: "#DDD6FE"),
        skillBadgeText: Color(hex: "#4C1D95")
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
