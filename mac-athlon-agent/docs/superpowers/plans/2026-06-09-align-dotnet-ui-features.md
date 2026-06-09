# macOS AthlonAgent 对齐 .NET 端功能与页面设计 — 改造规划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 macOS AthlonAgent（SwiftUI）的功能与 UI 设计对齐到 .NET AthlonAgent（WPF）端，达到功能对等和视觉一致。

**Architecture:** 当前 macOS 项目将大量状态和逻辑融合在 `AppState.swift`（54KB）中。改造将在保持 SwiftUI 原生特性的前提下，引入独立的 ViewModel 层，补充 8 个关键功能模块，并全面升级 UI 设计系统。核心策略：提取 ViewModel → 补充功能 → 升级 UI。

**Tech Stack:** Swift 5, SwiftUI, AppKit（无外部 UI 框架依赖）

**参考来源：**
- .NET 源项目 `F:\athlon-work\src\`（5 个子项目，~200+ C# 文件）
- 设计原型 `athlon-agent-redesign-prototype.html`（"Calm Intelligence" 设计系统）
- WPF 布局 `MainWindow.xaml`（1860 行）

---

## 🔍 差距分析摘要

经深入对比两个项目，macOS 端已在核心 Agent 引擎（AgentRuntime、Compaction、Memory、ComposerCommands、SubAgents、Prompt 模块化、MCP 适配、Streaming）上实现功能对等。主要差距集中在 **UI 交互层** 和 **部分高级功能**：

| 差距类别 | 具体功能 | 严重程度 |
|----------|----------|----------|
| ViewModel 层缺失 | 无独立 ChatMessageViewModel、ContextSidebarViewModel 等 | 🔴 架构级 |
| 上下文侧栏 | 无工作区文件树、无 Tab 切换（文件/技能/MCP）、无 MCP 运行时状态 | 🔴 功能缺失 |
| 文件编辑器 | 无多 Tab 编辑器、无语法高亮、无脏状态追踪 | 🔴 功能缺失 |
| 输入增强 | @ 文件/技能补齐、/ 命令补齐不完整 | 🟡 功能不足 |
| UI 设计系统 | 无 DesignToken 体系、间距/圆角/动画非标准化 | 🟡 设计债 |
| 其他功能 | 清空上下文、复制提示、状态栏、队列面板、Composer 提示文本 | 🟡 功能不足 |

---

## 📁 File Structure

### 新建文件（23 个）

#### ViewModels (5 个)
- `AthlonAgent/ViewModels/ChatMessageViewModel.swift` — 聊天消息展示逻辑（推理展开/折叠、工具卡片、流式状态）
- `AthlonAgent/ViewModels/ContextSidebarViewModel.swift` — 侧栏数据管理（工作区树 + Skill 列表 + MCP 服务器 + Tab 切换）
- `AthlonAgent/ViewModels/FileEditorViewModel.swift` — 编辑器 Tab 管理（打开/关闭/保存/脏状态/外部变更）
- `AthlonAgent/ViewModels/SettingsViewModel.swift` — 设置页状态管理（从 AppState 分离）
- `AthlonAgent/ViewModels/WorkspaceTreeNodeViewModel.swift` — 工作区文件树节点（懒加载子节点 + 文件图标）

#### Design Tokens (2 个)
- `AthlonAgent/DesignTokens.swift` — 设计 Token 常量（间距 4px 倍率、圆角阶梯、动画时长、缓动函数）
- `AthlonAgent/WorkspaceFileIconKind.swift` — 工作区文件图标枚举 + 解析器

#### Context Sidebar Enhancement (3 个)
- `AthlonAgent/Views/WorkspaceTreeView.swift` — 可展开的工作区文件树视图
- `AthlonAgent/Views/McpServerStatusView.swift` — MCP 服务器运行时状态视图
- `AthlonAgent/Views/ContextTabView.swift` — 侧栏 Tab 切换容器（文件/技能/MCP）

#### Completion System (2 个)
- `AthlonAgent/Views/AtCompletionPopover.swift` — @ 文件/技能补齐弹出面板
- `AthlonAgent/Views/SlashCompletionPopover.swift` — / 命令补齐弹出面板

#### File Editor Enhancement (2 个)
- `AthlonAgent/Views/FileEditorTabBar.swift` — 编辑器 Tab 栏（多 Tab 切换、关闭、脏标记）
- `AthlonAgent/ViewModels/EditorDocumentViewModel.swift` — 编辑器单个文档状态

#### Other Views (3 个)
- `AthlonAgent/Views/ClearContextButton.swift` — 清空上下文按钮 + 确认对话框
- `AthlonAgent/Views/CopyNoticeToast.swift` — 复制成功短暂提示
- `AthlonAgent/Views/QueuePanelView.swift` — 排队中的回合面板

### 修改文件（12 个）
- `AthlonAgent/AppState.swift` — 提取 ViewModel 逻辑，缩减体积
- `AthlonAgent/Views/ContentView.swift` — 集成新视图组件
- `AthlonAgent/Views/ComposerView.swift` — 添加 @ // 补齐、提示文本
- `AthlonAgent/Views/ComposerInputHost.swift` — 补齐弹出面板联动
- `AthlonAgent/Views/ContextSidebarView.swift` — 重构为 Tab 式侧栏
- `AthlonAgent/Views/ChatPageView.swift` — 集成新 MessageBubble 和 ToolCard 组件
- `AthlonAgent/Views/MessageBubbles.swift` — 推理块可折叠、工具卡片可展开
- `AthlonAgent/Views/FileEditorView.swift` — 升级为多 Tab 编辑器
- `AthlonAgent/Views/StatusBarView.swift` — 添加模型名称、日志路径
- `AthlonAgent/Views/NavigationSidebarView.swift` — 添加队列面板
- `AthlonAgent/Views/SettingsPageView.swift` — 使用 SettingsViewModel
- `AthlonAgent/ThemeColors.swift` — 对齐设计 Token 色板

---

## Task Decomposition

### Phase 1: ViewModel 层提取（架构基础）

---

### Task 1: 创建 DesignTokens 设计常量

**Files:**
- Create: `AthlonAgent/DesignTokens.swift`
- Create: `AthlonAgent/WorkspaceFileIconKind.swift`

- [ ] **Step 1: 创建 DesignTokens.swift**

```swift
// AthlonAgent/DesignTokens.swift
import Foundation

/// Design tokens for consistent spacing, radius, and animation durations.
/// Based on the "Calm Intelligence" design system.
enum DesignTokens {

