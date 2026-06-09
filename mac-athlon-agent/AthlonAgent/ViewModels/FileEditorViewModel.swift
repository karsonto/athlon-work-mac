// AthlonAgent/ViewModels/FileEditorViewModel.swift
import Foundation

@MainActor
final class FileEditorViewModel: ObservableObject {
    @Published var tabs: [EditorDocumentViewModel] = []
    @Published var activeDocument: EditorDocumentViewModel?
    @Published var isPaneVisible: Bool = false

    var hasOpenTabs: Bool { !tabs.isEmpty }
    var hasUnsavedChanges: Bool { tabs.contains { $0.isDirty } }

    var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func openFile(path: String, readOnly: Bool = false) async -> Bool {
        let fullPath = (path as NSString).standardizingPath
        if let existing = tabs.first(where: { $0.filePath == fullPath }) {
            existing.isReadOnly = readOnly
            activeDocument = existing
            isPaneVisible = true
            return true
        }
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return false
        }
        let doc = EditorDocumentViewModel(
            filePath: fullPath, content: content,
            displayName: (fullPath as NSString).lastPathComponent,
            isReadOnly: readOnly
        )
        tabs.append(doc)
        activeDocument = doc
        isPaneVisible = true
        return true
    }

    func closeTab(_ doc: EditorDocumentViewModel, force: Bool = false) {
        guard let idx = tabs.firstIndex(where: { $0.id == doc.id }) else { return }

        if doc.isDirty && !force {
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "「\(doc.displayName)」有未保存的更改"
                alert.informativeText = "是否在关闭前保存更改？"
                alert.addButton(withTitle: "保存")
                alert.addButton(withTitle: "不保存")
                alert.addButton(withTitle: "取消")
                alert.alertStyle = .warning
                let response = alert.runModal()
                switch response {
                case .alertFirstButtonReturn: // 保存
                    let saved = await saveDocument(doc)
                    if saved { performCloseTab(doc, at: idx) }
                case .alertSecondButtonReturn: // 不保存
                    performCloseTab(doc, at: idx)
                default: // 取消
                    break
                }
            }
            return
        }
        performCloseTab(doc, at: idx)
    }

    private func performCloseTab(_ doc: EditorDocumentViewModel, at idx: Int) {
        tabs.remove(at: idx)
        if tabs.isEmpty {
            activeDocument = nil
            isPaneVisible = false
        } else if activeDocument?.id == doc.id {
            activeDocument = tabs[min(idx, tabs.count - 1)]
        }
    }

    func saveDocument(_ doc: EditorDocumentViewModel) async -> Bool {
        do {
            try doc.content.write(toFile: doc.filePath, atomically: true, encoding: .utf8)
            doc.markSaved(doc.content)
            return true
        } catch { return false }
    }

    func handleExternalChange(_ fullPath: String) {
        let normalized = (fullPath as NSString).standardizingPath
        guard let doc = tabs.first(where: { $0.filePath == normalized }),
              !doc.isDirty,
              let newContent = try? String(contentsOfFile: normalized, encoding: .utf8)
        else { return }
        doc.reloadFromDisk(newContent)
    }

    func tryCloseAll() -> Bool {
        while !tabs.isEmpty {
            if tabs[0].isDirty { return false }
            tabs.remove(at: 0)
        }
        activeDocument = nil
        isPaneVisible = false
        return true
    }
}
