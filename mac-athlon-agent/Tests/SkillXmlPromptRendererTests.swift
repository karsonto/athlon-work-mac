import XCTest
@testable import AthlonAgent

final class SkillXmlPromptRendererTests: XCTestCase {
    func testAppendSkillPrompt_rendersCoreXmlFields() {
        let skill = AvailableSkillInfo(
            name: "demo_skill",
            description: "Demo & test",
            skillId: "demo_skill",
            skillDirectory: nil
        )

        var builder = ""
        SkillXmlPromptRenderer.appendSkillPrompt(to: &builder, skills: [skill])
        let text = builder

        XCTAssertTrue(text.contains("<available_skills>"))
        XCTAssertTrue(text.contains("<skill>"))
        XCTAssertTrue(text.contains("<name>demo_skill</name>"))
        XCTAssertTrue(text.contains("<description>Demo &amp; test</description>"))
        XCTAssertTrue(text.contains("<skill-id>demo_skill</skill-id>"))
        XCTAssertTrue(text.contains("load_skill_through_path"))
        XCTAssertFalse(text.contains("<files-root>/"))
        XCTAssertFalse(text.contains("## Code Execution"))
    }

    func testAppendSkillPrompt_rendersFilesRootAndCodeExecution_whenSkillDirectoryExists() throws {
        let skillDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlon-skill-xml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let expectedFilesRoot = ToolPathNormalizer.forModel(skillDir.standardizedFileURL.path)
        let skill = AvailableSkillInfo(
            name: "demo_skill",
            description: "Demo",
            skillId: "demo_skill",
            skillDirectory: skillDir.path
        )

        var builder = ""
        SkillXmlPromptRenderer.appendSkillPrompt(to: &builder, skills: [skill])
        let text = builder

        XCTAssertTrue(text.contains("<files-root>\(expectedFilesRoot)</files-root>"))
        XCTAssertTrue(text.contains("## Code Execution"))
        XCTAssertTrue(text.contains("<code_execution>"))
        XCTAssertTrue(text.contains("execute_command"))
    }

    func testAppendSkillPrompt_doesNothing_whenEmpty() {
        var builder = "prefix"
        SkillXmlPromptRenderer.appendSkillPrompt(to: &builder, skills: [])
        XCTAssertEqual(builder, "prefix")
    }
}
