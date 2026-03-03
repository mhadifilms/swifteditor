// CollaborationKit — Timeline operations expressed as CRDT ops
import Foundation
import CoreMediaPlus

/// A single operation on the collaborative timeline CRDT.
/// Every operation carries the CRDTIdentifier of the originating site
/// so that concurrent operations can be merged deterministically.
public enum TimelineOperation: Sendable, Codable, Equatable {
    // -- Clip operations --

    /// Insert a clip after the given anchor (nil = head of track).
    case insertClip(
        id: CRDTIdentifier,
        afterID: CRDTIdentifier?,
        trackID: CRDTIdentifier,
        clip: ClipPayload
    )

    /// Tombstone-delete a clip by its CRDT id.
    case deleteClip(id: CRDTIdentifier)

    /// Move a clip to a new position (after anchor) on a possibly different track.
    case moveClip(
        id: CRDTIdentifier,
        afterID: CRDTIdentifier?,
        toTrackID: CRDTIdentifier
    )

    /// Set a named property on a clip (LWW semantics).
    case setClipProperty(
        clipID: CRDTIdentifier,
        key: String,
        value: PropertyValue,
        timestamp: CRDTIdentifier
    )

    /// Trim the in-point of a clip (LWW semantics).
    case trimClipStart(
        clipID: CRDTIdentifier,
        newInPoint: Rational,
        timestamp: CRDTIdentifier
    )

    /// Trim the out-point of a clip (LWW semantics).
    case trimClipEnd(
        clipID: CRDTIdentifier,
        newOutPoint: Rational,
        timestamp: CRDTIdentifier
    )

    // -- Track operations --

    /// Insert a new track after the given anchor (nil = first track).
    case insertTrack(
        id: CRDTIdentifier,
        afterID: CRDTIdentifier?,
        kind: TrackKind
    )

    /// Tombstone-delete a track.
    case deleteTrack(id: CRDTIdentifier)
}

// MARK: - Supporting Types

/// The kind of track in the collaborative timeline.
public enum TrackKind: String, Sendable, Codable, Equatable {
    case video
    case audio
    case subtitle
}

/// Serializable clip payload carried inside an insertClip operation.
public struct ClipPayload: Sendable, Codable, Equatable {
    public let assetID: UUID
    public let sourceIn: Rational
    public let sourceOut: Rational
    public let speed: Double

    public init(assetID: UUID, sourceIn: Rational, sourceOut: Rational, speed: Double = 1.0) {
        self.assetID = assetID
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.speed = speed
    }
}

// MARK: - Operation Envelope

/// Wire envelope wrapping a timeline operation with metadata for transport.
public struct OperationEnvelope: Sendable, Codable {
    public let senderID: UUID
    public let sequenceNumber: UInt64
    public let operation: TimelineOperation

    public init(senderID: UUID, sequenceNumber: UInt64, operation: TimelineOperation) {
        self.senderID = senderID
        self.sequenceNumber = sequenceNumber
        self.operation = operation
    }
}
