// AthlonAgent/ViewModels/FileEditorViewModel.swift
import Foundation

@MainActor
final class FileEditorViewModel: ObservableObject {
    @Published var tabs: [EditorDocumentViewModel] = []
    @Published var activeDocument: EditorDocumentViewModel?
    @Published var isPaneVisible: Bool = false

    var hasOpenTabs: Bool { !tabs.isEmpty }
    var hasUnsavedChanges: Bool { tabs.contains { $0.isDirty } }

    private var appState: AppState?

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

    func closeTab(_ doc: EditorDocumentViewModel) {
        guard let idx = tabs.firstIndex(where: { $0.id == doc.id }) else { return }
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
