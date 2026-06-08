import Foundation

/// /compact — manually triggers session compaction.
final class CompactComposerCommand: IComposerCommand {
    let name = "compact"
    let description = "Manually trigger session context compaction"
    private let compactionService: ISessionCompactionService

    init(compactionService: ISessionCompactionService) {
        self.compactionService = compactionService
    }

    func execute(context: ComposerCommandContext) async -> ComposerCommandResult {
        let result = await compactionService.compact(session: context.session)
        let response = result ?? "Compaction completed (no summary generated)"
        return ComposerCommandResult(
            outcome: .handled(response),
            response: response
        )
    }
}