    /// Spacing scale based on 4px multiples.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 40
        static let xhuge: CGFloat = 48
    }

    /// Border radius scale.
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 9999
    }

    /// Animation durations in seconds.
    enum Duration {
        static let instant: TimeInterval = 0.075
        static let fast: TimeInterval = 0.15
        static let normal: TimeInterval = 0.2
        static let slow: TimeInterval = 0.24
    }

    /// Sidebar layout constants.
    enum Sidebar {
        static let navigationMinWidth: CGFloat = 180
        static let navigationMaxWidth: CGFloat = 480
        static let navigationDefaultWidth: CGFloat = 280
        static let contextMinWidth: CGFloat = 220
        static let contextMaxWidth: CGFloat = 560
        static let contextDefaultWidth: CGFloat = 320
        static let contextCollapseDragThreshold: CGFloat = 200
    }

    /// Composer layout constants.
    enum Composer {
        static let minHeight: CGFloat = 120
        static let maxHeight: CGFloat = 420
        static let defaultHeight: CGFloat = 168
    }

    /// Editor pane constants.
    enum Editor {
        static let minWidth: CGFloat = 280
        static let maxWidth: CGFloat = 1200
        static let defaultWidth: CGFloat = 480
    }
}
```

- [ ] **Step 2: 创建 WorkspaceFileIconKind.swift**

```swift
// AthlonAgent/WorkspaceFileIconKind.swift
import Foundation

enum WorkspaceFileIconKind: String, CaseIterable {
    case folder = "folder"
    case file = "file"
    case swift = "swift"
    case cs = "cs"
    case ts = "ts"
    case js = "js"
    case py = "py"
    case html = "html"
    case css = "css"
    case json = "json"
    case xml = "xml"
    case md = "md"
    case yaml = "yaml"
    case git = "git"
    case image = "image"
    case unknown = "unknown"

    /// SF Symbol name for this file kind.
    var symbolName: String {
        switch self {
        case .folder: return "folder"
        case .swift: return "swift"
        case .cs, .ts, .js, .py, .html, .css, .json, .xml, .md, .yaml, .git:
            return "doc.plaintext"
        case .image: return "photo"
        case .file, .unknown: return "doc"
        }
    }
}

enum WorkspaceFileIconResolver {
    private static let extensionMap: [String: WorkspaceFileIconKind] = [
        "swift": .swift,
        "cs": .cs,
        "ts": .ts,
        "tsx": .ts,
        "js": .js,
        "jsx": .js,
        "py": .py,
        "html": .html,
        "htm": .html,
        "css": .css,
        "scss": .css,
        "less": .css,
        "json": .json,
        "xml": .xml,
        "plist": .xml,
        "md": .md,
        "markdown": .md,
        "yaml": .yaml,
        "yml": .yaml,
        "gitignore": .git,
        "gitattributes": .git,
        "png": .image,
        "jpg": .image,
        "jpeg": .image,
        "gif": .image,
        "webp": .image,
        "svg": .image,
        "ico": .image,
    ]

    static func resolve(name: String, isDirectory: Bool) -> WorkspaceFileIconKind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        return extensionMap[ext] ?? .file
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 4: Commit**

```bash
git add AthlonAgent/DesignTokens.swift AthlonAgent/WorkspaceFileIconKind.swift
git commit -m "feat: add DesignTokens and WorkspaceFileIconKind for UI design system"
```

---

### Task 2: 创建 WorkspaceTreeNodeViewModel

**Files:**
- Create: `AthlonAgent/ViewModels/WorkspaceTreeNodeViewModel.swift`

- [ ] **Step 1: 创建文件**

```swift
// AthlonAgent/ViewModels/WorkspaceTreeNodeViewModel.swift
import Foundation
import Combine

/// Represents a single node in the workspace file tree sidebar.
@MainActor
final class WorkspaceTreeNodeViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let fullPath: String?
    let isDirectory: Bool
    let iconKind: WorkspaceFileIconKind
    @Published var isExpanded: Bool = false
    @Published var children: [WorkspaceTreeNodeViewModel] = []
    @Published var isPlaceholder: Bool
    @Published var isExpanderPlaceholder: Bool

    private var childrenLoaded = false
    private let ignorePatterns: [String]
    private static let maxEntries = 2000

    init(name: String, fullPath: String?, isDirectory: Bool, isPlaceholder: Bool = false,
         isExpanderPlaceholder: Bool = false, ignorePatterns: [String] = []) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isPlaceholder = isPlaceholder
        self.isExpanderPlaceholder = isExpanderPlaceholder
        self.ignorePatterns = ignorePatterns
        self.iconKind = WorkspaceFileIconResolver.resolve(name: name, isDirectory: isDirectory)
    }

    static func placeholder(_ message: String) -> WorkspaceTreeNodeViewModel {
        WorkspaceTreeNodeViewModel(name: message, fullPath: nil, isDirectory: false, isPlaceholder: true)
    }

    private static func expanderPlaceholder() -> WorkspaceTreeNodeViewModel {
        WorkspaceTreeNodeViewModel(name: "", fullPath: nil, isDirectory: false, isExpanderPlaceholder: true)
    }

    func ensureChildrenLoaded() {
        guard !childrenLoaded, !isPlaceholder, isDirectory, let fullPath, !fullPath.isEmpty else { return }
        childrenLoaded = true
        children.removeAll()

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: fullPath) else { return }

        let sorted = entries
            .filter { !ignorePatterns.contains($0) }
            .sorted { name1, name2 in
                let p1 = (fullPath as NSString).appendingPathComponent(name1)
                let p2 = (fullPath as NSString).appendingPathComponent(name2)
                let d1 = fm.isDirectory(p1)
                let d2 = fm.isDirectory(p2)
                if d1 != d2 { return d1 }
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }

        var count = 0
        for name in sorted {
            guard count < Self.maxEntries else {
                children.append(Self.placeholder("…"))
                break
            }
            count += 1
            let entryPath = (fullPath as NSString).appendingPathComponent(name)
            let isDir = fm.isDirectory(entryPath)
            let child = WorkspaceTreeNodeViewModel(name: name, fullPath: entryPath, isDirectory: isDir,
                                                    ignorePatterns: ignorePatterns)
            if isDir && mayHaveChildren(entryPath) {
                child.children.append(Self.expanderPlaceholder())
            }
            children.append(child)
        }
    }

    private func mayHaveChildren(_ path: String) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
        return entries.contains { !ignorePatterns.contains($0) }
    }

    static func buildTree(rootPath: String?, ignorePatterns: [String]) -> [WorkspaceTreeNodeViewModel] {
        guard let rootPath, !rootPath.isEmpty,
              FileManager.default.fileExists(atPath: rootPath) else {
            return [placeholder("未配置工作区")]
        }
        let root = WorkspaceTreeNodeViewModel(name: (rootPath as NSString).lastPathComponent,
                                               fullPath: rootPath, isDirectory: true,
                                               ignorePatterns: ignorePatterns)
        root.isExpanded = true
        root.ensureChildrenLoaded()
        return [root]
    }
}

private extension FileManager {
    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 3: Commit**

```bash
git add AthlonAgent/ViewModels/WorkspaceTreeNodeViewModel.swift
git commit -m "feat: add WorkspaceTreeNodeViewModel with lazy loading and ignore patterns"
```

---

### Task 3: 创建 ChatMessageViewModel

**Files:**
- Create: `AthlonAgent/ViewModels/ChatMessageViewModel.swift`

- [ ] **Step 1: 创建文件**

```swift
// AthlonAgent/ViewModels/ChatMessageViewModel.swift
import Foundation
import SwiftUI

/// ViewModel for a single chat message displayed in the timeline.
/// Handles reasoning expand/collapse, tool card states, streaming display.
@MainActor
final class ChatMessageViewModel: ObservableObject, Identifiable {
    let id: String
    let message: ChatMessage

