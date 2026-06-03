import Foundation

enum FileReadLineReader {
    static let lineTruncatedSuffix = "... [line truncated]"
    static let metaHeader = "--- file_read meta ---"

    struct Selection {
        let offset: Int
        let lineLimit: Int
    }

    struct ReadResult {
        let body: String
        let totalLines: Int
        let linesReturned: Int
        let offset: Int
        let truncated: Bool
        let nextOffset: Int?
    }

    static func resolveSelection(_ arguments: [String: String], settings: FileReadSettings) -> Selection {
        var offset = ToolArguments.int32(arguments, name: "offset", defaultValue: 0)
        var limit = ToolArguments.int32(arguments, name: "limit", defaultValue: 0)
        let startLine = ToolArguments.int32(arguments, name: "start_line", defaultValue: 0)
        let endLine = ToolArguments.int32(arguments, name: "end_line", defaultValue: 0)

        if startLine > 0 {
            offset = max(0, startLine - 1)
            limit = endLine >= startLine ? endLine - startLine + 1 : 0
        }

        if limit <= 0 {
            limit = settings.defaultLineLimit
        }
        limit = min(limit, settings.maxLinesPerCall)
        offset = max(0, offset)
        return Selection(offset: offset, lineLimit: limit)
    }

    static func read(
        fullPath: String,
        selection: Selection,
        settings: FileReadSettings
    ) throws -> ReadResult {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: fullPath))
        defer { try? handle.close() }

        guard let data = try handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return ReadResult(body: "", totalLines: 0, linesReturned: 0, offset: selection.offset, truncated: false, nextOffset: nil)
        }

        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let totalLines = settings.countTotalLines ? rawLines.count : 0

        var content = ""
        var linesReturned = 0
        var truncated = false
        var nextOffset: Int?

        for (lineIndex, line) in rawLines.enumerated() {
            if !settings.countTotalLines && lineIndex >= selection.offset + selection.lineLimit && linesReturned >= selection.lineLimit {
                truncated = true
                nextOffset = selection.offset + linesReturned
                break
            }

            guard lineIndex >= selection.offset, linesReturned < selection.lineLimit else { continue }

            let formatted = formatLine(lineIndex + 1, line: line, maxLineChars: settings.maxLineChars)
            let prefix = linesReturned == 0 ? "" : "\n"
            let addition = prefix + formatted
            if content.count + addition.count > settings.maxResponseChars {
                truncated = true
                nextOffset = lineIndex
                break
            }
            content += addition
            linesReturned += 1
        }

        if settings.countTotalLines && !truncated && linesReturned >= selection.lineLimit && totalLines > selection.offset + linesReturned {
            truncated = true
            nextOffset = selection.offset + linesReturned
        }

        let computedTotal = settings.countTotalLines ? totalLines : max(rawLines.count, linesReturned + selection.offset)
        var body = content
        if linesReturned > 0 || truncated || selection.offset > 0 {
            body = appendMetaFooter(body, totalLines: computedTotal, linesReturned: linesReturned, offset: selection.offset, truncated: truncated, nextOffset: nextOffset)
        }

        return ReadResult(
            body: body,
            totalLines: computedTotal,
            linesReturned: linesReturned,
            offset: selection.offset,
            truncated: truncated,
            nextOffset: nextOffset
        )
    }

    static func formatLine(_ lineNumber: Int, line: String, maxLineChars: Int) -> String {
        var value = line
        if value.count > maxLineChars {
            value = String(value.prefix(maxLineChars)) + lineTruncatedSuffix
        }
        return "\(lineNumber)|\(value)"
    }

    static func appendMetaFooter(
        _ body: String,
        totalLines: Int,
        linesReturned: Int,
        offset: Int,
        truncated: Bool,
        nextOffset: Int?
    ) -> String {
        var builder = ""
        if !body.isEmpty {
            builder += "\n\n"
        }
        builder += metaHeader + "\n"
        builder += "total_lines: \(totalLines)\n"
        builder += "lines_returned: \(linesReturned)\n"
        builder += "offset: \(offset)\n"
        builder += "truncated: \(truncated ? "true" : "false")\n"
        if truncated, let nextOffset {
            builder += "next_offset: \(nextOffset)\n"
        }
        return body + builder.trimmingCharacters(in: .newlines)
    }

    static func buildSummary(fileName: String, result: ReadResult) -> String {
        var summary = "Read \(result.linesReturned) of \(result.totalLines) lines from \(fileName)"
        if result.truncated, let next = result.nextOffset {
            summary += "; truncated — continue with offset=\(next)"
        }
        return summary
    }
}
