import Foundation

protocol IComposerCommand {
    var name: String { get }
    var description: String { get }
    func execute(context: ComposerCommandContext) async -> ComposerCommandResult
}