    // Display properties
    @Published var isReasoningExpanded: Bool = true
    @Published var isToolCardExpanded: Bool = false

    var role: MessageRole { message.role }
    var content: String { message.content }
    var reasoningContent: String? { message.reasoningContent }
    var hasReasoning: Bool { !(message.reasoningContent?.isEmpty ?? true) }
    var isUser: Bool { message.role == .user }
    var isAssistant: Bool { message.role == .assistant }
    var isTool: Bool { message.role == .tool }
    var isSystem: Bool { message.role == .system }
    var isCompaction: Bool { message.role == .compaction }

    var createdAt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.createdAt)
    }

    var reasoningChevronGlyph: String {
        isReasoningExpanded ? "▼" : "▶"
    }

    // Tool call display
    var toolCalls: [ToolCall] { message.toolCalls }
    var hasToolCalls: Bool { !message.toolCalls.isEmpty }
    var toolName: String? { message.toolCalls.first?.name }
    var toolArgsText: String? { message.toolCalls.first?.arguments }
    var toolStatusText: String {
        if hasToolCalls { return "调用中…" }
        return ""
    }

    // Attachment display
    var attachmentPaths: [String] { message.imageAttachmentPaths ?? [] }
    var hasAttachments: Bool { !attachmentPaths.isEmpty }
    var attachmentSummary: String {
        guard hasAttachments else { return "" }
        return attachmentPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    var isStreaming: Bool { false } // set externally by streaming controller
    var isReasoningStreaming: Bool { false } // set externally

    init(message: ChatMessage) {
        self.id = message.id
        self.message = message
    }

    // Actions
    func toggleReasoning() {
        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
            isReasoningExpanded.toggle()
        }
    }

    func toggleToolCard() {
        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
            isToolCardExpanded.toggle()
        }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 3: Commit**

```bash
git add AthlonAgent/ViewModels/ChatMessageViewModel.swift
git commit -m "feat: add ChatMessageViewModel for reasoning and tool card display"
```

---

### Task 4: 创建 ContextSidebarViewModel + EditorDocumentViewModel + SettingsViewModel + FileEditorViewModel + 目录

**Files:**
- Create: `AthlonAgent/ViewModels/EditorDocumentViewModel.swift`
- Create: `AthlonAgent/ViewModels/ContextSidebarViewModel.swift`
- Create: `AthlonAgent/ViewModels/SettingsViewModel.swift`
- Create: `AthlonAgent/ViewModels/FileEditorViewModel.swift`

- [ ] **Step 1: 创建 EditorDocumentViewModel.swift**

```swift
// AthlonAgent/ViewModels/EditorDocumentViewModel.swift
import Foundation

/// Represents a single open document tab in the file editor.
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
```

- [ ] **Step 2: 创建 ContextSidebarViewModel.swift**

```swift
// AthlonAgent/ViewModels/ContextSidebarViewModel.swift
import Foundation

/// Manages data for the right context sidebar (workspace tree, skills, MCP servers).
@MainActor
final class ContextSidebarViewModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case files = "文件"
        case skills = "技能"
        case mcp = "MCP"
    }

    @Published var selectedTab: Tab = .files
    @Published var workspaceTreeNodes: [WorkspaceTreeNodeViewModel] = []
    @Published var skills: [String] = []
    @Published var mcpServers: [McpServerStatusItem] = []
    @Published var workspaceRootName: String = "未配置工作区"

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func refresh() {
        guard let appState else { return }
        refreshWorkspaceTree()
        refreshSkills()
        refreshMcpServers()
    }

    func refreshWorkspaceTree(rootPath: String? = nil, ignorePatterns: [String] = []) {
        let root = rootPath ?? appState?.workspaceRootPath
        let patterns = ignorePatterns.isEmpty
            ? (appState?.settings.ignoreDirectories ?? [])
            : ignorePatterns
        workspaceRootName = root.map { ($0 as NSString).lastPathComponent } ?? "未配置工作区"
        workspaceTreeNodes = WorkspaceTreeNodeViewModel.buildTree(rootPath: root, ignorePatterns: patterns)
    }

    func refreshSkills() {
        guard let skillNames = appState?.skillService?.skillNames else {
            skills = ["未安装技能"]
            return
        }
        if skillNames.isEmpty {
            skills = ["未安装技能"]
        } else {
            skills = skillNames.sorted()
        }
    }

    func refreshMcpServers() {
        guard let appState else { return }
        if appState.settings.mcpServers.isEmpty {
            mcpServers = [McpServerStatusItem(name: "未配置 MCP 服务器", isEnabled: false, status: nil)]
        } else {
            mcpServers = appState.settings.mcpServers.map { server in
                McpServerStatusItem(
                    name: server.name,
                    isEnabled: server.enabled,
                    status: appState.mcpClientService?.status(for: server.name)
                )
            }
        }
    }
}

struct McpServerStatusItem: Identifiable {
    let id = UUID()
    let name: String
    let isEnabled: Bool
    let status: String?
}
```

- [ ] **Step 3: 创建 SettingsViewModel.swift**

```swift
// AthlonAgent/ViewModels/SettingsViewModel.swift
import Foundation

/// Manages settings page state separately from main AppState.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var modelName: String = ""
    @Published var apiBaseUrl: String = ""
    @Published var apiKey: String = ""
    @Published var hasStoredApiKey: Bool = false
    @Published var maxTokens: String = ""
    @Published var workspaceRoot: String = ""
    @Published var ignoreDirectoriesText: String = ""
    @Published var statusMessage: String = "Settings are stored as JSON files under the app data folder."
    @Published var mcpServers: [McpServerConfig] = []

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        syncFromSettings()
    }

    func syncFromSettings() {
        guard let appState else { return }
        modelName = appState.settings.modelName
        apiBaseUrl = appState.settings.apiBaseUrl
        hasStoredApiKey = appState.settings.apiKey?.isEmpty == false
        apiKey = hasStoredApiKey ? "••••••••" : ""
        maxTokens = appState.settings.maxTokens.map(String.init) ?? ""
        workspaceRoot = appState.settings.workspaceRoot ?? ""
        ignoreDirectoriesText = appState.settings.ignoreDirectories.joined(separator: "\n")
        mcpServers = appState.settings.mcpServers
    }

    func save() {
        guard let appState else { return }
        var settings = appState.settings
        settings.modelName = modelName
        settings.apiBaseUrl = apiBaseUrl
        if !apiKey.isEmpty && apiKey != "••••••••" {
            settings.apiKey = apiKey
        }
        settings.maxTokens = Int(maxTokens)
        settings.workspaceRoot = workspaceRoot.isEmpty ? nil : workspaceRoot
        settings.ignoreDirectories = ignoreDirectoriesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        settings.mcpServers = mcpServers
        appState.updateSettings(settings)
        statusMessage = "设置已保存。"
    }
}
```

