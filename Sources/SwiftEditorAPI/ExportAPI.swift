import Foundation
import AVFoundation
import CoreMediaPlus
import CommandBus

/// Facade for export operations.
public final class ExportAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher

    public init(dispatcher: CommandDispatcher) {
        self.dispatcher = dispatcher
    }

    @discardableResult
    public func export(to url: URL, preset: ExportPreset) async throws -> CommandResult {
        try await dispatcher.dispatch(ExportCommand(outputURL: url, preset: preset))
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
}
