import Foundation

// MARK: - Dynamic compaction settings (aligned with athlon-work)

struct DynamicCompactionSettings: Codable, Equatable {
    var enabled: Bool = true
    var targetUtilization: Double = 0.80
    var postCompactionUtilization: Double = 0.30
    var safetyMarginRatio: Double = 0.08
    var defaultReservedOutputTokens: Int = 8192
    var truncateLeadRatio: Double = 0.90
    var overflowPostCompactionUtilization: Double = 0.20
    var enableSemanticCutoff: Bool = true
    var enableUsageCalibration: Bool = true
    var usageCalibrationAlpha: Double = 0.15

    enum CodingKeys: String, CodingKey {
        case enabled
        case targetUtilization
        case postCompactionUtilization
        case safetyMarginRatio
        case defaultReservedOutputTokens
        case truncateLeadRatio
        case overflowPostCompactionUtilization
        case enableSemanticCutoff
        case enableUsageCalibration
        case usageCalibrationAlpha
    }
}

enum ContextPressureLevel: String, Codable {
    case normal = "Normal"
    case elevated = "Elevated"
    case high = "High"
    case critical = "Critical"
    case overflow = "Overflow"
}

struct ContextBudgetSnapshot: Equatable {
    let totalWindow: Int
    let reservedOutput: Int
    let fixedOverhead: Int
    let historyBudget: Int
    let estimatedHistory: Int
    let utilization: Double

    var estimatedTotalPrompt: Int { fixedOverhead + estimatedHistory }
    var usablePromptWindow: Int { max(1, totalWindow - reservedOutput) }
    var totalUtilization: Double { Double(estimatedTotalPrompt) / Double(usablePromptWindow) }
    var availableHistory: Int { max(0, historyBudget - estimatedHistory) }

    func withHistoryEstimate(_ estimatedHistory: Int, historyBudget: Int) -> ContextBudgetSnapshot {
        let budget = historyBudget > 0 ? historyBudget : self.historyBudget
        let utilization = budget > 0 ? Double(estimatedHistory) / Double(budget) : 1.0
        return ContextBudgetSnapshot(
            totalWindow: totalWindow,
            reservedOutput: reservedOutput,
            fixedOverhead: fixedOverhead,
            historyBudget: budget,
            estimatedHistory: estimatedHistory,
            utilization: utilization
        )
    }
}

struct CompactionRuntimeContext {
    var budget: ContextBudgetSnapshot
    let environmentPrompt: String
    let tools: [ToolDefinition]
    var calibrationMultiplier: Double
    var pressureOverride: ContextPressureLevel

    var forceOverflow: Bool { pressureOverride == .overflow }
}

struct DynamicCompactionPlan {
    var pressure: ContextPressureLevel
    var applyTruncateArgs: Bool
    var applyPrefixReEvict: Bool
    var applyConversationCompact: Bool
    var keepTokenBudget: Int
    var mustPreserveAppendix: String?

