// AthlonAgent/ViewModels/SettingsViewModel.swift
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var modelName: String = ""
    @Published var apiBaseUrl: String = ""
    @Published var apiKey: String = ""
    @Published var hasStoredApiKey: Bool = false
    @Published var maxTokens: String = ""
    @Published var workspaceRoot: String = ""
    @Published var ignoreDirectoriesText: String = ""
    @Published var statusMessage: String = "设置以 JSON 文件存储在应用数据目录下。"
    @Published var mcpServers: [McpServerSettings] = []

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        syncFromSettings()
    }

    func syncFromSettings() {
        guard let appState else { return }
        let model = appState.settings.model
        modelName = model.modelName
        apiBaseUrl = model.endpoint
        hasStoredApiKey = !model.apiKey.isEmpty
        apiKey = hasStoredApiKey ? "••••••••" : ""
        maxTokens = model.maxTokens > 0 ? String(model.maxTokens) : ""
        workspaceRoot = appState.workspaceRootPath ?? ""
        ignoreDirectoriesText = appState.settings.workspaceIgnore.directoryNames
            .joined(separator: "\n")
        mcpServers = appState.settings.mcpServers
    }

    func save() {
        guard let appState else { return }
        appState.settings.model.modelName = modelName
        appState.settings.model.endpoint = apiBaseUrl
        if !apiKey.isEmpty && apiKey != "••••••••" {
            appState.settings.model.apiKey = apiKey
        }
        if let tokens = Int(maxTokens) {
            appState.settings.model.maxTokens = tokens
        }
        appState.workspaceRootPath = workspaceRoot.isEmpty ? nil : workspaceRoot
        appState.settings.workspaceIgnore.directoryNames = ignoreDirectoriesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        appState.settings.mcpServers = mcpServers
        appState.saveSettings()
        statusMessage = "设置已保存。"
    }
}
