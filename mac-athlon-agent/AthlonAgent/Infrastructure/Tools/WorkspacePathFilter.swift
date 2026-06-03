import Foundation

enum WorkspacePathFilter {
    static func shouldIgnorePath(_ fullPath: String, directoryNames: [String]) -> Bool {
        for segment in fullPath.split(separator: "/", omittingEmptySubsequences: false) {
            if shouldIgnoreEntryName(String(segment), directoryNames: directoryNames) {
                return true
            }
        }
        return false
    }

    static func shouldIgnoreEntryName(_ name: String, directoryNames: [String]) -> Bool {
        directoryNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
