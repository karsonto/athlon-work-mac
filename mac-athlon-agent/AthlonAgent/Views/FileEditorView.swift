import SwiftUI

// MARK: - File Editor View
struct FileEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFile: String = ""
    @State private var fileContent: String = ""

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

                Spacer()

                Button("保存") {
                    // Placeholder save
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

            // Editor
            TextEditor(text: $fileContent)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(16)
                .background(colors.appBackground)
        }
        .background(colors.appBackground)
    }
}
