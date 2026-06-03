import XCTest
@testable import AthlonAgent

final class GlobPatternHelperTests: XCTestCase {
    func testMatchesGlob_doubleStarPrefix_doesNotTrap() {
        XCTAssertTrue(GlobPatternHelper.matchesGlob("Tests/README.md", pattern: "**/README*"))
        XCTAssertTrue(GlobPatternHelper.matchesGlob("README.md", pattern: "**/README*"))
        XCTAssertFalse(GlobPatternHelper.matchesGlob("Tests/other.txt", pattern: "**/README*"))
    }

    func testMatchesGlob_doubleStarRecursive() {
        XCTAssertTrue(GlobPatternHelper.matchesGlob("src/a.txt", pattern: "**/*"))
        XCTAssertTrue(GlobPatternHelper.matchesGlob("a.txt", pattern: "**/*"))
    }

    func testMatchesGlob_singleStarWithinSegment() {
        XCTAssertTrue(GlobPatternHelper.matchesGlob("foo.cs", pattern: "*.cs"))
        XCTAssertFalse(GlobPatternHelper.matchesGlob("bar/foo.cs", pattern: "*.cs"))
    }

    func testExpandBraces() {
        let expanded = GlobPatternHelper.expandBraces("**/*.{png,jpg}")
        XCTAssertEqual(Set(expanded), Set(["**/*.png", "**/*.jpg"]))
    }

    func testEnumerateMatches_findsFileUnderSubdirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-glob-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let readme = root.appendingPathComponent("Tests/README-sample.md")
        try FileManager.default.createDirectory(
            at: readme.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "hello".write(to: readme, atomically: true, encoding: .utf8)

        let matches = GlobPatternHelper.enumerateMatches(
            rootDirectory: root.path,
            pattern: "**/README*",
            ignorePatterns: []
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].hasSuffix("README-sample.md"))
    }
}
