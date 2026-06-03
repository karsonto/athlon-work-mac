import SwiftUI

// MARK: - Settings Page
struct SettingsPageView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .model

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.text)
                Spacer()
                Button("返回") {
                    appState.currentPage = .chat
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(colors.accent)
            }
            .padding(.horizontal, 20)
            .frame(height: LayoutMetrics.splitPaneHeaderHeight)
            .background(colors.chrome)
            .overlay(Rectangle().fill(colors.border.opacity(0.6)).frame(height: 1), alignment: .bottom)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        settingsTabRow(tab)
                    }
                    Spacer()
                }
                .frame(width: 180)
                .background(colors.panel)

                Rectangle().fill(colors.border).frame(width: 1)

                ScrollView {
                    settingsTabContent
                        .frame(maxWidth: LayoutMetrics.settingsMaxWidth, alignment: .leading)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(colors.appBackground)
    }

    @ViewBuilder
    private func settingsTabRow(_ tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.iconName)
                    .frame(width: 18)
                Text(tab.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundColor(selectedTab == tab ? colors.navActiveText : colors.subtleText)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? colors.navActiveBg : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch selectedTab {
        case .model:
            modelSettingsContent
        case .compaction:
            compactionSettingsContent
        case .mcp:
            mcpSettingsContent
        case .skills:
            skillsSettingsContent
        case .permissions:
            permissionsSettingsContent
        case .ignore:
            ignoreSettingsContent
        case .workspace:
            workspaceSettingsContent
        case .appearance:
            appearanceSettingsContent
        case .plan:
            planSettingsContent
        case .agentTurn:
            agentTurnSettingsContent
        case .logging:
            loggingSettingsContent
        }
    }

    private var modelSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型配置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            settingsField("Provider", text: $appState.settings.model.provider, placeholder: "openai")
            settingsField("API Endpoint", text: $appState.settings.model.endpoint, placeholder: "https://api.openai.com/v1")
            settingsField("Model Name", text: $appState.settings.model.modelName, placeholder: "gpt-4o")
            settingsField("Max Tokens", text: maxTokensBinding, placeholder: "0 (auto)")
            settingsField("API Key", text: $appState.settings.model.apiKey, placeholder: "sk-...", secure: true)

            Toggle("启用流式输出", isOn: $appState.settings.model.enableStreaming)
                .font(.system(size: 13))
                .toggleStyle(.switch)
                .foregroundColor(colors.text)

            settingsIntField("流式空闲超时（秒）", value: $appState.settings.model.streamingIdleTimeoutSeconds)

            Button("保存设置") {
                appState.saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
        }
    }

    private var maxTokensBinding: Binding<String> {
        Binding(
            get: { appState.settings.model.maxTokens == 0 ? "" : String(appState.settings.model.maxTokens) },
            set: { appState.settings.model.maxTokens = Int($0) ?? 0 }
        )
    }

    private var mcpConfigPath: String {
        McpConfigFileService.path()
    }

    private var mcpSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MCP 服务器")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Text("高级编辑请直接修改配置文件（Claude Desktop 格式）")
                .font(.system(size: 13))
                .foregroundColor(colors.subtleText)

            Text(mcpConfigPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(colors.subtleText)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(mcpConfigPath, inFileViewerRootedAtPath: AppPathProvider.shared.configPath)
                }
                Button("用默认编辑器打开") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mcpConfigPath))
                }
            }
            .buttonStyle(.bordered)

            ForEach(appState.settings.mcpServers) { server in
                let uiServer = appState.mcpServers.first { $0.id == server.id || $0.name == server.name }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.text)
                        Text(uiServer?.summary ?? server.transportType)
                            .font(.system(size: 11))
                            .foregroundColor(colors.subtleText)
                    }
                    Spacer()
                    Toggle("", isOn: mcpEnabledBinding(serverId: server.id))
                        .labelsHidden()
                    Circle()
                        .fill((uiServer?.isStatusHealthy == true) ? colors.success : colors.subtleText)
                        .frame(width: 8, height: 8)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(colors.panel).overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border)))
            }

            Button("保存并刷新连接") { appState.saveSettings() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
        }
    }

    private func mcpEnabledBinding(serverId: String) -> Binding<Bool> {
        Binding(
            get: {
                appState.settings.mcpServers.first(where: { $0.id == serverId })?.enabled ?? false
            },
            set: { enabled in
                guard let index = appState.settings.mcpServers.firstIndex(where: { $0.id == serverId }) else { return }
                appState.settings.mcpServers[index].enabled = enabled
            }
        )
    }

    private var skillsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("技能")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Text(SkillConfigFileService.path())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(colors.subtleText)
                .textSelection(.enabled)

            ForEach(appState.skills) { skill in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.text)
                        Text(skill.description)
                            .font(.system(size: 11))
                            .foregroundColor(colors.subtleText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: skillEnabledBinding(skillName: skill.name))
                        .labelsHidden()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(colors.panel).overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border)))
            }

            Button("保存技能设置") { appState.saveSkillSettings() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
        }
    }

    private func skillEnabledBinding(skillName: String) -> Binding<Bool> {
        Binding(
            get: {
                if let item = appState.settings.skills.first(where: { $0.name == skillName }) {
                    return item.enabled
                }
                return appState.skills.first(where: { $0.name == skillName })?.isEnabled ?? true
            },
            set: { enabled in
                if let index = appState.settings.skills.firstIndex(where: { $0.name == skillName }) {
                    appState.settings.skills[index].enabled = enabled
                } else {
                    appState.settings.skills.append(SkillSettings(name: skillName, enabled: enabled, path: skillName))
                }
            }
        )
    }

    private var workspaceSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("工作区")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            ForEach(appState.settings.workspaces) { workspace in
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(workspace.rootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(colors.subtleText)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(colors.panel).overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border)))
            }

            Button("选择当前工作区目录") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url {
                    appState.setWorkspaceRoot(url.path)
                    let entry = WorkspaceSettings(rootPath: url.path, name: url.lastPathComponent)
                    if !appState.settings.workspaces.contains(where: { $0.rootPath == entry.rootPath }) {
                        appState.settings.workspaces.append(entry)
                    }
                    appState.saveSettings()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var appearanceSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("外观")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Picker("主题", selection: $appState.settings.appearance.theme) {
                Text("深色").tag("dark")
                Text("浅色").tag("light")
            }
            .pickerStyle(.segmented)

            settingsDoubleField("字体大小", value: $appState.settings.appearance.fontSize)

            Button("保存并应用") {
                appState.saveSettings()
                appState.theme = appState.settings.appearance.theme == "light" ? .light : .dark
                appState.themeStorage = appState.settings.appearance.theme
                appState.themeManager.saveTheme(appState.theme)
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
        }
    }

    private var planSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("计划模式")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Toggle("自动续跑", isOn: $appState.settings.plan.autoContinueEnabled)
            settingsIntField("最大自动续跑轮数", value: $appState.settings.plan.maxAutoContinueRounds)
            settingsIntField("最大子任务数", value: $appState.settings.plan.maxSubtasks)
            settingsIntField("Overview 最少字符", value: $appState.settings.plan.minOverviewChars)
            settingsIntField("子任务描述最少字符", value: $appState.settings.plan.minSubtaskDescriptionChars)
            settingsIntField("子任务验收最少字符", value: $appState.settings.plan.minSubtaskExpectedOutcomeChars)
        }
    }

    private var agentTurnSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("对话回合")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            settingsIntField("超时（分钟）", value: $appState.settings.agentTurn.timeoutMinutes)
        }
    }

    private var loggingSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("日志")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Text("目录：\(appState.logsPath)")
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)

            settingsField("级别", text: $appState.settings.logging.minimumLevel, placeholder: "Information")
        }
    }

    private var compactionSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("上下文压缩")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            settingsIntField("触发消息数", value: $appState.settings.contextCompaction.triggerMessages)
            settingsIntField("触发 Token 数", value: $appState.settings.contextCompaction.triggerTokens)
            settingsIntField("保留消息数", value: $appState.settings.contextCompaction.keepMessages)
            settingsIntField("上下文窗口 Token", value: $appState.settings.contextCompaction.contextWindowTokens)

            settingsDoubleField("压缩触发比例", value: $appState.settings.contextCompaction.compactTriggerRatio)

            Toggle("压缩时包含推理内容", isOn: $appState.settings.contextCompaction.includeReasoningInModelContext)
                .font(.system(size: 13))
                .toggleStyle(.switch)

            Toggle("压缩前卸载大文件", isOn: $appState.settings.contextCompaction.offloadBeforeCompact)
                .font(.system(size: 13))
                .toggleStyle(.switch)

            DisclosureGroup("高级：摘要提示词") {
                TextEditor(text: $appState.settings.contextCompaction.summaryPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(colors.panelAlt))
            }
            .font(.system(size: 13))
            .foregroundColor(colors.text)

            Divider()

            Text("工具结果淘汰")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.text)

            Toggle("启用工具结果淘汰", isOn: $appState.settings.contextCompaction.toolResultEviction.enabled)
                .toggleStyle(.switch)
            settingsIntField("最大结果字符数", value: $appState.settings.contextCompaction.toolResultEviction.maxResultChars)
            settingsIntField("预览保留字符数", value: $appState.settings.contextCompaction.toolResultEviction.previewChars)

            Divider()

            Text("参数截断")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.text)

            Toggle("启用参数截断", isOn: $appState.settings.contextCompaction.truncateArgs.enabled)
                .toggleStyle(.switch)
            settingsIntField("最大参数长度", value: $appState.settings.contextCompaction.truncateArgs.maxArgLength)

            Button("保存设置") { appState.saveSettings() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
        }
    }

    private var permissionsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("工具权限")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            Toggle("执行 shell 命令前询问", isOn: $appState.settings.toolPermissions.askBeforeEveryCommand)
                .font(.system(size: 13))
                .toggleStyle(.switch)

            Text("命令允许前缀")
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)

            ForEach(appState.settings.toolPermissions.commandAllowList.indices, id: \.self) { index in
                HStack {
                    TextField("允许前缀", text: Binding(
                        get: { appState.settings.toolPermissions.commandAllowList[index] },
                        set: { appState.settings.toolPermissions.commandAllowList[index] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.panelAlt))

                    Button(action: {
                        appState.settings.toolPermissions.commandAllowList.remove(at: index)
                    }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("添加允许前缀") {
                appState.settings.toolPermissions.commandAllowList.append("git")
            }
            .font(.system(size: 12))

            Text("命令拒绝列表")
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)

            ForEach(appState.settings.toolPermissions.commandDenyList.indices, id: \.self) { index in
                HStack {
                    TextField("命令模式", text: Binding(
                        get: { appState.settings.toolPermissions.commandDenyList[index] },
                        set: { appState.settings.toolPermissions.commandDenyList[index] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.panelAlt))

                    Button(action: {
                        appState.settings.toolPermissions.commandDenyList.remove(at: index)
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("添加拒绝项") {
                appState.settings.toolPermissions.commandDenyList.append("")
            }
            .buttonStyle(.plain)
            .foregroundColor(colors.accent)

            Button("保存设置") { appState.saveSettings() }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
        }
    }

    private var ignoreSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("忽略目录")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.text)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 6) {
                ForEach(appState.settings.workspaceIgnore.directoryNames, id: \.self) { dir in
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(colors.subtleText)
                        Text(dir)
                            .font(.system(size: 11))
                            .foregroundColor(colors.text)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.panelAlt))
                }
            }
        }
    }

    private func settingsIntField(_ label: String, value: Binding<Int>) -> some View {
        settingsField(
            label,
            text: Binding(
                get: { value.wrappedValue == 0 ? "" : String(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) ?? 0 }
            ),
            placeholder: "0"
        )
    }

    private func settingsDoubleField(_ label: String, value: Binding<Double>) -> some View {
        settingsField(
            label,
            text: Binding(
                get: { String(value.wrappedValue) },
                set: { value.wrappedValue = Double($0) ?? value.wrappedValue }
            ),
            placeholder: "0.7"
        )
    }

    @ViewBuilder
    private func settingsField(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(colors.panelAlt))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case model, compaction, mcp, skills, workspace, appearance, plan, agentTurn, logging, permissions, ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: "模型"
        case .compaction: "上下文压缩"
        case .mcp: "MCP 服务"
        case .skills: "技能"
        case .workspace: "工作区"
        case .appearance: "外观"
        case .plan: "计划"
        case .agentTurn: "对话回合"
        case .logging: "日志"
        case .permissions: "工具权限"
        case .ignore: "忽略目录"
        }
    }

    var iconName: String {
        switch self {
        case .model: "brain"
        case .compaction: "arrow.down.right.and.arrow.up.left"
        case .mcp: "server.rack"
        case .skills: "sparkles"
        case .workspace: "folder"
        case .appearance: "paintbrush"
        case .plan: "list.bullet.rectangle"
        case .agentTurn: "clock"
        case .logging: "doc.text"
        case .permissions: "lock.shield"
        case .ignore: "eye.slash"
        }
    }
}
