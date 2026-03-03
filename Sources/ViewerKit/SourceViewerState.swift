import Foundation
import Observation
import CoreMediaPlus

/// Manages the source viewer state independently from the timeline viewer.
@Observable
public final class SourceViewerState: @unchecked Sendable {
    public var sourceAssetURL: URL?
    public var sourceAssetID: UUID?
    public let inOutPoints: InOutPointModel

    public var isSourceLoaded: Bool {
        sourceAssetURL != nil && sourceAssetID != nil
    }

    public init() {
        self.inOutPoints = InOutPointModel()
    }

    /// Load a source asset into the source viewer.
    public func loadSource(url: URL, assetID: UUID) {
        sourceAssetURL = url
        sourceAssetID = assetID
        inOutPoints.clearBoth()
    }

    /// Unload the current source asset.
    public func unloadSource() {
        sourceAssetURL = nil
        sourceAssetID = nil
        inOutPoints.clearBoth()
    }
}
