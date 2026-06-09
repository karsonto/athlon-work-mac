import Foundation

struct CompactionRuntimeContext {
    var budget: ContextBudgetSnapshot
    let environmentPrompt: String
    let tools: [ToolDefinition]
    var calibrationMultiplier: Double
    var pressureOverride: ContextPressureLevel

    var forceOverflow: Bool { pressureOverride == .overflow }
}

struct CompactionExecutionRequest {
    let kind: CompactionKind
    let force: Bool
    let emitAudit: Bool
    var runtimeContext: CompactionRuntimeContext?
    var plan: DynamicCompactionPlan?

    init(
        kind: CompactionKind,
        force: Bool,
        emitAudit: Bool,
        runtimeContext: CompactionRuntimeContext? = nil,
        plan: DynamicCompactionPlan? = nil
    ) {
        self.kind = kind
        self.force = force
        self.emitAudit = emitAudit
        self.runtimeContext = runtimeContext
        self.plan = plan
    }

    static func legacy(kind: CompactionKind, force: Bool, emitAudit: Bool) -> CompactionExecutionRequest {
        CompactionExecutionRequest(kind: kind, force: force, emitAudit: emitAudit)
    }
}
