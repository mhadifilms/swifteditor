import Foundation
import AVFoundation
import CoreMediaPlus

/// Multi-track audio mixer wrapping AVAudioEngine.
public final class AudioMixer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var playerNodes: [UUID: AVAudioPlayerNode] = [:]
    private let mainMixer: AVAudioMixerNode

    /// Per-track effect chains, keyed by track ID.
    public var effectChains: [UUID: AudioEffectChain] = [:]

    /// Tracks which effect unit nodes are currently attached, keyed by track ID.
    private var attachedEffectNodes: [UUID: [AVAudioUnit]] = [:]

    public init() {
        self.mainMixer = engine.mainMixerNode
    }

    /// Add a track to the mixer, returning a player node ID.
    public func addTrack(id: UUID) -> AVAudioPlayerNode {
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: mainMixer, format: nil)
        playerNodes[id] = node
        return node
    }

    /// Remove a track from the mixer.
    public func removeTrack(id: UUID) {
        guard let node = playerNodes.removeValue(forKey: id) else { return }
        detachEffectNodes(for: id)
        effectChains.removeValue(forKey: id)
        engine.detach(node)
    }

    // MARK: - Effect Chain Integration

    /// Set the effect chain for a track. Rebuilds the audio graph for that track.
    public func setEffectChain(_ chain: AudioEffectChain, for trackID: UUID) {
        effectChains[trackID] = chain
        rebuildEffectGraph(for: trackID)
    }

    /// Rebuild the audio graph for a single track, inserting effect nodes
    /// between the player node and the main mixer.
    public func rebuildEffectGraph(for trackID: UUID) {
        guard let playerNode = playerNodes[trackID] else { return }

        // Detach old effect nodes for this track.
        detachEffectNodes(for: trackID)

        // Disconnect the player node from its current destination.
        engine.disconnectNodeOutput(playerNode)

        guard let chain = effectChains[trackID] else {
            // No effects: connect player directly to main mixer.
            engine.connect(playerNode, to: mainMixer, format: nil)
            return
        }

        let effectUnits = chain.buildAudioUnits()
        guard !effectUnits.isEmpty else {
            engine.connect(playerNode, to: mainMixer, format: nil)
            return
        }

        // Attach all effect nodes to the engine.
        for unit in effectUnits {
            engine.attach(unit)
        }
        attachedEffectNodes[trackID] = effectUnits

        // Build chain: player -> effect[0] -> effect[1] -> ... -> mainMixer
        engine.connect(playerNode, to: effectUnits[0], format: nil)
        for i in 0..<(effectUnits.count - 1) {
            engine.connect(effectUnits[i], to: effectUnits[i + 1], format: nil)
        }
        engine.connect(effectUnits[effectUnits.count - 1], to: mainMixer, format: nil)
    }

    /// Rebuild the audio graph for all tracks that have effect chains.
    public func rebuildAllEffectGraphs() {
        for trackID in playerNodes.keys {
            rebuildEffectGraph(for: trackID)
        }
    }

    /// Detach and clean up effect nodes for a track.
    private func detachEffectNodes(for trackID: UUID) {
        guard let nodes = attachedEffectNodes.removeValue(forKey: trackID) else { return }
        for node in nodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
    }

    /// Set volume for a track (0.0 - 1.0).
    public func setVolume(_ volume: Float, for trackID: UUID) {
        playerNodes[trackID]?.volume = volume
    }

    /// Set pan for a track (-1.0 left, 0.0 center, 1.0 right).
    public func setPan(_ pan: Float, for trackID: UUID) {
        playerNodes[trackID]?.pan = pan
    }

    /// Start the audio engine.
    public func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    /// Stop the audio engine.
    public func stop() {
        engine.stop()
    }

    /// Install a metering tap on the main output.
    public func installMeteringTap(
        bufferSize: AVAudioFrameCount = 1024,
        handler: @escaping (Float, Float) -> Void
    ) {
        let format = mainMixer.outputFormat(forBus: 0)
        mainMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)

            var peakL: Float = 0
            var peakR: Float = 0

            if channelCount > 0 {
                for i in 0..<frameCount {
                    let sample = abs(channelData[0][i])
                    if sample > peakL { peakL = sample }
                }
            }
            if channelCount > 1 {
                for i in 0..<frameCount {
                    let sample = abs(channelData[1][i])
                    if sample > peakR { peakR = sample }
                }
            } else {
                peakR = peakL
            }

            handler(peakL, peakR)
        }
    }

    /// Remove the metering tap.
    public func removeMeteringTap() {
        mainMixer.removeTap(onBus: 0)
    }
}