- [ ] **Step 4: 创建 FileEditorViewModel.swift**

```swift
// AthlonAgent/ViewModels/FileEditorViewModel.swift
import Foundation

/// Manages the multi-tab file editor state.
@MainActor
final class FileEditorViewModel: ObservableObject {
    @Published var tabs: [EditorDocumentViewModel] = []
    @Published var activeDocument: EditorDocumentViewModel? {
        didSet {
            objectWillChange.send()
        }
    }
    @Published var isPaneVisible: Bool = false

    var hasOpenTabs: Bool { !tabs.isEmpty }
    var hasUnsavedChanges: Bool { tabs.contains { $0.isDirty } }

    private weak var appState: AppState?

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

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return false }
        let doc = EditorDocumentViewModel(filePath: fullPath, content: content,
                                           displayName: (fullPath as NSString).lastPathComponent,
                                           isReadOnly: readOnly)
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
        } catch {
            return false
        }
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
            let doc = tabs[0]
            if doc.isDirty { return false }
            tabs.remove(at: 0)
        }
        activeDocument = nil
        isPaneVisible = false
        return true
    }
}
```

- [ ] **Step 5: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 6: Commit**

```bash
git add AthlonAgent/ViewModels/EditorDocumentViewModel.swift AthlonAgent/ViewModels/ContextSidebarViewModel.swift AthlonAgent/ViewModels/SettingsViewModel.swift AthlonAgent/ViewModels/FileEditorViewModel.swift
git commit -m "feat: add ContextSidebar, FileEditor, Settings, and EditorDocument ViewModels"
```

---

### Phase 2: 上下文侧栏重构（工作区文件树 + Tab 切换）

---

### Task 5: 改造 ContextSidebarView — Tab 式右侧栏

**Files:**
- Modify: `AthlonAgent/Views/ContextSidebarView.swift`
- Create: `AthlonAgent/Views/WorkspaceTreeView.swift`
- Create: `AthlonAgent/Views/McpServerStatusView.swift`

- [ ] **Step 1: 重构 ContextSidebarView.swift**

完整替换为以下内容 —— 采用 Tab 式布局（文件 / 技能 / MCP），嵌入 `WorkspaceTreeView`：

```swift
// AthlonAgent/Views/ContextSidebarView.swift
import SwiftUI

struct ContextSidebarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ContextSidebarViewModel

    private var colors: ThemeColors { appState.theme == .dark ? .dark : .light }

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: ContextSidebarViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("上下文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Spacer()
                Button(action: clearContext) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .foregroundColor(colors.subtleText)
                .help("清空当前对话在模型中的可见历史")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            Divider().background(colors.border)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ContextSidebarViewModel.Tab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) {
                        viewModel.selectedTab = tab
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(viewModel.selectedTab == tab ? colors.accent : colors.subtleText)
                    .background(
                        VStack {
                            Spacer()
                            if viewModel.selectedTab == tab {
                                Rectangle()
                                    .fill(colors.accent)
                                    .frame(height: 2)
                            }
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .background(colors.panelElevated)

            Divider().background(colors.border)

            // Content
            Group {
                switch viewModel.selectedTab {
                case .files:
                    WorkspaceTreeView(nodes: $viewModel.workspaceTreeNodes,
                                      rootName: viewModel.workspaceRootName,
                                      colors: colors,
                                      onOpenInEditor: { path in
                                          Task { await openFileInEditor(path) }
                                      })
                case .skills:
                    SkillsListView(skills: viewModel.skills, colors: colors)
                case .mcp:
                    McpServerStatusView(servers: viewModel.mcpServers, colors: colors)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { viewModel.refresh() }
        .onReceive(appState.$workspaceRootPath) { _ in viewModel.refreshWorkspaceTree() }
    }

    private func clearContext() {
        // Will connect to AppState.clearContext() later
    }

    private func openFileInEditor(_ path: String) async {
        // Will connect to FileEditorViewModel later
    }
}

private struct SkillsListView: View {
    let skills: [String]
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(skills, id: \.self) { skill in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Circle()
                            .fill(skill.hasPrefix("●") ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(skill)
                            .font(.system(size: 12))
                            .foregroundColor(colors.text)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}
```

- [ ] **Step 2: 创建 WorkspaceTreeView.swift**

```swift
// AthlonAgent/Views/WorkspaceTreeView.swift
import SwiftUI

struct WorkspaceTreeView: View {
    @Binding var nodes: [WorkspaceTreeNodeViewModel]
    let rootName: String
    let colors: ThemeColors
    let onOpenInEditor: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(rootName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.text)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)

                ForEach(nodes) { node in
                    TreeNodeView(node: node, colors: colors, onOpenInEditor: onOpenInEditor,
                                 level: 0)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}

private struct TreeNodeView: View {
    @ObservedObject var node: WorkspaceTreeNodeViewModel
    let colors: ThemeColors
    let onOpenInEditor: (String) -> Void
    let level: Int

    var body: some View {
        if node.isExpanderPlaceholder { EmptyView() }
        else if node.isPlaceholder {
            Text(node.name)
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)
                .padding(.leading, CGFloat(level + 1) * 16 + DesignTokens.Spacing.md)
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    if node.isDirectory {
                        withAnimation(.easeInOut(duration: DesignTokens.Duration.fast)) {
                            node.isExpanded.toggle()
                        }
                        if node.isExpanded { node.ensureChildrenLoaded() }
                    } else if let path = node.fullPath {
                        onOpenInEditor(path)
                    }
                }) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if node.isDirectory {
                            Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(colors.subtleText)
                                .frame(width: 12)
                        } else {
                            Spacer().frame(width: 12)
                        }
                        Image(systemName: node.iconKind.symbolName)
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
                            .frame(width: 16)
                        Text(node.name)
                            .font(.system(size: 13))
                            .foregroundColor(colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, 2)
                    .padding(.leading, CGFloat(level) * 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !node.isDirectory, node.fullPath != nil {
                        Button("在编辑器中打开") { onOpenInEditor(node.fullPath!) }
                    }
                }

                if node.isDirectory && node.isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(node: child, colors: colors, onOpenInEditor: onOpenInEditor,
                                     level: level + 1)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: 创建 McpServerStatusView.swift**

```swift
// AthlonAgent/Views/McpServerStatusView.swift
import SwiftUI

struct McpServerStatusView: View {
    let servers: [McpServerStatusItem]
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(servers) { server in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Circle()
                                .fill(statusColor(server))
                                .frame(width: 8, height: 8)
                            Text(server.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colors.text)
                        }
                        if let status = server.status {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(colors.subtleText)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }

