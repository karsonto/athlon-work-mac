// AthlonAgent/Views/CodeEditorContentView.swift
import SwiftUI
import AppKit

// MARK: - Language Recognition
enum CodeLanguage: String, CaseIterable {
    case swift, kotlin, java, python, javascript, typescript, css, html, xml, markdown, json, yaml, dockerfile, csharp, cpp, c, rust, go, ruby, php, sql, shell

    static func from(filePath: String) -> CodeLanguage? {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let name = (filePath as NSString).lastPathComponent.lowercased()
        let map: [String: CodeLanguage] = [
            "swift": .swift, "kt": .kotlin, "kts": .kotlin,
            "java": .java, "py": .python,
            "js": .javascript, "jsx": .javascript, "mjs": .javascript,
            "ts": .typescript, "tsx": .typescript,
            "css": .css, "scss": .css, "less": .css,
            "html": .html, "htm": .html,
            "xml": .xml, "plist": .xml, "xaml": .xml, "svg": .xml,
            "md": .markdown, "markdown": .markdown,
            "json": .json,
            "yaml": .yaml, "yml": .yaml,
            "dockerfile": .dockerfile,
            "cs": .csharp,
            "cpp": .cpp, "cxx": .cpp, "cc": .cpp,
            "c": .c, "h": .c, "hpp": .cpp,
            "rs": .rust,
            "go": .go,
            "rb": .ruby,
            "php": .php,
            "sql": .sql,
            "sh": .shell, "bash": .shell, "zsh": .shell,
        ]
        if let lang = map[ext] { return lang }
        let baseName = name.hasPrefix("dockerfile") ? "dockerfile" : nil
        if let baseName, let lang = map[baseName] { return lang }
        return nil
    }
}

// MARK: - Syntax Highlight Colors (light/dark aware)
struct EditorSyntaxColors {
    let text: NSColor
    let keyword: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let type: NSColor
    let function: NSColor
    let property: NSColor
    let lineNumber: NSColor
    let selectionBackground: NSColor
    let currentLineBackground: NSColor
    let background: NSColor

    static func dark() -> EditorSyntaxColors {
        EditorSyntaxColors(
            text: NSColor(white: 0.92, alpha: 1),
            keyword: NSColor(red: 0.82, green: 0.35, blue: 0.82, alpha: 1),    // magenta
            string: NSColor(red: 0.74, green: 0.58, blue: 0.28, alpha: 1),      // orange-yellow
            comment: NSColor(red: 0.38, green: 0.48, blue: 0.38, alpha: 1),     // gray-green
            number: NSColor(red: 0.55, green: 0.65, blue: 0.95, alpha: 1),      // light blue
            type: NSColor(red: 0.35, green: 0.75, blue: 0.85, alpha: 1),        // cyan
            function: NSColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 1),    // blue
            property: NSColor(red: 0.75, green: 0.50, blue: 0.90, alpha: 1),    // purple
            lineNumber: NSColor(white: 0.45, alpha: 1),
            selectionBackground: NSColor(white: 0.25, alpha: 0.6),
            currentLineBackground: NSColor(white: 0.15, alpha: 0.5),
            background: NSColor(red: 0.1176, green: 0.1176, blue: 0.1176, alpha: 1) // #1E1E1E
        )
    }

    static func light() -> EditorSyntaxColors {
        EditorSyntaxColors(
            text: NSColor(white: 0.15, alpha: 1),
            keyword: NSColor(red: 0.63, green: 0.08, blue: 0.62, alpha: 1),
            string: NSColor(red: 0.72, green: 0.35, blue: 0.05, alpha: 1),
            comment: NSColor(red: 0.25, green: 0.42, blue: 0.18, alpha: 1),
            number: NSColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1),
            type: NSColor(red: 0.10, green: 0.50, blue: 0.60, alpha: 1),
            function: NSColor(red: 0.20, green: 0.40, blue: 0.70, alpha: 1),
            property: NSColor(red: 0.50, green: 0.20, blue: 0.70, alpha: 1),
            lineNumber: NSColor(white: 0.55, alpha: 1),
            selectionBackground: NSColor(white: 0.80, alpha: 0.5),
            currentLineBackground: NSColor(white: 0.92, alpha: 0.6),
            background: NSColor(white: 0.97, alpha: 1)
        )
    }
}

