import Foundation

enum AppPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case chat
    case settings
    case knowledge
    case schedule

    var id: String { rawValue }

    func title(language: String) -> String {
        switch self {
        case .chat: return L10n.t("nav.chat", language: language)
        case .settings: return L10n.t("nav.settings", language: language)
        case .knowledge: return L10n.t("nav.knowledge", language: language)
        case .schedule: return L10n.t("nav.schedule", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        case .knowledge: return "books.vertical"
        case .schedule: return "calendar"
        }
    }
}
