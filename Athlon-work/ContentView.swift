//
//  ContentView.swift
//  Athlon-work
//
//  Created by karson on 2026/7/29.
//

import SwiftUI

/// Compatibility wrapper — prefer `MainShellView` via `Athlon_workApp`.
struct ContentView: View {
    var body: some View {
        MainShellView()
    }
}

#Preview {
    ContentView()
        .environment(MainShellStore())
}