// MARK: - Simple Regex-based Tokenizer
struct SimpleSyntaxTokenizer {
    let language: CodeLanguage?

    private struct TokenRule {
        let pattern: String
        let attributeKey: NSAttributedString.Key
    }

    func highlight(_ text: String, colors: EditorSyntaxColors) -> NSAttributedString {
        guard let _ = language else {
            return NSAttributedString(string: text, attributes: [.foregroundColor: colors.text])
        }
        let result = NSMutableAttributedString(string: text, attributes: [.foregroundColor: colors.text, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
        // Apply highlighting by extension-based rules
        let rules = tokenRules(for: colors)
        let nsText = text as NSString
        for rule in rules {
            do {
                let regex = try NSRegularExpression(pattern: rule.pattern, options: [])
                regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
                    guard let range = match?.range else { return }
                    result.addAttribute(rule.attributeKey, value: colorsForAttr(rule.attributeKey, colors: colors), range: range)
                }
            } catch {}
        }
        return result
    }

    private func tokenRules(for colors: EditorSyntaxColors) -> [TokenRule] {
        // Single-line comments
        var rules: [(String, NSAttributedString.Key)] = [
            ("//.*", .foregroundColor),
            ("#.*", .foregroundColor),
            ("--.*", .foregroundColor),
            ("\"\"\"[^\"]*\"\"\"", .foregroundColor),
        ]
        // Keywords common across languages
        let keywords = "\\b(func|let|var|if|else|for|while|return|class|struct|enum|protocol|import|guard|switch|case|break|continue|async|await|try|throw|catch|in|where|true|false|nil|self|Self|public|private|internal|fileprivate|open|static|override|mutating|nonmutating|indirect|lazy|weak|unowned|required|convenience|dynamic|final|extension|subscript|init|deinit|operator|precedencegroup|associatedtype|typealias|throws|rethrows|do|repeat|default)\\b"
        rules.append((keywords, .foregroundColor))

        // Strings
        rules.append(("\"[^\"]*\"", .foregroundColor))
        rules.append(("'[^']*'", .foregroundColor))
        rules.append(("`[^`]*`", .foregroundColor))

        // Numbers
        rules.append(("\\b[0-9]+(\\.[0-9]+)?\\b", .foregroundColor))

        return rules.map { TokenRule(pattern: $0.0, attributeKey: $0.1) }
    }

    private func colorsForAttr(_ key: NSAttributedString.Key, colors: EditorSyntaxColors) -> NSColor {
        // Simplified: use appropriate color per category
        switch key {
        case .foregroundColor: return colors.text
        default: return colors.text
        }
    }
}

// MARK: - NSViewRepresentable Code Editor
struct CodeEditorContentView: NSViewRepresentable {
    @Binding var text: String
    let isReadOnly: Bool
    let filePath: String
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        applyColors(textView: textView, isDark: isDark)
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyHighlighting()
        }
        if textView.isEditable == isReadOnly {
            textView.isEditable = !isReadOnly
        }
        applyColors(textView: textView, isDark: isDark)
    }

    private func applyColors(textView: NSTextView, isDark: Bool) {
        let colors = isDark ? EditorSyntaxColors.dark() : EditorSyntaxColors.light()
        textView.backgroundColor = colors.background
        textView.insertionPointColor = colors.text
        textView.selectedTextAttributes = [.backgroundColor: colors.selectionBackground]
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorContentView
        weak var textView: NSTextView?

        init(_ parent: CodeEditorContentView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            applyHighlighting()
        }

        func applyHighlighting() {
            guard let textView else { return }
            let lang = CodeLanguage.from(filePath: parent.filePath)
            let colors = parent.isDark ? EditorSyntaxColors.dark() : EditorSyntaxColors.light()
            let tokenizer = SimpleSyntaxTokenizer(language: lang)
            let attributed = tokenizer.highlight(textView.string, colors: colors)
            textView.textStorage?.setAttributedString(attributed)
        }
    }
}
