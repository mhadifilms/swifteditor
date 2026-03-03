import Foundation
import AVFoundation
import CoreMediaPlus
import AudioEngine

/// Facade for audio operations.
public final class AudioAPI: @unchecked Sendable {
    private let mixer: AudioMixer

    public init(mixer: AudioMixer) {
        self.mixer = mixer
    }

    // MARK: - Track Control

    /// Set volume for a track (0.0 - 1.0)
    public func setVolume(_ volume: Float, for trackID: UUID) {
        mixer.setVolume(volume, for: trackID)
    }

    /// Set pan for a track (-1.0 left, 0.0 center, 1.0 right)
    public func setPan(_ pan: Float, for trackID: UUID) {
        mixer.setPan(pan, for: trackID)
    }

    // MARK: - Engine Lifecycle

    /// Start the audio engine
    public func startEngine() throws {
        try mixer.start()
    }

    /// Stop the audio engine
    public func stopEngine() {
        mixer.stop()
    }

    // MARK: - Track Management

    /// Add a track to the audio mixer, returning the player node
    @discardableResult
    public func addTrack(id: UUID) -> AVAudioPlayerNode {
        mixer.addTrack(id: id)
    }

    /// Remove a track from the audio mixer
    public func removeTrack(id: UUID) {
        mixer.removeTrack(id: id)
    }

    // MARK: - Effect Chains

    /// Set the effect chain for a track. Rebuilds the audio graph.
    public func setEffectChain(_ chain: AudioEffectChain, for trackID: UUID) {
        mixer.setEffectChain(chain, for: trackID)
    }

    /// Get the effect chain for a track
    public func effectChain(for trackID: UUID) -> AudioEffectChain? {
        mixer.effectChains[trackID]
    }

    /// Rebuild the audio graph for a specific track
    public func rebuildEffectGraph(for trackID: UUID) {
        mixer.rebuildEffectGraph(for: trackID)
    }

    /// Rebuild the audio graph for all tracks
    public func rebuildAllEffectGraphs() {
        mixer.rebuildAllEffectGraphs()
    }

    // MARK: - Metering

    /// Install a metering tap on the main output.
    /// The handler receives (peakLeft, peakRight) values (0.0-1.0).
    public func installMeteringTap(bufferSize: AVAudioFrameCount = 1024,
                                    handler: @escaping (Float, Float) -> Void) {
        mixer.installMeteringTap(bufferSize: bufferSize, handler: handler)
    }

    /// Remove the metering tap
    public func removeMeteringTap() {
        mixer.removeMeteringTap()
    }
}
