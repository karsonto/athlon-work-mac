import SwiftUI

// MARK: - Content View (3-Column Layout)
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        ZStack {
            colors.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TitleBarView()
                    .environmentObject(appState)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if appState.isNavigationSidebarVisible {
                            NavigationSidebarView()
                                .environmentObject(appState)
                                .frame(width: appState.navigationSidebarWidth)
                                .background(colors.panel)

                            DraggableSidebarSplitter(edge: .navigation)
                                .environmentObject(appState)
                        }

                        VStack(spacing: 0) {
                            contentArea
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(colors.chatBackground)

                            if appState.currentPage == .chat || appState.currentPage == .welcome {
                                StatusBarView()
                                    .environmentObject(appState)
                            }
                        }

                        if appState.isContextSidebarVisible {
                            DraggableSidebarSplitter(edge: .context)
                                .environmentObject(appState)

                            ContextSidebarView()
                                .environmentObject(appState)
                                .frame(width: appState.contextSidebarWidth)
                                .background(colors.panel)
                        }
                    }
                    .onAppear {
                        clampSidebarWidths(for: geo.size.width)
                    }
                    .onChange(of: geo.size.width) { _, width in
                        clampSidebarWidths(for: width)
                    }
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .preferredColorScheme(appState.theme.colorScheme)
        .environment(\.themeColors, colors)
        .background(WindowConfigurator())
    }

    @ViewBuilder
    private var contentArea: some View {
        switch appState.currentPage {
        case .chat, .welcome:
            ChatPageView()
                .environmentObject(appState)
        case .settings:
            SettingsPageView()
                .environmentObject(appState)
        case .fileEditor:
            FileEditorView()
                .environmentObject(appState)
        }
    }

    private func clampSidebarWidths(for totalWidth: CGFloat) {
        let minCenter: CGFloat = 400
        let maxSidebars = max(totalWidth - minCenter, 0)
        if appState.navigationSidebarWidth + appState.contextSidebarWidth > maxSidebars {
            let ratio = maxSidebars / (appState.navigationSidebarWidth + appState.contextSidebarWidth)
            appState.navigationSidebarWidth = max(LayoutMetrics.sidebarMinWidth, appState.navigationSidebarWidth * ratio)
            appState.contextSidebarWidth = max(LayoutMetrics.contextSidebarMinWidth, appState.contextSidebarWidth * ratio)
        }
    }
}
