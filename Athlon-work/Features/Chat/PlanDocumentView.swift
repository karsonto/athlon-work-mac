import AppKit
import SwiftUI
import WebKit

struct PlanDocumentView: NSViewRepresentable {
    var html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Secondary window host for plan markdown/HTML.
@MainActor
final class PlanDocumentWindowController: NSWindowController {
    convenience init(markdownOrHtml: String, title: String = "Plan") {
        let html = PlanDocumentHtmlBuilder.build(markdownOrHtml: markdownOrHtml, title: title)
        let hosting = NSHostingView(rootView: PlanDocumentView(html: html).frame(minWidth: 640, minHeight: 480))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hosting
        window.center()
        self.init(window: window)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
