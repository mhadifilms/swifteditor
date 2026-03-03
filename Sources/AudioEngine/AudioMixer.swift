import Foundation
import AVFoundation
import CoreMediaPlus

/// Multi-track audio mixer wrapping AVAudioEngine.
public final class AudioMixer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var playerNodes: [UUID: AVAudioPlayerNode] = [:]
    private let mainMixer: AVAudioMixerNode

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
        engine.detach(node)
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
