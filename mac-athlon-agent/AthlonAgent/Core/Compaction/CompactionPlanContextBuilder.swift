import Foundation

/// Injects active plan state into compaction summaries so long-running work survives context compression.
enum CompactionPlanContextBuilder {
    static func buildSummaryPromptAppendix(_ plan: AgentPlan?) -> String? {
        guard let plan else { return nil }

        var lines: [String] = []
        lines.append("<active_plan_snapshot>")
        lines.append(
            "The following plan is still active. Your extracted summary MUST preserve session intent, " +
            "artifacts, and next steps aligned with this plan. Do not mark subtasks done unless already finished."
        )
        lines.append("")
        lines.append(PlanMarkdownFormatter.toMarkdown(plan, detailed: true))
        appendIncompleteSubtasksSection(to: &lines, plan: plan)
        lines.append("</active_plan_snapshot>")
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func enrichSummaryText(_ summary: String, plan: AgentPlan?) -> String {
        guard let appendix = buildPersistedAppendix(plan) else { return summary }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n---\n\n" + appendix
    }

    private static func buildPersistedAppendix(_ plan: AgentPlan?) -> String? {
        guard let plan else { return nil }

        var lines: [String] = []
        lines.append("[Active plan snapshot — continue from this plan after compression]")
        lines.append("")
        lines.append(PlanMarkdownFormatter.toMarkdown(plan, detailed: true))
        appendIncompleteSubtasksSection(to: &lines, plan: plan)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendIncompleteSubtasksSection(to lines: inout [String], plan: AgentPlan) {
        let incomplete = plan.subtasks.filter { subtask in
            subtask.status == .pending || subtask.status == .inProgress
        }
        guard !incomplete.isEmpty else { return }

        lines.append("")
        lines.append("## Incomplete subtasks (must remain open in summary)")
        for subtask in incomplete {
            let marker = subtask.status == .inProgress ? "[IN PROGRESS]" : "[TODO]"
            lines.append("- \(marker) **\(subtask.name)**: \(subtask.description)")
            lines.append("  - Expected outcome: \(subtask.expectedOutcome)")
        }
    }
}
