import SwiftUI

// MARK: - Bottom Status Bar
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Left: model status
            Text("● Local Model Active")
                .font(.system(size: 12))
                .foregroundColor(colors.success)

            Spacer()

            // Center: model name
            Text("模型: \(appState.settings.model.modelName)")
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)

            Spacer()

            // Right: logs path
            Text("Logs: \(logsPath)")
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, 10)
        .background(colors.chrome)
        .overlay(
            Rectangle()
                .fill(colors.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var logsPath: String {
        appState.logsPath
    }
}
