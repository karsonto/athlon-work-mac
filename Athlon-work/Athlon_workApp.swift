//
//  Athlon_workApp.swift
//  Athlon-work
//
//  Created by karson on 2026/7/29.
//

import SwiftUI

@main
struct Athlon_workApp: App {
    @State private var store = MainShellStore()

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environment(store)
                .frame(
                    minWidth: AppLayoutMetrics.windowMinWidth,
                    minHeight: AppLayoutMetrics.windowMinHeight
                )
                .onAppear {
                    // No license / SSO gates — ensure data dirs and apply language preference.
                    try? AppPathProvider().ensureCreated()
                    _ = L10n.Language.parse(store.settings.ui.language)
                }
        }
        .defaultSize(
            width: AppLayoutMetrics.windowMinWidth,
            height: AppLayoutMetrics.windowMinHeight
        )
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("menu.newSession", language: store.language)) {
                    store.createSession()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("View") {
                Button(L10n.t("menu.toggleNav", language: store.language)) {
                    store.toggleNavVisible()
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button(L10n.t("menu.toggleContext", language: store.language)) {
                    store.toggleContextVisible()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
    }
}
