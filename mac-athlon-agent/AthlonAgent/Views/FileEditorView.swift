// AthlonAgent/Views/FileEditorView.swift
import SwiftUI
import AppKit

struct FileEditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = FileEditorViewModel(appState: AppState())

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
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
                .background(colors.panelAlt)

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

                    // Text editor with syntax highlighting
                    CodeEditorContentView(
                        text: Binding(
                            get: { doc.content },
                            set: { doc.onContentChanged($0) }
                        ),
                        isReadOnly: doc.isReadOnly,
                        filePath: doc.filePath,
                        isDark: appState.theme == .dark
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(colors.subtleText)
                    Text("无打开的文件")
                        .font(.system(size: 13))
                        .foregroundColor(colors.subtleText)
                    Text("从侧栏工作区树双击文件打开")
                        .font(.system(size: 11))
                        .foregroundColor(colors.disabledText)
                    Spacer()
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
        .onAppear {
            viewModel.appState = appState
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
