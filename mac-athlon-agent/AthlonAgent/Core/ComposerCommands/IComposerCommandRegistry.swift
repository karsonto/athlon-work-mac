import Foundation

protocol IComposerCommandRegistry {
    func register(_ command: IComposerCommand)
    func find(_ name: String) -> IComposerCommand?
    var allCommands: [IComposerCommand] { get }
}
