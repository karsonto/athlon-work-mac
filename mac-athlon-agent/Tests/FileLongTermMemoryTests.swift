import XCTest
@testable import AthlonAgent

final class FileLongTermMemoryTests: XCTestCase {
    var tempDir: String!
    var memory: FileLongTermMemory!

    override func setUp() async throws {
        tempDir = NSTemporaryDirectory().appending(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        memory = try FileLongTermMemory(memoryDir: tempDir)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(atPath: tempDir)
    }

    func testReadCuratedReturnsEmptyWhenNoFile() async throws {
        let result = try await memory.readCurated()
        XCTAssertEqual(result, "")
    }

    func testWriteAndReadCurated() async throws {
        try await memory.writeCurated("# Test Memory")
        let result = try await memory.readCurated()
        XCTAssertEqual(result, "# Test Memory")
    }

    func testAppendAndReadDaily() async throws {
        try await memory.appendDaily("Fact A\n")
        try await memory.appendDaily("Fact B\n")
        let daily = try await memory.readDaily(date: Date())
        XCTAssertTrue(daily.contains("Fact A"))
        XCTAssertTrue(daily.contains("Fact B"))
    }

    func testListDailyFilesAfterWatermark() async throws {
        try await memory.appendDaily("test")
        let files = try await memory.listDailyFilesAfter(watermark: Date.distantPast)
        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(files.allSatisfy { $0.hasSuffix(".md") && $0 != "MEMORY.md" })
    }

    func testReadDailyFileByRelativePath() async throws {
        try await memory.appendDaily("hello")
        let files = try await memory.listDailyFilesAfter(watermark: Date.distantPast)
        guard let first = files.first else { return XCTFail("No daily files") }
        let content = try await memory.readDailyFile(relativePath: first)
        XCTAssertEqual(content, "hello")
    }

    func testWatermarkRoundTrip() async throws {
        let date = Date()
        try await memory.writeWatermark(date)
        let read = try await memory.readWatermark()
        XCTAssertLessThan(abs(read.timeIntervalSince(date)), 1)
    }

    func testArchiveMovesFile() async throws {
        try await memory.appendDaily("archive me")
        let files = try await memory.listDailyFilesAfter(watermark: Date.distantPast)
        guard let first = files.first else { return XCTFail("No daily files") }
        try await memory.archiveDailyFile(relativePath: first)
        let content = try await memory.readDailyFile(relativePath: first)
        XCTAssertEqual(content, "")
    }
}
