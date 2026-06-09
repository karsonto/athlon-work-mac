import Foundation

/// File-based two-layer long-term memory storage.
/// Layer 1: memory/YYYY-MM-DD.md (append-only daily ledgers)
/// Layer 2: memory/MEMORY.md     (LLM-consolidated, deduplicated, size-bounded)
final class FileLongTermMemory: ILongTermMemory {
    private let fileManager = FileManager.default
    private let memoryDir: String
    private let settings: MemorySettings
    private let curatedPath: String
    private let watermarkPath: String
    private let archiveDir: String
    private let dateFormatter: DateFormatter

    init(memoryDir: String, settings: MemorySettings = MemorySettings()) throws {
        self.memoryDir = memoryDir
        self.settings = settings
        self.curatedPath = (memoryDir as NSString).appendingPathComponent(settings.curatedFileName)
        self.watermarkPath = (memoryDir as NSString).appendingPathComponent(settings.watermarkFileName)
        self.archiveDir = (memoryDir as NSString).appendingPathComponent("archive")
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        try fileManager.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
    }

    func readCurated() async throws -> String {
        guard fileManager.fileExists(atPath: curatedPath) else { return "" }
        return try String(contentsOfFile: curatedPath, encoding: .utf8)
    }

    func appendDaily(_ text: String) async throws {
        let path = dailyPath(for: Date())
        try fileManager.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: path) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            try handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } else {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func readDaily(date: Date) async throws -> String {
        let path = dailyPath(for: date)
        guard fileManager.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    func listDailyFilesAfter(watermark: Date) async throws -> [String] {
        guard fileManager.fileExists(atPath: memoryDir) else { return [] }
        let contents = try fileManager.contentsOfDirectory(atPath: memoryDir)
        return contents
            .filter { $0.hasSuffix(".md") && $0 != settings.curatedFileName && $0 != settings.watermarkFileName }
            .filter { fileName in
                let path = (memoryDir as NSString).appendingPathComponent(fileName)
                let lastWrite = (try? fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                return lastWrite > watermark
            }
            .sorted()
    }

    func readDailyFile(relativePath: String) async throws -> String {
        let path = (memoryDir as NSString).appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    func writeCurated(_ content: String) async throws {
        try content.write(toFile: curatedPath, atomically: true, encoding: .utf8)
    }

    func readWatermark() async throws -> Date {
        guard fileManager.fileExists(atPath: watermarkPath) else { return Date.distantPast }
        let text = try String(contentsOfFile: watermarkPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Date.distantPast }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text) ?? Date.distantPast
    }

    func writeWatermark(_ watermark: Date) async throws {
        let formatter = ISO8601DateFormatter()
        let text = formatter.string(from: watermark)
        try text.write(toFile: watermarkPath, atomically: true, encoding: .utf8)
    }

    func archiveDailyFile(relativePath: String) async throws {
        try fileManager.createDirectory(atPath: archiveDir, withIntermediateDirectories: true)
        let src = (memoryDir as NSString).appendingPathComponent(relativePath)
        let dst = (archiveDir as NSString).appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: src) {
            if fileManager.fileExists(atPath: dst) {
                try fileManager.removeItem(atPath: dst)
            }
            try fileManager.moveItem(atPath: src, toPath: dst)
        }
    }

    func listAllMemoryFilePaths() async throws -> [String] {
        var result: [String] = []
        if fileManager.fileExists(atPath: curatedPath) {
            result.append(settings.memoryDirName + "/" + settings.curatedFileName)
        }

        guard fileManager.fileExists(atPath: memoryDir) else { return result }
        let contents = try fileManager.contentsOfDirectory(atPath: memoryDir)
        for fileName in contents where fileName.hasSuffix(".md")
            && fileName != settings.curatedFileName
            && fileName != settings.watermarkFileName {
            result.append(settings.memoryDirName + "/" + fileName)
        }
        return result.sorted()
    }

    /// Archives daily ledger files older than `dailyFileRetentionDays`.
    func archiveExpiredDailyFiles() async throws {
        guard settings.dailyFileRetentionDays > 0,
              fileManager.fileExists(atPath: memoryDir) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.dailyFileRetentionDays, to: Date()) ?? Date.distantPast
        let contents = try fileManager.contentsOfDirectory(atPath: memoryDir)
        for fileName in contents where fileName.hasSuffix(".md")
            && fileName != settings.curatedFileName
            && fileName != settings.watermarkFileName {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            guard let fileDate = dateFormatter.date(from: nameWithoutExt), fileDate < cutoff else { continue }
            try await archiveDailyFile(relativePath: fileName)
        }
    }

    private func dailyPath(for date: Date) -> String {
        let fileName = dateFormatter.string(from: date) + ".md"
        return (memoryDir as NSString).appendingPathComponent(fileName)
    }
}
