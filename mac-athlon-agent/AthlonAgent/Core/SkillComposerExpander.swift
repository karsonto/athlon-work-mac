import Foundation

struct AvailableSkillInfo: Equatable {
    let name: String
    let description: String
    let skillId: String
    let skillDirectory: String?
}

/// Expands `@skill:skillId` references in user composer text before sending to the agent.
enum SkillComposerExpander {
    private static let skillReferencePattern = try! NSRegularExpression(
        pattern: "@skill:([^\\s]+)",
        options: [.caseInsensitive]
    )

    static func expand(_ userInput: String, availableSkills: [AvailableSkillInfo]) -> String {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return userInput }

        let knownIds = Set(availableSkills.map(\.skillId))
        let range = NSRange(userInput.startIndex..<userInput.endIndex, in: userInput)
        let matches = skillReferencePattern.matches(in: userInput, range: range)
        guard !matches.isEmpty else { return userInput }

        var blocks: [String] = []
        var warnings: [String] = []

        for match in matches {
            guard match.numberOfRanges > 1,
                  let skillRange = Range(match.range(at: 1), in: userInput) else { continue }
            let skillId = String(userInput[skillRange])
            if knownIds.contains(skillId) {
                blocks.append(
                    """
                    [Skill reference: \(skillId)]
                    Use load_skill_through_path(skillId="\(skillId)", path="SKILL.md") to load full instructions before proceeding.
                    """
                )
            } else {
                warnings.append("Unknown skill '\(skillId)' in @skill reference; install or enable the skill first.")
            }
        }

        var builder = ""
        if !blocks.isEmpty {
            builder += Array(Set(blocks)).joined(separator: "\n\n")
            builder += "\n\n"
        }
        builder += userInput
        if !warnings.isEmpty {
            builder += "\n"
            builder += Array(Set(warnings)).joined(separator: "\n")
        }
        return builder
    }
}

extension SkillService {
    func availableSkillInfos(settings: AppSettings) -> [AvailableSkillInfo] {
        SkillFilter.enabledSkillItems(skills, settings: settings).map {
            AvailableSkillInfo(
                name: $0.name,
                description: $0.description,
                skillId: $0.id,
                skillDirectory: $0.skillDirectory
            )
        }
    }
}
