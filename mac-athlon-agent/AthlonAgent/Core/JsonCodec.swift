import Foundation

enum JsonCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func encodeLine<T: Encodable>(_ value: T) throws -> String {
        let data = try lineEncoder.encode(value)
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JsonCodec", code: 1)
        }
        return s
    }
}
