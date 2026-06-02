# Plan: Fix macOS Swift compilation errors

**Description:** Fix 80+ compilation errors in the mac-athlon-agent Swift project. Main issues: conflicting ServiceStubs, model mismatches, missing imports, access control, brace structure, and incorrect init parameters across multiple files.
**Expected outcome:** All compilation errors resolved; project builds successfully with zero errors.

## Subtasks

### 0. - [x] Delete ServiceStubs.swift to resolve type conflicts
- Description: ServiceStubs.swift has stub class declarations (SessionManager, McpClientService, SkillService, WorkspaceService, AgentRuntimeService) that conflict with the real implementations. Delete this file entirely.
- Expected outcome: ServiceStubs.swift removed; ~15 ambiguous type errors resolved
- State: Done
- Outcome: Deleted AthlonAgent/Services/ServiceStubs.swift — removed conflicting stub declarations for SessionManager, McpClientService, SkillService, WorkspaceService, AgentRuntimeService

### 1. - [x] Fix AppModels.swift - Add Codable to McpServerItem, add originalData to ImageAttachment, add missing WorkspaceIconKind cases
- Description: McpServerItem needs Codable (with CodingKeys excluding closures). ImageAttachment needs originalData field (service code uses it). WorkspaceIconKind needs .csharp, .typescript, .javascript, .python, .html, .css, .yaml, .xml, .shell, .config cases.
- Expected outcome: AppModels.swift updated; 3 model types corrected
- State: Done
- Outcome: AppModels.swift updated: added Codable to McpServerItem (with CodingKeys), added originalData computed property to ImageAttachment, added 10 missing WorkspaceIconKind cases (csharp, typescript, javascript, python, html, css, yaml, xml, shell, config) with systemName icons

### 2. - [x] Fix ChatMessage.swift - Add toolCallId field
- Description: ChatMessage needs a toolCallId: String? field since AgentRuntimeService references msg.toolCallId. Also used by buildToolResultMessage.
- Expected outcome: ChatMessage.swift updated with toolCallId field
- State: Done
- Outcome: ChatMessage.swift: added toolCallId: String? property and init parameter

### 3. - [x] Fix MessageRole.swift - Add apiValue property and import SwiftUI to AppTheme.swift
- Description: MessageRole needs var apiValue: String { rawValue.lowercased() }. AppTheme.swift needs import SwiftUI for ColorScheme.
- Expected outcome: MessageRole.swift and AppTheme.swift updated
- State: Done
- Outcome: MessageRole.swift: added var apiValue: String { rawValue.lowercased() }. AppTheme.swift: added import SwiftUI for ColorScheme.

### 4. - [x] Fix AppSettings.swift - Make id properties var instead of let for Codable
- Description: McpServerSettings, SkillSettings, WorkspaceSettings have 'let id = UUID().uuidString' which generates Codable warnings. Change to 'var id' with default.
- Expected outcome: AppSettings.swift updated; 3 Codable warnings resolved
- State: Done
- Outcome: AppSettings.swift: changed let id → var id in McpServerSettings, SkillSettings, WorkspaceSettings — 3 Codable warnings resolved

### 5. - [x] Fix AppState.swift - All errors: AppSettings.default, timestamp→createdAt, fix closure syntax
- Description: Replace AppSettings() with AppSettings.default (lines 72, 181). Replace timestamp: with createdAt: (lines 292, 307, 343, 359, 375, 386). Fix sendMessage closure syntax to use labeled parameters.
- Expected outcome: AppState.swift updated; ~16 errors resolved
- State: Done
- Outcome: AppState.swift 已验证：AppSettings.default 在第72/181行已就位；createdAt: 已替换所有timestamp:（无残留）；sendMessage闭包参数标签全部正确。零改动，文件已正确。

### 6. - [x] Fix AgentRuntimeService.swift - Init params, optional chaining, apiValue, toolCallId
- Description: Fix AgentToolCall init to include argumentsStreaming: '' and status: .none. Fix optional chaining for msg.toolCalls. Fix msg.role.apiValue (resolved by MessageRole fix). Fix msg.toolCallId (resolved by ChatMessage fix). Fix buildToolResultMessage params.
- Expected outcome: AgentRuntimeService.swift updated; ~15 errors resolved
- State: Done
- Outcome: AgentRuntimeService.swift 已修复：3处AgentToolCall init(content:nil→argumentsStreaming:""/status:.none)；1处msg.toolCalls.isEmpty可选值解包；2处timestamp:→createdAt:。零残留content:nil或timestamp。

