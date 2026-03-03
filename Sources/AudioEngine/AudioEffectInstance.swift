import AVFoundation
import Foundation
import Observation

/// The type of audio effect, mapping to specific AUAudioUnit implementations.
public enum AudioEffectType: Sendable, Codable, Hashable {
    case eq
    case compressor
    case reverb
    case delay
    case custom(AudioComponentDescription)
}

extension AudioComponentDescription: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(componentType)
        hasher.combine(componentSubType)
        hasher.combine(componentManufacturer)
        hasher.combine(componentFlags)
        hasher.combine(componentFlagsMask)
    }
}

extension AudioComponentDescription: @retroactive Equatable {
    public static func == (lhs: AudioComponentDescription, rhs: AudioComponentDescription) -> Bool {
        lhs.componentType == rhs.componentType
            && lhs.componentSubType == rhs.componentSubType
            && lhs.componentManufacturer == rhs.componentManufacturer
            && lhs.componentFlags == rhs.componentFlags
            && lhs.componentFlagsMask == rhs.componentFlagsMask
    }
}

extension AudioComponentDescription: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case componentType, componentSubType, componentManufacturer
        case componentFlags, componentFlagsMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            componentType: try container.decode(UInt32.self, forKey: .componentType),
            componentSubType: try container.decode(UInt32.self, forKey: .componentSubType),
            componentManufacturer: try container.decode(UInt32.self, forKey: .componentManufacturer),
            componentFlags: try container.decode(UInt32.self, forKey: .componentFlags),
            componentFlagsMask: try container.decode(UInt32.self, forKey: .componentFlagsMask)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(componentType, forKey: .componentType)
        try container.encode(componentSubType, forKey: .componentSubType)
        try container.encode(componentManufacturer, forKey: .componentManufacturer)
        try container.encode(componentFlags, forKey: .componentFlags)
        try container.encode(componentFlagsMask, forKey: .componentFlagsMask)
    }
}

/// A single audio effect instance with its type, enabled state, and parameter values.
@Observable
public final class AudioEffectInstance: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public let effectType: AudioEffectType
    public var isEnabled: Bool
    public var parameters: [String: Float]

    public init(
        id: UUID = UUID(),
        name: String,
        effectType: AudioEffectType,
        isEnabled: Bool = true,
        parameters: [String: Float] = [:]
    ) {
        self.id = id
        self.name = name
        self.effectType = effectType
        self.isEnabled = isEnabled
        self.parameters = Self.defaultParameters(for: effectType).merging(parameters) { _, new in new }
    }

    /// Default parameter values for each built-in effect type.
    public static func defaultParameters(for effectType: AudioEffectType) -> [String: Float] {
        switch effectType {
        case .eq:
            return [
                "lowFrequency": 200,
                "lowGain": 0,
                "midFrequency": 1000,
                "midGain": 0,
                "highFrequency": 6000,
                "highGain": 0,
                "globalGain": 0,
            ]
        case .compressor:
            return [
                "threshold": -20,
                "headRoom": 5,
                "attackTime": 0.001,
                "releaseTime": 0.05,
                "masterGain": 0,
            ]
        case .reverb:
            return [
                "wetDryMix": 30,
            ]
        case .delay:
            return [
                "delayTime": 0.3,
                "feedback": 40,
                "lowPassCutoff": 15000,
                "wetDryMix": 20,
            ]
        case .custom:
            return [:]
        }
    }
}
