import SwiftUI

// MARK: - Layout Metrics
/// Aligned with WPF AppLayoutMetrics and MainWindow.xaml layout contract.
enum LayoutMetrics {
    static let splitPaneHeaderHeight: CGFloat = 48
    static let titleBarHeight: CGFloat = 64
    static let titleBarPaddingHorizontal: CGFloat = 24

    static let sidebarMinWidth: CGFloat = 180
    static let sidebarMaxWidth: CGFloat = 480
    static let sidebarDefaultWidth: CGFloat = 220

    static let contextSidebarMinWidth: CGFloat = 220
    static let contextSidebarMaxWidth: CGFloat = 560
    static let contextSidebarDefaultWidth: CGFloat = 300
    static let contextSidebarCollapseThreshold: CGFloat = 200

    static let editorPaneDefaultWidth: CGFloat = 480
    static let editorPaneMinWidth: CGFloat = 280
    static let editorPaneMaxWidth: CGFloat = 1200

    static let statusBarHeight: CGFloat = 36
    static let splitterHitArea: CGFloat = 8

    static let composerDefaultHeight: CGFloat = 168
    static let composerMinHeight: CGFloat = 120
    static let composerMaxHeight: CGFloat = 420
    static let composerMaxWidth: CGFloat = 900
    static let composerCornerRadius: CGFloat = 28
    static let composerOuterPaddingHorizontal: CGFloat = 20
    static let composerOuterPaddingVertical: CGFloat = 16
    static let composerInnerPaddingHorizontal: CGFloat = 16
    static let composerInnerPaddingVertical: CGFloat = 14
    static let composerTextMinHeight: CGFloat = 56
    static let composerFontSize: CGFloat = 15
    static let sendButtonSize: CGFloat = 40

    static let messageBubbleMaxWidth: CGFloat = 640
    static let userBubbleMaxWidth: CGFloat = 520
    static let messageBubbleCornerRadius: CGFloat = 24
    static let messageBubblePaddingH: CGFloat = 20
    static let messageBubblePaddingV: CGFloat = 16
    static let messageSpacing: CGFloat = 16

    static let chatScrollPaddingTop: CGFloat = 20
    static let chatScrollPaddingHorizontal: CGFloat = 24
    static let chatScrollPaddingBottom: CGFloat = 28

    static let settingsMaxWidth: CGFloat = 760
    static let navButtonCornerRadius: CGFloat = 16
}