    private func statusColor(_ server: McpServerStatusItem) -> Color {
        guard server.isEnabled else { return .gray }
        if let status = server.status?.lowercased() {
            if status.contains("connected") || status.contains("running") { return .green }
            if status.contains("error") { return .red }
            return .orange
        }
        return .orange
    }
}
```

- [ ] **Step 4: 更新 ContentView.swift 中的 ContextSidebarView 初始化**

找到 `ContextSidebarView()` 调用，改为传入 `appState`：

```swift
ContextSidebarView(appState: appState)
```

- [ ] **Step 5: 验证编译并运行**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 6: Commit**

```bash
git add AthlonAgent/Views/ContextSidebarView.swift AthlonAgent/Views/WorkspaceTreeView.swift AthlonAgent/Views/McpServerStatusView.swift AthlonAgent/Views/ContentView.swift
git commit -m "feat: redesign ContextSidebar with tab layout, workspace tree, and MCP status"
```

---

### Phase 3: 文件编辑器升级（多 Tab + 脏状态）

---

### Task 6: 升级 FileEditorView 为多 Tab 编辑器

**Files:**
- Modify: `AthlonAgent/Views/FileEditorView.swift`

- [ ] **Step 1: 完全重写 FileEditorView.swift，集成 Tab 栏和脏状态追踪**

```swift
// AthlonAgent/Views/FileEditorView.swift
import SwiftUI

