import Foundation
import Testing
@testable import Athlon_work

struct KnowledgeStoreTests {
    @Test func addFilesAndKeywordSearch() throws {
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("athlon-kb-\(UUID().uuidString)")
        defer { try? fm.removeItem(atPath: root) }

        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        let sample = (root as NSString).appendingPathComponent("alpha.txt")
        try "Athlon knowledge base contains widgets and gadgets.".write(
            toFile: sample,
            atomically: true,
            encoding: .utf8
        )

        let store = KnowledgeStore(rootPath: (root as NSString).appendingPathComponent("kb"))
        _ = try store.addFiles([sample], moduleName: "Test")
        let modules = try store.listModules()
        #expect(modules.count == 1)
        #expect(modules[0].documentIds.count == 1)

        let search = KnowledgeSearchService(store: store)
        var settings = KnowledgeSearchSettings()
        settings.minScore = 0.1
        let hits = try search.search(query: "widgets", settings: settings)
        #expect(!hits.isEmpty)
        #expect(hits[0].snippet.lowercased().contains("widget"))
    }
}
