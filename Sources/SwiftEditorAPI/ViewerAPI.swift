import Foundation
import CoreMediaPlus
import ViewerKit

/// Facade for viewer operations: in/out points, JKL shuttle, source viewer, and frame stepping.
public final class ViewerAPI: @unchecked Sendable {
    private let inOutModel: InOutPointModel
    private let shuttle: JKLShuttleController
    private let sourceViewer: SourceViewerState
    private let transport: TransportController

    public init(inOutModel: InOutPointModel,
                shuttle: JKLShuttleController,
                sourceViewer: SourceViewerState,
                transport: TransportController) {
        self.inOutModel = inOutModel
        self.shuttle = shuttle
        self.sourceViewer = sourceViewer
        self.transport = transport
    }

    // MARK: - In/Out Points

    /// Mark the in point at the given time.
    public func setInPoint(_ time: Rational) {
        inOutModel.setIn(time)
    }

    /// Mark the out point at the given time.
    public func setOutPoint(_ time: Rational) {
        inOutModel.setOut(time)
    }

    /// Clear the in point.
    public func clearInPoint() {
        inOutModel.clearIn()
    }

    /// Clear the out point.
    public func clearOutPoint() {
        inOutModel.clearOut()
    }

    /// Clear both in and out points.
    public func clearInOutPoints() {
        inOutModel.clearBoth()
    }

    /// The current in point, if set.
    public var inPoint: Rational? {
        inOutModel.inPoint
    }

    /// The current out point, if set.
    public var outPoint: Rational? {
        inOutModel.outPoint
    }

    /// The duration between in and out points, if both are set.
    public var markedDuration: Rational? {
        inOutModel.markedDuration
    }

    /// Whether the given time falls within the in/out range.
    public func isInRange(_ time: Rational) -> Bool {
        inOutModel.contains(time)
    }

    // MARK: - JKL Shuttle

    /// Press J: start or increase reverse shuttle.
    public func pressJ() {
        shuttle.pressJ()
    }

    /// Press K: stop shuttle / pause.
    public func pressK() {
        shuttle.pressK()
    }

    /// Press L: start or increase forward shuttle.
    public func pressL() {
        shuttle.pressL()
    }

    /// Reset shuttle speed to zero.
    public func resetShuttle() {
        shuttle.pressK()
    }

    /// Current shuttle speed. Positive = forward, negative = reverse, 0 = stopped.
    public var shuttleSpeed: Double {
        shuttle.currentSpeed
    }

    /// Whether the transport is currently shuttling.
    public var isShuttling: Bool {
        shuttle.currentSpeed != 0
    }

    // MARK: - Source Viewer

    /// Load an asset into the source viewer.
    public func loadSource(url: URL, assetID: UUID) {
        sourceViewer.loadSource(url: url, assetID: assetID)
    }

    /// Unload the current source asset.
    public func unloadSource() {
        sourceViewer.unloadSource()
    }

    /// Whether a source is currently loaded.
    public var isSourceVisible: Bool {
        sourceViewer.isSourceLoaded
    }

    /// The asset ID currently loaded in the source viewer.
    public var sourceAssetID: UUID? {
        sourceViewer.sourceAssetID
    }

    /// Set in point on the source viewer's in/out model.
    public func setSourceInPoint(_ time: Rational) {
        sourceViewer.inOutPoints.setIn(time)
    }

    /// Set out point on the source viewer's in/out model.
    public func setSourceOutPoint(_ time: Rational) {
        sourceViewer.inOutPoints.setOut(time)
    }

    /// Clear source viewer in/out points.
    public func clearSourceInOutPoints() {
        sourceViewer.inOutPoints.clearBoth()
    }

    // MARK: - Frame Stepping

    /// Step forward by one frame at the given frame rate.
    public func stepForward(frameRate: Double) {
        let rate = Rational(Int64(frameRate * 1000), 1000)
        transport.stepForward(frames: 1, frameRate: rate)
    }

    /// Step backward by one frame at the given frame rate.
    public func stepBackward(frameRate: Double) {
        let rate = Rational(Int64(frameRate * 1000), 1000)
        transport.stepBackward(frames: 1, frameRate: rate)
    }
}
