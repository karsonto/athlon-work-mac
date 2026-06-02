import SwiftUI

// MARK: - Custom Title Bar
struct TitleBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Drag region
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(appState.theme == .dark
                        ? Color(hex: "#6366F1") : Color(hex: "#4F46E5"))
                Text("Athlon Agent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(appState.theme == .dark
                        ? Color(hex: "#F4F4F5") : Color(hex: "#18181B"))
            }
            .padding(.leading, 16)

            Spacer()

            // Window controls (macOS traffic lights are handled by the system)
        }
        .frame(height: LayoutMetrics.titleBarHeight)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(appState.theme == .dark
                    ? Color(hex: "#3F3F46").opacity(0.3)
                    : Color(hex: "#D4D4D8").opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
