import Foundation

/// Audit log aligned with WPF `AuditLogService` → `~/.athlon-agent/audit/audit-yyyy-MM-dd.jsonl`.
enum AuditLogService {
    /// Legacy/simple entries (e.g. tool approval) using string detail map.
    static func log(
        action: String,
        detail: [String: String] = [:],
        paths: AppPathProvider = .shared
    ) {
        var payload: [String: Any] = [:]
        if !detail.isEmpty {
            payload["detail"] = detail
        }
        write(action: action, payload: payload, paths: paths)
    }

    /// Structured payload (matches WPF `WriteAsync(action, payload)`).
    static func write(
        action: String,
        payload: [String: Any],
        paths: AppPathProvider = .shared
    ) {
        let date = dayStamp()
        let dir = paths.auditPath
        let filePath = (dir as NSString).appendingPathComponent("audit-\(date).jsonl")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let entry: [String: Any] = [
            "time": isoTimestamp(),
            "action": action,
            "payload": payload
        ]
        appendJsonLine(entry, to: filePath)
    }

    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func appendJsonLine(_ object: [String: Any], to filePath: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: filePath) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }
}
