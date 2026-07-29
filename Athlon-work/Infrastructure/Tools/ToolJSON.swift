import Foundation

nonisolated enum ToolJSON {
    static func object(from arguments: String) throws -> [String: Any] {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return [:] }
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentToolError.invalidArguments("Arguments are not UTF-8")
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            if let dict = obj as? [String: Any] { return dict }
            throw AgentToolError.invalidArguments("Arguments must be a JSON object")
        } catch let error as AgentToolError {
            throw error
        } catch {
            throw AgentToolError.invalidArguments(error.localizedDescription)
        }
    }

    static func validateObjectString(_ arguments: String) throws {
        _ = try object(from: arguments)
    }
}
