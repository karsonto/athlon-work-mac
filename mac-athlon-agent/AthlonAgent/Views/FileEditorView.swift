import SwiftUI

// MARK: - File Editor View
struct FileEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var fileContent: String = ""
    @State private var loadError: String?
    @State private var saveError: String?

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 聊天") {
                    appState.currentPage = .chat
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(colors.accent)

                Spacer()

                Text(appState.editingFilePath ?? "文件编辑器")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.text)
                    .lineLimit(1)

                Spacer()

                Button("保存") {
                    saveFile()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(colors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(height: LayoutMetrics.splitPaneHeaderHeight)
            .background(colors.panel)
            .overlay(
                Rectangle().fill(colors.border).frame(height: 1),
                alignment: .bottom
            )

            if let loadError {
                Text(loadError)
                    .font(.system(size: 12))
                    .foregroundColor(colors.toolFailureText)
                    .padding(12)
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 12))
                    .foregroundColor(colors.toolFailureText)
                    .padding(.horizontal, 12)
            }

            TextEditor(text: $fileContent)
                .font(.system(size: 13, design: .monospaced))
                .hideScrollContentBackgroundIfAvailable()
                .padding(16)
                .background(colors.appBackground)
        }
        .background(colors.appBackground)
        .onAppear { loadFile() }
        .onValueChange(of: appState.editingFilePath) { _ in loadFile() }
    }

    private func loadFile() {
        loadError = nil
        saveError = nil
        guard let path = appState.editingFilePath else {
            fileContent = ""
            return
        }
        if let content = appState.workspaceService.readFileContent(path: path) {
            fileContent = content
        } else {
            loadError = "无法读取文件: \(path)"
            fileContent = ""
        }
    }

    private func saveFile() {
        saveError = nil
        guard let path = appState.editingFilePath else { return }
        do {
            try appState.workspaceService.writeFileContent(path: path, content: fileContent)
        } catch {
            saveError = "保存失败: \(error.localizedDescription)"
        }
    }
}
