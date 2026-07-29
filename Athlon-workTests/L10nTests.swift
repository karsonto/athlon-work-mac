import Foundation
import Testing
@testable import Athlon_work

struct L10nTests {
    @Test func zhAndEnKeysResolve() {
        let zh = L10n.t("nav.chat", language: "zh-CN")
        let en = L10n.t("nav.chat", language: "en-US")
        #expect(zh == "对话")
        #expect(en == "Chat")
        #expect(L10n.Language.parse("en") == .enUS)
        #expect(L10n.Language.parse("zh-CN") == .zhCN)
    }

    @Test func missingKeyFallsBackToKey() {
        let value = L10n.t("does.not.exist", language: "en-US")
        #expect(value == "does.not.exist")
    }
}