    static func create(
        pressure: ContextPressureLevel,
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        force: Bool
    ) -> DynamicCompactionPlan {
        let dynamic = settings.dynamicCompaction
        if !dynamic.enabled {
            return DynamicCompactionPlan(
                pressure: pressure,
                applyTruncateArgs: false,
                applyPrefixReEvict: false,
                applyConversationCompact: ContextPressureEvaluator.shouldCompact(
                    budget: budget,
                    conversation: conversation,
                    settings: settings,
                    pressure: pressure,
                    force: force
                ),
                keepTokenBudget: 0,
                mustPreserveAppendix: nil
            )
        }

        let applyTruncate = ContextPressureEvaluator.shouldApplyTruncateArgs(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let applyReEvict = ContextPressureEvaluator.shouldApplyPrefixReEvict(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let applyCompact = ContextPressureEvaluator.shouldCompact(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        )
        let keepTokenBudget = ContextPressureEvaluator.resolveKeepTokenBudget(
            budget: budget,
            pressure: pressure,
            conversation: conversation,
            settings: settings,
            includesConversationCompact: applyCompact || force
        )

        var mustPreserve: String?
        if dynamic.enableSemanticCutoff, applyCompact {
            mustPreserve = SemanticCutoffPlanner.buildMustPreserveAppendix(
                conversation: conversation,
                settings: settings,
                keepTokenBudget: keepTokenBudget
            )
        }

        return DynamicCompactionPlan(
            pressure: pressure,
            applyTruncateArgs: applyTruncate,
            applyPrefixReEvict: applyReEvict,
            applyConversationCompact: applyCompact,
            keepTokenBudget: keepTokenBudget,
            mustPreserveAppendix: mustPreserve
        )
    }
}

struct CompactionExecutionRequest {
    let kind: CompactionKind
    let force: Bool
    let emitAudit: Bool
    var runtimeContext: CompactionRuntimeContext?
    var plan: DynamicCompactionPlan?
}

enum ContextBudgetCalculator {
    static func compute(
        environmentPrompt: String,
        tools: [ToolDefinition],
        messages: [ChatMessage],
        compactionSettings: ContextCompactionSettings,
        modelSettings: ModelSettings,
        calibrationMultiplier: Double = 1.0
    ) -> ContextBudgetSnapshot {
        let dynamic = compactionSettings.dynamicCompaction
        let totalWindow = max(1, compactionSettings.contextWindowTokens)
        let reservedOutput = modelSettings.maxTokens > 0
            ? modelSettings.maxTokens
            : dynamic.defaultReservedOutputTokens

        let systemTokens = ContextTokenEstimator.estimateTextTokens(environmentPrompt, calibrationMultiplier: calibrationMultiplier)
        let toolsTokens = estimateToolsTokens(tools, calibrationMultiplier: calibrationMultiplier)
        let margin = Int(floor(Double(totalWindow) * dynamic.safetyMarginRatio))
        let fixedOverhead = systemTokens + toolsTokens + margin
        let historyBudget = max(512, totalWindow - reservedOutput - fixedOverhead)

        let conversation = filterConversation(messages)
        let estimatedHistory = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: compactionSettings.includeReasoningInModelContext,
            calibrationMultiplier: calibrationMultiplier
        )
        let utilization = historyBudget > 0 ? Double(estimatedHistory) / Double(historyBudget) : 1.0

        return ContextBudgetSnapshot(
            totalWindow: totalWindow,
            reservedOutput: reservedOutput,
            fixedOverhead: fixedOverhead,
            historyBudget: historyBudget,
            estimatedHistory: estimatedHistory,
            utilization: utilization
        )
    }

    static func recomputeHistory(
        snapshot: ContextBudgetSnapshot,
        messages: [ChatMessage],
        compactionSettings: ContextCompactionSettings,
        calibrationMultiplier: Double = 1.0
    ) -> ContextBudgetSnapshot {
        let conversation = filterConversation(messages)
        let estimatedHistory = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: compactionSettings.includeReasoningInModelContext,
            calibrationMultiplier: calibrationMultiplier
        )
        return snapshot.withHistoryEstimate(estimatedHistory, historyBudget: snapshot.historyBudget)
    }

    private static func estimateToolsTokens(_ tools: [ToolDefinition], calibrationMultiplier: Double) -> Int {
        guard !tools.isEmpty else { return 0 }
        var total = 0
        for tool in tools {
            total += ContextTokenEstimator.estimateTextTokens(tool.name, calibrationMultiplier: calibrationMultiplier)
            total += ContextTokenEstimator.estimateTextTokens(tool.description, calibrationMultiplier: calibrationMultiplier)
            total += ContextTokenEstimator.estimateTextTokens(tool.source, calibrationMultiplier: calibrationMultiplier)
            if let parameters = tool.parameters {
                for (key, value) in parameters {
                    total += ContextTokenEstimator.estimateTextTokens(key, calibrationMultiplier: calibrationMultiplier)
                    if let stringValue = value as? String {
                        total += ContextTokenEstimator.estimateTextTokens(stringValue, calibrationMultiplier: calibrationMultiplier)
                    }
                }
            }
        }
        total += ContextTokenEstimator.estimateTextTokens("schema-overhead", calibrationMultiplier: calibrationMultiplier)
        return total
    }

