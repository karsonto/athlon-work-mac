import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgePageView: View {
    @Environment(MainShellStore.self) private var store
    @State private var modules: [KnowledgeModule] = []
    @State private var searchQuery: String = ""
    @State private var searchHits: [KnowledgeSearchHit] = []
    @State private var statusMessage: String = ""
    @State private var storeRef: KnowledgeStore?
    @State private var searchService: KnowledgeSearchService?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                moduleList
                    .frame(minWidth: 220, idealWidth: 260)
                detailPane
                    .frame(minWidth: 360)
            }
        }
        .background(store.themeManager.chrome.appBackground.color)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.t("knowledge.title", language: store.settings.ui.language))
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Toggle(
                L10n.t("knowledge.enabled", language: store.settings.ui.language),
                isOn: Binding(
                    get: { store.settings.knowledge.enabled },
                    set: { enabled in
                        store.settings.knowledge.enabled = enabled
                        store.persistSettingsPublic()
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .frame(height: AppLayoutMetrics.panelHeaderHeight)
    }

    private var moduleList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("knowledge.modules", language: store.settings.ui.language))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    addFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help(L10n.t("knowledge.addFolder", language: store.settings.ui.language))
                Button {
                    addFiles()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help(L10n.t("knowledge.addFiles", language: store.settings.ui.language))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            List {
                ForEach(modules) { module in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.name)
                            .font(.system(size: 13, weight: .medium))
                        Text("\(module.documentIds.count) docs")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            removeModule(module)
                        } label: {
                            Text(L10n.t("knowledge.remove", language: store.settings.ui.language))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(store.themeManager.chrome.panel.color)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(
                    L10n.t("knowledge.searchPlaceholder", language: store.settings.ui.language),
                    text: $searchQuery
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
                Button(L10n.t("knowledge.search", language: store.settings.ui.language)) {
                    runSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if searchHits.isEmpty {
                Text(L10n.t("knowledge.searchEmpty", language: store.settings.ui.language))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Spacer()
            } else {
                List(searchHits, id: \.documentId) { hit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(hit.sourcePath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(hit.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
    }

    private func reload() {
        let ks = KnowledgeStore(paths: AppPathProvider(), settings: store.settings.knowledge)
        storeRef = ks
        searchService = KnowledgeSearchService(store: ks)
        modules = (try? ks.listModules()) ?? []
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ensureStore().addFolder(at: url.path)
            statusMessage = "Added folder: \(url.lastPathComponent)"
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .sourceCode, .json, .data]
        guard panel.runModal() == .OK else { return }
        do {
            _ = try ensureStore().addFiles(panel.urls.map(\.path))
            statusMessage = "Added \(panel.urls.count) file(s)"
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeModule(_ module: KnowledgeModule) {
        do {
            try ensureStore().removeModule(id: module.id)
            statusMessage = "Removed \(module.name)"
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func runSearch() {
        do {
            let service: KnowledgeSearchService
            if let searchService {
                service = searchService
            } else {
                service = KnowledgeSearchService(store: try ensureStore())
            }
            searchHits = try service.search(query: searchQuery, settings: store.settings.knowledge.search)
            if searchHits.isEmpty {
                statusMessage = "No hits"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func ensureStore() throws -> KnowledgeStore {
        if let storeRef { return storeRef }
        let ks = KnowledgeStore(paths: AppPathProvider(), settings: store.settings.knowledge)
        try ks.ensureReady()
        storeRef = ks
        searchService = KnowledgeSearchService(store: ks)
        return ks
    }
}

#Preview {
    KnowledgePageView()
        .environment(MainShellStore())
}
