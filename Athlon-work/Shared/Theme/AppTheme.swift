import Foundation
import Observation
import SwiftUI

enum ThemeKind: String, Codable, CaseIterable, Sendable {
    case dark = "Dark"
    case light = "Light"

    static func parse(_ themeName: String?) -> ThemeKind {
        themeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Light") == .orderedSame ? .light : .dark
    }
}

struct ThemeRGBA: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ hex: String, alpha: Double = 1) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        red = Double((rgb >> 16) & 0xFF) / 255
        green = Double((rgb >> 8) & 0xFF) / 255
        blue = Double(rgb & 0xFF) / 255
        self.alpha = alpha
    }

    var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var cssRGBA: String {
        let a = String(format: "%g", alpha)
        return "rgba(\(Int((red * 255).rounded())), \(Int((green * 255).rounded())), \(Int((blue * 255).rounded())), \(a))"
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Chrome colors used by SwiftUI shell and chat CSS tokens.
struct UiChromeColors: Hashable, Sendable {
    var appBackground: ThemeRGBA
    var chrome: ThemeRGBA
    var panel: ThemeRGBA
    var panelAlt: ThemeRGBA
    var composer: ThemeRGBA
    var composerBorder: ThemeRGBA
    var border: ThemeRGBA
    var borderHover: ThemeRGBA
    var text: ThemeRGBA
    var textSecondary: ThemeRGBA
    var subtleText: ThemeRGBA
    var disabledText: ThemeRGBA
    var disabledBackground: ThemeRGBA
    var accent: ThemeRGBA
    var accentHover: ThemeRGBA
    var accentActive: ThemeRGBA
    var accentSubtle: ThemeRGBA
    var userBubble: ThemeRGBA
    var assistantBubble: ThemeRGBA
    var success: ThemeRGBA
    var danger: ThemeRGBA
    var warning: ThemeRGBA
    var toolThinkingBg: ThemeRGBA
    var toolThinkingText: ThemeRGBA
    var toolSuccessBg: ThemeRGBA
    var toolSuccessText: ThemeRGBA
    var toolFailureBg: ThemeRGBA
    var toolFailureText: ThemeRGBA
    var scrollThumb: ThemeRGBA
    var scrollThumbOpacity: Double
    var chatBackgroundTop: ThemeRGBA
    var chatBackgroundBottom: ThemeRGBA
}

struct AppThemePalette: Hashable, Sendable {
    var kind: ThemeKind
    var chrome: UiChromeColors
}

enum DarkAppThemePalette {
    static func create() -> AppThemePalette {
        AppThemePalette(
            kind: .dark,
            chrome: UiChromeColors(
                appBackground: ThemeRGBA("#0B0D10"),
                chrome: ThemeRGBA("#0E1116"),
                panel: ThemeRGBA("#12151A"),
                panelAlt: ThemeRGBA("#1A1E26"),
                composer: ThemeRGBA("#161A21"),
                composerBorder: ThemeRGBA("#2A303A"),
                border: ThemeRGBA("#232833"),
                borderHover: ThemeRGBA("#3A4250"),
                text: ThemeRGBA("#F3F4F6"),
                textSecondary: ThemeRGBA("#C4C9D1"),
                subtleText: ThemeRGBA("#8B93A1"),
                disabledText: ThemeRGBA("#5C6573"),
                disabledBackground: ThemeRGBA("#1E232C"),
                accent: ThemeRGBA("#5B8CFF"),
                accentHover: ThemeRGBA("#4A7AF0"),
                accentActive: ThemeRGBA("#3D6AE0"),
                accentSubtle: ThemeRGBA("#5B8CFF", alpha: Double(0x28) / 255),
                userBubble: ThemeRGBA("#252A33"),
                assistantBubble: ThemeRGBA("#0E1116"),
                success: ThemeRGBA("#10B981"),
                danger: ThemeRGBA("#EF4444"),
                warning: ThemeRGBA("#F59E0B"),
                toolThinkingBg: ThemeRGBA("#161A21"),
                toolThinkingText: ThemeRGBA("#C4C9D1"),
                toolSuccessBg: ThemeRGBA("#161A21"),
                toolSuccessText: ThemeRGBA("#10B981"),
                toolFailureBg: ThemeRGBA("#161A21"),
                toolFailureText: ThemeRGBA("#EF4444"),
                scrollThumb: ThemeRGBA("#6B7382"),
                scrollThumbOpacity: 0.45,
                chatBackgroundTop: ThemeRGBA("#0E1116"),
                chatBackgroundBottom: ThemeRGBA("#0E1116")
            )
        )
    }
}

enum LightAppThemePalette {
    static func create() -> AppThemePalette {
        AppThemePalette(
            kind: .light,
            chrome: UiChromeColors(
                appBackground: ThemeRGBA("#F1F5F9"),
                chrome: ThemeRGBA("#F8FAFC"),
                panel: ThemeRGBA("#FFFFFF"),
                panelAlt: ThemeRGBA("#F8FAFC"),
                composer: ThemeRGBA("#FFFFFF"),
                composerBorder: ThemeRGBA("#E2E8F0"),
                border: ThemeRGBA("#E2E8F0"),
                borderHover: ThemeRGBA("#94A3B8"),
                text: ThemeRGBA("#0F172A"),
                textSecondary: ThemeRGBA("#475569"),
                subtleText: ThemeRGBA("#64748B"),
                disabledText: ThemeRGBA("#94A3B8"),
                disabledBackground: ThemeRGBA("#E2E8F0"),
                accent: ThemeRGBA("#6366F1"),
                accentHover: ThemeRGBA("#4F46E5"),
                accentActive: ThemeRGBA("#4338CA"),
                accentSubtle: ThemeRGBA("#6366F1", alpha: Double(0x1F) / 255),
                userBubble: ThemeRGBA("#F2F2F2"),
                assistantBubble: ThemeRGBA("#F8FAFC"),
                success: ThemeRGBA("#16A34A"),
                danger: ThemeRGBA("#E11D48"),
                warning: ThemeRGBA("#F59E0B"),
                toolThinkingBg: ThemeRGBA("#F5F3FF"),
                toolThinkingText: ThemeRGBA("#475569"),
                toolSuccessBg: ThemeRGBA("#F0FDF4"),
                toolSuccessText: ThemeRGBA("#15803D"),
                toolFailureBg: ThemeRGBA("#FFF1F2"),
                toolFailureText: ThemeRGBA("#BE123C"),
                scrollThumb: ThemeRGBA("#64748B"),
                scrollThumbOpacity: 0.40,
                chatBackgroundTop: ThemeRGBA("#F8FAFC"),
                chatBackgroundBottom: ThemeRGBA("#F8FAFC")
            )
        )
    }
}

@Observable
final class AppThemeManager {
    var kind: ThemeKind
    var palette: AppThemePalette

    var chrome: UiChromeColors { palette.chrome }
    var accent: ThemeRGBA { chrome.accent }

    init(kind: ThemeKind = .dark) {
        self.kind = kind
        self.palette = kind == .light ? LightAppThemePalette.create() : DarkAppThemePalette.create()
    }

    func apply(_ kind: ThemeKind) {
        self.kind = kind
        palette = kind == .light ? LightAppThemePalette.create() : DarkAppThemePalette.create()
    }

    func applyFromSettings(_ ui: UiSettings) {
        apply(ThemeKind.parse(ui.theme))
    }

    func setTheme(_ kind: ThemeKind, uiSettings: inout UiSettings?) {
        if uiSettings != nil {
            uiSettings?.theme = kind == .light ? "Light" : "Dark"
        }
        apply(kind)
    }

    /// CSS custom properties injected into the chat WKWebView shell.
    func chatThemeTokenCSS() -> String {
        let isLight = kind == .light
        let c = chrome
        let scrollThumb = ThemeRGBA(c.scrollThumb.hex, alpha: c.scrollThumbOpacity)
        return """
        :root {
          --chat-bg: \(c.chatBackgroundTop.hex);
          --assistant-text: \(isLight ? "#1E293B" : "#F4F4F5");
          --scroll-thumb: \(scrollThumb.cssRGBA);
          --user-bubble: \(c.userBubble.hex);
          --user-bubble-text: \(c.text.hex);
          --reasoning-border: \(isLight ? "rgba(221,214,254,0.7)" : "rgba(139,92,246,0.25)");
          --reasoning-bg: \(isLight ? "rgba(245,243,255,0.5)" : "rgba(46,16,101,0.3)");
          --reasoning-ring: \(isLight ? "rgba(237,233,254,0.6)" : "rgba(139,92,246,0.15)");
          --reasoning-summary: \(isLight ? "#4C1D95" : "#EDE9FE");
          --reasoning-text: \(isLight ? "#334155" : "#D4D4D8");
          --subtle-text: \(c.subtleText.hex);
          --border: \(c.border.hex);
          --panel: \(c.panel.hex);
          --tool-thinking-bg: \(c.toolThinkingBg.hex);
          --tool-thinking-text: \(c.toolThinkingText.hex);
          --tool-success-bg: \(c.toolSuccessBg.hex);
          --tool-success-text: \(c.toolSuccessText.hex);
          --tool-failure-bg: \(c.toolFailureBg.hex);
          --tool-failure-text: \(c.toolFailureText.hex);
          --diff-add-bg: \(ThemeRGBA(c.success.hex, alpha: 0.12).cssRGBA);
          --diff-del-bg: \(ThemeRGBA(c.danger.hex, alpha: 0.12).cssRGBA);
          --diff-add-text: \(c.success.hex);
          --diff-del-text: \(c.danger.hex);
          --md-link: \(c.accent.hex);
          --md-inline-code-bg: \(isLight ? "#F1F5F9" : "#18181B");
          --md-text: \(isLight ? "#1E293B" : "#F4F4F5");
          --md-code-block-border: \(c.border.hex);
          --md-code-block-bg: \(isLight ? "#F8FAFC" : "#18181B");
          --md-code-header: \(c.subtleText.hex);
          --md-code-btn-border: \(c.border.hex);
          --md-code-btn-bg: \(c.panel.hex);
          --md-code-btn-color: \(c.textSecondary.hex);
          --md-code-pre: \(isLight ? "#24292F" : "#F1F5F9");
          --md-table-border: \(c.border.hex);
          --md-table-header-bg: \(c.panelAlt.hex);
          --md-blockquote-color: \(c.subtleText.hex);
          --md-blockquote-bg: \(c.panelAlt.hex);
          --accent: \(c.accent.hex);
        }
        """
    }

    func codeSyntaxOverrideCSS() -> String {
        guard kind == .light else { return "" }
        return """
        .code-block pre,
        .code-block pre code,
        .code-block pre code.hljs {
          color: #24292F !important;
          background: #F8FAFC !important;
        }
        .code-block .hljs-comment,
        .code-block .hljs-quote {
          color: #57606A !important;
        }
        .code-block .hljs-keyword,
        .code-block .hljs-selector-tag,
        .code-block .hljs-subst {
          color: #CF222E !important;
        }
        .code-block .hljs-string,
        .code-block .hljs-doctag,
        .code-block .hljs-regexp {
          color: #0A3069 !important;
        }
        .code-block .hljs-title,
        .code-block .hljs-section,
        .code-block .hljs-selector-id {
          color: #8250DF !important;
        }
        .code-block .hljs-variable,
        .code-block .hljs-template-variable,
        .code-block .hljs-attribute,
        .code-block .hljs-name {
          color: #953800 !important;
        }
        .code-block .hljs-number,
        .code-block .hljs-literal,
        .code-block .hljs-type,
        .code-block .hljs-built_in,
        .code-block .hljs-builtin-name,
        .code-block .hljs-symbol,
        .code-block .hljs-bullet {
          color: #0550AE !important;
        }
        """
    }
}