    private static func filterConversation(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .compaction }
    }
}

enum ContextPressureEvaluator {
    static func resolveTruncateThreshold(_ settings: DynamicCompactionSettings) -> Double {
        settings.targetUtilization * settings.truncateLeadRatio
    }

    static func resolveCompactThreshold(_ settings: DynamicCompactionSettings) -> Double {
        settings.targetUtilization
    }

    static func evaluate(
        budget: ContextBudgetSnapshot,
        settings: DynamicCompactionSettings,
        forceOverflow: Bool = false
    ) -> ContextPressureLevel {
        if forceOverflow { return .overflow }

        let utilization = budget.totalUtilization
        let target = settings.targetUtilization

        if utilization >= target { return .critical }
        if utilization >= resolveTruncateThreshold(settings) { return .high }
        if utilization >= target * 0.6875 { return .elevated }
        return .normal
    }

    static func resolveKeepTokenBudget(
        budget: ContextBudgetSnapshot,
        pressure: ContextPressureLevel,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        includesConversationCompact: Bool
    ) -> Int {
        let dynamic = settings.dynamicCompaction
        let staticKeep = resolveStaticKeepTokenBudget(conversation: conversation, settings: settings)

        if !dynamic.enabled {
            return staticKeep
        }

        if pressure != .overflow, !includesConversationCompact {
            return max(staticKeep, 512)
        }

        let keepTargetUtil = pressure == .overflow
            ? dynamic.overflowPostCompactionUtilization
            : dynamic.postCompactionUtilization
        let targetHistory = Int(floor(keepTargetUtil * Double(budget.usablePromptWindow) - Double(budget.fixedOverhead)))
        let dynamicKeep = max(512, targetHistory)
        return max(dynamicKeep, staticKeep)
    }

    static func shouldApplyTruncateArgs(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow { return true }
        if meetsStaticTruncateThreshold(conversation: conversation, settings: settings) { return true }
        return budget.totalUtilization >= resolveTruncateThreshold(settings.dynamicCompaction)
    }

    static func shouldApplyPrefixReEvict(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow || pressure == .critical {
            return shouldApplyTruncateArgs(
                budget: budget,
                conversation: conversation,
                settings: settings,
                pressure: pressure,
                force: force
            )
        }
        return shouldApplyTruncateArgs(
            budget: budget,
            conversation: conversation,
            settings: settings,
            pressure: pressure,
            force: force
        ) && budget.totalUtilization >= resolveTruncateThreshold(settings.dynamicCompaction)
    }

    static func shouldCompact(
        budget: ContextBudgetSnapshot,
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        pressure: ContextPressureLevel,
        force: Bool
    ) -> Bool {
        if force || pressure == .overflow { return true }

        if !settings.dynamicCompaction.enabled {
            let estimated = ContextTokenEstimator.estimate(
                conversation,
                includeReasoningInModelContext: settings.includeReasoningInModelContext
            )
            return ConversationCutoffPlanner.shouldCompact(
                conversation,
                estimatedTokens: estimated,
                settings: settings,
                force: false
            )
        }

        return budget.totalUtilization >= resolveCompactThreshold(settings.dynamicCompaction)
    }

