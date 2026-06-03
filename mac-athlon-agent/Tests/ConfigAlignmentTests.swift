import XCTest
@testable import AthlonAgent

final class ConfigAlignmentTests: XCTestCase {
    func testClaudeDesktopMcpConfigRoundTrip() throws {
        let servers = [
            McpServerSettings(
                name: "filesystem",
                transportType: "stdio",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                enabled: true
            )
        ]
        let config = ClaudeDesktopMcpConfigMapper.fromSettingsList(servers)
        let json = try ClaudeDesktopMcpConfigMapper.serialize(config)
        let parsed = ClaudeDesktopMcpConfigMapper.parse(json)
        XCTAssertNotNil(parsed)
        let restored = ClaudeDesktopMcpConfigMapper.toSettingsList(parsed!)
        XCTAssertEqual(restored.first?.name, "filesystem")
        XCTAssertEqual(restored.first?.command, "npx")
        XCTAssertTrue(restored.first?.enabled == true)
    }

    func testSkillSettingsMergerPrefersSavedEnabledState() {
        let installed = [("demo", "demo")]
        let saved = [SkillSettings(name: "demo", enabled: false, path: "demo")]
        let merged = SkillSettingsMerger.merge(
            skillsRootPath: "/tmp/skills",
            installedSkills: installed,
            saved: saved
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].enabled)
    }
}
