import AppKit
import WebKit

enum HtmlPreviewWindow {
    static func show(html: String, title: String = "HTML 预览", isDark: Bool) {
        let panel = HtmlPreviewPanel(html: html, title: title, isDark: isDark)
        panel.show()
    }
}

private final class HtmlPreviewPanel: NSWindow {
    init(html: String, title: String, isDark: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = title
        center()
        contentView = HtmlPreviewHostingView(html: html, isDark: isDark)
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }
}

private final class HtmlPreviewHostingView: NSView {
    init(html: String, isDark: Bool) {
        super.init(frame: .zero)
        let webView = WKWebView(frame: bounds)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        let bodyBg = isDark ? "#1e1e1e" : "#ffffff"
        let bodyColor = isDark ? "#e4e4e7" : "#0f172a"
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>body{font-family:-apple-system,sans-serif;margin:16px;background:\(bodyBg);color:\(bodyColor);}</style>
        </head><body>\(html)</body></html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    required init?(coder: NSCoder) { nil }
}
