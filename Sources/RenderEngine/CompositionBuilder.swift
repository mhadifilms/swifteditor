@preconcurrency import AVFoundation
import CoreMediaPlus
import EffectsEngine

/// Builds AVMutableComposition + AVVideoComposition from a timeline model.
/// This is the bridge between the editing model and AVFoundation's playback/export pipeline.
public final class CompositionBuilder: @unchecked Sendable {

    public struct CompositionResult: @unchecked Sendable {
        public let composition: AVMutableComposition
        public let videoComposition: AVMutableVideoComposition
        public let audioMix: AVMutableAudioMix?
    }

    public init() {}

    /// Build an AVPlayerItem from timeline data.
    @MainActor
    public func buildPlayerItem(
        videoTracks: [TrackBuildData],
        audioTracks: [TrackBuildData],
        renderSize: CGSize,
        frameDuration: CMTime
    ) async throws -> AVPlayerItem {
        let result = try await buildComposition(
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            renderSize: renderSize,
            frameDuration: frameDuration
        )
        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        if let audioMix = result.audioMix {
            playerItem.audioMix = audioMix
        }
        return playerItem
    }

    /// Build the AVFoundation composition objects.
    public func buildComposition(
        videoTracks: [TrackBuildData],
        audioTracks: [TrackBuildData],
        renderSize: CGSize,
        frameDuration: CMTime
    ) async throws -> CompositionResult {
        let composition = AVMutableComposition()

        // Maps our timeline track UUID -> AVFoundation composition track ID
        var videoTrackIDMap: [(trackData: TrackBuildData, compositionTrackID: CMPersistentTrackID)] = []
        var audioTrackIDMap: [(trackData: TrackBuildData, compositionTrackID: CMPersistentTrackID)] = []

        // Create AVFoundation video tracks and insert time ranges
        for trackData in videoTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in trackData.clips {
                guard let asset = clip.asset else { continue }
                guard let sourceTrack = try? await asset.loadTracks(withMediaType: .video).first else { continue }

                let insertTime = clip.startTime.cmTime
                let sourceRange = CMTimeRange(
                    start: clip.sourceIn.cmTime,
                    duration: clip.duration.cmTime
                )

                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
            }

            videoTrackIDMap.append((trackData: trackData, compositionTrackID: compositionTrack.trackID))
        }

        // Create AVFoundation audio tracks and insert time ranges
        for trackData in audioTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in trackData.clips {
                guard let asset = clip.asset else { continue }
                guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }

                let insertTime = clip.startTime.cmTime
                let sourceRange = CMTimeRange(
                    start: clip.sourceIn.cmTime,
                    duration: clip.duration.cmTime
                )

                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
            }

            audioTrackIDMap.append((trackData: trackData, compositionTrackID: compositionTrack.trackID))
        }

        // Build video composition with custom compositor
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.customVideoCompositorClass = MetalCompositor.self
        videoComposition.instructions = buildInstructions(
            videoTrackIDMap: videoTrackIDMap,
            composition: composition
        )

        // Build audio mix
        let audioMix = buildAudioMix(audioTrackIDMap: audioTrackIDMap)

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    // MARK: - Instruction Generation

    /// Generates CompositorInstructions by finding time boundaries across all video clips
    /// and creating one instruction per constant-clip-set segment.
    private func buildInstructions(
        videoTrackIDMap: [(trackData: TrackBuildData, compositionTrackID: CMPersistentTrackID)],
        composition: AVMutableComposition
    ) -> [AVVideoCompositionInstructionProtocol] {
        // Collect all clip time boundaries
        var boundaries: Set<Rational> = []
        for entry in videoTrackIDMap {
            for clip in entry.trackData.clips {
                boundaries.insert(clip.startTime)
                boundaries.insert(clip.startTime + clip.duration)
            }
        }

        let sortedBoundaries = boundaries.sorted()
        guard sortedBoundaries.count >= 2 else { return [] }

        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for i in 0 ..< sortedBoundaries.count - 1 {
            let segmentStart = sortedBoundaries[i]
            let segmentEnd = sortedBoundaries[i + 1]
            guard segmentEnd > segmentStart else { continue }

            let timeRange = CMTimeRange(start: segmentStart.cmTime, duration: (segmentEnd - segmentStart).cmTime)

            // Find which clips are active in this time segment
            var layerInsts: [LayerInstruction] = []
            var activeTrackIDs: [CMPersistentTrackID] = []

            for entry in videoTrackIDMap {
                for clip in entry.trackData.clips {
                    let clipEnd = clip.startTime + clip.duration
                    // Clip is active if it overlaps this segment
                    if clip.startTime < segmentEnd && clipEnd > segmentStart {
                        activeTrackIDs.append(entry.compositionTrackID)
                        layerInsts.append(LayerInstruction(
                            trackID: entry.compositionTrackID,
                            clipID: clip.clipID,
                            opacity: clip.opacity,
                            blendMode: clip.blendMode,
                            effectStack: clip.effectStack
                        ))
                    }
                }
            }

            guard !layerInsts.isEmpty else { continue }

            let instruction = CompositorInstruction(
                timeRange: timeRange,
                sourceTrackIDs: activeTrackIDs,
                layerInstructions: layerInsts
            )
            instructions.append(instruction)
        }

        return instructions
    }

    // MARK: - Audio Mix

    /// Builds an AVMutableAudioMix with per-track volume parameters.
    private func buildAudioMix(
        audioTrackIDMap: [(trackData: TrackBuildData, compositionTrackID: CMPersistentTrackID)]
    ) -> AVMutableAudioMix? {
        var inputParameters: [AVMutableAudioMixInputParameters] = []

        for entry in audioTrackIDMap {
            let params = AVMutableAudioMixInputParameters(track: nil)
            params.trackID = entry.compositionTrackID

            // Set per-clip volume ramps
            for clip in entry.trackData.clips {
                let startTime = clip.startTime.cmTime
                let clipDuration = clip.duration.cmTime
                let timeRange = CMTimeRange(start: startTime, duration: clipDuration)
                params.setVolume(clip.volume, at: timeRange.start)
            }

            inputParameters.append(params)
        }

        guard !inputParameters.isEmpty else { return nil }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters
        return audioMix
    }

    // MARK: - Build Data Types

    /// Data needed to build a track.
    public struct TrackBuildData: Sendable {
        public let trackID: UUID
        public let clips: [ClipBuildData]

        public init(trackID: UUID, clips: [ClipBuildData]) {
            self.trackID = trackID
            self.clips = clips
        }
    }

    /// Data needed to build a clip.
    public struct ClipBuildData: @unchecked Sendable {
        public let clipID: UUID
        public let asset: AVAsset?
        public let startTime: Rational
        public let sourceIn: Rational
        public let sourceOut: Rational
        public let effectStack: EffectStack?
        public let volume: Float
        public let opacity: Double
        public let blendMode: BlendMode

        public var duration: Rational { sourceOut - sourceIn }

        public init(clipID: UUID, asset: AVAsset?, startTime: Rational,
                    sourceIn: Rational, sourceOut: Rational,
                    effectStack: EffectStack? = nil,
                    volume: Float = 1.0,
                    opacity: Double = 1.0,
                    blendMode: BlendMode = .normal) {
            self.clipID = clipID
            self.asset = asset
            self.startTime = startTime
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
            self.effectStack = effectStack
            self.volume = volume
            self.opacity = opacity
            self.blendMode = blendMode
        }
    }
}
