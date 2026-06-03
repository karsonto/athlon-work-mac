import SwiftUI

// MARK: - Custom Title Bar
struct TitleBarView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#7DD3FC"), colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Athlon Agent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.text)

            Spacer()
        }
        .padding(.horizontal, LayoutMetrics.titleBarPaddingHorizontal)
        .frame(height: LayoutMetrics.titleBarHeight)
        .background(colors.chrome)
        .background(WindowDragHandle())
        .overlay(
            Rectangle()
                .fill(colors.border.opacity(0.6))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
