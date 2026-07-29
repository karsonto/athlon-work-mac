import Foundation

/// Builds the WKWebView chat shell HTML (AG-UI timeline + theme tokens).
struct ChatHtmlBuilder {
    var themeManager: AppThemeManager
    var assetBaseURL: String

    init(themeManager: AppThemeManager = AppThemeManager(), assetBaseURL: String = "./") {
        self.themeManager = themeManager
        self.assetBaseURL = assetBaseURL.hasSuffix("/") ? assetBaseURL : assetBaseURL + "/"
    }

    /// Relative asset paths under `Resources/Chat/`.
    func highlightStylesheetName() -> String {
        themeManager.kind == .light ? "github.min.css" : "github-dark.min.css"
    }

    func buildShellHTML() -> String {
        let assets = assetBaseURL
        let highlight = highlightStylesheetName()
        return """
        <!DOCTYPE html><html><head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
        <link rel="stylesheet" href="\(assets)\(highlight)" id="hljs-theme"/>
        <link rel="stylesheet" href="\(assets)chat-shell.css"/>
        <style id="chat-theme-tokens">\(themeManager.chatThemeTokenCSS())</style>
        <style id="chat-code-syntax">\(themeManager.codeSyntaxOverrideCSS())</style>
        </head><body>
        <div id="chat-scroll">
        <div id="empty-state" class="empty-state" aria-hidden="true"></div>
        <button id="load-older" type="button" hidden></button>
        <div id="messages"></div>
        </div>
        <div id="image-lightbox" class="image-lightbox" hidden>
        <button type="button" class="image-lightbox-backdrop" aria-label="Close"></button>
        <img class="image-lightbox-img" alt=""/>
        <button type="button" class="image-lightbox-close" aria-label="Close">×</button>
        </div>
        <script src="\(assets)highlight.min.js"></script>
        <script src="\(assets)marked.min.js"></script>
        <script>\(buildI18nBootstrapScript())</script>
        <script src="\(assets)chat-timeline.js"></script>
        </body></html>
        """
    }

    func buildDispatchScript(_ streamEvent: AgentStreamEvent) -> String {
        "handleEvent(\(ChatEventSerializer.serialize(streamEvent)));"
    }

    /// Updates chat theme tokens in-place so theme switches do not reload the timeline.
    func buildThemeUpdateScript() -> String {
        let highlightHref = "\(assetBaseURL)\(highlightStylesheetName())"
        let tokensB64 = Data(themeManager.chatThemeTokenCSS().utf8).base64EncodedString()
        let syntaxB64 = Data(themeManager.codeSyntaxOverrideCSS().utf8).base64EncodedString()
        let hrefJSON = jsonString(highlightHref)
        let tokensJSON = jsonString(tokensB64)
        let syntaxJSON = jsonString(syntaxB64)
        return "applyThemeUpdate(\(hrefJSON), \(tokensJSON), \(syntaxJSON));"
    }

    func buildI18nUpdateScript() -> String {
        let i18nJSON = chatI18nJSON()
        return "window.__chatI18n=\(i18nJSON);if(typeof applyChatI18n==='function')applyChatI18n();"
    }

    func buildReplayDocumentHTML(eventJSONArray: String) -> String {
        let shell = buildShellHTML()
        let footer = "</body></html>"
        guard shell.hasSuffix(footer) else { return shell }
        let payload = Data(eventJSONArray.utf8).base64EncodedString()
        let replayScript = """
        <script>
        (function(){
          try {
            var binary = atob("\(payload)");
            var bytes = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            replayEvents(JSON.parse(new TextDecoder('utf-8').decode(bytes)));
          } catch (e) {
            console.error("replayEvents failed", e);
          }
        })();
        </script>
        \(footer)
        """
        return String(shell.dropLast(footer.count)) + replayScript
    }

    // MARK: - i18n (default zh-CN)

    private func buildI18nBootstrapScript() -> String {
        "window.__chatI18n=" + chatI18nJSON() + ";"
    }

    private func chatI18nJSON() -> String {
        let map = defaultZhCNI18n()
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    func defaultZhCNI18n() -> [String: String] {
        [
            "copy": "复制",
            "copied": "已复制",
            "preview": "预览",
            "code": "代码",
            "thinking": "正在思考",
            "thought": "已思考",
            "seconds": "{0}秒",
            "welcomeTitle": "开始新的对话",
            "welcomeTitleWithName": "你好，{0}",
            "welcomeDescription": "Athlon Agent 可以帮您分析代码、生成原型、优化设计，或执行任何开发任务。",
            "loadOlder": "更早…",
            "approvalTitle": "需要批准才能执行",
            "approvalDescription": "请检查工具和参数，然后选择是否允许本次执行。",
            "approvalPending": "等待批准",
            "approve": "允许",
            "deny": "拒绝",
            "allowedStatus": "已允许",
            "deniedStatus": "已拒绝",
            "approved": "已允许，本次工具将继续执行",
            "denied": "已拒绝，本次工具不会执行",
            "filesChangedOne": "1 个文件已修改",
            "filesChangedMany": "{0} 个文件已修改",
            "editedFilesOne": "编辑了 1 个文件",
            "editedFilesMany": "编辑了 {0} 个文件",
            "exploredFilesOne": "查看了 1 个文件",
            "exploredFilesMany": "查看了 {0} 个文件",
            "searchesOne": "1 次搜索",
            "searchesMany": "{0} 次搜索",
            "commandsOne": "运行了 1 条命令",
            "commandsMany": "运行了 {0} 条命令",
            "thoughtsOne": "思考了 1 次",
            "thoughtsMany": "思考了 {0} 次",
            "unmodifiedLines": "{0} 行未修改",
            "noDiffAvailable": "暂无可用 diff",
        ]
    }

    /// Encodes a Swift string as a JSON string literal (quoted + escaped) for embedding in JS.
    private func jsonString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
