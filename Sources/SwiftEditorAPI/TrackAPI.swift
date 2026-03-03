import Foundation
import CoreMediaPlus
import TimelineKit

/// Information about a track on the timeline.
public struct TrackInfo: Sendable {
    public let id: UUID
    public let name: String
    public let type: TrackType
    public let isMuted: Bool
    public let isLocked: Bool
    public let clipCount: Int

    public init(id: UUID, name: String, type: TrackType, isMuted: Bool, isLocked: Bool, clipCount: Int) {
        self.id = id
        self.name = name
        self.type = type
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.clipCount = clipCount
    }
}

/// Facade for track property operations.
/// These modify simple properties directly (no commands needed for undo).
public final class TrackAPI: @unchecked Sendable {
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    // MARK: - Track Mutation

    /// Set the muted state of a track.
    public func setTrackMuted(_ trackID: UUID, muted: Bool) {
        if let track = timeline.videoTracks.first(where: { $0.id == trackID }) {
            track.isMuted = muted
        } else if let track = timeline.audioTracks.first(where: { $0.id == trackID }) {
            track.isMuted = muted
        }
    }

    /// Set the locked state of a track.
    public func setTrackLocked(_ trackID: UUID, locked: Bool) {
        if let track = timeline.videoTracks.first(where: { $0.id == trackID }) {
            track.isLocked = locked
        } else if let track = timeline.audioTracks.first(where: { $0.id == trackID }) {
            track.isLocked = locked
        }
    }

    /// Rename a track.
    public func renameTrack(_ trackID: UUID, name: String) {
        if let track = timeline.videoTracks.first(where: { $0.id == trackID }) {
            track.name = name
        } else if let track = timeline.audioTracks.first(where: { $0.id == trackID }) {
            track.name = name
        }
    }

    /// Enable or disable a clip.
    public func setClipEnabled(_ clipID: UUID, enabled: Bool) {
        timeline.clip(by: clipID)?.isEnabled = enabled
    }

    // MARK: - Track Query

    /// All video tracks on the timeline.
    public var videoTracks: [VideoTrackModel] {
        timeline.videoTracks
    }

    /// All audio tracks on the timeline.
    public var audioTracks: [AudioTrackModel] {
        timeline.audioTracks
    }

    /// Get info for a specific track.
    public func trackInfo(_ trackID: UUID) -> TrackInfo? {
        if let track = timeline.videoTracks.first(where: { $0.id == trackID }) {
            return TrackInfo(
                id: track.id,
                name: track.name,
                type: .video,
                isMuted: track.isMuted,
                isLocked: track.isLocked,
                clipCount: timeline.clipsOnTrack(trackID).count
            )
        }
        if let track = timeline.audioTracks.first(where: { $0.id == trackID }) {
            return TrackInfo(
                id: track.id,
                name: track.name,
                type: .audio,
                isMuted: track.isMuted,
                isLocked: track.isLocked,
                clipCount: timeline.clipsOnTrack(trackID).count
            )
        }
        return nil
    }

    /// Get all clips on a specific track, sorted by start time.
    public func allClipsOnTrack(_ trackID: UUID) -> [ClipModel] {
        timeline.clipsOnTrack(trackID)
    }
}