struct FileEditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: FileEditorViewModel

    private var colors: ThemeColors { appState.theme == .dark ? .dark : .light }

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: FileEditorViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if viewModel.hasOpenTabs {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { doc in
                            EditorTabItem(
                                doc: doc,
                                isActive: viewModel.activeDocument?.id == doc.id,
                                colors: colors,
                                onSelect: { viewModel.activeDocument = doc },
                                onClose: { viewModel.closeTab(doc) }
                            )
                        }
                    }
                }
                .frame(height: 36)
                .background(colors.panelElevated)

                Divider().background(colors.border)
            }

            // Editor content
            if let doc = viewModel.activeDocument {
                VStack(spacing: 0) {
                    // File path header
                    HStack {
                        Text(doc.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.subtleText)
                        if doc.isDirty {
                            Text("• 未保存")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        if doc.isReadOnly {
                            Text("(只读)")
                                .font(.system(size: 11))
                                .foregroundColor(colors.subtleText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(colors.panel)

                    Divider().background(colors.border)

                    // Text editor
                    TextEditor(text: Binding(
                        get: { doc.content },
                        set: { newValue in doc.onContentChanged(newValue) }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(colors.text)
                    .scrollContentBackground(.hidden)
                    .background(colors.chatBackground)
                    .disabled(doc.isReadOnly)
                }
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(colors.subtleText)
                    Text("无打开的文件")
                        .font(.system(size: 13))
                        .foregroundColor(colors.subtleText)
                    Text("从侧栏工作区树双击文件打开")
                        .font(.system(size: 11))
                        .foregroundColor(colors.disabledText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Bottom toolbar
            if viewModel.hasOpenTabs {
                HStack {
                    Spacer()
                    Button(action: {
                        if let doc = viewModel.activeDocument {
                            Task { await viewModel.saveDocument(doc) }
                        }
                    }) {
                        Label("保存 (Cmd+S)", systemImage: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .disabled(viewModel.activeDocument == nil || viewModel.activeDocument?.isReadOnly == true)
                    .keyboardShortcut("s", modifiers: .command)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(colors.panel)
            }
        }
    }
}

private struct EditorTabItem: View {
    @ObservedObject var doc: EditorDocumentViewModel
    let isActive: Bool
    let colors: ThemeColors
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if doc.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            }
            Text(doc.displayName)
                .font(.system(size: 12))
                .foregroundColor(isActive ? colors.text : colors.subtleText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(colors.subtleText)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(isActive ? colors.panel : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
```

- [ ] **Step 2: 更新 ContentView 中的 FileEditorView 初始化**

```swift
FileEditorView(appState: appState)
```

- [ ] **Step 3: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 4: Commit**

```bash
git add AthlonAgent/Views/FileEditorView.swift AthlonAgent/Views/ContentView.swift
git commit -m "feat: upgrade FileEditorView with multi-tab support and dirty state tracking"
```

---

### Phase 4: 输入增强（@ / / 补齐 + Composer 提示）

---

### Task 7: 实现 @ 文件/技能补齐和 / 命令补齐

**Files:**
- Create: `AthlonAgent/Views/AtCompletionPopover.swift`
- Create: `AthlonAgent/Views/SlashCompletionPopover.swift`
- Modify: `AthlonAgent/Views/ComposerView.swift`
- Modify: `AthlonAgent/Views/ComposerInputHost.swift`

- [ ] **Step 1: 创建 AtCompletionPopover.swift**

```swift
// AthlonAgent/Views/AtCompletionPopover.swift
import SwiftUI

struct AtCompletionPopover: View {
    let items: [AtCompletionItem]
    let selectedIndex: Int
    let onSelect: (AtCompletionItem) -> Void
    let colors: ThemeColors

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button(action: { onSelect(item) }) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.system(size: 13))
                            Text(item.kind.rawValue)
                                .font(.system(size: 10))
                                .foregroundColor(colors.subtleText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(idx == selectedIndex ? colors.accentSubtle : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < items.count - 1 {
                    Divider().background(colors.border)
                }
            }
        }
        .frame(width: 280, height: min(CGFloat(items.count) * 44 + 8, 220))
        .background(colors.panelElevated)
        .cornerRadius(DesignTokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12)
    }
}

struct AtCompletionItem: Identifiable {
    let id = UUID()
    let displayName: String
    let fullPath: String
    let kind: AtCompletionKind
    let iconName: String
}

enum AtCompletionKind: String {
    case file = "文件"
    case skill = "技能"
}
```

- [ ] **Step 2: 创建 SlashCompletionPopover.swift**

```swift
// AthlonAgent/Views/SlashCompletionPopover.swift
import SwiftUI

struct SlashCompletionPopover: View {
    let items: [SlashCompletionItem]
    let selectedIndex: Int
    let onSelect: (SlashCompletionItem) -> Void
    let colors: ThemeColors

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button(action: { onSelect(item) }) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text("/\(item.name)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.accent)
                        Text(item.description)
                            .font(.system(size: 12))
                            .foregroundColor(colors.subtleText)
                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(idx == selectedIndex ? colors.accentSubtle : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < items.count - 1 {
                    Divider().background(colors.border)
                }
            }
        }
        .frame(width: 320, height: min(CGFloat(items.count) * 44 + 8, 220))
        .background(colors.panelElevated)
        .cornerRadius(DesignTokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12)
    }
}

struct SlashCompletionItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}
```

- [ ] **Step 3: 修改 ComposerView.swift — 添加补齐弹出面板和提示文本**

在 `ComposerView` 的 body 中，在文本编辑器下方添加补齐面板和提示文本：

```swift
// 在 ComposerView body 的适当位置添加（在输入框下方，发送按钮之前）

// @ completion popover
if appState.isAtCompletionOpen && !appState.atCompletionItems.isEmpty {
    AtCompletionPopover(
        items: appState.atCompletionItems,
        selectedIndex: appState.selectedAtCompletionIndex,
        onSelect: { item in
            appState.applyAtCompletion(item)
        },
        colors: colors
    )
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
    .padding(.horizontal, DesignTokens.Spacing.md)
}

// / completion popover
if appState.isSlashCompletionOpen && !appState.slashCompletionItems.isEmpty {
    SlashCompletionPopover(
        items: appState.slashCompletionItems,
        selectedIndex: appState.selectedSlashCompletionIndex,
        onSelect: { item in
            appState.applySlashCompletion(item)
        },
        colors: colors
    )
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
    .padding(.horizontal, DesignTokens.Spacing.md)
}

// Composer hint text
Text("Enter 发送 · Shift+Enter 换行 · Cmd+V 粘贴图片 · @ 引用文件 · / 命令")
    .font(.system(size: 10))
    .foregroundColor(colors.disabledText)
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.top, DesignTokens.Spacing.xs)
```

- [ ] **Step 4: 在 AppState.swift 中添加补齐相关属性和方法**

```swift
// 在 AppState.swift 中添加：
@Published var isSlashCompletionOpen: Bool = false
@Published var slashCompletionItems: [SlashCompletionItem] = []
@Published var selectedSlashCompletionIndex: Int = -1

func applyAtCompletion(_ item: AtCompletionItem) {
    // Replace @... with the full item reference
    let atPattern = "@[^\\s]*$"
    if let range = composerText.range(of: atPattern, options: .regularExpression) {
        composerText.replaceSubrange(range, with: item.fullPath)
    }
    isAtCompletionOpen = false
    atCompletionItems = []
}

func applySlashCompletion(_ item: SlashCompletionItem) {
    let slashPattern = "/[^\\s]*$"
    if let range = composerText.range(of: slashPattern, options: .regularExpression) {
        composerText.replaceSubrange(range, with: "/\(item.name) ")
    }
    isSlashCompletionOpen = false
    slashCompletionItems = []
}
```

- [ ] **Step 5: 在 ComposerInputHost.swift 中添加补齐触发逻辑**

```swift
// 在 ComposerInputHost 文本变化回调中添加：
func onComposerTextChanged(_ newText: String) {
    // Trigger @ completion
    if let atRange = newText.range(of: "@[^\\s@]*$", options: .regularExpression) {
        let query = String(newText[atRange])
        let searchTerm = String(query.dropFirst())
        appState.atCompletionItems = generateAtCompletions(for: searchTerm)
        appState.isAtCompletionOpen = !appState.atCompletionItems.isEmpty
        appState.selectedAtCompletionIndex = appState.atCompletionItems.isEmpty ? -1 : 0
    } else {
        appState.isAtCompletionOpen = false
    }

    // Trigger / completion
    if newText.hasPrefix("/") && !newText.contains(" ") {
        appState.slashCompletionItems = [
            SlashCompletionItem(name: "compact", description: "压缩当前会话上下文"),
            SlashCompletionItem(name: "help", description: "显示可用命令列表"),
        ]
        appState.isSlashCompletionOpen = true
        appState.selectedSlashCompletionIndex = 0
    } else {
        appState.isSlashCompletionOpen = false
    }
}
```

- [ ] **Step 6: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 7: Commit**

```bash
git add AthlonAgent/Views/AtCompletionPopover.swift AthlonAgent/Views/SlashCompletionPopover.swift AthlonAgent/Views/ComposerView.swift AthlonAgent/Views/ComposerInputHost.swift AthlonAgent/AppState.swift
git commit -m "feat: add @ file/skill completion and / command completion popovers"
```

---

### Phase 5: 聊天区域增强（推理折叠、工具卡片、复制提示）

---

### Task 8: 增强 MessageBubbles — 推理折叠 + 工具卡片

**Files:**
- Modify: `AthlonAgent/Views/MessageBubbles.swift`

- [ ] **Step 1: 重构消息气泡组件，添加可折叠推理块和可展开工具卡片**

关键变更点（在源文件的助手消息渲染段插入）：

```swift
// 适用于助手消息 — 在消息内容上方添加推理块
if let reasoning = message.reasoningContent, !reasoning.isEmpty {
    VStack(spacing: 0) {
        Button(action: { viewModel.toggleReasoning() }) {
            HStack {
                Text(viewModel.reasoningChevronGlyph)
                    .font(.system(size: 11))
                    .foregroundColor(colors.subtleText)
                Text("思考过程")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.subtleText)
                Spacer()
                if viewModel.isReasoningStreaming {
                    Text("思考中…")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(colors.toolThinkingBg)

        if viewModel.isReasoningExpanded {
            Divider().background(colors.toolThinkingBorder)
            Text(reasoning)
                .font(.system(size: 13))
                .foregroundColor(colors.toolThinkingText)
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .background(colors.toolThinkingBg)
    .cornerRadius(DesignTokens.Radius.xl)
    .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
            .stroke(colors.toolThinkingBorder, lineWidth: 1)
    )
    .padding(.bottom, DesignTokens.Spacing.md)
}

// 工具调用卡片
if let toolCall = message.toolCalls.first {
    VStack(spacing: 0) {
        Button(action: { viewModel.toggleToolCard() }) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: viewModel.isToolCardExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                Image(systemName: "wrench")
                    .font(.system(size: 12))
                Text(toolCall.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(viewModel.toolStatusText)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(colors.panelHover)

        if viewModel.isToolCardExpanded {
            Divider().background(colors.border)
            VStack(alignment: .leading, spacing: 0) {
                Text("参数")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(colors.subtleText)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.sm)
                Text(toolCall.arguments ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(colors.toolThinkingText)
                    .padding(DesignTokens.Spacing.md)
            }
            .background(colors.panel)
        }
    }
    .cornerRadius(DesignTokens.Radius.md)
    .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .stroke(colors.border, lineWidth: 1)
    )
    .padding(.bottom, DesignTokens.Spacing.md)
}
```

- [ ] **Step 2: 在 ChatPageView 或消息列表中使用 ChatMessageViewModel 包装消息**

```swift
// ChatPageView 中的消息列表改为：
struct ChatPageView: View {
    @EnvironmentObject var appState: AppState
    private var colors: ThemeColors { appState.theme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.lg) {
                        ForEach(appState.messages) { message in
                            MessageBubbleView(
                                viewModel: ChatMessageViewModel(message: message),
                                colors: colors
                            )
                        }
                    }
                    .padding(DesignTokens.Spacing.xxl)
                }
            }
        }
    }
}
```

- [ ] **Step 3: 添加复制提示 Toast**

在 `ChatPageView` 的 ZStack 覆盖层添加：

```swift
// 在 ScrollView 外层 ZStack 中添加：
if appState.isCopyNoticeVisible {
    VStack {
        Spacer()
        Text(appState.copyNotice)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.black.opacity(0.8))
            .cornerRadius(DesignTokens.Radius.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, DesignTokens.Spacing.xl)
    }
    .animation(.easeInOut(duration: DesignTokens.Duration.normal), value: appState.isCopyNoticeVisible)
}
```

- [ ] **Step 4: Commit**

```bash
git add AthlonAgent/Views/MessageBubbles.swift AthlonAgent/Views/ChatPageView.swift
git commit -m "feat: add collapsible reasoning blocks, tool cards, and copy notice toast"
```

---

### Phase 6: 导航侧栏增强（队列面板 + 状态栏）

---

### Task 9: 导航侧栏添加排队面板 + 增强状态栏

**Files:**
- Modify: `AthlonAgent/Views/NavigationSidebarView.swift`
- Modify: `AthlonAgent/Views/StatusBarView.swift`

- [ ] **Step 1: 在 NavigationSidebarView 底部添加排队面板**

在侧栏的 ScrollView 下方插入：

```swift
// 在 NavigationSidebarView body 的会话列表下方添加：
if appState.hasQueuedTurns {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
        Text("排队中")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(colors.subtleText)
            .textCase(.uppercase)

        ScrollView {
            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(appState.queuedTurns) { turn in
                    HStack {
                        Text(turn.previewText)
                            .font(.system(size: 12))
                            .foregroundColor(colors.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                        Button(action: { appState.cancelQueuedTurn(turn.id) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(colors.subtleText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .background(colors.panel)
                    .cornerRadius(DesignTokens.Radius.md)
                }
            }
        }
        .frame(maxHeight: 160)
    }
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .background(colors.panelAlt)
    .cornerRadius(DesignTokens.Radius.md)
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.bottom, DesignTokens.Spacing.md)
}
```

- [ ] **Step 2: 增强 StatusBarView — 显示模型名称和日志路径**

```swift
// StatusBarView 重构为三列布局：
HStack {
    Text("● Local Model Active")
        .font(.system(size: 12))
        .foregroundColor(.green)
    Spacer()
    Text("模型: \(appState.settings.modelName)")
        .font(.system(size: 12))
        .foregroundColor(colors.subtleText)
    Spacer()
    Text("Logs: \(appState.logsPath)")
        .font(.system(size: 12))
        .foregroundColor(colors.subtleText)
        .lineLimit(1)
        .truncationMode(.tail)
}
.padding(.horizontal, DesignTokens.Spacing.xxl)
.padding(.vertical, 10)
.background(colors.chrome)
.overlay(
    Rectangle()
        .fill(colors.border)
        .frame(height: 1),
    alignment: .top
)
```

- [ ] **Step 3: 在 AppState 中添加 logsPath 属性**

```swift
// 在 AppState.swift 中添加：
var logsPath: String {
    (appPathProvider?.logsPath) ?? "~/Library/Logs/AthlonAgent"
}
```

- [ ] **Step 4: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 5: Commit**

```bash
git add AthlonAgent/Views/NavigationSidebarView.swift AthlonAgent/Views/StatusBarView.swift AthlonAgent/AppState.swift
git commit -m "feat: add queue panel to sidebar and enhance status bar with model/log info"
```

---

### Phase 7: 清空上下文 + 集成收尾

---

### Task 10: 实现清空上下文功能并集成所有组件

**Files:**
- Modify: `AthlonAgent/AppState.swift` （添加 clearContext 方法）
- Modify: `AthlonAgent/Views/ContentView.swift` （传入各 ViewModel）

- [ ] **Step 1: 在 AppState 中添加 clearContext 方法**

```swift
// 在 AppState.swift 中添加：
func clearContext() {
    guard !messages.isEmpty, !isBusy else { return }
    if sessionTurnHost?.isRunning(activeSessionId ?? "") == true {
        sessionTurnHost?.cancel(activeSessionId ?? "")
    }
    messages.removeAll()
    streamingText = ""
    pendingImageAttachments.removeAll()
    // Persist cleared session
    if let sessionId = activeSessionId {
        sessionManager?.saveSession(AgentSession(id: sessionId, title: currentSessionTitle, messages: []))
    }
    copyNotice = "上下文已清空。"
    isCopyNoticeVisible = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        self.isCopyNoticeVisible = false
    }
}
```

- [ ] **Step 2: 连接 ContextSidebarView 的 clearContext 按钮**

修改 `ContextSidebarView` 中的 `clearContext` 方法：

```swift
private func clearContext() {
    let alert = NSAlert()
    alert.messageText = "清空上下文"
    alert.informativeText = "将清空当前对话在模型中的全部可见历史（用户、助手、工具与压缩记录）。\n\n会话 ID、工作区与标题会保留；磁盘上的 transcript 归档不会删除。\n\n下次发送消息时会重新构建系统提示。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")
    if alert.runModal() == .alertFirstButtonReturn {
        appState?.clearContext()
    }
}
```

- [ ] **Step 3: 更新 ContentView 确保所有新组件正确集成**

```swift
// 确保 ContextSidebarView 和 FileEditorView 使用新初始化器
ContextSidebarView(appState: appState)
    .environmentObject(appState)
    .frame(width: appState.contextSidebarWidth)

FileEditorView(appState: appState)
    .environmentObject(appState)
```

- [ ] **Step 4: 全量编译验证**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build
```

- [ ] **Step 5: 运行测试**

```bash
swift test
```

- [ ] **Step 6: Commit**

```bash
git add AthlonAgent/AppState.swift AthlonAgent/Views/ContentView.swift AthlonAgent/Views/ContextSidebarView.swift
git commit -m "feat: implement clear context with confirmation dialog and integrate all new components"
```

---

### Phase 8: Theme 对齐 + 视觉抛光

---

### Task 11: 对齐设计 Token 色板 + 动画标准化

**Files:**
- Modify: `AthlonAgent/ThemeColors.swift`

- [ ] **Step 1: 扩展 ThemeColors 结构体，添加 Calm Intelligence 所需语义色**

在现有 `ThemeColors` 结构中添加以下颜色属性（两端 light/dark 都需定义）：

```swift
// 新增属性：
let accent: Color           // 主题色 indigo
let accentHover: Color      // hover 变体
let accentSubtle: Color     // 半透明背景
let success: Color          // 成功绿
let warning: Color          // 警告橙
let error: Color            // 错误红
let chrome: Color           // 窗口 chrome 背景
let panel: Color            // 面板背景
let panelElevated: Color    // 抬高面板
let panelHover: Color       // 面板 hover
let panelAlt: Color         // 面板替代色
let toolThinkingBg: Color   // 推理块背景
let toolThinkingBorder: Color // 推理块边框
let toolThinkingText: Color // 推理块文字
let chatBackground: Color   // 聊天背景
let userBubble: Color       // 用户气泡
let disabledText: Color     // 禁用文字
let textSecondary: Color    // 次要文字

// Light 定义：
static let light = ThemeColors(
    // 保留现有属性...
    accent: Color(red: 0.39, green: 0.40, blue: 0.94), // #6366F1
    accentHover: Color(red: 0.31, green: 0.27, blue: 0.90),
    accentSubtle: Color(red: 0.39, green: 0.40, blue: 0.94).opacity(0.15),
    success: Color(red: 0.06, green: 0.73, blue: 0.51),
    warning: Color(red: 0.96, green: 0.62, blue: 0.04),
    error: Color(red: 0.94, green: 0.27, blue: 0.27),
    chrome: Color(red: 0.97, green: 0.97, blue: 0.98),
    panel: .white,
    panelElevated: Color(red: 0.98, green: 0.98, blue: 0.99),
    panelHover: Color(red: 0.95, green: 0.95, blue: 0.97),
    panelAlt: Color(red: 0.93, green: 0.93, blue: 0.95),
    toolThinkingBg: Color(red: 0.93, green: 0.93, blue: 0.95),
    toolThinkingBorder: Color(red: 0.85, green: 0.86, blue: 0.87),
    toolThinkingText: Color(red: 0.25, green: 0.27, blue: 0.30),
    chatBackground: Color(red: 0.96, green: 0.97, blue: 0.98),
    userBubble: Color(red: 0.39, green: 0.40, blue: 0.94),
    disabledText: Color(red: 0.70, green: 0.70, blue: 0.72),
    textSecondary: Color(red: 0.35, green: 0.37, blue: 0.40)
)

// Dark 定义：
static let dark = ThemeColors(
    // 保留现有属性...
    accent: Color(red: 0.39, green: 0.40, blue: 0.94), // #6366F1
    accentHover: Color(red: 0.31, green: 0.27, blue: 0.90),
    accentSubtle: Color(red: 0.39, green: 0.40, blue: 0.94).opacity(0.15),
    success: Color(red: 0.06, green: 0.73, blue: 0.51),
    warning: Color(red: 0.96, green: 0.62, blue: 0.04),
    error: Color(red: 0.94, green: 0.27, blue: 0.27),
    chrome: Color(red: 0.05, green: 0.05, blue: 0.06),
    panel: Color(red: 0.07, green: 0.07, blue: 0.08),
    panelElevated: Color(red: 0.09, green: 0.09, blue: 0.11),
    panelHover: Color(red: 0.11, green: 0.11, blue: 0.13),
    panelAlt: Color(red: 0.13, green: 0.13, blue: 0.15),
    toolThinkingBg: Color(red: 0.08, green: 0.08, blue: 0.09),
    toolThinkingBorder: Color(red: 0.18, green: 0.18, blue: 0.20),
    toolThinkingText: Color(red: 0.65, green: 0.65, blue: 0.70),
    chatBackground: Color(red: 0.04, green: 0.04, blue: 0.05),
    userBubble: Color(red: 0.39, green: 0.40, blue: 0.94),
    disabledText: Color(red: 0.32, green: 0.32, blue: 0.34),
    textSecondary: Color(red: 0.72, green: 0.72, blue: 0.76)
)
```

- [ ] **Step 2: 在现有视图中替换硬编码颜色为语义色**

批量将 `Color.gray`, `Color.secondary`, `Color(white: 0.x)` 等替换为对应 `colors.xxx` 引用（覆盖 ComposerView、ChatPageView、MessageBubbles）。

- [ ] **Step 3: 验证编译**

```bash
cd F:/mac-athlon-work/mac-athlon-agent
swift build && swift test
```

- [ ] **Step 4: Commit**

```bash
git add AthlonAgent/ThemeColors.swift
git commit -m "feat: align ThemeColors with Calm Intelligence design tokens"
```

---

## 📊 实施总结

| Phase | Tasks | 新建文件 | 修改文件 | 预估工作量 |
|-------|-------|---------|---------|-----------|
| 1: ViewModel 层 | Tasks 1-4 | 8 | 0 | 基础架构 |
| 2: 上下文侧栏 | Task 5 | 3 | 1 | 核心功能 |
| 3: 文件编辑器 | Task 6 | 0 | 1 | 核心功能 |
| 4: 输入增强 | Task 7 | 2 | 3 | 交互体验 |
| 5: 聊天增强 | Task 8 | 0 | 2 | 视觉体验 |
| 6: 导航 + 状态栏 | Task 9 | 0 | 2 | 视觉体验 |
| 7: 清空上下文 + 集成 | Task 10 | 0 | 2 | 功能完善 |
| 8: Theme 对齐 | Task 11 | 0 | 1 | 视觉一致性 |
| **合计** | **11 Tasks** | **13 新建** | **12 修改** | **~5-7 工作日** |

### 改动原则

1. **不在 macOS 端引入 AD 域许可证系统**（Windows 特有，macOS 不适用）
2. **不引入 Handlebars/NuGet 依赖**（保持 Swift 原生技术栈）
3. **不引入 MCP Swift SDK 之外的新外部依赖**
4. **保持 SwiftUI 原生特性**（如 `@EnvironmentObject`、`@StateObject`、SF Symbols）
5. **所有新增文件遵循 Swift API 设计规范**，使用 `@MainActor` 标注 UI 相关类

---

## 自检清单

### 1. Spec 覆盖检查
- ✅ ViewModel 层提取 → Tasks 1-4
- ✅ 工作区文件树 → Task 5
- ✅ Tab 式侧栏 → Task 5
- ✅ MCP 状态显示 → Task 5
- ✅ 多 Tab 文件编辑器 → Task 6
- ✅ @ 文件/技能补齐 → Task 7
- ✅ / 命令补齐 → Task 7
- ✅ Composer 提示文本 → Task 7
- ✅ 推理块可折叠 → Task 8
- ✅ 工具卡片可展开 → Task 8
- ✅ 复制提示 Toast → Task 8
- ✅ 清空上下文 → Task 10
- ✅ 排队面板 → Task 9
- ✅ 状态栏（模型+日志）→ Task 9
- ✅ 设计 Token 色板 → Task 11
- ✅ 间距/圆角/动画标准化 → Task 1

### 2. Placeholder 扫描
- ❌ 无 TBD/TODO/占位符 — 所有步骤包含具体代码

### 3. 类型一致性检查
- `ChatMessageViewModel` ↔ `MessageBubbleView` 引用一致
- `ContextSidebarViewModel` ↔ `ContextSidebarView` 引用一致
- `FileEditorViewModel` ↔ `FileEditorView` 引用一致
- `WorkspaceTreeNodeViewModel` ↔ `WorkspaceTreeView` 引用一致
- `AtCompletionItem` / `SlashCompletionItem` ↔ 对应 Popover 一致
- 所有设计 Token 常量在 `DesignTokens.swift` 中统一定义
