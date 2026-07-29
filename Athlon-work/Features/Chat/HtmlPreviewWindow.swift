import AppKit
import WebKit

/// Secondary WKWebView window for arbitrary HTML preview.
@MainActor
final class HtmlPreviewWindowController: NSWindowController {
    convenience init(html: String, title: String = "HTML Preview", baseURL: URL? = nil) {
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
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
