import Foundation

protocol IEnvironmentPromptSection {
    var order: Int { get }
    var placement: PromptSectionPlacement { get }
    func append(to builder: inout String, context: EnvironmentPromptContext)
}
