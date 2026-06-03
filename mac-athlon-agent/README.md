<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white&labelColor=333">
  <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white&labelColor=eee">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple&logoColor=white&labelColor=333">
</picture>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white&labelColor=333">
  <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white&labelColor=eee">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white&labelColor=333">
</picture>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/MCP-Swift%20SDK%200.12+-purple?labelColor=333">
  <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/MCP-Swift%20SDK%200.12+-purple?labelColor=eee">
  <img alt="MCP" src="https://img.shields.io/badge/MCP-Swift%20SDK%200.12+-purple?labelColor=333">
</picture>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/badge/License-MIT-green?labelColor=333">
  <source media="(prefers-color-scheme: light)" srcset="https://img.shields.io/badge/License-MIT-green?labelColor=eee">
  <img alt="MIT" src="https://img.shields.io/badge/License-MIT-green?labelColor=333">
</picture>

# Athlon Agent

> **macOS 桌面 AI 编程助手** — 基于 LLM + MCP 协议，提供文件操作、命令执行、计划编写等全链路编码辅助能力。

Athlon Agent 是一个功能完备的 **macOS 原生桌面 Agent 应用**，使用 Swift + SwiftUI 构建。它搭载了大语言模型（LLM）运行时，通过 [MCP（Model Context Protocol）](https://modelcontextprotocol.io) 协议扩展工具生态，为开发者提供智能编码辅助。

---

## ✨ 功能特性

### 🧠 智能 Agent 引擎
- **LLM 驱动的对话式编码辅助** — 基于 OpenAI Chat Completions API（兼容接口）
- **流式响应（SSE）** — 实时流式显示 AI 回复与推理过程
- **工具调用（Tool Calls）** — AI 可自主调用文件、命令、搜索等工具
- **上下文压缩** — 自动管理长对话 Token 窗口，防止超限

### 📋 Plan / Agent 双模式
- **Agent 模式** — AI 自主思考并调用工具完成任务
- **Plan 模式** — 先生成计划再逐步执行，适合复杂多步骤任务
- **自动继续** — 计划可自动执行后续步骤，无需人工干预
- **Plan Notebook** — 类 Jupyter 笔记本式的计划展示与交互

### 🛠 内置工具系统
| 工具 | 功能 |
|---|---|
| `FileReadTool` | 读取工作区文件（支持分块、行号） |
| `FileEditTool` | 编辑文件（精确替换 + 自动备份） |
| `FileWriteTool` | 创建/覆盖文件 |
| `FileListTool` | 列出目录内容 |
| `GlobFilesTool` | Glob 模式匹配搜索文件 |
| `GrepFilesTool` | 文件内容文本搜索 |
| `ExecuteCommandTool` | 执行 Shell 命令（macOS zsh） |
| `LoadSkillThroughPathTool` | 加载技能资源 |
| `PlanTools` | 计划的创建、执行、管理 |
| `WorkspaceGuard` | 工作区安全保护（防止越界访问） |

### 🔌 MCP（Model Context Protocol）集成
- 兼容 **Claude Desktop MCP 配置格式**
- 支持任意 MCP 服务器注册与管理
- 通过 `McpRegistry` 集中管理 MCP 客户端连接
- 内置 MCP 工具名称编解码

### 💬 会话管理
- **多会话** — 同时管理多个独立对话
- **回合队列** — 支持回合排队（全局并发上限 3）
- **UI 联动** — `SessionTurnUiController` 驱动界面状态
- **会话快照** — 自动保存/恢复会话状态

### 🖥 原生 macOS 桌面体验
- **三栏布局** — 导航栏 / 主内容区 / 上下文信息栏（可拖拽调整宽度）
- **Markdown 渲染** — 实时渲染 AI 输出的 Markdown
- **Mermaid 图表** — 本地渲染（内嵌 `mermaid.min.js`），无需网络
- **HTML 预览** — 独立的 HTML 预览窗口
- **内置文件编辑器** — 快速查看/编辑工作区文件
- **主题支持** — 亮色/暗色主题切换
- **快捷键支持** — Cmd+N 新建会话，Cmd+, 打开设置，Cmd+W 关闭等
- **优雅关闭** — 等待当前回合完成后再退出应用

### ⚙️ 丰富的设置项
- 模型选择（API Key、Endpoint、Model 名称）
- 上下文压缩策略（Token 阈值、摘要行为）
- 工具执行审批（Tool Approval Gate）
- 技能（Skill）配置与管理
- 工作区路径设置

---

## 🏗 项目架构

```
┌──────────────────────────────────────────────┐
│  Views (SwiftUI)                              │
│  ContentView · ChatPageView · NavigationBar   │
│  MessageBubbles · Composer · SettingsPage     │
├──────────────────────────────────────────────┤
│  ViewModels                                   │
│  PlanViewModel                                │
├──────────────────────────────────────────────┤
│  AppState (全局状态单例 @MainActor)            │
│  + App/Services (回合管理、UI 联动)            │
├──────────────────────────────────────────────┤
│  Core (核心业务层)                             │
│  AgentRuntime · SystemPromptOrchestrator       │
│  Compaction · Plan · SkillComposer            │
├──────────────────────────────────────────────┤
│  Infrastructure (基础设施)                     │
│  OpenAiChatModelClient · Tools · McpRegistry  │
│  FileStorageService · SettingsStore            │
├──────────────────────────────────────────────┤
│  Mcp (MCP SDK 适配层)                         │
│  SdkMcpClient · McpSdkClientFactory            │
├──────────────────────────────────────────────┤
│  Models · Services                             │
│  数据模型 + 应用服务                            │
└──────────────────────────────────────────────┘
```

### 分层详解

| 层 | 职责 | 关键文件 |
|---|---|---|
| **Views** | SwiftUI 视图，用户交互 | `ContentView.swift`, `ChatPageView.swift`, `MessageBubbles.swift` |
| **ViewModels** | 视图状态与业务逻辑桥接 | `PlanViewModel.swift` |
| **App State** | 全局单例状态中心 | `AppState.swift` (~1285 行) |
| **App/Services** | 会话回合管理 | `SessionTurnHost.swift`, `SessionTurnQueue.swift` |
| **Core** | Agent 运行时、提示编排、上下文压缩、计划管理 | `AgentRuntime.swift`, `SystemPromptOrchestrator.swift` |
| **Infrastructure** | API 客户端、工具实现、存储、设置 | `OpenAiChatModelClient.swift`, `Tools/*`, `FileStorageService.swift` |
| **Mcp** | MCP 协议适配 | `SdkMcpClient.swift`, `McpSdkClientFactory.swift` |
| **Models** | 数据模型定义 | `AppSettings.swift`, `ChatMessage.swift`, `AgentSession.swift` |
| **Services** | 应用级服务 | `AgentRuntimeService.swift`, `SessionManager.swift` |

---

## 🛠 技术栈

| 技术 | 说明 |
|---|---|
| **语言** | Swift 5 |
| **UI 框架** | SwiftUI + AppKit |
| **最低系统** | macOS 14 (Sonoma) |
| **构建工具** | Swift Package Manager (Tools Version 6.0) |
| **LLM API** | OpenAI Chat Completions API（兼容接口） |
| **外部依赖** | [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk.git) ≥ 0.12.0 |
| **MCP 协议** | Model Context Protocol（服务器/客户端架构） |
| **持久化** | JSON 文件存储（`FileStorageService`） |
| **凭据管理** | macOS Keychain（`CredentialStore`） |
| **审计日志** | 文件 + HTTP 日志服务 |

---

## 🚀 快速开始

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode 16+（推荐）
- 一个 OpenAI API Key（或其他兼容 API）

### 构建运行

```bash
# 克隆项目
git clone https://github.com/your-org/athlon-agent.git
cd athlon-agent

# 使用 Xcode 打开
open Package.swift

# 或命令行构建
swift build -c debug

# 运行
swift run
```

> **提示**：建议在 Xcode 中打开项目以获得完整的 IDE 支持。

### 首次启动配置

1. **设置 API Key** — 启动后进入 Settings → Model，输入 API Key（或设置环境变量 `OPENAI_API_KEY`）
2. **选择模型** — 选择所需的 LLM 模型（如 `gpt-4o`）
3. **设置工作区** — 在 Settings → Workspace 中选择要操作的代码目录
4. **（可选）配置 MCP 服务器** — Settings → MCP 中添加 MCP 服务器

---

## 📁 项目结构

```
AthlonAgent/
├── AthlonAgentApp.swift          # @main 入口
├── AppDelegate.swift             # NSApplicationDelegate
├── AppState.swift                # 全局状态 (~1285 行)
├── ThemeColors.swift             # 主题颜色
├── LayoutMetrics.swift           # 布局常量
│
├── App/
│   └── Services/                 # 会话回合管理
│       ├── SessionTurnHost.swift
│       ├── SessionTurnUiController.swift
│       ├── SessionTurnQueue.swift
│       ├── PlanAutoContinuePolicy.swift
│       └── PlanAutoContinueTracker.swift
│
├── Core/                         # 核心业务逻辑
│   ├── AgentRuntime.swift        # Agent 引擎 (~641 行)
│   ├── SystemPromptOrchestrator.swift  # 提示词编排 (~18k)
│   ├── SkillComposerExpander.swift
│   ├── AssistantToolCallsCodec.swift
│   ├── SessionTurnReconciler.swift
│   ├── ClaudeDesktopMcpConfig.swift
│   ├── JsonCodec.swift / McpToolNameCodec.swift
│   ├── Plan/                     # 计划子系统
│   │   ├── AgentInteractionMode.swift
│   │   ├── CreatePlanRequest.swift
│   │   ├── PlanMarkdownFormatter.swift
│   │   ├── PlanToolCatalog.swift
│   │   ├── PlanValidation.swift
│   │   ├── PlanExecuteDefaults.swift
│   │   └── PlanPhase.swift
│   └── Compaction/               # 上下文压缩子系统
│       ├── ConversationCompactor.swift
│       ├── ConversationCutoffPlanner.swift
│       ├── PreCompletionPipeline.swift
│       ├── ToolResultEvictor.swift
│       ├── ContextTokenEstimator.swift
│       └── ... (共 15 个文件)
│
├── Infrastructure/               # 基础设施
│   ├── OpenAiChatModelClient.swift  # LLM API 客户端 (~612 行)
│   ├── FileStorageService.swift     # 文件存储 (~14k)
│   ├── McpRegistry.swift            # MCP 注册中心
│   ├── SettingsStore.swift
│   ├── CredentialStore.swift
│   ├── AuditLogService.swift
│   ├── Tools/                       # 工具实现 (21 个文件)
│   │   ├── FileReadTool.swift / FileWriteTool.swift
│   │   ├── FileEditTool.swift / FileListTool.swift
│   │   ├── GlobFilesTool.swift / GrepFilesTool.swift
│   │   ├── ExecuteCommandTool.swift
│   │   ├── LoadSkillThroughPathTool.swift
│   │   ├── PlanNotebook.swift / PlanTools.swift
│   │   ├── CompositeToolRouter.swift
│   │   ├── WorkspaceGuard.swift
│   │   └── ...
│   └── ...
│
├── Mcp/                          # MCP 协议层
│   ├── SdkMcpClient.swift
│   ├── McpSdkClientFactory.swift
│   ├── McpTypes.swift
│   └── McpArgumentsJson.swift
│
├── Models/                       # 数据模型
│   ├── AppSettings.swift
│   ├── AgentSession.swift
│   ├── ChatMessage.swift
│   ├── MessageRole.swift
│   ├── AppTheme.swift
│   ├── AppModels.swift
│   └── ContextCompactionSettings.swift
│
├── Services/                     # 应用服务
│   ├── AgentRuntimeService.swift
│   ├── SessionManager.swift
│   ├── McpClientService.swift
│   ├── SkillService.swift
│   ├── ImageAttachmentService.swift
│   ├── ThemeManager.swift
│   └── WorkspaceService.swift
│
├── ViewModels/
│   └── PlanViewModel.swift
│
├── Views/                        # SwiftUI 视图
│   ├── ContentView.swift         # 根视图（三栏布局）
│   ├── ChatPageView.swift
│   ├── MessageBubbles.swift
│   ├── ComposerView.swift / ComposerInputHost.swift
│   ├── NavigationSidebarView.swift
│   ├── ContextSidebarView.swift
│   ├── MarkdownRendererView.swift
│   ├── MermaidPreviewWindow.swift
│   ├── HtmlPreviewWindow.swift
│   ├── FileEditorView.swift
│   ├── SettingsPageView.swift
│   ├── DraggableSplitter.swift
│   └── ...
│
└── Resources/
    └── mermaid.min.js            # Mermaid 图表引擎（本地嵌入）

Tests/                            # 单元测试 (11 个文件)
├── ChatTimelineOrderTests.swift
├── CompactionTests.swift
├── GlobPatternHelperTests.swift
├── PlanToolCatalogTests.swift
├── WorkspaceGuardTests.swift
└── ...
```

---

## 🔌 MCP 兼容配置

Athlon Agent 兼容 **Claude Desktop 格式的 MCP 配置**：

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/workspace"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-token>"
      }
    }
  }
}
```

---

## 🧪 测试

项目包含 **11 个测试文件**，覆盖核心模块：

```bash
# 运行所有测试
swift test