    static func meetsStaticTruncateThreshold(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings
    ) -> Bool {
        let estimated = ContextTokenEstimator.estimate(
            conversation,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        return ConversationCutoffPlanner.shouldTruncateArgs(
            conversation,
            estimatedTokens: estimated,
            settings: settings.truncateArgs
        )
    }

    private static func resolveStaticKeepTokenBudget(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings
    ) -> Int {
        if settings.keepTokens > 0 { return settings.keepTokens }
        if settings.keepMessages <= 0 || conversation.isEmpty { return 0 }
        let tailStart = max(0, conversation.count - settings.keepMessages)
        return ContextTokenEstimator.estimateSuffix(
            conversation,
            startIndex: tailStart,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
    }
}

enum SemanticMessageScorer {
    private static let preserveScoreThreshold = 3

    static func score(_ message: ChatMessage) -> Int {
        if SummaryMessageBuilder.isSummaryMessage(message) { return -5 }

        var score: Int
        switch message.role {
        case .user: score = 3
        case .tool: score = scoreToolMessage(message)
        default: score = 0
        }

        score += scorePathSignals(message.content)
        if !message.reasoningContent.isEmpty {
            score += scorePathSignals(message.reasoningContent)
        }
        return score
    }

    static func shouldPreserveInSummary(_ message: ChatMessage) -> Bool {
        score(message) >= preserveScoreThreshold
    }

    private static func scoreToolMessage(_ message: ChatMessage) -> Int {
        let content = message.content
        if content.localizedCaseInsensitiveContains("evicted/")
            || content.localizedCaseInsensitiveContains("Archived at:") {
            return 1
        }
        if content.localizedCaseInsensitiveContains("file_write")
            || content.localizedCaseInsensitiveContains("file_edit")
            || content.localizedCaseInsensitiveContains("execute_command") {
            return 2
        }
        return 0
    }

    private static func scorePathSignals(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        if text.localizedCaseInsensitiveContains(".cs")
            || text.localizedCaseInsensitiveContains(".tsx")
            || text.localizedCaseInsensitiveContains(".json")
            || text.contains("\\")
            || text.contains("/") {
            return 2
        }
        return 0
    }
}

enum SemanticCutoffPlanner {
    static func determineCutoffIndex(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        keepTokenBudget: Int
    ) -> Int {
        if conversation.isEmpty || keepTokenBudget <= 0 { return 0 }

        let protectedStart = findProtectedTailStart(conversation)
        let tokenKeepStart = findTokenBasedTailStart(
            conversation,
            keepTokenBudget: keepTokenBudget,
            includeReasoningInModelContext: settings.includeReasoningInModelContext
        )
        let rawCutoff = min(protectedStart, tokenKeepStart)
        return ConversationCutoffPlanner.findSafeCutoffPoint(conversation, cutoffIndex: rawCutoff)
    }

    static func buildMustPreserveAppendix(
        conversation: [ChatMessage],
        settings: ContextCompactionSettings,
        keepTokenBudget: Int
    ) -> String? {
        guard settings.dynamicCompaction.enableSemanticCutoff, !conversation.isEmpty else { return nil }

        let cutoff = determineCutoffIndex(
            conversation: conversation,
            settings: settings,
            keepTokenBudget: keepTokenBudget
        )
        if cutoff <= 0 { return nil }

        var lines = [
            "<must_preserve>",
            "The following facts from earlier history MUST appear in your summary:"
        ]
        for index in 0..<cutoff {
            let message = conversation[index]
            guard SemanticMessageScorer.shouldPreserveInSummary(message) else { continue }
            lines.append("- [\(message.role.rawValue)] \(truncateForAppendix(message.content))")
        }
        lines.append("</must_preserve>")
        return lines.joined(separator: "\n")
    }

    private static func findProtectedTailStart(_ conversation: [ChatMessage]) -> Int {
        for index in stride(from: conversation.count - 1, through: 0, by: -1) {
            if conversation[index].role == .user { return index }
        }
        return conversation.count
    }

    private static func findTokenBasedTailStart(
        _ conversation: [ChatMessage],
        keepTokenBudget: Int,
        includeReasoningInModelContext: Bool
    ) -> Int {
        var tokensKept = 0
        for index in stride(from: conversation.count - 1, through: 0, by: -1) {
            tokensKept += ContextTokenEstimator.estimateMessage(
                conversation[index],
                includeReasoningInModelContext: includeReasoningInModelContext
            )
            if tokensKept > keepTokenBudget {
                return min(conversation.count, index + 1)
            }
        }
        return 0
    }

    private static func truncateForAppendix(_ content: String?) -> String {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "(empty)"
        }
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 240 { return normalized }
        return String(normalized.prefix(240)) + "..."
    }
}

enum PrefixToolResultReEvictor {
    static func apply(
        messages: [ChatMessage],
        settings: ContextCompactionSettings,
        prefixCutoffExclusive: Int
    ) -> (messages: [ChatMessage], changed: Bool) {
        if prefixCutoffExclusive <= 0 { return (messages, false) }

        let previewChars = max(256, settings.toolResultEviction.previewChars / 2)
        var changed = false
        var updated: [ChatMessage] = []
        updated.reserveCapacity(messages.count)

        for (index, message) in messages.enumerated() {
            var current = message
            if index >= prefixCutoffExclusive
                || current.role != .tool
                || !isEvictedPlaceholder(current.content) {
                updated.append(current)
                continue
            }

            let tightened = tightenPreview(current.content, previewChars: previewChars)
            if tightened != current.content {
                current.content = tightened
                changed = true
            }
            updated.append(current)
        }

        return changed ? (updated, true) : (messages, false)
    }

