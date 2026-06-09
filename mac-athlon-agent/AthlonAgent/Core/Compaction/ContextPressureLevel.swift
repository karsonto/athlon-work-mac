import Foundation

enum ContextPressureLevel: String, Codable, Equatable {
    case normal
    case elevated
    case high
    case critical
    case overflow
}
