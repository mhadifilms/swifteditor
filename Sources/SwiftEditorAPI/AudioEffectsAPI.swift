@preconcurrency import AVFoundation
import Foundation
import AudioEngine

/// Facade for managing audio effect chains per track.
public final class AudioEffectsAPI: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var chains: [UUID: AudioEffectChain] = [:]

    public init() {}

    // MARK: - Chain Access

    /// Get or create the effect chain for a track.
    public func chain(for trackID: UUID) -> AudioEffectChain {
        lock.lock()
        defer { lock.unlock() }
        if let existing = chains[trackID] {
            return existing
        }
        let newChain = AudioEffectChain()
        chains[trackID] = newChain
        return newChain
    }

    /// Remove the entire effect chain for a track.
    public func removeChain(for trackID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        chains.removeValue(forKey: trackID)
    }

    // MARK: - Effect Management

    /// Add an effect to a track's chain. Returns the new effect's ID.
    @discardableResult
    public func addEffect(trackID: UUID, name: String, type: AudioEffectType) -> UUID {
        let instance = AudioEffectInstance(name: name, effectType: type)
        chain(for: trackID).append(instance)
        return instance.id
    }

    /// Remove an effect from a track's chain.
    public func removeEffect(trackID: UUID, effectID: UUID) {
        chain(for: trackID).remove(id: effectID)
    }

    /// Reorder an effect within a track's chain.
    public func moveEffect(trackID: UUID, fromIndex: Int, toIndex: Int) {
        chain(for: trackID).move(fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Toggle an effect on or off.
    public func toggleEffect(trackID: UUID, effectID: UUID) {
        chain(for: trackID).toggleEnabled(id: effectID)
    }

    /// Set a parameter value on an effect.
    public func setEffectParameter(trackID: UUID, effectID: UUID, parameter: String, value: Float) {
        let c = chain(for: trackID)
        guard let effect = c.effects.first(where: { $0.id == effectID }) else { return }
        effect.parameters[parameter] = value
    }

    /// Read parameters for an effect. Returns nil if the effect is not found.
    public func effectParameters(trackID: UUID, effectID: UUID) -> [String: Float]? {
        let c = chain(for: trackID)
        return c.effects.first(where: { $0.id == effectID })?.parameters
    }

    /// List all effects in a track's chain.
    public func effects(for trackID: UUID) -> [AudioEffectInstance] {
        chain(for: trackID).effects
    }

    // MARK: - Presets

    /// Apply a preset to a track, creating a new effect instance. Returns the new effect's ID.
    @discardableResult
    public func applyPreset(trackID: UUID, preset: AudioEffectPreset) -> UUID {
        let instance = preset.makeInstance()
        chain(for: trackID).append(instance)
        return instance.id
    }

    /// List all built-in presets.
    public var availablePresets: [AudioEffectPreset] {
        AudioEffectPreset.builtIn
    }

    /// List all built-in audio effects.
    public var builtInAudioEffects: [BuiltInAudioEffectDescriptor] {
        BuiltInAudioEffects.all
    }

    /// Add a built-in audio effect to a track by descriptor ID. Returns the new effect's ID.
    @discardableResult
    public func addBuiltInEffect(trackID: UUID, descriptorID: String) -> UUID? {
        guard let instance = BuiltInAudioEffects.createInstance(for: descriptorID) else { return nil }
        chain(for: trackID).append(instance)
        return instance.id
    }

    // MARK: - Audio Unit Management

    /// Build AVAudioUnit nodes for all effects in a track's chain.
    public func buildAudioUnits(for trackID: UUID) -> [AVAudioUnit] {
        chain(for: trackID).buildAudioUnits()
    }

    /// Clear cached audio unit nodes for a track's chain.
    public func clearAudioUnits(for trackID: UUID) {
        chain(for: trackID).clearAudioUnits()
    }
}
