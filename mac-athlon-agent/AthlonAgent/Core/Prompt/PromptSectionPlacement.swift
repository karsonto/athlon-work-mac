import Foundation

enum PromptSectionPlacement {
    case `static`     // Included in frozen prompt (prepareForTurn)
    case preCall      // Included in frozen prompt after static sections (prepareForTurn)
}
