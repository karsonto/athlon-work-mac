import Foundation

/// Parses user input to detect `/command` patterns.
struct ComposerCommandParser {
    /// Returns the command name and arguments if input is a command, else nil.
    static func parse(_ input: String) -> (command: String, args: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let withoutSlash = String(trimmed.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let command = String(parts.first ?? "").lowercased()
        guard !command.isEmpty else { return nil }
        let args = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return (command, args)
    }
}