    private static func isEvictedPlaceholder(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.localizedCaseInsensitiveContains("[Tool result evicted")
    }

    private static func tightenPreview(_ content: String, previewChars: Int) -> String {
        let marker = "Preview:"
        guard let range = content.range(of: marker, options: .caseInsensitive) else {
            return content.count <= previewChars * 3
                ? content
                : String(content.prefix(previewChars * 3)) + "\n...(preview tightened)"
        }

        let head = String(content[..<range.upperBound])
        let preview = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count <= previewChars * 2 { return content }

        let shortened = String(preview.prefix(previewChars)) + "\n...\n" + String(preview.suffix(previewChars))
        return head + "\n" + shortened
    }
}

protocol TokenEstimatorCalibrating: Sendable {
    func multiplier(for sessionId: String) -> Double
    func observe(sessionId: String, estimatedPromptTokens: Int, actualPromptTokens: Int?)
}

final class TokenEstimatorCalibrator: TokenEstimatorCalibrating, @unchecked Sendable {
    private let settings: ContextCompactionSettings
    private var multipliers: [String: Double] = [:]
    private let lock = NSLock()

    init(settings: ContextCompactionSettings) {
        self.settings = settings
    }

    func multiplier(for sessionId: String) -> Double {
        let dynamic = settings.dynamicCompaction
        guard dynamic.enableUsageCalibration, !sessionId.isEmpty else { return 1.0 }
        lock.lock()
        defer { lock.unlock() }
        return multipliers[sessionId] ?? 1.0
    }

    func observe(sessionId: String, estimatedPromptTokens: Int, actualPromptTokens: Int?) {
        let dynamic = settings.dynamicCompaction
        guard dynamic.enableUsageCalibration,
              !sessionId.isEmpty,
              let actual = actualPromptTokens,
              actual > 0,
              estimatedPromptTokens > 0 else { return }

        let alpha = min(1.0, max(0.01, dynamic.usageCalibrationAlpha))
        var observed = Double(actual) / Double(estimatedPromptTokens)
        observed = min(2.5, max(0.5, observed))

        lock.lock()
        defer { lock.unlock() }
        if let previous = multipliers[sessionId] {
            multipliers[sessionId] = previous + alpha * (observed - previous)
        } else {
            multipliers[sessionId] = observed
        }
    }
}
