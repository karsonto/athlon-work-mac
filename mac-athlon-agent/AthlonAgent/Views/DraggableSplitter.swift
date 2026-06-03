import SwiftUI

struct DraggableSidebarSplitter: View {
    @EnvironmentObject var appState: AppState
    let edge: SplitterEdge

    enum SplitterEdge {
        case navigation
        case context
    }

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    var body: some View {
        Rectangle()
            .fill(colors.border.opacity(0.6))
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        switch edge {
                        case .navigation:
                            appState.navigationSidebarWidth = max(
                                LayoutMetrics.sidebarMinWidth,
                                appState.navigationSidebarWidth + value.translation.width
                            )
                        case .context:
                            appState.contextSidebarWidth = max(
                                0,
                                appState.contextSidebarWidth - value.translation.width
                            )
                        }
                    }
                    .onEnded { _ in
                        if edge == .context {
                            if appState.contextSidebarWidth < LayoutMetrics.contextSidebarCollapseThreshold {
                                appState.isContextSidebarVisible = false
                                appState.contextSidebarWidth = max(
                                    appState.contextSidebarWidth,
                                    LayoutMetrics.contextSidebarDefaultWidth
                                )
                            } else {
                                appState.contextSidebarWidth = min(
                                    max(appState.contextSidebarWidth, LayoutMetrics.contextSidebarMinWidth),
                                    LayoutMetrics.contextSidebarMaxWidth
                                )
                            }
                        }
                        appState.persistUiSettingsDebounced()
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}
