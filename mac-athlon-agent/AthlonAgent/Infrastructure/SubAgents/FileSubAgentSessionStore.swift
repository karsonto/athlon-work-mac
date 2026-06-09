import Foundation

final class FileSubAgentSessionStore: SubAgentSessionStore {
    private let paths: AppPathProvider
    private let fileManager = FileManager.default

    init(paths: AppPathProvider = .shared) {
        self.paths = paths
    }

    func load(parentSessionId: String, subSessionId: String) async throws -> SubAgentSessionBundle? {
        let directory = subAgentDirectory(parentSessionId: parentSessionId, subSessionId: subSessionId)
        let sessionPath = (directory as NSString).appendingPathComponent("session.json")
        guard fileManager.fileExists(atPath: sessionPath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: sessionPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let session = try? decoder.decode(AgentSession.self, from: data) else { return nil }
        let role = try loadRole(directory: directory) ?? ""
        return SubAgentSessionBundle(session: session, role: role)
    }

    func save(parentSessionId: String, subSessionId: String, bundle: SubAgentSessionBundle) async throws {
        let directory = subAgentDirectory(parentSessionId: parentSessionId, subSessionId: subSessionId)
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let sessionPath = (directory as NSString).appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle.session).write(to: URL(fileURLWithPath: sessionPath))
        try saveRole(directory: directory, role: bundle.role)
    }

    private func subAgentDirectory(parentSessionId: String, subSessionId: String) -> String {
        (paths.sessionsPath as NSString)
            .appendingPathComponent(parentSessionId)
            .appending("/subagents/default/\(subSessionId)")
    }

    private struct SubAgentMeta: Codable {
        var role: String
    }

    private func loadRole(directory: String) throws -> String? {
        let metaPath = (directory as NSString).appendingPathComponent("meta.json")
        guard fileManager.fileExists(atPath: metaPath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: metaPath))
        return try JSONDecoder().decode(SubAgentMeta.self, from: data).role
    }

    private func saveRole(directory: String, role: String) throws {
        let metaPath = (directory as NSString).appendingPathComponent("meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(SubAgentMeta(role: role)).write(to: URL(fileURLWithPath: metaPath))
    }
}
