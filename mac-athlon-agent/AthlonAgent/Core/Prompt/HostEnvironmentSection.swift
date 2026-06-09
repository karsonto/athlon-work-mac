import Foundation

struct HostEnvironmentSection: IEnvironmentPromptSection {
    let order = 200
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        let now = formatter.string(from: Date())
        let tz = TimeZone.current.identifier

        var hostLine = "Host: macOS \(context.host.osVersion) | \(now) \(tz) | \(context.host.userName)"
        if context.hasWorkspace, let root = context.workspaceRoot {
            hostLine += " | cwd=\(root)"
        }
        hostLine += " | skills=\(context.host.skillsDirectory)"
        builder += hostLine + "\n"
        builder += "\n"
    }
}
