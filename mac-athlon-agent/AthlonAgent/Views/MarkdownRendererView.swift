import SwiftUI
import WebKit

// MARK: - Markdown Renderer (WebKit-based)
struct MarkdownRendererView: NSViewRepresentable {
    let markdownText: String
    let isDarkTheme: Bool

    init(_ markdownText: String, isDarkTheme: Bool = true) {
        self.markdownText = markdownText
        self.isDarkTheme = isDarkTheme
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "mermaidReady")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.isInspectable = true

        if #available(macOS 14.0, *) {
            webView.isInspectable = true
        }

        context.coordinator.webView = webView
        updateHTML(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        updateHTML(in: webView)
    }

    private func updateHTML(in webView: WKWebView) {
        let html = buildHTML(markdownText, isDark: isDarkTheme)
        webView.loadHTMLString(html, baseURL: nil)

        // Re-inject mermaid after load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript("""
                if (typeof mermaid !== 'undefined') {
                    mermaid.run({ querySelector: '.mermaid' });
                }
            """, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(markdownText: markdownText, isDarkTheme: isDarkTheme)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var markdownText: String
        var isDarkTheme: Bool
        weak var webView: WKWebView?

        init(markdownText: String, isDarkTheme: Bool) {
            self.markdownText = markdownText
            self.isDarkTheme = isDarkTheme
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mermaidReady" {
                // Mermaid initialized
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Post-process: dynamically set height for sizing
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let height = result as? CGFloat, height > 0 else { return }
                // Height is auto-managed by SwiftUI layout
            }

            // Run mermaid
            webView.evaluateJavaScript("""
                if (typeof mermaid !== 'undefined') {
                    mermaid.run({ querySelector: '.mermaid' });
                }
            """, completionHandler: nil)
        }
    }
}

// MARK: - HTML Builder
private func buildHTML(_ markdown: String, isDark: Bool) -> String {
    let escapedMarkdown = escapeForJavaScript(markdown)
    let theme = isDark ? darkThemeCSS : lightThemeCSS

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
    \(theme)
    \(markdownStyles)
    </style>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script>
        mermaid.initialize({
            startOnLoad: false,
            theme: '\(isDark ? "dark" : "default")',
            securityLevel: 'loose',
            fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'
        });
    </script>
    </head>
    <body>
    <div id="content"></div>
    <script>
        const md = \(escapedMarkdown);
        document.getElementById('content').innerHTML = marked.parse(md);
        if (typeof mermaid !== 'undefined') {
            mermaid.run({ querySelector: '.mermaid' });
        }
    </script>
    </body>
    </html>
    """
}

private func escapeForJavaScript(_ text: String) -> String {
    // Use JSON encoder to safely embed markdown as JS string
    let encoder = JSONEncoder()
    // Simple approach: manually escape
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "${", with: "\\${")
        .replacingOccurrences(of: "\r\n", with: "\\n")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
    return "`\(escaped)`"
}

// MARK: - Dark Theme CSS
private let darkThemeCSS = """
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}
html, body {
    background-color: #18181B;
    color: #F4F4F5;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 13px;
    line-height: 1.6;
    padding: 8px 0;
}
a { color: #6366F1; text-decoration: none; }
a:hover { text-decoration: underline; }
h1, h2, h3, h4, h5, h6 { color: #F4F4F5; margin: 16px 0 8px; font-weight: 600; }
h1 { font-size: 1.5em; border-bottom: 1px solid #3F3F46; padding-bottom: 8px; }
h2 { font-size: 1.3em; }
h3 { font-size: 1.1em; }
h4 { font-size: 1em; }
p { margin: 4px 0; }
ul, ol { margin: 8px 0; padding-left: 24px; }
li { margin: 2px 0; }
blockquote {
    border-left: 3px solid #6366F1;
    padding: 4px 12px;
    margin: 8px 0;
    color: #A1A1AA;
    background: rgba(99,102,241,0.05);
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 8px 0;
}
th, td {
    border: 1px solid #3F3F46;
    padding: 6px 10px;
    text-align: left;
    font-size: 12px;
}
th { background: #27272A; color: #A1A1AA; font-weight: 600; }
td { background: #1A1A1E; }
img { max-width: 100%; border-radius: 6px; }
hr { border: none; border-top: 1px solid #3F3F46; margin: 12px 0; }
strong { color: #FAFAFA; font-weight: 600; }
em { color: #D4D4D8; }
"""

