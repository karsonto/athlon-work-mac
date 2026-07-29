import Foundation

/// Renders skill bodies into an XML-ish prompt section for the system prompt.
nonisolated enum SkillPromptRenderer {
    static func render(skills: [(info: AvailableSkillInfo, body: String)]) -> String {
        guard !skills.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("<available_skills>")
        for item in skills {
            let name = escape(item.info.name)
            let desc = escape(item.info.description)
            lines.append("<skill name=\"\(name)\" description=\"\(desc)\">")
            lines.append(item.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("</skill>")
        }
        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    static func renderFromCatalog(
        catalog: SkillCatalog,
        settings: AppSettings,
        maxBodyChars: Int = 12_000
    ) -> String {
        let available = catalog.listAvailableSkills(settings: settings).filter(\.enabled)
        var pairs: [(AvailableSkillInfo, String)] = []
        for info in available {
            guard var body = catalog.loadSkillBody(info: info) else { continue }
            if body.count > maxBodyChars {
                body = String(body.prefix(maxBodyChars)) + "\n…(truncated)"
            }
            pairs.append((info, body))
        }
        return render(skills: pairs)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
