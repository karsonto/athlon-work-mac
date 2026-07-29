import SwiftUI

struct FileEditorView: View {
    @Bindable var editor: FileEditorStore
    var onClose: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextEditor(text: $editor.content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if let error = editor.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if let status = editor.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
            Text(editor.displayPath.isEmpty ? editor.filePath : editor.displayPath)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .help(editor.filePath)
            if editor.isDirty {
                Text("•")
                    .foregroundStyle(.orange)
                    .help("未保存的更改")
            }
            Spacer(minLength: 8)
            Button("保存") { onSave() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!editor.isDirty)
                .keyboardShortcut("s", modifiers: [.command])
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭编辑器")
        }
        .padding(.horizontal, 12)
        .frame(height: AppLayoutMetrics.splitPaneHeaderHeight)
    }
}