// MARK: - Light Theme CSS
private let lightThemeCSS = """
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}
html, body {
    background-color: #FFFFFF;
    color: #1F2937;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 13px;
    line-height: 1.6;
    padding: 8px 0;
}
a { color: #4F46E5; text-decoration: none; }
a:hover { text-decoration: underline; }
h1, h2, h3, h4, h5, h6 { color: #111827; margin: 16px 0 8px; font-weight: 600; }
h1 { font-size: 1.5em; border-bottom: 1px solid #E5E7EB; padding-bottom: 8px; }
h2 { font-size: 1.3em; }
h3 { font-size: 1.1em; }
h4 { font-size: 1em; }
p { margin: 4px 0; }
ul, ol { margin: 8px 0; padding-left: 24px; }
li { margin: 2px 0; }
blockquote {
    border-left: 3px solid #4F46E5;
    padding: 4px 12px;
    margin: 8px 0;
    color: #6B7280;
    background: rgba(79,70,229,0.05);
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 8px 0;
}
th, td {
    border: 1px solid #E5E7EB;
    padding: 6px 10px;
    text-align: left;
    font-size: 12px;
}
th { background: #F9FAFB; color: #6B7280; font-weight: 600; }
td { background: #FFFFFF; }
img { max-width: 100%; border-radius: 6px; }
hr { border: none; border-top: 1px solid #E5E7EB; margin: 12px 0; }
strong { color: #111827; font-weight: 600; }
em { color: #374151; }
"""

// MARK: - Code / Mermaid styles
private let markdownStyles = """
/* Code blocks */
code {
    background: #27272A;
    color: #F4F4F5;
    padding: 2px 6px;
    border-radius: 4px;
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 12px;
}
pre {
    background: #1A1A1E;
    border: 1px solid #3F3F46;
    border-radius: 8px;
    padding: 12px;
    margin: 8px 0;
    overflow-x: auto;
}
pre code {
    background: none;
    padding: 0;
    font-size: 12px;
    line-height: 1.5;
}

/* Mermaid diagrams */
.mermaid {
    margin: 12px 0;
    padding: 16px;
    background: #1A1A1E;
    border: 1px solid #3F3F46;
    border-radius: 8px;
    text-align: center;
}
.mermaid svg {
    max-width: 100%;
    height: auto;
}

/* Scrollbar */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #3F3F46; border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: #52525B; }
"""

// MARK: - Convenience SwiftUI View
struct MarkdownContent: View {
    let text: String
    let isDarkTheme: Bool

    var body: some View {
        if text.contains("```mermaid") {
            MarkdownRendererView(text, isDarkTheme: isDarkTheme)
                .frame(minHeight: 120)
        } else if hasMarkdownSyntax(text) {
            MarkdownRendererView(text, isDarkTheme: isDarkTheme)
                .frame(minHeight: 20)
        } else {
            // Plain text fallback
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }

    private func hasMarkdownSyntax(_ text: String) -> Bool {
        let markers = ["**", "__", "`", "#", "- ", "* ", "1.", "> ", "\\[", "![", "|", "~~"]
        return markers.contains(where: text.contains)
    }
}

// MARK: - Markdown Text View (editable area)
struct MarkdownToolbar: View {
    let onInsert: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolbarButton("B", title: "粗体") { onInsert("****") }
            toolbarButton("I", title: "斜体", italic: true) { onInsert("__") }
            toolbarButton("`", title: "代码") { onInsert("``") }
            toolbarButton("~~", title: "删除线") { onInsert("~~~~") }
            Divider().frame(height: 16).padding(.horizontal, 4)
            toolbarButton("#", title: "标题") { onInsert("# ") }
            toolbarButton("•", title: "列表") { onInsert("- ") }
            toolbarButton("1.", title: "编号") { onInsert("1. ") }
            toolbarButton(">", title: "引用") { onInsert("> ") }
            Divider().frame(height: 16).padding(.horizontal, 4)
            toolbarButton("```", title: "代码块") { onInsert("```\n\n```") }
            toolbarButton("📊", title: "Mermaid") { onInsert("```mermaid\ngraph TD\n  A --> B\n```") }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "#1A1A1E"))
        .overlay(Rectangle().fill(Color(hex: "#3F3F46")).frame(height: 1), alignment: .top)
    }

    private func toolbarButton(_ text: String, title: String, italic: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: italic ? .regular : .medium))
                .italic(italic)
                .frame(minWidth: 24, minHeight: 22)
                .foregroundColor(Color(hex: "#A1A1AA"))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.05))
        )
        .help(title)
    }
}
