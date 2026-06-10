import Foundation

struct FileReadSettings: Codable, Sendable {
    var maxFileBytes: Int64 = 2 * 1024 * 1024
    var defaultLineLimit: Int = 500
    var maxLinesPerCall: Int = 2_000
    var maxResponseChars: Int = 32_768
    var maxLineChars: Int = 1_024
    var countTotalLines: Bool = true
}

struct ToolPermissionSettings: Codable, Sendable {
    var askBeforeEveryCommand: Bool = false
    var fileScopePolicy: String = "AskOutsideWorkspace"
    var commandAllowList: [String] = ["git", "dotnet", "python", "node", "npm", "swift", "xcodebuild"]
    var commandDenyList: [String] = ["rm -rf", "rm -r", "rm --recursive", "mkfs", "dd if=", "format"]
}
