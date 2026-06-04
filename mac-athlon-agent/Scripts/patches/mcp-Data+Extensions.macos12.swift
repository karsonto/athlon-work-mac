import Foundation

extension Data {
    private static let dataURLPattern = #"^data:([^,;]+)(?:;charset=([^,;]+))?(?:;base64)?,(.*)$"#

    /// Checks if a given string is a valid data URL.
    public static func isDataURL(string: String) -> Bool {
        parseDataURL(string) != nil
    }

    /// Parses a data URL string into its MIME type and data components.
    public static func parseDataURL(_ string: String) -> (mimeType: String, data: Data)? {
        guard let regex = try? NSRegularExpression(pattern: dataURLPattern, options: []) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges >= 4,
              let mediatypeRange = Range(match.range(at: 1), in: string),
              let encodedDataRange = Range(match.range(at: 3), in: string)
        else {
            return nil
        }

        let mediatype = String(string[mediatypeRange])
        let charset: String? = {
            guard match.range(at: 2).location != NSNotFound,
                  let charsetRange = Range(match.range(at: 2), in: string)
            else { return nil }
            return String(string[charsetRange])
        }()
        let encodedData = String(string[encodedDataRange])
        let isBase64 = string.contains(";base64,")

        var mimeType = mediatype.isEmpty ? "text/plain" : mediatype
        if let charset, !charset.isEmpty, mimeType.starts(with: "text/") {
            mimeType += ";charset=\(charset)"
        }

        let decodedData: Data
        if isBase64 {
            guard let base64Data = Data(base64Encoded: encodedData) else { return nil }
            decodedData = base64Data
        } else {
            guard let percentDecodedData = encodedData.removingPercentEncoding?.data(using: .utf8) else {
                return nil
            }
            decodedData = percentDecodedData
        }

        return (mimeType: mimeType, data: decodedData)
    }

    /// Encodes the data as a data URL string with an optional MIME type.
    public func dataURLEncoded(mimeType: String? = nil) -> String {
        let base64Data = base64EncodedString()
        return "data:\(mimeType ?? "text/plain");base64,\(base64Data)"
    }
}
