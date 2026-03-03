@preconcurrency import AVFoundation
import Foundation
import CoreMediaPlus
import CommandBus
import RenderEngine
import TimelineKit
import EffectsEngine

/// Handler for ExportCommand — bridges to AVAssetExportSession.
public final class ExportHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = ExportCommand

    private let compositionBuilder: CompositionBuilder
    private let timelineProvider: @Sendable () -> TimelineModel
    private let assetResolver: @Sendable (UUID) -> AVAsset?
    private let effectStackResolver: @Sendable (UUID) -> EffectStack?
    private let onProgress: (@Sendable (Float) -> Void)?
    private let onSmartRenderAnalysis: (@Sendable ([ExportSegment], Double) -> Void)?

    public init(
        compositionBuilder: CompositionBuilder,
        timelineProvider: @escaping @Sendable () -> TimelineModel,
        assetResolver: @escaping @Sendable (UUID) -> AVAsset?,
        effectStackResolver: @escaping @Sendable (UUID) -> EffectStack? = { _ in nil },
        onProgress: (@Sendable (Float) -> Void)? = nil,
        onSmartRenderAnalysis: (@Sendable ([ExportSegment], Double) -> Void)? = nil
    ) {
        self.compositionBuilder = compositionBuilder
        self.timelineProvider = timelineProvider
        self.assetResolver = assetResolver
        self.effectStackResolver = effectStackResolver
        self.onProgress = onProgress
        self.onSmartRenderAnalysis = onSmartRenderAnalysis
    }

    public func validate(_ command: ExportCommand) throws {
        // Ensure output directory exists
        let dir = command.outputURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw CommandError.validationFailed("Output directory does not exist")
        }
    }

    public func execute(_ command: ExportCommand) async throws -> (any Command)? {
        let timeline = timelineProvider()

        // Build track data for the composition builder
        let videoTrackData = timeline.videoTracks.map { track in
            CompositionBuilder.TrackBuildData(
                trackID: track.id,
                clips: timeline.clipsOnTrack(track.id).map { clip in
                    CompositionBuilder.ClipBuildData(
                        clipID: clip.id,
                        asset: assetResolver(clip.sourceAssetID),
                        startTime: clip.startTime,
                        sourceIn: clip.sourceIn,
                        sourceOut: clip.sourceOut,
                        effectStack: effectStackResolver(clip.id)
                    )
                }
            )
        }

        let audioTrackData = timeline.audioTracks.map { track in
            CompositionBuilder.TrackBuildData(
                trackID: track.id,
                clips: timeline.clipsOnTrack(track.id).map { clip in
                    CompositionBuilder.ClipBuildData(
                        clipID: clip.id,
                        asset: assetResolver(clip.sourceAssetID),
                        startTime: clip.startTime,
                        sourceIn: clip.sourceIn,
                        sourceOut: clip.sourceOut,
                        effectStack: effectStackResolver(clip.id)
                    )
                }
            )
        }

        let renderSize = renderSizeForPreset(command.preset)
        let frameDuration = CMTime(value: 1, timescale: 24)

        // Run SmartRenderer analysis before export to determine passthrough segments
        let smartRenderer = SmartRenderer()
        let outputFormat = exportFormatForPreset(command.preset, renderSize: renderSize)
        let sourceClips = buildSourceClipInfos(from: videoTrackData, outputFormat: outputFormat)
        let segments = smartRenderer.analyze(clips: sourceClips, outputFormat: outputFormat)
        let ratio = smartRenderer.passthroughRatio(segments: segments)

        // Report analysis results via callback
        onSmartRenderAnalysis?(segments, ratio)

        let result = try await compositionBuilder.buildComposition(
            videoTracks: videoTrackData,
            audioTracks: audioTrackData,
            renderSize: renderSize,
            frameDuration: frameDuration
        )

        // Map preset to AVAssetExportSession preset
        let avPreset = avExportPreset(for: command.preset)
        let fileType = avFileType(for: command.preset)

        guard let session = AVAssetExportSession(asset: result.composition, presetName: avPreset) else {
            throw CommandError.executionFailed("Failed to create export session")
        }

        session.outputURL = command.outputURL
        session.outputFileType = fileType
        session.videoComposition = result.videoComposition
        if let audioMix = result.audioMix {
            session.audioMix = audioMix
        }

        // Remove existing file if present
        try? FileManager.default.removeItem(at: command.outputURL)

        // Start a progress polling timer before export
        let progressCallback = onProgress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progressCallback?(session.progress)
        }

        defer {
            progressTimer.invalidate()
            progressCallback?(1.0)
        }

        // Export using modern async API
        try await session.export(to: command.outputURL, as: fileType)

        return nil
    }

    // MARK: - Preset Mapping

    private func renderSizeForPreset(_ preset: ExportPreset) -> CGSize {
        switch preset {
        case .h264_1080p, .h265_1080p:
            return CGSize(width: 1920, height: 1080)
        case .h264_4k, .h265_4k:
            return CGSize(width: 3840, height: 2160)
        case .prores422, .prores4444, .proresProxy:
            return CGSize(width: 1920, height: 1080)
        }
    }

    private func avExportPreset(for preset: ExportPreset) -> String {
        switch preset {
        case .h264_1080p:
            return AVAssetExportPreset1920x1080
        case .h264_4k:
            return AVAssetExportPreset3840x2160
        case .h265_1080p:
            return AVAssetExportPresetHEVC1920x1080
        case .h265_4k:
            return AVAssetExportPresetHEVC3840x2160
        case .prores422:
            return AVAssetExportPresetAppleProRes422LPCM
        case .prores4444:
            return AVAssetExportPresetAppleProRes4444LPCM
        case .proresProxy:
            return AVAssetExportPresetAppleProRes422LPCM
        }
    }

    private func avFileType(for preset: ExportPreset) -> AVFileType {
        switch preset {
        case .h264_1080p, .h264_4k:
            return .mp4
        case .h265_1080p, .h265_4k:
            return .mp4
        case .prores422, .prores4444, .proresProxy:
            return .mov
        }
    }

    // MARK: - SmartRenderer Helpers

    private func exportFormatForPreset(_ preset: ExportPreset, renderSize: CGSize) -> ExportFormat {
        let codec: VideoCodec = switch preset {
        case .h264_1080p, .h264_4k: .h264
        case .h265_1080p, .h265_4k: .hevc
        case .prores422: .prores422
        case .prores4444: .prores4444
        case .proresProxy: .proresProxy
        }
        return ExportFormat(
            codec: codec,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            frameRate: Rational(24, 1)
        )
    }

    private func buildSourceClipInfos(
        from videoTrackData: [CompositionBuilder.TrackBuildData],
        outputFormat: ExportFormat
    ) -> [SourceClipInfo] {
        var clipInfos: [SourceClipInfo] = []
        let allClips = videoTrackData.flatMap(\.clips)

        for clip in allClips {
            let hasEffects = clip.effectStack?.activeEffects.isEmpty == false
            clipInfos.append(SourceClipInfo(
                clipID: clip.clipID,
                timeRange: TimeRange(
                    start: clip.startTime,
                    duration: clip.duration
                ),
                codec: .unknown,
                width: outputFormat.width,
                height: outputFormat.height,
                hasEffects: hasEffects,
                hasTransform: false,
                opacity: clip.opacity,
                blendMode: clip.blendMode,
                isComposited: false
            ))
        }
        return clipInfos
    }
}
