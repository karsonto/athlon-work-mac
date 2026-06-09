import Foundation

/// macOS host metadata for environment prompts (aligned with WPF `IAgentHostEnvironment`).
struct MacAgentHostEnvironment {
    let skillsDirectory: String

    init(skillsDirectory: String = AppPathProvider.shared.skillsPath) {
        self.skillsDirectory = skillsDirectory
    }

    var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    var userName: String {
        NSFullUserName()
    }
}
