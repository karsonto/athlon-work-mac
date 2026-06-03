import Foundation

struct PreCompletionOptions: Equatable {
    static let `default` = PreCompletionOptions()

    static let agentLoop = PreCompletionOptions(
        allowTruncateArgs: true,
        allowConversationCompact: true,
        emitCompactionAudit: true
    )

    static let forceCompact = PreCompletionOptions(
        allowTruncateArgs: true,
        allowConversationCompact: true,
        forceConversationCompact: true,
        emitCompactionAudit: true
    )

    static let manualForceCompact = PreCompletionOptions(
        allowTruncateArgs: true,
        allowConversationCompact: true,
        forceConversationCompact: true,
        emitCompactionAudit: true,
        compactionKind: .manualCompact
    )

    var allowTruncateArgs: Bool = true
    var allowConversationCompact: Bool = true
    var forceConversationCompact: Bool = false
    var emitCompactionAudit: Bool = true
    var compactionKind: CompactionKind = .conversationCompact
}
