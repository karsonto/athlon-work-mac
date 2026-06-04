import SwiftUI

@main
enum AthlonAgentAppLauncher {
    static func main() {
        if #available(macOS 13.0, *) {
            AthlonAgentAppModern.main()
        } else {
            AthlonAgentAppLegacy.main()
        }
    }
}

private struct AthlonAgentRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .preferredColorScheme(appState.theme.colorScheme)
            .frame(minWidth: 1100, minHeight: 720)
            .onAppear {
                AppDelegate.appState = appState
            }
    }
}

private struct AthlonAgentCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
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

struct AthlonAgentAppLegacy: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AthlonAgentRootView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AthlonAgentCommands(appState: appState)
        }
    }
}

@available(macOS 13.0, *)
struct AthlonAgentAppModern: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AthlonAgentRootView(appState: appState)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AthlonAgentCommands(appState: appState)
        }
    }
}
