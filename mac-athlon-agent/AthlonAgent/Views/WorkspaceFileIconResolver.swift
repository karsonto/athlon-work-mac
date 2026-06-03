import SwiftUI

enum WorkspaceFileIconResolver {
    static func systemName(for node: WorkspaceNode) -> String {
        if node.isDirectory { return "folder.fill" }
        let name = node.name.lowercased()
        let ext = (name as NSString).pathExtension

        if name == ".gitignore" || name == ".gitattributes" { return "arrow.triangle.branch" }
        if name == "dockerfile" || name.hasSuffix(".dockerfile") { return "shippingbox.fill" }
        if name.hasPrefix("readme") { return "doc.richtext" }

        switch ext {
        case "swift": return "swift"
        case "cs": return "number"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "tsx", "jsx", "mjs": return "curlybraces"
        case "json", "jsonc": return "curlybraces.square"
        case "md", "markdown": return "doc.richtext"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush.fill"
        case "yaml", "yml": return "list.bullet.rectangle"
        case "xml", "xaml", "csproj", "sln": return "chevron.left.slash.chevron.right"
        case "sh", "bash", "zsh": return "terminal.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "pdf": return "doc.fill"
        default: return "doc"
        }
    }

    static func tint(for node: WorkspaceNode, colors: ThemeColors) -> Color {
        if node.isDirectory { return Color(hex: "#F59E0B") }
        let name = node.name.lowercased()
        let ext = (name as NSString).pathExtension
        switch ext {
        case "swift": return Color(hex: "#F97316")
        case "cs": return Color(hex: "#8B5CF6")
        case "py": return Color(hex: "#3B82F6")
        case "js", "ts", "tsx", "jsx": return Color(hex: "#EAB308")
        case "md", "markdown": return Color(hex: "#64748B")
        case "html", "htm": return Color(hex: "#EF4444")
        default: return colors.subtleText
        }
    }
}
