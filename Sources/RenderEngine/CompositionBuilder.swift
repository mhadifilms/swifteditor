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
        }

        // Build video composition with custom compositor
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.customVideoCompositorClass = MetalCompositor.self
        videoComposition.instructions = []

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: nil
        )
    }

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

        public var duration: Rational { sourceOut - sourceIn }

        public init(clipID: UUID, asset: AVAsset?, startTime: Rational,
                    sourceIn: Rational, sourceOut: Rational,
                    effectStack: EffectStack? = nil) {
            self.clipID = clipID
            self.asset = asset
            self.startTime = startTime
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
            self.effectStack = effectStack
        }
    }
}
