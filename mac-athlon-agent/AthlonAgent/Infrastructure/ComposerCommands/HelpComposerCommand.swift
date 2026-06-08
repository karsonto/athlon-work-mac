import Foundation

/// /help — lists available composer commands.
final class HelpComposerCommand: IComposerCommand {
    let name = "help"
    let description = "Show this help message"
    private let registry: IComposerCommandRegistry

    init(registry: IComposerCommandRegistry) {
        self.registry = registry
    }

    func execute(context: ComposerCommandContext) async -> ComposerCommandResult {
        let lines = registry.allCommands.map { "/\($0.name): \($0.description)" }
        let response = "Available commands:\n" + lines.joined(separator: "\n")
        return ComposerCommandResult(
            outcome: .handled(response),
            response: response
        )
    }
}
