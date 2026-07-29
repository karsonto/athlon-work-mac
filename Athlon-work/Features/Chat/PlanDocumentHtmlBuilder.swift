import Foundation

enum ComposerHarnessMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case agent
    case ask
    case plan
    case coding

    var id: String { rawValue }

    func title(language: String) -> String {
        switch self {
        case .agent: return L10n.t("composer.mode.agent", language: language)
        case .ask: return L10n.t("composer.mode.ask", language: language)
        case .plan: return L10n.t("composer.mode.plan", language: language)
        case .coding: return L10n.t("composer.mode.coding", language: language)
        }
    }
}

nonisolated enum PlanDocumentHtmlBuilder {
    static func build(markdownOrHtml: String, title: String = "Plan") -> String {
        let body: String
        if markdownOrHtml.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            body = markdownOrHtml
        } else {
            body = markdownToSimpleHtml(markdownOrHtml)
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>\(escape(title))</title>
        <style>
          :root { color-scheme: light dark; }
          body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                 margin: 24px; line-height: 1.55; }
          h1,h2,h3 { line-height: 1.25; }
          code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          pre { background: rgba(127,127,127,0.12); padding: 12px; border-radius: 8px; overflow: auto; }
          a { color: #0a84ff; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func markdownToSimpleHtml(_ md: String) -> String {
        var lines: [String] = []
        var inCode = false
        for line in md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("```") {
                if inCode {
                    lines.append("</code></pre>")
                } else {
                    lines.append("<pre><code>")
                }
                inCode.toggle()
                continue
            }
            if inCode {
                lines.append(escape(line))
                continue
            }
            if line.hasPrefix("### ") {
                lines.append("<h3>\(escape(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                lines.append("<h2>\(escape(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                lines.append("<h1>\(escape(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("- ") {
                lines.append("<li>\(escape(String(line.dropFirst(2))))</li>")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("<br/>")
            } else {
                lines.append("<p>\(escape(line))</p>")
            }
        }
        if inCode { lines.append("</code></pre>") }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