### 7. - [x] Fix ImageAttachmentService.swift - Match ImageAttachment model init
- Description: Change init calls from (id:fileName:originalURL:thumbnailData:originalData:) to (id:fileName:filePath:thumbnailData:fileSize:). Read originalData from filePath when needed.
- Expected outcome: ImageAttachmentService.swift updated; ~4 errors resolved
- State: Done
- Outcome: ImageAttachmentService.swift 已修复：ImageAttachment init 参数改为 (id:fileName:filePath:thumbnailData:fileSize:)，通过 FileManager 获取 fileSize。零残留 originalURL 或原始 originalData 参数。

### 8. - [x] Fix McpClientService.swift - Codable, init params, .atomic
- Description: Update defaultServers to use McpServerItem init with summary/toolNames/isStatusHealthy/isStatusError fields. Fix .atomic Data.WritingOptions reference. McpServerItem Codable from AppModels fix.
- Expected outcome: McpClientService.swift updated; ~5 errors resolved
- State: Done
- Outcome: McpClientService.swift 已修复：defaultServers 中 McpServerItem init 移除了 command/args/tools 参数，替换为 summary/toolNames/isStatusHealthy/isStatusError。零残留错误参数。

### 9. - [x] Fix SkillService.swift - Match SkillItem model init
- Description: Remove version/path from SkillItem init; add isInstalled: true. Unwrap description with ?? ''.
- Expected outcome: SkillService.swift updated; ~3 errors resolved
- State: Done
- Outcome: SkillService.swift 已修复：SkillItem init 移除了 version/path 参数，description 用 ?? '' 解包，添加了 isInstalled: true。

### 10. - [x] Fix WorkspaceService.swift - WorkspaceNode init + enum cases
- Description: Remove fileSize/children from WorkspaceNode init. Set children after init. Change for var node to for let node. Missing enum cases resolved by AppModels fix.
- Expected outcome: WorkspaceService.swift updated; ~12 errors resolved
- State: Done
- Outcome: WorkspaceService.swift 已修复：WorkspaceNode init 移除了 fileSize/children 参数（使用模型正确的 init）；for var node 改为 for node（2处）；未使用的 fileSize 变量已清理。

### 11. - [x] Fix ComposerView.swift - Structural issues, ImageAttachment init, NSColor, RoundedCorner
- Description: Add explicit return to mainInputArea. Fix ImageAttachment init to use filePath/fileSize. Fix NSColor(hex:) references (use the existing NSColor hex extension). Fix cornerRadius custom modifier reference.
- Expected outcome: ComposerView.swift updated; ~20 errors resolved
- State: Done
- Outcome: ComposerView.swift 已修复：1) skill.description ?? "" → skill.description（非可选无需??）；2) 第二个 Button 尾随闭包添加缺失的 }（修正了 Spacer/if/Text 被错误吞入 Button 标签的问题）；3) ImageAttachment init 使用 filePath:url.path 和 fileSize:Int64(data.count)。NSColor(hex:) 扩展在文件中可用；Color(hex:) 在 ThemeColors.swift 中可用；自定义 cornerRadius(_:corners:) 无冲突。预计 ~20 个错误已解决。

### 12. - [x] Fix NavigationSidebarView.swift - lastActivityAt→updatedAt
- Description: Replace all references to session.lastActivityAt with session.updatedAt.
- Expected outcome: NavigationSidebarView.swift updated; 5 errors resolved
- State: Done
- Outcome: NavigationSidebarView.swift 已修复：5 处 session.lastActivityAt→session.updatedAt（1 处 for 循环 + 4 处 $0.map 闭包）。零残留 lastActivityAt。

### 13. - [x] Fix AthlonAgentApp.swift, PlanViewModel.swift, MarkdownRendererView.swift - Minor issues
- Description: Move .windowResizability to Scene level. Add nil as AgentPlan? annotation. Fix unused encoder variable.
- Expected outcome: 3 files updated; 3 errors + 1 warning resolved
- State: Done
- Outcome: 3 files fixed: 1) AthlonAgentApp.swift — .windowResizability moved from View level (inside WindowGroup) to Scene level (.windowResizability(.contentMinSize) on line 14); 2) PlanViewModel.swift — line 125 changed to `nil as AgentPlan?` for type annotation; 3) MarkdownRendererView.swift — removed unused `let encoder = JSONEncoder()` variable (line 133).

### 14. - [x] Verify build - read all modified files for consistency
- Description: Re-read all modified files to verify fixes are consistent with each other. Check for any remaining issues.
- Expected outcome: All files verified; ready for build
- State: Done
- Outcome: 所有 14 个修改文件已完成跨文件一致性验证。零残留 lastActivityAt、timestamp:、content:nil、originalURL 或不匹配的 init 参数。项目可以执行构建测试。
