import Foundation

/// File-based knowledge store (JSON index + document files).
/// SQLite + embeddings can follow later; this provides parity-lite search without bridging deps.
nonisolated struct KnowledgeModule: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var sourcePath: String
    var documentIds: [String]
    var createdAt: String
    var updatedAt: String
}

nonisolated struct KnowledgeDocument: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var moduleId: String
    var title: String
    var sourcePath: String
    var extractedTextPath: String
    var charCount: Int
    var createdAt: String
}

nonisolated struct KnowledgeIndex: Codable, Hashable, Sendable {
    var modules: [KnowledgeModule] = []
    var documents: [KnowledgeDocument] = []
}

nonisolated final class KnowledgeStore: @unchecked Sendable {
    private let rootPath: String
    private let fileManager: FileManager
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let lock = NSLock()

    init(rootPath: String, fileManager: FileManager = .default) {
        self.rootPath = rootPath
        self.fileManager = fileManager
    }

    convenience init(paths: AppPathProviding, settings: KnowledgeSettings = .init()) {
        let root = (paths.rootPath as NSString).appendingPathComponent(settings.directoryName)
        self.init(rootPath: root)
    }

    var indexPath: String {
        (rootPath as NSString).appendingPathComponent("index.json")
    }

    var documentsDir: String {
        (rootPath as NSString).appendingPathComponent("documents")
    }

    func ensureReady() throws {
        try fileManager.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: documentsDir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: indexPath) {
            try saveIndex(KnowledgeIndex())
        }
    }

    func loadIndex() throws -> KnowledgeIndex {
        try ensureReady()
        lock.lock(); defer { lock.unlock() }
        let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
        return try decoder.decode(KnowledgeIndex.self, from: data)
    }

    func listModules() throws -> [KnowledgeModule] {
        try loadIndex().modules.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func addFolder(at folderPath: String, name: String? = nil) throws -> KnowledgeModule {
        try ensureReady()
        let stamp = ISO8601DateFormatter.athlon.string(from: Date())
        let moduleId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let moduleName = name ?? (folderPath as NSString).lastPathComponent
        var module = KnowledgeModule(
            id: moduleId,
            name: moduleName,
            sourcePath: folderPath,
            documentIds: [],
            createdAt: stamp,
            updatedAt: stamp
        )

        var index = try loadIndex()
        let files = try enumerateTextFiles(under: folderPath)
        for file in files {
            let doc = try ingestFile(file, moduleId: moduleId, stamp: stamp)
            module.documentIds.append(doc.id)
            index.documents.append(doc)
        }
        index.modules.append(module)
        try saveIndex(index)
        return module
    }

    @discardableResult
    func addFiles(_ filePaths: [String], moduleName: String = "Imports") throws -> KnowledgeModule {
        try ensureReady()
        let stamp = ISO8601DateFormatter.athlon.string(from: Date())
        var index = try loadIndex()
        let existing = index.modules.first(where: { $0.name == moduleName })
        var module = existing ?? KnowledgeModule(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            name: moduleName,
            sourcePath: "",
            documentIds: [],
            createdAt: stamp,
            updatedAt: stamp
        )
        if existing == nil {
            index.modules.append(module)
        }

        for path in filePaths {
            let doc = try ingestFile(path, moduleId: module.id, stamp: stamp)
            if !module.documentIds.contains(doc.id) {
                module.documentIds.append(doc.id)
            }
            if let idx = index.documents.firstIndex(where: { $0.id == doc.id }) {
                index.documents[idx] = doc
            } else {
                index.documents.append(doc)
            }
        }
        module.updatedAt = stamp
        if let mi = index.modules.firstIndex(where: { $0.id == module.id }) {
            index.modules[mi] = module
        }
        try saveIndex(index)
        return module
    }

    func removeModule(id: String) throws {
        var index = try loadIndex()
        let docs = index.documents.filter { $0.moduleId == id }
        for doc in docs {
            try? fileManager.removeItem(atPath: doc.extractedTextPath)
        }
        index.documents.removeAll { $0.moduleId == id }
        index.modules.removeAll { $0.id == id }
        try saveIndex(index)
    }

    func loadExtractedText(documentId: String) throws -> String {
        let index = try loadIndex()
        guard let doc = index.documents.first(where: { $0.id == documentId }) else {
            throw FileStorageError.io("Document not found: \(documentId)")
        }
        return try String(contentsOfFile: doc.extractedTextPath, encoding: .utf8)
    }

    // MARK: - Private

    private func saveIndex(_ index: KnowledgeIndex) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try encoder.encode(index)
        try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
    }

    private func ingestFile(_ path: String, moduleId: String, stamp: String) throws -> KnowledgeDocument {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let docId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let outPath = (documentsDir as NSString).appendingPathComponent("\(docId).txt")
        try text.write(toFile: outPath, atomically: true, encoding: .utf8)
        return KnowledgeDocument(
            id: docId,
            moduleId: moduleId,
            title: (path as NSString).lastPathComponent,
            sourcePath: path,
            extractedTextPath: outPath,
            charCount: text.count,
            createdAt: stamp
        )
    }

    private func enumerateTextFiles(under folder: String) throws -> [String] {
        let exts: Set<String> = ["md", "txt", "swift", "py", "ts", "tsx", "js", "json", "yml", "yaml", "cs", "go", "rs", "java"]
        var results: [String] = []
        guard let enumerator = fileManager.enumerator(atPath: folder) else { return [] }
        while let rel = enumerator.nextObject() as? String {
            let ext = (rel as NSString).pathExtension.lowercased()
            guard exts.contains(ext) else { continue }
            results.append((folder as NSString).appendingPathComponent(rel))
            if results.count >= 500 { break }
        }
        return results
    }
}
