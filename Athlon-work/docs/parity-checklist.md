# Athlon Agent macOS — Parity Checklist (P0–P8)

对照 Windows Athlon Agent；状态：`[ ]` 未做 / `[~]` 进行中 / `[x]` 完成 / `[-]` 明确不做。

## P0 — 契约冻结与资源

- [x] `AgentStreamEvent` Swift 同构枚举
- [x] `ChatEventSerializer` AG-UI JSON（camelCase payload）
- [x] 会话目录 schema（`session.json` / `conversation.jsonl` / `subagents/default/{id}`）
- [x] `AppSettings`（无 SSO / License）
- [x] Chat 资源搬迁（`Resources/Chat/**`）
- [x] `ChatHtmlBuilder` 壳 HTML + 主题 CSS tokens
- [x] `docs/agui-event-contract.md`
- [x] `chat-fixture-events.json` replay fixture
- [x] 本 parity checklist

## P1 — SwiftUI 壳 + WKWebView 空转

- [x] 三栏壳（导航 / 聊天 / 右栏）尺寸对齐
- [x] Chat / Settings / Knowledge / Schedule 导航入口
- [x] `ChatWebView`：`handleEvent` / `replayEvents` / script message handler
- [x] Dark/Light 主题切换热更新（`applyThemeUpdate`）
- [x] 空状态 + Composer 布局对齐
- [x] Fixture 注入后时间线视觉接近 Windows

## P2 — AgentRuntime 核心循环

- [x] `AgentRuntime` / turn coordinator / tool pipeline
- [x] `AgentStreamAdapter` → AG-UI 事件
- [x] OpenAI-compatible streaming client
- [x] `FileStorageService` 会话读写接入 Runtime
- [x] Keychain API key（`model-api-key`）
- [x] macOS 命令工具（`/bin/zsh -lc`，UTF-8）
- [x] Compaction / hygiene 中间件骨架
- [x] 单轮 file_list / file_read 可跑通

## P3 — 内置工具 + 审批

- [x] `file_list` / `file_read` / `file_write` / `file_edit` / `apply_patch`
- [x] `grep_files` / `glob_files` / `execute_command`
- [x] Tool approval（Ask / Deny）+ `TOOL_APPROVAL_*`
- [x] Workspace guard + ignore patterns
- [x] `TOOL_CALL_OUTPUT` 流式可见

## P4 — 会话 UI 主路径

- [x] Session list create / switch / delete
- [x] Streaming bubbles + tool cards + reasoning
- [x] 历史回放 / load-older
- [x] Composer 发送 / 停止 / 附件
- [x] 并发 turn / 队列 UI
- [x] 切换会话不串流

## P5 — Settings / Workspace / 右栏

- [x] Model / 语言 / Compaction / MCP Search / Tool Approval 设置页
- [x] Knowledge Embedding / Training Data 设置（无 SSO/License 文案）
- [x] Workspace 树 + Reveal in Finder
- [x] 基础编辑器 / 预览
- [x] Skills + MCP 状态芯片
- [x] `config/settings.json` 持久化

## P6 — MCP / Skills / Knowledge / Memory

- [x] Skills 加载 + prompt 渲染（`~/.athlon-agent/skills`）
- [x] MCP stdio（streamable HTTP 后续）
- [x] MCP tool search 模式（stub）
- [x] Knowledge 文件索引 + 关键词检索进 turn（SQLite/embeddings 后续）
- [x] Long-term memory（`MEMORY.md` / daily notes；consolidation 后续增强）

## P7 — SubAgent / Schedule / Plan / SSH / 预览

- [x] SubAgent spawn / send / history + 目录布局
- [x] Schedule 日/间隔/一次性任务 + KeepAwake
- [x] Plan harness 文档预览 + Composer 模式
- [x] Mermaid / HTML 预览窗
- [x] SSH workspace（`ssh` 进程 list/read + 本地 fallback）

## P8 — 本地化、打磨、收口

- [x] zh-CN / en-US 字符串表（`L10n`）
- [x] 主题/侧栏快捷键（⌘B / ⌘⌥B / ⌘N / ⌘Enter）
- [x] golden transcript 对比说明
- [x] Developer ID / 公证打包方案（无 Velopack）
- [x] 勾选 P0–P8 主要验收项

## Explicitly out of scope

- [-] ImpSSO / SSO 启动门 / 左栏 SSO 身份条
- [-] License / 注册 / `license.lic`
- [-] Velopack 自动更新（另立方案）
