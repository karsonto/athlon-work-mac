import XCTest
@testable import AthlonAgent

final class CompactionAuditDisplayTests: XCTestCase {
    func testParse_strategyAndLayers() {
        let content = """
        CompactionKind: conversationcompact
        CompactionStrategy: manual_compact
        CompactionLayers: tool_result_eviction,conversation_compact
        TokensBefore: 100
        TokensAfter: 40

        Summary: 已手动压缩 5 条消息。
        """
        let info = CompactionAuditDisplay.parse(content)
        XCTAssertEqual(info.cardTitle, "③ 手动对话压缩")
        XCTAssertTrue(info.strategySubtitle.contains("用户手动压缩"))
        XCTAssertTrue(info.strategySubtitle.contains("工具结果归档"))
        XCTAssertEqual(info.summary, "已手动压缩 5 条消息。")
    }
}
