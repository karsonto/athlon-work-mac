import Foundation

/// Appends content before each reasoning iteration (aligned with WPF `IPreReasoningPromptContributor`).
protocol IPreReasoningPromptContributor {
    var priority: Int { get }
    func append(to builder: inout String, context: EnvironmentPromptContext) async
}