# 运行特定测试用例
swift test --filter CompactionTests
```

测试覆盖范围：
- 上下文压缩 (`CompactionTests`)
- 时间线排序 (`ChatTimelineOrderTests`)
- 会话调和 (`SessionTurnReconcilerTests`)
- 工具路由 (`CompositeToolRouterTests`)
- 工作区安全 (`WorkspaceGuardTests`, `ToolPathDisplayTests`)
- Glob 模式 (`GlobPatternHelperTests`)
- 计划工具 (`PlanToolCatalogTests`)
- 配置对齐 (`ConfigAlignmentTests`)
- 命令审计 (`ExecuteCommandAuditTests`)
- 压缩审计 (`CompactionAuditDisplayTests`)

---

## 🤝 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交修改 (`git commit -am 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

### 开发规范

- 遵循 Swift API 设计规范
- 所有公开 API 添加文档注释
- 核心逻辑需编写单元测试
- 保持与现有架构风格一致（MVVM + 服务层）
- 新增工具需注册到 `BuiltInTools` 或 `CompositeToolRouter`

---

## 📄 开源协议

本项目采用 MIT 协议 — 详见 [LICENSE](LICENSE) 文件。

---

<p align="center">
  <sub>Built with ❤️ for the macOS developer community</sub>
</p>
