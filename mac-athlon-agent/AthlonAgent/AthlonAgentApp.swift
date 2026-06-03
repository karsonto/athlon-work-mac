import SwiftUI

@main
struct AthlonAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.theme.colorScheme)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    AppDelegate.appState = appState
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新会话") {
                    appState.createNewSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("设置") {
                    appState.currentPage = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
