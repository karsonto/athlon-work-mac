import CoreGraphics
import Foundation

/// Shared layout sizes so split-pane chrome lines up with the Cursor-like shell.
enum AppLayoutMetrics {
    static let splitPaneHeaderHeight: CGFloat = 48
    static let panelHeaderHeight: CGFloat = 48
    static let scrollBarGutter: CGFloat = 6
    static let splitterHitSize: CGFloat = 12

    static let composerMaxContentWidth: CGFloat = 1120
    static let composerEmptyMaxContentWidth: CGFloat = 880
    static let composerEmptyHeroHeight: CGFloat = 180
    static let composerEmptyTextMinHeight: CGFloat = 64

    static let windowMinWidth: CGFloat = 1100
    static let windowMinHeight: CGFloat = 700
}

enum UiLayoutConstraints {
    static let contextSidebarMinWidth: CGFloat = 220
    static let contextSidebarMaxWidth: CGFloat = 560
    static let contextSidebarDefaultWidth: CGFloat = 320
    static let contextSidebarCollapseDragThreshold: CGFloat = 200

    static let navigationSidebarMinWidth: CGFloat = 220
    static let navigationSidebarMaxWidth: CGFloat = 420
    static let navigationSidebarDefaultWidth: CGFloat = 260

    static let editorPaneMinWidth: CGFloat = 280
    static let editorPaneMaxWidth: CGFloat = 1200
    static let editorPaneDefaultWidth: CGFloat = 480

    static let composerMinHeight: CGFloat = 120
    static let composerMaxHeight: CGFloat = 420
    static let composerDefaultHeight: CGFloat = 168
}

extension AppLayoutMetrics {
    static let navDefaultWidth = UiLayoutConstraints.navigationSidebarDefaultWidth
    static let contextDefaultWidth = UiLayoutConstraints.contextSidebarDefaultWidth
    static let composerDefaultHeight = UiLayoutConstraints.composerDefaultHeight
}
