import Foundation
import Observation

@Observable
@MainActor
final class FileEditorStore {
    var filePath: String = ""
    var displayPath: String = ""
    var content: String = ""
    var originalContent: String = ""
    var isOpen: Bool = false
    var isDirty: Bool { content != originalContent }
    var errorMessage: String?
    var statusMessage: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func open(path: String, workspaceRoot: String? = nil) {
        errorMessage = nil
        statusMessage = nil
        let standardized = (path as NSString).standardizingPath
        do {
            let text = try String(contentsOfFile: standardized, encoding: .utf8)
            filePath = standardized
            content = text
            originalContent = text
            displayPath = relativePath(full: standardized, root: workspaceRoot) ?? standardized
            isOpen = true
        } catch {
            errorMessage = error.localizedDescription
            isOpen = false
        }
    }

    @discardableResult
    func save() -> Bool {
        guard isOpen, !filePath.isEmpty else { return false }
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            originalContent = content
            statusMessage = "已保存"
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func close() {
        isOpen = false
        filePath = ""
        displayPath = ""
        content = ""
        originalContent = ""
        errorMessage = nil
        statusMessage = nil
    }

    private func relativePath(full: String, root: String?) -> String? {
        guard let root, !root.isEmpty else { return nil }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        if full == root { return (full as NSString).lastPathComponent }
        return nil
    }
}
