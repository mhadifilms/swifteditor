import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Facade for multicam clip operations.
/// Mutating operations go through CommandBus for undo support.
public final class MulticamAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let timeline: TimelineModel

    public init(dispatcher: CommandDispatcher, timeline: TimelineModel) {
        self.dispatcher = dispatcher
        self.timeline = timeline
    }

    // MARK: - Command-Based Operations

    /// Create a multicam clip from multiple angle sources.
    @discardableResult
    public func createMulticamClip(
        angles: [MulticamAngle],
        trackID: UUID,
        at position: Rational,
        duration: Rational
    ) async throws -> CommandResult {
        let command = CreateMulticamClipCommand(
            angleIDs: angles.map(\.id),
            angleNames: angles.map(\.name),
            angleSourceAssetIDs: angles.map(\.sourceAssetID),
            angleSourceIns: angles.map(\.sourceIn),
            angleSourceOuts: angles.map(\.sourceOut),
            trackID: trackID,
            position: position,
            duration: duration
        )
        return try await dispatcher.dispatch(command)
    }

    /// Switch the active angle of a multicam clip.
    @discardableResult
    public func switchAngle(
        clipID: UUID,
        angleIndex: Int,
        at time: Rational? = nil
    ) async throws -> CommandResult {
        let command = SwitchAngleCommand(clipID: clipID, angleIndex: angleIndex, atTime: time)
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Query

    /// Check if a clip is a multicam clip.
    public func isMulticamClip(_ clipID: UUID) -> Bool {
        timeline.isMulticamClip(clipID)
    }

    /// Get the multicam model for a clip.
    public func multicamModel(for clipID: UUID) -> MulticamClipModel? {
        timeline.multicamModel(for: clipID)
    }

    /// All multicam clips on the timeline, keyed by multicam clip ID.
    public var multicamClips: [UUID: MulticamClipModel] {
        timeline.multicamClips
    }
}
