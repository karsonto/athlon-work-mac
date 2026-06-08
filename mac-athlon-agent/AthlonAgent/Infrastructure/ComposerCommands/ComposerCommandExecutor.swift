import Foundation

/// Checks user input for `/command` patterns and executes matching commands.
final class ComposerCommandExecutor {
    private let registry: IComposerCommandRegistry

    init(registry: IComposerCommandRegistry) {
        self.registry = registry
    }

    /// Tries to execute a composer command from the input.
    /// Returns .notACommand if input is not a command, .unrecognized for unknown commands.
    func tryExecute(input: String, context: ComposerCommandContext) async -> ComposerCommandResult {
        guard let parsed = ComposerCommandParser.parse(input) else {
            return ComposerCommandResult(outcome: .notACommand, response: nil)
        }

        guard let command = registry.find(parsed.command) else {
            return ComposerCommandResult(
                outcome: .unrecognized(parsed.command),
                response: "Unknown command: /\(parsed.command). Type /help for available commands."
            )
        }

        return await command.execute(context: context)
    }
}
