import Foundation

enum SessionHttpLogService {
    static func log(
        sessionId: String,
        requestSummary: [String: Any],
        responseSummary: [String: Any],
        paths: AppPathProvider = .shared
    ) {
        let dir = (paths.sessionDirectory(sessionId) as NSString).appendingPathComponent("http")
        let filePath = (dir as NSString).appendingPathComponent("interactions.jsonl")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "request": redact(requestSummary),
            "response": responseSummary
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: filePath) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }

    private static func redact(_ payload: [String: Any]) -> [String: Any] {
        var copy = payload
        if var headers = copy["headers"] as? [String: String] {
            for key in headers.keys where key.lowercased().contains("authorization") || key.lowercased().contains("api-key") {
                headers[key] = "[REDACTED]"
            }
            copy["headers"] = headers
        }
        if copy["apiKey"] != nil {
            copy["apiKey"] = "[REDACTED]"
        }
        return copy
    }
}
