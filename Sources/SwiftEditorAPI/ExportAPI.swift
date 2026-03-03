import Foundation
import AVFoundation
import Combine
import CoreMediaPlus
import CoreGraphics
import CommandBus
import RenderEngine

/// Facade for export operations.
@Observable
public final class ExportAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher

    /// Current export progress (0.0 to 1.0). Observable from SwiftUI views.
    public private(set) var progress: Float = 0

    /// Whether an export is currently running.
    public private(set) var isExporting: Bool = false

    /// Combine publisher that emits progress values during export.
    public let progressPublisher = PassthroughSubject<Float, Never>()

    public init(dispatcher: CommandDispatcher) {
        self.dispatcher = dispatcher
    }

    /// Called by ExportHandler to report incremental progress.
    internal func reportProgress(_ value: Float) {
        self.progress = value
        self.progressPublisher.send(value)
    }

    internal func setExporting(_ value: Bool) {
        self.isExporting = value
        if value { self.progress = 0 }
    }

    @discardableResult
    public func export(to url: URL, preset: ExportPreset) async throws -> CommandResult {
        setExporting(true)
        defer { setExporting(false) }
        return try await dispatcher.dispatch(ExportCommand(outputURL: url, preset: preset))
    }

    /// Direct export using AVAssetExportSession
    public func exportDirectly(composition: AVComposition,
                                videoComposition: AVVideoComposition?,
                                audioMix: AVAudioMix?,
                                outputURL: URL,
                                fileType: AVFileType = .mp4,
                                presetName: String = AVAssetExportPresetHighestQuality) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw CommandError.executionFailed("Failed to create export session")
        }

        session.outputURL = outputURL
        session.outputFileType = fileType
        session.videoComposition = videoComposition
        session.audioMix = audioMix

        await session.export()

        if let error = session.error {
            throw error
        }

        guard session.status == .completed else {
            throw CommandError.executionFailed("Export failed with status: \(session.status.rawValue)")
        }
    }

    /// Build HDR-aware video settings for AVAssetWriter.
    /// Returns a dictionary suitable for AVAssetWriterInput output settings.
    public static func hdrVideoSettings(
        for config: HDRConfiguration,
        width: Int,
        height: Int,
        codec: AVVideoCodecType = .hevc
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]

        if config.isHDR {
            var compressionProperties: [String: Any] = [:]

            switch config.transferFunction {
            case .pq:
                compressionProperties[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
                compressionProperties[AVVideoTransferFunctionKey] = AVVideoTransferFunction_SMPTE_ST_2084_PQ
                compressionProperties[AVVideoYCbCrMatrixKey] = AVVideoYCbCrMatrix_ITU_R_2020
            case .hlg:
                compressionProperties[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
                compressionProperties[AVVideoTransferFunctionKey] = AVVideoTransferFunction_ITU_R_2100_HLG
                compressionProperties[AVVideoYCbCrMatrixKey] = AVVideoYCbCrMatrix_ITU_R_2020
            case .sdr:
                break
            }

            if !compressionProperties.isEmpty {
                settings[AVVideoCompressionPropertiesKey] = compressionProperties
            }
        }

        return settings
    }
}
