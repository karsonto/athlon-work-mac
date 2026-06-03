import Foundation

enum CompactionStrategy: String {
    case conversationCompact
    case forceCompact
    case manualCompact
}

enum CompactionLayer: Int, Comparable {
    case truncateArgs
    case toolResultEviction
    case conversationCompact

    static func < (lhs: CompactionLayer, rhs: CompactionLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct CompactionAuditDisplayInfo {
    let cardTitle: String
    let strategySubtitle: String
    let summary: String
    let detail: String
}

enum CompactionAuditDisplay {
    static func parse(_ content: String) -> CompactionAuditDisplayInfo {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var legacyKind = ""
        var strategyToken = ""
        var layersToken = ""
        var summary = ""

        for line in lines {
            let text = String(line)
            if text.lowercased().hasPrefix("compactionkind:") {
                legacyKind = String(text.dropFirst("CompactionKind:".count)).trimmingCharacters(in: .whitespaces)
            } else if text.lowercased().hasPrefix("compactionstrategy:") {
                strategyToken = String(text.dropFirst("CompactionStrategy:".count)).trimmingCharacters(in: .whitespaces)
            } else if text.lowercased().hasPrefix("compactionlayers:") {
                layersToken = String(text.dropFirst("CompactionLayers:".count)).trimmingCharacters(in: .whitespaces)
            } else if text.lowercased().hasPrefix("summary:") {
                summary = String(text.dropFirst("Summary:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        let strategy = resolveStrategy(strategyToken: strategyToken, legacyKind: legacyKind)
        let layers = parseLayers(layersToken: layersToken, strategy: strategy)
        return CompactionAuditDisplayInfo(
            cardTitle: cardTitle(for: strategy),
            strategySubtitle: buildStrategySubtitle(strategy: strategy, layers: layers),
            summary: summary,
            detail: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func formatStrategy(_ strategy: CompactionStrategy) -> String {
        switch strategy {
        case .forceCompact: return "force_compact"
        case .manualCompact: return "manual_compact"
        case .conversationCompact: return "conversation_compact"
        }
    }

    static func formatLayers(_ layers: [CompactionLayer]) -> String {
        Array(Set(layers))
            .sorted()
            .map { layer in
                switch layer {
                case .truncateArgs: return "truncate_args"
                case .toolResultEviction: return "tool_result_eviction"
                case .conversationCompact: return "conversation_compact"
                }
            }
            .joined(separator: ",")
    }

    private static func cardTitle(for strategy: CompactionStrategy) -> String {
        switch strategy {
        case .forceCompact: return "③ 强制对话压缩"
        case .manualCompact: return "③ 手动对话压缩"
        case .conversationCompact: return "③ 对话压缩（LLM 摘要）"
        }
    }

    private static func resolveStrategy(strategyToken: String, legacyKind: String) -> CompactionStrategy {
        if !strategyToken.isEmpty {
            switch strategyToken.lowercased() {
            case "force_compact": return .forceCompact
            case "manual_compact": return .manualCompact
            default: return .conversationCompact
            }
        }
        switch legacyKind.lowercased() {
        case "manualcompact": return .manualCompact
        case "forcecompact": return .forceCompact
        default: return .conversationCompact
        }
    }

    private static func parseLayers(layersToken: String, strategy: CompactionStrategy) -> [CompactionLayer] {
        guard !layersToken.isEmpty else {
            return [.conversationCompact]
        }
        var layers: [CompactionLayer] = []
        for part in layersToken.split(separator: ",") {
            switch part.trimmingCharacters(in: .whitespaces).lowercased() {
            case "truncate_args": layers.append(.truncateArgs)
            case "tool_result_eviction": layers.append(.toolResultEviction)
            case "conversation_compact": layers.append(.conversationCompact)
            default: break
            }
        }
        return layers.isEmpty ? [.conversationCompact] : layers
    }

    private static func buildStrategySubtitle(strategy: CompactionStrategy, layers: [CompactionLayer]) -> String {
        let trigger: String
        switch strategy {
        case .forceCompact:
            trigger = "触发：模型上下文超限后强制压缩"
        case .manualCompact:
            trigger = "触发：用户手动压缩"
        case .conversationCompact:
            trigger = "触发：消息数 / Token 阈值"
        }
        let layerText = layers.map(layerLabel).joined(separator: " → ")
        return "\(trigger) · 层级：\(layerText)"
    }

    private static func layerLabel(_ layer: CompactionLayer) -> String {
        switch layer {
        case .truncateArgs: return "② 工具参数截断"
        case .toolResultEviction: return "① 工具结果归档"
        case .conversationCompact: return "③ LLM 对话摘要"
        }
    }
}
