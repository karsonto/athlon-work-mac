import Foundation

enum SkillFilter {
    static func enabledSkillItems(_ items: [SkillItem], settings: AppSettings) -> [SkillItem] {
        let disabled = Set(
            settings.skills
                .filter { !$0.enabled && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { $0.name.lowercased() }
        )
        return items
            .filter { !disabled.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
