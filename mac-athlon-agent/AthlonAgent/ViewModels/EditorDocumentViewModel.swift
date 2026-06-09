// AthlonAgent/ViewModels/EditorDocumentViewModel.swift
import Foundation

@MainActor
final class EditorDocumentViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let filePath: String
    let displayName: String
    @Published var content: String
    @Published var isDirty: Bool = false
    @Published var isReadOnly: Bool

    private var savedContentHash: Int

    init(filePath: String, content: String, displayName: String? = nil, isReadOnly: Bool = false) {
        self.filePath = filePath
        self.content = content
        self.displayName = displayName ?? (filePath as NSString).lastPathComponent
        self.isReadOnly = isReadOnly
        self.savedContentHash = content.hashValue
    }

    func markSaved(_ newContent: String) {
        content = newContent
        savedContentHash = newContent.hashValue
        isDirty = false
    }

    func reloadFromDisk(_ newContent: String) {
        content = newContent
        savedContentHash = newContent.hashValue
        isDirty = false
    }

    func onContentChanged(_ newContent: String) {
        content = newContent
        isDirty = newContent.hashValue != savedContentHash
    }
}
