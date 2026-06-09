import Foundation

struct SkillsSection: IEnvironmentPromptSection {
    let skillsProvider: () -> [AvailableSkillInfo]

    var order: Int { 600 }
    var placement: PromptSectionPlacement { .preCall }

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        let skills = skillsProvider()
        builder += "\n"
        guard !skills.isEmpty else { return }
        SkillXmlPromptRenderer.appendSkillPrompt(to: &builder, skills: skills)
    }
}
