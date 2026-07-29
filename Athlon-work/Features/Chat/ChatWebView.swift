import AppKit
import SwiftUI
import WebKit

/// Imperative bridge for injecting AG-UI events into the chat WKWebView.
@MainActor
final class ChatWebViewBridge {
    weak var webView: WKWebView?
    var themeManager: AppThemeManager
    private var isDocumentReady = false
    private enum PendingScript {
        case jsonCall(function: String, argumentJSON: String, isJSONArray: Bool)
        case raw(String)
    }
    private var pendingScripts: [PendingScript] = []

    init(themeManager: AppThemeManager = AppThemeManager()) {
        self.themeManager = themeManager
    }

    func markReady() {
        isDocumentReady = true
        flushPending()
    }

    func resetReadyState() {
        isDocumentReady = false
        // Keep pendingScripts — events may be queued before the WebView mounts (empty-state send).
    }

    func clearPendingScripts() {
        pendingScripts.removeAll()
    }

    func dispatchJSON(_ json: String) {
        dispatchHandleEvent(json)
    }

    func replayEventsJSON(_ eventsJSONArray: String) {
        dispatchReplayEvents(eventsJSONArray)
    }

    private func dispatchHandleEvent(_ json: String) {
        enqueueOrDispatch(function: "handleEvent", argumentJSON: json)
    }

    private func dispatchReplayEvents(_ eventsJSONArray: String) {
        enqueueOrDispatch(function: "replayEvents", argumentJSON: eventsJSONArray, isJSONArray: true)
    }

    private func enqueueOrDispatch(function: String, argumentJSON: String, isJSONArray: Bool = false) {
        guard let webView else {
            pendingScripts.append(.jsonCall(function: function, argumentJSON: argumentJSON, isJSONArray: isJSONArray))
            return
        }
        guard isDocumentReady else {
            pendingScripts.append(.jsonCall(function: function, argumentJSON: argumentJSON, isJSONArray: isJSONArray))
            return
        }
        runJSONCall(on: webView, function: function, argumentJSON: argumentJSON, isJSONArray: isJSONArray)
    }

    private func runJSONCall(
        on webView: WKWebView,
        function: String,
        argumentJSON: String,
        isJSONArray: Bool
    ) {
        if let object = parseJSONObject(argumentJSON, isJSONArray: isJSONArray) {
            let script = "\(function)(argument)"
            webView.callAsyncJavaScript(
                script,
                arguments: ["argument": object],
                in: nil,
                in: .page
            ) { result in
                if case let .failure(error) = result {
                    let nsError = error as NSError
                    let jsMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
                    let jsLine = nsError.userInfo["WKJavaScriptExceptionLineNumber"] as? Int ?? -1
                    let jsColumn = nsError.userInfo["WKJavaScriptExceptionColumnNumber"] as? Int ?? -1
                    NSLog(
                        "[ChatWebView] callAsyncJavaScript failed: %@ | js=%@ line=%d col=%d",
                        error.localizedDescription,
                        jsMessage,
                        jsLine,
                        jsColumn
                    )
                }
            }
            return
        }

        // Fallback for malformed payloads.
        let legacy = isJSONArray
            ? "\(function)(\(argumentJSON));"
            : "\(function)(\(argumentJSON));"
        webView.evaluateJavaScript(legacy, completionHandler: { _, error in
            if let error {
                NSLog("[ChatWebView] evaluate failed: %@", error.localizedDescription)
            }
        })
    }

    private func parseJSONObject(_ json: String, isJSONArray: Bool) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(
            with: data,
            options: isJSONArray ? [] : [.fragmentsAllowed]
        )
    }

    func applyThemeUpdate() {
        let script = ChatHtmlBuilder(themeManager: themeManager, assetBaseURL: "./")
            .buildThemeUpdateScript()
        evaluate(script)
    }

    func evaluate(_ script: String) {
        guard let webView else {
            pendingScripts.append(.raw(script))
            return
        }
        guard isDocumentReady else {
            pendingScripts.append(.raw(script))
            return
        }
        webView.evaluateJavaScript(script, completionHandler: { _, error in
            if let error {
                NSLog("[ChatWebView] evaluate failed: %@", error.localizedDescription)
            }
        })
    }

    private func flushPending() {
        guard let webView, isDocumentReady else { return }
        let scripts = pendingScripts
        pendingScripts.removeAll()
        for script in scripts {
            switch script {
            case let .jsonCall(function, argumentJSON, isJSONArray):
                runJSONCall(on: webView, function: function, argumentJSON: argumentJSON, isJSONArray: isJSONArray)
            case let .raw(text):
                webView.evaluateJavaScript(text, completionHandler: nil)
            }
        }
    }
}

struct ChatWebView: NSViewRepresentable {
    var bridge: ChatWebViewBridge
    var themeManager: AppThemeManager
    var onToolApproval: ((String, Bool) -> Void)?
    var onLoadOlder: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "athlon")

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        config.setValue(true, forKey: "drawsBackground")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setValue(false, forKey: "opaque")
#if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
#endif

        context.coordinator.webView = webView
        bridge.webView = webView
        bridge.themeManager = themeManager
        bridge.resetReadyState()
        context.coordinator.loadShell(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        bridge.webView = webView
        bridge.themeManager = themeManager
        if context.coordinator.lastThemeKind != themeManager.kind {
            context.coordinator.lastThemeKind = themeManager.kind
            bridge.applyThemeUpdate()
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "athlon")
        coordinator.webView = nil
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ChatWebView
        weak var webView: WKWebView?
        var lastThemeKind: ThemeKind
        private var assetBaseURL: URL?

        init(parent: ChatWebView) {
            self.parent = parent
            self.lastThemeKind = parent.themeManager.kind
        }

        func loadShell(into webView: WKWebView) {
            do {
                let baseURL = try ChatAssetProvider.ensureChatResourceDirectory()
                assetBaseURL = baseURL
                let html = ChatHtmlBuilder(
                    themeManager: parent.themeManager,
                    assetBaseURL: "./"
                ).buildShellHTML()
                webView.loadHTMLString(html, baseURL: baseURL)
            } catch {
                let fallback = """
                <!DOCTYPE html><html><body style="font-family:-apple-system;padding:24px;color:#ef4444">
                Failed to load chat assets: \(error.localizedDescription)
                </body></html>
                """
                webView.loadHTMLString(fallback, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.bridge.markReady()
            parent.bridge.applyThemeUpdate()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            parent.onOpenURL?(url)
            postHostMessage(["type": "openLink", "url": url.absoluteString])
            decisionHandler(.cancel)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "athlon" else { return }
            let body: [String: Any]
            if let dict = message.body as? [String: Any] {
                body = dict
            } else if let text = message.body as? String,
                      let data = text.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                body = dict
            } else {
                return
            }

            guard let type = body["type"] as? String else { return }
            switch type {
            case "toolApproval":
                let toolCallId = body["toolCallId"] as? String ?? ""
                let approved = body["approved"] as? Bool ?? false
                guard !toolCallId.isEmpty else { return }
                parent.onToolApproval?(toolCallId, approved)
            case "loadOlder":
                parent.onLoadOlder?()
            case "openLink":
                if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                    parent.onOpenURL?(url)
                }
            case "openImage":
                if let urlString = (body["url"] as? String) ?? (body["src"] as? String),
                   let url = URL(string: urlString) {
                    parent.onOpenURL?(url)
                }
            case "copy":
                if let text = body["text"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            default:
                break
            }
        }

        private func postHostMessage(_ payload: [String: Any]) {
            // Reserved for future host→page echo; currently unused.
            _ = payload
        }
    }
}
