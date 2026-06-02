import SwiftUI
import Combine

// MARK: - Theme Manager
/// Manages application theme state with system appearance detection and persistence.
class ThemeManager: ObservableObject {
    @Published var theme: AppTheme = .dark
    @Published var effectiveColorScheme: ColorScheme = .dark

    private let defaultsKey = "app_theme"

    init() {
        loadTheme()
    }

    // MARK: - Load / Save
    private func loadTheme() {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let theme = AppTheme(rawValue: stored) {
            self.theme = theme
        } else {
            // Detect system appearance
            self.theme = detectSystemAppearance()
        }
        applyTheme()
    }

    func saveTheme(_ theme: AppTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
        applyTheme()
    }

    func toggleTheme() {
        let next: AppTheme = theme == .dark ? .light : .dark
        saveTheme(next)
    }

    private func detectSystemAppearance() -> AppTheme {
        let style = NSApp.effectiveAppearance.name
        if style == .darkAqua || style == .vibrantDark {
            return .dark
        }
        return .light
    }

    private func applyTheme() {
        effectiveColorScheme = theme == .dark ? .dark : .light
        NSApp.appearance = theme == .dark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }

    // MARK: - Theme Colors
    var colors: ThemeColors {
        theme == .dark ? .dark : .light
    }
}
