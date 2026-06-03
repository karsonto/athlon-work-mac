import AppKit
import WebKit

enum MermaidMarkdownExtractor {
    static func extractDiagrams(from markdown: String) -> [String] {
        let pattern = #"```mermaid\s*([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let bodyRange = Range(match.range(at: 1), in: markdown) else { return nil }
            let body = String(markdown[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }
    }
}

enum MermaidPreviewWindow {
    static func show(markdown: String, isDark: Bool) {
        let diagrams = MermaidMarkdownExtractor.extractDiagrams(from: markdown)
        guard !diagrams.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无法预览"
            alert.informativeText = "未找到 ```mermaid 代码块。"
            alert.runModal()
            return
        }

        guard Bundle.main.url(forResource: "mermaid.min", withExtension: "js") != nil else {
            let alert = NSAlert()
            alert.messageText = "无法预览"
            alert.informativeText = "缺少离线 Mermaid 资源（mermaid.min.js）。"
            alert.runModal()
            return
        }

        let panel = MermaidPreviewPanel(diagrams: diagrams, isDark: isDark)
        panel.show()
    }
}

private final class MermaidPreviewPanel: NSWindow {
    init(diagrams: [String], isDark: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Mermaid 图表预览"
        center()
        contentView = MermaidPreviewHostingView(diagrams: diagrams, isDark: isDark)
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }
}

private final class MermaidPreviewHostingView: NSView {
    init(diagrams: [String], isDark: Bool) {
        super.init(frame: .zero)
        let webView = WKWebView(frame: bounds)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        let blocks = diagrams.enumerated().map { index, code in
            """
            <section class="diagram">
            <h3>图表 \(index + 1)</h3>
            <pre class="mermaid">\(escapeHTML(code))</pre>
            </section>
            """
        }.joined(separator: "\n")

        let theme = isDark ? "dark" : "default"
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <script src="mermaid.min.js"></script>
        <style>
        body { font-family: -apple-system, sans-serif; margin: 16px; background: \(isDark ? "#1e1e1e" : "#fff"); color: \(isDark ? "#ddd" : "#111"); }
        h3 { font-size: 13px; opacity: 0.8; }
        .mermaid { margin: 12px 0 24px; }
        </style>
        <script>mermaid.initialize({ startOnLoad: true, theme: '\(theme)' });</script>
        </head><body>\(blocks)</body></html>
        """
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    required init?(coder: NSCoder) { nil }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
