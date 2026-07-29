import Foundation

/// Loads `chat-fixture-events.json` for debug replay into `ChatWebView`.
enum ChatFixtureLoader {
    static func loadEventsJSONArray() throws -> String {
        guard let url = ChatAssetProvider.fixtureEventsURL() else {
            throw ChatFixtureError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        // Validate JSON is an array (or wrap a single object).
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized: Any
        if object is [Any] {
            normalized = object
        } else {
            normalized = [object]
        }
        let out = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
        guard let string = String(data: out, encoding: .utf8) else {
            throw ChatFixtureError.invalidEncoding
        }
        return string
    }

    static func loadEventsJSONArrayOrEmpty() -> String {
        (try? loadEventsJSONArray()) ?? "[]"
    }
}

enum ChatFixtureError: Error, LocalizedError {
    case fileNotFound
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "chat-fixture-events.json not found"
        case .invalidEncoding: return "Fixture JSON is not UTF-8"
        }
    }
}
