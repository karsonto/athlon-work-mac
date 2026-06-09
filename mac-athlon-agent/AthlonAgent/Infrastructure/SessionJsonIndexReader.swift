import Foundation

/// Reads session metadata from `session.json` without deserializing the messages array.
enum SessionJsonIndexReader {
    static func tryRead(sessionJsonPath: String) -> SessionIndexEntry? {
        guard FileManager.default.fileExists(atPath: sessionJsonPath) else { return nil }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: sessionJsonPath))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            guard let id = object["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let title: String
            if let parsedTitle = object["title"] as? String,
               !parsedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = parsedTitle
            } else {
                title = "New chat"
            }

            let updatedAt: Date
            if let parsed = parseDate(object["updatedAt"]) {
                updatedAt = parsed
            } else if let parsed = parseDate(object["createdAt"]) {
                updatedAt = parsed
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: sessionJsonPath),
                      let modified = attrs[.modificationDate] as? Date {
                updatedAt = modified
            } else {
                updatedAt = Date()
            }

            let sessionDir = (sessionJsonPath as NSString).deletingLastPathComponent
            return SessionIndexEntry(id: id, title: title, path: sessionDir, updatedAt: updatedAt)
        } catch {
            return nil
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let date = value as? Date { return date }
        if let text = value as? String {
            return ISO8601DateFormatter().date(from: text)
                ?? ISO8601DateFormatter().date(from: text.replacingOccurrences(of: "Z", with: "+00:00"))
        }
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }
}
