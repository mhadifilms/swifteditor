import Foundation

/// A saveable/loadable configuration for an audio effect.
public struct AudioEffectPreset: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let effectType: AudioEffectType
    public let parameters: [String: Float]

    public init(name: String, effectType: AudioEffectType, parameters: [String: Float]) {
        self.name = name
        self.effectType = effectType
        self.parameters = parameters
    }

    // MARK: - Built-in Presets

    /// Warm vocal EQ: boost low-mids, gentle high roll-off.
    public static let warmVocal = AudioEffectPreset(
        name: "Warm Vocal",
        effectType: .eq,
        parameters: [
            "lowFrequency": 200,
            "lowGain": 2,
            "midFrequency": 800,
            "midGain": 3,
            "highFrequency": 6000,
            "highGain": -1,
            "globalGain": 0,
        ]
    )

    /// Punchy drums compressor: fast attack, medium release, moderate ratio.
    public static let punchyDrums = AudioEffectPreset(
        name: "Punchy Drums",
        effectType: .compressor,
        parameters: [
            "threshold": -18,
            "headRoom": 6,
            "attackTime": 0.003,
            "releaseTime": 0.08,
            "masterGain": 2,
        ]
    )

    /// Room reverb: subtle room ambience.
    public static let roomReverb = AudioEffectPreset(
        name: "Room Reverb",
        effectType: .reverb,
        parameters: [
            "wetDryMix": 20,
        ]
    )

    /// Vocal presence EQ: boost presence range for clarity.
    public static let vocalPresence = AudioEffectPreset(
        name: "Vocal Presence",
        effectType: .eq,
        parameters: [
            "lowFrequency": 120,
            "lowGain": -2,
            "midFrequency": 3000,
            "midGain": 4,
            "highFrequency": 10000,
            "highGain": 2,
            "globalGain": 0,
        ]
    )

    /// Slapback delay: short delay for doubling effect.
    public static let slapbackDelay = AudioEffectPreset(
        name: "Slapback Delay",
        effectType: .delay,
        parameters: [
            "delayTime": 0.08,
            "feedback": 10,
            "lowPassCutoff": 12000,
            "wetDryMix": 25,
        ]
    )

    /// Gentle compressor: light compression for dialogue or voiceover.
    public static let gentleCompressor = AudioEffectPreset(
        name: "Gentle Compressor",
        effectType: .compressor,
        parameters: [
            "threshold": -12,
            "headRoom": 10,
            "attackTime": 0.01,
            "releaseTime": 0.15,
            "masterGain": 0,
        ]
    )

    /// All built-in presets.
    public static let builtIn: [AudioEffectPreset] = [
        warmVocal, punchyDrums, roomReverb, vocalPresence, slapbackDelay, gentleCompressor,
    ]

    // MARK: - Save / Load

    /// Save this preset to a JSON file at the given URL.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Load a preset from a JSON file at the given URL.
    public static func load(from url: URL) throws -> AudioEffectPreset {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AudioEffectPreset.self, from: data)
    }

    /// Create an AudioEffectInstance from this preset.
    public func makeInstance(id: UUID = UUID()) -> AudioEffectInstance {
        AudioEffectInstance(
            id: id,
            name: name,
            effectType: effectType,
            isEnabled: true,
            parameters: parameters
        )
    }
}
