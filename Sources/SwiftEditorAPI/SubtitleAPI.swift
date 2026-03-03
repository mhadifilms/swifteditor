import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Facade for subtitle track and cue operations.
/// Mutating operations go through CommandBus for undo support.
public final class SubtitleAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let timeline: TimelineModel

    public init(dispatcher: CommandDispatcher, timeline: TimelineModel) {
        self.dispatcher = dispatcher
        self.timeline = timeline
    }

    // MARK: - Command-Based Operations

    /// Add a new subtitle track.
    @discardableResult
    public func addSubtitleTrack(name: String = "Subtitles") async throws -> CommandResult {
        let command = AddSubtitleTrackCommand(name: name)
        return try await dispatcher.dispatch(command)
    }

    /// Remove a subtitle track.
    @discardableResult
    public func removeSubtitleTrack(trackID: UUID) async throws -> CommandResult {
        let command = RemoveSubtitleTrackCommand(trackID: trackID)
        return try await dispatcher.dispatch(command)
    }

    /// Add a subtitle cue to a track.
    @discardableResult
    public func addSubtitleCue(
        trackID: UUID,
        text: String,
        startTime: Rational,
        endTime: Rational,
        style: SubtitleStyle = .default
    ) async throws -> CommandResult {
        let command = AddSubtitleCueCommand(
            trackID: trackID,
            text: text,
            startTime: startTime,
            endTime: endTime,
            fontName: style.fontName,
            fontSize: Double(style.fontSize),
            textColorR: style.textColor.r,
            textColorG: style.textColor.g,
            textColorB: style.textColor.b,
            textColorA: style.textColor.a,
            bgColorR: style.backgroundColor?.r,
            bgColorG: style.backgroundColor?.g,
            bgColorB: style.backgroundColor?.b,
            bgColorA: style.backgroundColor?.a,
            position: style.position.rawValue,
            alignment: style.alignment.rawValue,
            isBold: style.isBold,
            isItalic: style.isItalic
        )
        return try await dispatcher.dispatch(command)
    }

    /// Remove a subtitle cue from a track.
    @discardableResult
    public func removeSubtitleCue(trackID: UUID, cueID: UUID) async throws -> CommandResult {
        let command = RemoveSubtitleCueCommand(trackID: trackID, cueID: cueID)
        return try await dispatcher.dispatch(command)
    }

    /// Update properties of a subtitle cue.
    @discardableResult
    public func updateSubtitleCue(
        trackID: UUID,
        cueID: UUID,
        text: String? = nil,
        startTime: Rational? = nil,
        endTime: Rational? = nil,
        style: SubtitleStyle? = nil
    ) async throws -> CommandResult {
        let command = UpdateSubtitleCueCommand(
            trackID: trackID,
            cueID: cueID,
            text: text,
            startTime: startTime,
            endTime: endTime,
            fontName: style?.fontName,
            fontSize: style.map { Double($0.fontSize) },
            textColorR: style?.textColor.r,
            textColorG: style?.textColor.g,
            textColorB: style?.textColor.b,
            textColorA: style?.textColor.a,
            bgColorR: style?.backgroundColor?.r,
            bgColorG: style?.backgroundColor?.g,
            bgColorB: style?.backgroundColor?.b,
            bgColorA: style?.backgroundColor?.a,
            positionValue: style?.position.rawValue,
            alignmentValue: style?.alignment.rawValue,
            isBold: style?.isBold,
            isItalic: style?.isItalic
        )
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Query

    /// All subtitle tracks on the timeline.
    public var subtitleTracks: [SubtitleTrackModel] {
        timeline.subtitleTracks
    }

    /// Get the active subtitle cue at a given time on a specific track.
    public func cue(at time: Rational, trackID: UUID) -> SubtitleCue? {
        guard let track = timeline.subtitleTracks.first(where: { $0.id == trackID }) else {
            return nil
        }
        return track.cue(at: time)
    }
}
