import Foundation
import CoreGraphics
import CoreMediaPlus
import CommandBus
import MediaManager

/// Facade for media import and management.
public final class MediaAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let importer: AssetImporter
    private let thumbnailGenerator: ThumbnailGenerator

    public init(dispatcher: CommandDispatcher, importer: AssetImporter,
                thumbnailGenerator: ThumbnailGenerator) {
        self.dispatcher = dispatcher
        self.importer = importer
        self.thumbnailGenerator = thumbnailGenerator
    }

    @discardableResult
    public func importMedia(urls: [URL]) async throws -> CommandResult {
        try await dispatcher.dispatch(ImportMediaCommand(urls: urls))
    }

    /// Direct access to import without command system (for internal use)
    public func importAssetsDirectly(from urls: [URL]) async throws -> [ImportedAsset] {
        try await importer.importAssets(from: urls)
    }

    /// Generate a thumbnail
    public func generateThumbnail(for url: URL, at time: Rational,
                                   size: CGSize = CGSize(width: 160, height: 90)) async throws -> CGImage {
        try await thumbnailGenerator.generateThumbnail(for: url, at: time, size: size)
    }
}
