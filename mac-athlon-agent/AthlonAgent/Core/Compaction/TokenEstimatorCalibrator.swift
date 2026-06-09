import Foundation

protocol TokenEstimatorCalibrating: Sendable {
    func getMultiplier(sessionId: String) -> Double
    func observe(sessionId: String, estimatedPromptTokens: Int, actualPromptTokens: Int?)
}

final class TokenEstimatorCalibrator: TokenEstimatorCalibrating, @unchecked Sendable {
    private let settings: AppSettings
    private let lock = NSLock()
    private var multipliers: [String: Double] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    func getMultiplier(sessionId: String) -> Double {
        guard settings.contextCompaction.dynamicCompaction.enableUsageCalibration,
              !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 1.0
        }
        lock.lock()
        defer { lock.unlock() }
        return multipliers[sessionId] ?? 1.0
    }

    func observe(sessionId: String, estimatedPromptTokens: Int, actualPromptTokens: Int?) {
        guard settings.contextCompaction.dynamicCompaction.enableUsageCalibration,
              !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let actual = actualPromptTokens, actual > 0,
              estimatedPromptTokens > 0 else {
            return
        }

        let alpha = min(1.0, max(0.01, settings.contextCompaction.dynamicCompaction.usageCalibrationAlpha))
        var observed = Double(actual) / Double(estimatedPromptTokens)
        observed = min(2.5, max(0.5, observed))

        lock.lock()
        defer { lock.unlock() }
        let previous = multipliers[sessionId] ?? 1.0
        multipliers[sessionId] = previous + alpha * (observed - previous)
    }
}
