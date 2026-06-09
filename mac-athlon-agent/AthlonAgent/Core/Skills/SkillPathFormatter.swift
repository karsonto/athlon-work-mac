import Foundation

enum SkillPathFormatter {
    static func formatFilesRoot(skillDirectory: String?) -> String? {
        guard let skillDirectory,
              !skillDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: skillDirectory) else {
            return nil
        }
        let fullPath = URL(fileURLWithPath: skillDirectory).standardizedFileURL.path
        return ToolPathNormalizer.forModel(fullPath)
    }

    static func formatFilesRoot(skill: AvailableSkillInfo) -> String? {
        formatFilesRoot(skillDirectory: skill.skillDirectory)
    }
}
