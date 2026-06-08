import Foundation

enum ComposerCommandOutcome {
    case handled(String)
    case notACommand
    case unrecognized(String)
}
