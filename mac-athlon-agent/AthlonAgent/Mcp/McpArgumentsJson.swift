import Foundation
import MCP

enum McpArgumentsJson {
    static func parseValueDictionary(_ argumentsJson: String) -> [String: Value]? {
        let trimmed = argumentsJson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: Value] = [:]
        for (key, value) in object {
            if let converted = toValue(value) {
                result[key] = converted
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func toValue(_ any: Any) -> Value? {
        switch any {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if floor(number.doubleValue) == number.doubleValue {
                return .int(number.intValue)
            }
            return .double(number.doubleValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.compactMap { toValue($0) })
        case let dict as [String: Any]:
            var object: [String: Value] = [:]
            for (key, value) in dict {
                if let converted = toValue(value) {
                    object[key] = converted
                }
            }
            return .object(object)
        default:
            return nil
        }
    }
}

enum McpValueJson {
    static func encodeToString(_ value: Value) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func objectSchema(from inputSchemaJson: String) -> [String: Any]? {
        guard let data = inputSchemaJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if json["type"] as? String == "object" {
            return json
        }
        return [
            "type": "object",
            "properties": json,
            "required": [] as [String]
        ]
    }
}
