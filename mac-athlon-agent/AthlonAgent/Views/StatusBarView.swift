import SwiftUI

// MARK: - Bottom Status Bar
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Model status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#22C55E"))
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#A1A1AA"))
            }

            Spacer()

            // Current model
            Text("Model: gpt-4o")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#A1A1AA"))

            Spacer()

            // Logs path
            Text("Logs: \(appState.logsPath)")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#A1A1AA"))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(appState.logsPath)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(height: LayoutMetrics.statusBarHeight)
        .background(
            appState.theme == .dark
                ? Color(hex: "#27272A")
                : Color(hex: "#F4F4F5")
        )
        .overlay(
            Rectangle()
                .fill(appState.theme == .dark
                    ? Color(hex: "#3F3F46")
                    : Color(hex: "#D4D4D8"))
                .frame(height: 1),
            alignment: .top
        )
    }
}
