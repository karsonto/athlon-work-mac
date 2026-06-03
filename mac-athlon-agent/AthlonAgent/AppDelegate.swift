import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first { $0.isVisible }?.makeKey()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState = Self.appState else {
            return .terminateNow
        }
        if appState.isShuttingDown {
            return .terminateNow
        }

        Task { @MainActor in
            await appState.shutdownAsync()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
