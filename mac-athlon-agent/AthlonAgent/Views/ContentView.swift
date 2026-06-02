import SwiftUI

// MARK: - Content View (3-Column Layout)
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sidebarWidth: CGFloat = LayoutMetrics.sidebarDefaultWidth
    @State private var contextWidth: CGFloat = LayoutMetrics.contextSidebarDefaultWidth

    private var currentColors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        ZStack {
            currentColors.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TitleBarView()
                    .environmentObject(appState)

                // 3-pane layout
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        // Left sidebar
                        NavigationSidebarView()
                            .environmentObject(appState)
                            .frame(width: sidebarWidth)
                            .background(currentColors.panel)

                        // Divider
                        Rectangle()
                            .fill(currentColors.border)
                            .frame(width: 1)

                        // Center content area
                        contentArea
                            .background(currentColors.chatBackground)

                        // Right sidebar (conditional)
                        if sidebarWidth + contextWidth < geo.size.width - 60 {
                            Rectangle()
                                .fill(currentColors.border)
                                .frame(width: 1)

                            ContextSidebarView()
                                .environmentObject(appState)
                                .frame(width: contextWidth)
                                .background(currentColors.panel)
                        }
                    }
                }

                StatusBarView()
                    .environmentObject(appState)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .preferredColorScheme(appState.theme.colorScheme)
    }

    // MARK: - Route-based Content
    @ViewBuilder
    private var contentArea: some View {
        switch appState.currentPage {
        case .chat:
            ChatPageView()
                .environmentObject(appState)
        case .settings:
            SettingsPageView()
        case .fileEditor:
            FileEditorView()
                .environmentObject(appState)
        case .welcome:
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundColor(currentColors.accent)
                Text("Welcome to Athlon Agent")
                    .font(.title2)
                    .foregroundColor(currentColors.text)
                Text("Start a new chat or open an existing session from the sidebar.")
                    .font(.body)
                    .foregroundColor(currentColors.subtleText)
                Button("New Chat") {
                    appState.createNewSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
