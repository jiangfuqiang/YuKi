import Foundation

enum VoiceDenoiseStrength: String, Codable, CaseIterable, Identifiable {
    case off, standard, strong, custom
    var id: String { rawValue }
    var strengthPercent: Float {
        switch self {
        case .off, .standard: VoiceDenoiseSettings.standardStrengthPercent
        case .strong, .custom: VoiceDenoiseSettings.strongStrengthPercent
        }
    }
    var attenuationLimitDb: Float {
        switch self {
        case .off: 0
        case .standard, .strong, .custom: 100
        }
    }
    var postFilterBeta: Float { self == .strong ? 0.02 : 0 }
}

struct VoiceDenoiseSettings: Codable, Equatable {
    static let standardStrengthPercent: Float = 50
    static let strongStrengthPercent: Float = 70

    var strength: VoiceDenoiseStrength = .standard
    var customStrengthPercent: Float = Self.strongStrengthPercent
    var isEnabled: Bool { strength != .off }
    var effectiveStrengthPercent: Float { strength == .custom ? customStrengthPercent : strength.strengthPercent }

    static func attenuationLimitDb(forStrengthPercent percent: Float) -> Float {
        let value = min(max(percent, 0), 100)
        return value <= standardStrengthPercent ? 12 + value / standardStrengthPercent * 88 : 100
    }
    static func postFilterBeta(forStrengthPercent percent: Float) -> Float {
        let value = min(max(percent, 0), 100)
        return value > standardStrengthPercent ? (value - standardStrengthPercent) * 0.001 : 0
    }
    var effectiveAttenuationLimitDb: Float {
        strength == .custom ? Self.attenuationLimitDb(forStrengthPercent: customStrengthPercent) : strength.attenuationLimitDb
    }
    var effectivePostFilterBeta: Float {
        strength == .custom ? Self.postFilterBeta(forStrengthPercent: customStrengthPercent) : strength.postFilterBeta
    }
}

