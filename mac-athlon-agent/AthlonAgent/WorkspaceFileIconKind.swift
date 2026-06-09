// AthlonAgent/WorkspaceFileIconKind.swift
import Foundation

enum WorkspaceFileIconKind: String, CaseIterable {
    case folder
    case file
    case swift
    case cs
    case ts
    case js
    case py
    case html
    case css
    case json
    case xml
    case md
    case yaml
    case git
    case image
    case unknown

    var symbolName: String {
        switch self {
        case .folder: return "folder"
        case .swift: return "swift"
        case .image: return "photo"
        case .file, .cs, .ts, .js, .py, .html, .css, .json, .xml, .md, .yaml, .git, .unknown:
            return "doc.plaintext"
        }
    }
}

enum WorkspaceFileIconKindResolver {
    private static let extensionMap: [String: WorkspaceFileIconKind] = [
        "swift": .swift, "cs": .cs, "ts": .ts, "tsx": .ts,
        "js": .js, "jsx": .js, "py": .py, "html": .html, "htm": .html,
        "css": .css, "scss": .css, "less": .css,
        "json": .json, "xml": .xml, "plist": .xml,
        "md": .md, "markdown": .md,
        "yaml": .yaml, "yml": .yaml,
        "gitignore": .git, "gitattributes": .git,
        "png": .image, "jpg": .image, "jpeg": .image,
        "gif": .image, "webp": .image, "svg": .image, "ico": .image,
    ]

    static func resolve(name: String, isDirectory: Bool) -> WorkspaceFileIconKind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        return extensionMap[ext] ?? .file
    }
}
