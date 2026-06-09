import XCTest
@testable import AthlonAgent

final class SessionJsonIndexReaderTests: XCTestCase {
    func testTryRead_parsesMetadataWithoutMessagesArray() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-index-\(UUID().uuidString)", isDirectory: true)
        let sessionDir = root.appendingPathComponent("sessions/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionJson = sessionDir.appendingPathComponent("session.json")
        let largeBody = String(repeating: "x", count: 50_000)
        let payload: [String: Any] = [
            "id": "session-a",
            "title": "大对话",
            "createdAt": "2025-06-01T00:00:00Z",
            "updatedAt": "2025-06-02T00:00:00Z",
            "messages": [
                ["id": "m1", "role": "user", "content": largeBody]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: sessionJson)

        let entry = SessionJsonIndexReader.tryRead(sessionJsonPath: sessionJson.path)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.id, "session-a")
        XCTAssertEqual(entry?.title, "大对话")
        XCTAssertEqual(entry?.path, sessionDir.path)
    }

    func testTryRead_returnsNil_whenIdMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionJson = root.appendingPathComponent("session.json")
        let payload: [String: Any] = ["title": "No id"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: sessionJson)

        XCTAssertNil(SessionJsonIndexReader.tryRead(sessionJsonPath: sessionJson.path))
    }

    func testTryRead_defaultsTitleAndUsesCreatedAtFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionJson = root.appendingPathComponent("session.json")
        let payload: [String: Any] = [
            "id": "session-b",
            "createdAt": "2025-06-01T12:00:00Z",
            "messages": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: sessionJson)

        let entry = SessionJsonIndexReader.tryRead(sessionJsonPath: sessionJson.path)

        XCTAssertEqual(entry?.title, "New chat")
        XCTAssertEqual(entry?.id, "session-b")
        XCTAssertNotNil(entry?.updatedAt)
    }
}
