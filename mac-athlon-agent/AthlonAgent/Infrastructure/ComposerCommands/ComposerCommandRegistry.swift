import Foundation

final class ComposerCommandRegistry: IComposerCommandRegistry {
    private var commands: [String: IComposerCommand] = [:]

    func register(_ command: IComposerCommand) {
        commands[command.name.lowercased()] = command
    }

    func find(_ name: String) -> IComposerCommand? {
        commands[name.lowercased()]
    }

    var allCommands: [IComposerCommand] {
        Array(commands.values)
    }
}
