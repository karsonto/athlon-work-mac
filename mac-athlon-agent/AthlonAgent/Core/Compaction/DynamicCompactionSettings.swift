import Foundation

struct DynamicCompactionSettings: Codable, Equatable {
    var enabled: Bool = true
    var targetUtilization: Double = 0.80
    var postCompactionUtilization: Double = 0.30
    var safetyMarginRatio: Double = 0.08
    var defaultReservedOutputTokens: Int = 8192
    var truncateLeadRatio: Double = 0.90
    var overflowPostCompactionUtilization: Double = 0.20
    var enableSemanticCutoff: Bool = true
    var enableUsageCalibration: Bool = true
    var usageCalibrationAlpha: Double = 0.15

    enum CodingKeys: String, CodingKey {
        case enabled
        case targetUtilization = "target_utilization"
        case postCompactionUtilization = "post_compaction_utilization"
        case safetyMarginRatio = "safety_margin_ratio"
        case defaultReservedOutputTokens = "default_reserved_output_tokens"
        case truncateLeadRatio = "truncate_lead_ratio"
        case overflowPostCompactionUtilization = "overflow_post_compaction_utilization"
        case enableSemanticCutoff = "enable_semantic_cutoff"
        case enableUsageCalibration = "enable_usage_calibration"
        case usageCalibrationAlpha = "usage_calibration_alpha"
    }
}
