import Foundation

// MARK: - Image Attachment
struct ImageAttachment: Identifiable, Codable {
    let id: String
    let fileName: String
    let filePath: URL
    let thumbnailData: Data?
    let fileSize: Int64
    var originalData: Data? { try? Data(contentsOf: filePath) }

    var thumbnail: Data? { thumbnailData }
}

// MARK: - MCP Server Item
struct McpServerItem: Identifiable, Codable {
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

    enum CodingKeys: String, CodingKey {
        case id, name, summary, toolNames, isEnabled, isStatusHealthy, isStatusError, isExpanded
    }
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
    case csharp = "csharp"
    case typescript = "typescript"
    case javascript = "javascript"
    case python = "python"
    case html = "html"
    case css = "css"
    case yaml = "yaml"
    case xml = "xml"
    case shell = "shell"
    case config = "config"

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
        case .csharp: "c.square"
        case .typescript: "t.square"
        case .javascript: "j.square"
        case .python: "p.square"
        case .html: "chevron.left.slash.chevron.right"
        case .css: "paintpalette"
        case .yaml: "list.bullet.rectangle"
        case .xml: "tag"
        case .shell: "terminal"
        case .config: "gearshape"
        }
    }
}
