import Foundation

struct ProductGuidanceSection: IEnvironmentPromptSection {
    let order = 700
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "When context grows large, history is auto-compressed; full transcripts are kept under the session transcripts folder.\n"
    }
}
