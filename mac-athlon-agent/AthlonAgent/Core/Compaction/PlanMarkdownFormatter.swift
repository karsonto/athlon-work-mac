import Foundation

/// Formats persisted `AgentPlan` snapshots for compaction context (not interactive plan mode).
enum PlanMarkdownFormatter {
    static func toMarkdown(_ plan: AgentPlan, detailed: Bool) -> String {
        var lines: [String] = []
        lines.append("# Plan: \(plan.name)")
        lines.append("")

        if !plan.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("> \(plan.description.trimmingCharacters(in: .whitespacesAndNewlines))")
            lines.append("")
        }

        appendSection(&lines, title: "Overview", body: plan.overview)
        appendSection(&lines, title: "Architecture", body: plan.architecture)
        appendMermaidSection(&lines, mermaid: plan.mermaid)
        appendSection(&lines, title: "Testing Strategy", body: plan.testingStrategy)
        appendSection(&lines, title: "Out of Scope", body: plan.outOfScope)

        if !plan.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendSection(&lines, title: "Expected Outcome", body: plan.expectedOutcome)
        }

        if plan.subtasks.isEmpty {
            lines.append("_No implementation steps._")
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        lines.append("---")
        lines.append("")
        lines.append(detailed ? "## Implementation Plan" : "## Subtasks")
        lines.append("")

        for (index, subtask) in plan.subtasks.enumerated() {
            if detailed {
                lines.append(formatSubtaskDetailed(index: index, subtask: subtask))
                lines.append("")
            } else {
                lines.append(formatSubtaskOneLine(subtask))
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendSection(_ lines: inout [String], title: String, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append("## \(title)")
        lines.append("")
        lines.append(trimmed)
        lines.append("")
    }

    private static func appendMermaidSection(_ lines: inout [String], mermaid: String) {
        let trimmed = mermaid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append("## Architecture Diagram")
        lines.append("")
        lines.append("```mermaid")
        lines.append(trimmed)
        lines.append("```")
        lines.append("")
    }

    private static func formatSubtaskOneLine(_ subtask: PlanSubtask) -> String {
        let prefix: String
        switch subtask.status {
        case .pending: prefix = "- [ ]"
        case .inProgress: prefix = "- [ ] [WIP]"
        case .done: prefix = "- [x]"
        case .abandoned: prefix = "- [ ] [Abandoned]"
        }
        return "\(prefix) \(subtask.name)"
    }

    private static func formatSubtaskDetailed(index: Int, subtask: PlanSubtask) -> String {
        var lines: [String] = []
        lines.append("### \(index + 1). \(formatSubtaskOneLine(subtask))")
        if !subtask.files.isEmpty {
            let files = subtask.files.map { "`\($0)`" }.joined(separator: ", ")
            lines.append("- **Files:** \(files)")
        }
        lines.append("- **Description:** \(subtask.description)")
        lines.append("- **Acceptance:** \(subtask.expectedOutcome)")
        lines.append("- **State:** \(subtask.status.rawValue)")
        if let outcome = subtask.outcome, !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- **Outcome:** \(outcome)")
        }
        return lines.joined(separator: "\n")
    }
}
