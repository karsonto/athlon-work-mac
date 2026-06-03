import SwiftUI

// MARK: - Bottom Status Bar
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var connectionColor: Color {
        if appState.agentRuntime?.error != nil {
            return colors.danger
        }
        if appState.isAgentRunning {
            return colors.accent
        }
        return colors.success
    }

    private var connectionLabel: String {
        if appState.agentRuntime?.error != nil {
            return "Error"
        }
        if appState.isAgentRunning {
            return "Generating"
        }
        return "Ready"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text(connectionLabel)
                    .font(.system(size: 11))
                    .foregroundColor(colors.subtleText)
            }

            Spacer()

            Text("Model: \(appState.settings.model.modelName)")
                .font(.system(size: 11))
                .foregroundColor(colors.subtleText)

            Spacer()

            Text("Logs: \(appState.logsPath)")
                .font(.system(size: 11))
                .foregroundColor(colors.subtleText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(appState.logsPath)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(height: LayoutMetrics.statusBarHeight)
        .background(colors.chrome)
        .overlay(
            Rectangle()
                .fill(colors.border.opacity(0.6))
                .frame(height: 1),
            alignment: .top
        )
    }
}
