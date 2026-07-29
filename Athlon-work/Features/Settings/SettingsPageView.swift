import SwiftUI

struct SettingsPageView: View {
    @Environment(MainShellStore.self) private var store

    @State private var allowListText: String = ""
    @State private var denyListText: String = ""
    @State private var maxTokensText: String = ""

    var body: some View {
        ScrollView {
            Form {
                Section("模型") {
                    TextField("Provider", text: Bindable(store).settings.model.provider)
                    TextField("Endpoint", text: Bindable(store).settings.model.endpoint)
                    TextField("Model", text: Bindable(store).settings.model.modelName)
                    TextField("Max Tokens", text: $maxTokensText)
                        .onChange(of: maxTokensText) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                store.settings.model.maxTokens = nil
                            } else if let value = Int(trimmed) {
                                store.settings.model.maxTokens = value
                            }
                        }
                    Toggle("启用流式输出", isOn: Bindable(store).settings.model.enableStreaming)
                    SecureField("API Key", text: Bindable(store).apiKeyDraft)
                        .textContentType(.password)
                }

                Section("界面") {
                    Picker("主题", selection: themeBinding) {
                        Text("深色").tag(ThemeKind.dark)
                        Text("浅色").tag(ThemeKind.light)
                    }
                    TextField("界面语言", text: Bindable(store).settings.ui.language)
                    Toggle("显示工具调用", isOn: Bindable(store).settings.ui.showToolCalls)
                }

                Section("上下文压缩") {
                    Toggle("启用压缩", isOn: Bindable(store).settings.contextCompaction.enabled)
                }

                Section("工具审批") {
                    Toggle("启用审批", isOn: Bindable(store).settings.toolPermissions.approvalEnabled)
                    Toggle("每条命令询问", isOn: Bindable(store).settings.toolPermissions.askBeforeEveryCommand)
                    TextField("允许命令列表（逗号分隔）", text: $allowListText, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("拒绝命令列表（逗号分隔）", text: $denyListText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("MCP 搜索") {
                    Toggle("启用 MCP 工具搜索", isOn: Bindable(store).settings.mcpSearch.enabled)
                    TextField("模式 (direct|search|auto)", text: Bindable(store).settings.mcpSearch.mode)
                    TextField("Auto 工具数阈值", value: Bindable(store).settings.mcpSearch.autoThresholdToolCount, format: .number)
                }

                Section("Knowledge") {
                    Toggle("启用 Knowledge", isOn: Bindable(store).settings.knowledge.enabled)
                    TextField("Embedding Endpoint", text: Bindable(store).settings.knowledge.embedding.endpoint)
                    TextField("Embedding Model", text: Bindable(store).settings.knowledge.embedding.model)
                }

                Section("Training Data") {
                    Toggle("启用训练数据采集", isOn: Bindable(store).settings.trainingData.enabled)
                }

                Section("SubAgent / Memory / Schedule") {
                    Toggle("启用 SubAgent", isOn: Bindable(store).settings.subAgent.enabled)
                    Toggle("启用长期记忆", isOn: Bindable(store).settings.memory.enabled)
                    Toggle("启用定时任务", isOn: Bindable(store).settings.schedule.enabled)
                }

                Section {
                    Button("保存设置") {
                        applyListFields()
                        store.saveSettingsFromForm()
                    }
                    .buttonStyle(.borderedProminent)

                    if let status = store.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
        .background(store.themeManager.chrome.appBackground.color)
        .navigationTitle("设置")
        .onAppear {
            syncFormFieldsFromSettings()
        }
    }

    private var themeBinding: Binding<ThemeKind> {
        Binding(
            get: { store.themeManager.kind },
            set: { kind in
                var ui: UiSettings? = store.settings.ui
                store.themeManager.setTheme(kind, uiSettings: &ui)
                if let ui { store.settings.ui = ui }
            }
        )
    }

    private func syncFormFieldsFromSettings() {
        allowListText = store.settings.toolPermissions.commandAllowList.joined(separator: ", ")
        denyListText = store.settings.toolPermissions.commandDenyList.joined(separator: ", ")
        if let max = store.settings.model.maxTokens {
            maxTokensText = String(max)
        } else {
            maxTokensText = ""
        }
        store.apiKeyDraft = store.apiKeyDraft
    }

    private func applyListFields() {
        store.settings.toolPermissions.commandAllowList = splitCommaList(allowListText)
        store.settings.toolPermissions.commandDenyList = splitCommaList(denyListText)
        let trimmed = maxTokensText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.model.maxTokens = trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func splitCommaList(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    SettingsPageView()
        .environment(MainShellStore())
        .frame(width: 720, height: 600)
}
