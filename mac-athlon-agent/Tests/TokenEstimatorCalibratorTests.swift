import XCTest
@testable import AthlonAgent

final class TokenEstimatorCalibratorTests: XCTestCase {
    func testGetMultiplierReturnsOneWhenDisabled() {
        var settings = AppSettings.default
        settings.contextCompaction.dynamicCompaction.enableUsageCalibration = false
        let calibrator = TokenEstimatorCalibrator(settings: settings)
        XCTAssertEqual(calibrator.getMultiplier(sessionId: "s1"), 1.0)
    }

    func testObserveUpdatesMultiplierTowardObservedRatio() {
        var settings = AppSettings.default
        settings.contextCompaction.dynamicCompaction.enableUsageCalibration = true
        settings.contextCompaction.dynamicCompaction.usageCalibrationAlpha = 0.5
        let calibrator = TokenEstimatorCalibrator(settings: settings)

        calibrator.observe(sessionId: "s1", estimatedPromptTokens: 1000, actualPromptTokens: 2000)
        let multiplier = calibrator.getMultiplier(sessionId: "s1")
        XCTAssertGreaterThan(multiplier, 1.0)
        XCTAssertLessThanOrEqual(multiplier, 2.5)
    }

    func testDynamicCompactionSettingsDefaultsMatchWpf() {
        let dynamic = DynamicCompactionSettings()
        XCTAssertTrue(dynamic.enabled)
        XCTAssertEqual(dynamic.targetUtilization, 0.80, accuracy: 0.001)
        XCTAssertEqual(dynamic.postCompactionUtilization, 0.30, accuracy: 0.001)
        XCTAssertEqual(dynamic.overflowPostCompactionUtilization, 0.20, accuracy: 0.001)
    }

    func testContextPressureEvaluatorCriticalAtTargetUtilization() {
        let settings = DynamicCompactionSettings()
        let budget = ContextBudgetSnapshot(
            totalWindow: 100_000,
            reservedOutput: 8192,
            fixedOverhead: 10_000,
            historyBudget: 81_908,
            estimatedHistory: 70_000,
            utilization: 0.9
        )
        let pressure = ContextPressureEvaluator.evaluate(
            budget: budget,
            settings: settings,
            forceOverflow: false
        )
        XCTAssertEqual(pressure, .critical)
    }
}
