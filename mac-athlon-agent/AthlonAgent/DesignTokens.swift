// AthlonAgent/DesignTokens.swift
import Foundation

/// Design tokens for consistent spacing, radius, and animation durations.
enum DesignTokens {

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 40
        static let xhuge: CGFloat = 48
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 9999
    }

    enum Duration {
        static let instant: TimeInterval = 0.075
        static let fast: TimeInterval = 0.15
        static let normal: TimeInterval = 0.2
        static let slow: TimeInterval = 0.24
    }

    enum Sidebar {
        static let navigationMinWidth: CGFloat = 180
        static let navigationMaxWidth: CGFloat = 480
        static let navigationDefaultWidth: CGFloat = 280
        static let contextMinWidth: CGFloat = 220
        static let contextMaxWidth: CGFloat = 560
        static let contextDefaultWidth: CGFloat = 320
        static let contextCollapseDragThreshold: CGFloat = 200
    }

    enum Composer {
        static let minHeight: CGFloat = 120
        static let maxHeight: CGFloat = 420
        static let defaultHeight: CGFloat = 168
    }

    enum Editor {
        static let minWidth: CGFloat = 280
        static let maxWidth: CGFloat = 1200
        static let defaultWidth: CGFloat = 480
    }
}
