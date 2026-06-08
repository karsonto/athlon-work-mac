import Foundation

enum PromptSectionPlacement {
    case `static`     // Included in frozen prompt (prepareForTurn)
    case preCall      // Added before each reasoning iteration (buildForReasoningIteration)
}
