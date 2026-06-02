import Foundation

// MARK: - Image Attachment
struct ImageAttachment: Identifiable, Codable {
    let id: String
    let fileName: String
    let filePath: URL
    let thumbnailData: Data?
    let fileSize: Int64

    var thumbnail: Data? { thumbnailData }
}

// MARK: - MCP Server Item
struct McpServerItem: Identifiable {
    let id: String
    var name: String
    var displayInitial: String { String(name.prefix(1)).uppercased() }
    var summary: String
    var toolNames: [String]
    var isEnabled: Bool
    var isStatusHealthy: Bool
    var isStatusError: Bool
    var showStatusDot: Bool { isStatusHealthy || isStatusError }
    var isExpanded: Bool = false
    var hasTools: Bool { !toolNames.isEmpty }
    var chevron: String { isExpanded ? "▾" : "▸" }

    var toggleExpandedAction: () -> Void = {}
    var toggleEnabledAction: (Bool) -> Void = { _ in }
}

// MARK: - Skill Item
struct SkillItem: Identifiable {
    let id: String
    var name: String
    var displayInitial: String { String(name.prefix(1)).uppercased() }
    var description: String
    var isEnabled: Bool
    var isInstalled: Bool
    var statusText: String { isInstalled ? "" : "未安装" }
}

// MARK: - Workspace File Node
final class WorkspaceNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let iconKind: WorkspaceIconKind
    @Published var isExpanded: Bool = false
    @Published var children: [WorkspaceNode]?
    var isExpanderPlaceholder: Bool { false }

    init(id: String = UUID().uuidString,
         name: String,
         path: String,
         isDirectory: Bool,
         iconKind: WorkspaceIconKind = .file) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.iconKind = iconKind
    }
}

enum WorkspaceIconKind: String {
    case folder = "folder"
    case file = "file"
    case swift = "swift"
    case xcode = "xcode"
    case image = "image"
    case json = "json"
    case markdown = "markdown"
    case terminal = "terminal"
    case settings = "settings"

    var systemName: String {
        switch self {
        case .folder: "folder"
        case .file: "doc"
        case .swift: "swift"
        case .xcode: "hammer"
        case .image: "photo"
        case .json: "curlybraces"
        case .markdown: "text.alignleft"
        case .terminal: "terminal"
        case .settings: "gearshape"
        }
    }
}
