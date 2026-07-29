import AppKit
import WebKit

/// Opens a secondary window with WKWebView rendering Mermaid diagrams.
@MainActor
final class MermaidPreviewWindowController: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!

    convenience init(source: String, title: String = "Mermaid Preview") {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = webView
        window.center()
        self.init(window: window)
        self.webView = webView
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.html(for: source), baseURL: Self.mermaidBaseURL())
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func mermaidBaseURL() -> URL? {
        if let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid") {
            return url.deletingLastPathComponent()
        }
        if let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") {
            return url.deletingLastPathComponent()
        }
        // Dev fallback: Resources/Mermaid next to sources
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Chat
            .deletingLastPathComponent() // Features
            .appendingPathComponent("Resources/Mermaid", isDirectory: true)
        return fallback
    }

    static func html(for source: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <script src="mermaid.min.js"></script>
          <style>
            body { margin: 16px; background: #111; color: #eee; }
            .mermaid { background: #1a1a1a; padding: 16px; border-radius: 8px; }
          </style>
        </head>
        <body>
          <pre class="mermaid">
        \(escaped)
          </pre>
          <script>
            mermaid.initialize({ startOnLoad: true, theme: 'dark' });
          </script>
        </body>
        </html>
        """
    }
}
