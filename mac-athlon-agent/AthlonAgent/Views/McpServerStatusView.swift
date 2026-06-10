// AthlonAgent/Views/McpServerStatusView.swift
import SwiftUI

struct McpServerStatusView: View {
    let servers: [McpServerStatusItem]
    let colors: ThemeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(servers) { server in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Circle()
                                .fill(statusColor(server))
                                .frame(width: 8, height: 8)
                            Text(server.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colors.text)
                        }
                        if let status = server.status {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Circle()
                                    .fill(connectionColor(status))
                                    .frame(width: 6, height: 6)
                                Text(statusLabel(status))
                                    .font(.system(size: 11))
                                    .foregroundColor(colors.subtleText)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }

    private func statusColor(_ server: McpServerStatusItem) -> Color {
        guard server.isEnabled else { return .gray }
        guard let status = server.status else { return .orange }
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .error, .disconnected:
            return .red
        }
    }

    private func connectionColor(_ status: McpUiConnectionState) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .error, .disconnected: return .red
        }
    }

    private func statusLabel(_ status: McpUiConnectionState) -> String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中…"
        case .error: return "错误"
        case .disconnected: return "已断开"
        }
    }
}
