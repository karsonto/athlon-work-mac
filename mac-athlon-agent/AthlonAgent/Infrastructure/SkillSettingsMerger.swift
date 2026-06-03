import Foundation

enum SkillSettingsMerger {
    static func merge(
        skillsRootPath: String,
        installedSkills: [(name: String, folderName: String)],
        saved: [SkillSettings]
    ) -> [SkillSettings] {
        let savedByName = Dictionary(
            saved
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var merged: [SkillSettings] = []
        var seen = Set<String>()

        for skill in installedSkills.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let key = skill.name.lowercased()
            let existing = savedByName[key]
            let path = existing?.path?.trimmingCharacters(in: .whitespacesAndNewlines)
            merged.append(SkillSettings(
                name: skill.name,
                enabled: existing?.enabled ?? true,
                path: (path?.isEmpty == false) ? path : skill.folderName
            ))
            seen.insert(key)
        }

        for orphan in saved.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let key = orphan.name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            merged.append(orphan)
        }

        return merged
    }

    static func scanInstalled(skillsRootPath: String) -> [(name: String, folderName: String)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: skillsRootPath) else {
            return []
        }
        var result: [(String, String)] = []
        for entry in entries where !entry.hasPrefix(".") {
            let folder = (skillsRootPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let skillMd = (folder as NSString).appendingPathComponent("SKILL.md")
            let skillLower = (folder as NSString).appendingPathComponent("skill.md")
            guard FileManager.default.fileExists(atPath: skillMd)
                || FileManager.default.fileExists(atPath: skillLower) else {
                continue
            }
            let name = entry
            result.append((name, entry))
        }
        return result
    }
}
