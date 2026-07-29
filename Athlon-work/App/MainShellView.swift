import SwiftUI

struct MainShellView: View {
    @Environment(MainShellStore.self) private var store

    private var chrome: UiChromeColors { store.themeManager.chrome }

    var body: some View {
        HSplitView {
            if store.navVisible {
                NavigationSidebarView()
                    .frame(
                        minWidth: UiLayoutConstraints.navigationSidebarMinWidth,
                        idealWidth: AppLayoutMetrics.navDefaultWidth,
                        maxWidth: UiLayoutConstraints.navigationSidebarMaxWidth
                    )
            }

            pageHost
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            if store.contextVisible {
                ContextSidebarView()
                    .frame(
                        minWidth: UiLayoutConstraints.contextSidebarMinWidth,
                        idealWidth: AppLayoutMetrics.contextDefaultWidth,
                        maxWidth: UiLayoutConstraints.contextSidebarMaxWidth
                    )
            }
        }
        .background(chrome.appBackground.color)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.toggleNavVisible()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(L10n.t("menu.toggleNav", language: store.language))
                .keyboardShortcut("b", modifiers: [.command])
            }

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    store.toggleContextVisible()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(L10n.t("menu.toggleContext", language: store.language))
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
        .preferredColorScheme(store.themeManager.kind == .dark ? .dark : .light)
    }

    @ViewBuilder
    private var pageHost: some View {
        switch store.currentPage {
        case .chat:
            ChatPageView()
        case .settings:
            SettingsPageView()
        case .knowledge:
            KnowledgePageView()
        case .schedule:
            SchedulePageView()
        }
    }
}

#Preview {
    MainShellView()
        .environment(MainShellStore())
        .frame(width: 1280, height: 820)
        .preferredColorScheme(.dark)
}
