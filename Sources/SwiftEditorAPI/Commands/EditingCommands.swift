import Foundation
import CoreMediaPlus
import CommandBus

// MARK: - Editing Commands

public struct MoveClipCommand: Command {
    public static let typeIdentifier = "editing.moveClip"
    public let clipID: UUID
    public let toTrackID: UUID
    public let position: Rational
    public var undoDescription: String { "Move Clip" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, toTrackID: UUID, position: Rational) {
        self.clipID = clipID
        self.toTrackID = toTrackID
        self.position = position
    }
}

public struct TrimClipCommand: Command {
    public static let typeIdentifier = "editing.trimClip"
    public let clipID: UUID
    public let edge: TrimEdge
    public let toTime: Rational
    public var undoDescription: String { "Trim Clip" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, edge: TrimEdge, toTime: Rational) {
        self.clipID = clipID
        self.edge = edge
        self.toTime = toTime
    }
}

public struct SplitClipCommand: Command {
    public static let typeIdentifier = "editing.splitClip"
    public let clipID: UUID
    public let atTime: Rational
    public var undoDescription: String { "Split Clip" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, atTime: Rational) {
        self.clipID = clipID
        self.atTime = atTime
    }
}

public struct DeleteClipCommand: Command {
    public static let typeIdentifier = "editing.deleteClip"
    public let clipID: UUID
    public var undoDescription: String { "Delete Clip" }
    public var isMutating: Bool { true }

    public init(clipID: UUID) {
        self.clipID = clipID
    }
}

public struct AddClipCommand: Command {
    public static let typeIdentifier = "editing.addClip"
    public let sourceAssetID: UUID
    public let trackID: UUID
    public let position: Rational
    public let sourceIn: Rational
    public let sourceOut: Rational
    public var undoDescription: String { "Add Clip" }
    public var isMutating: Bool { true }

    public init(sourceAssetID: UUID, trackID: UUID, position: Rational,
                sourceIn: Rational, sourceOut: Rational) {
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.position = position
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

public struct InsertEditCommand: Command {
    public static let typeIdentifier = "editing.insertEdit"
    public let sourceAssetID: UUID
    public let trackID: UUID
    public let atTime: Rational
    public let sourceIn: Rational
    public let sourceOut: Rational
    public var undoDescription: String { "Insert Edit" }
    public var isMutating: Bool { true }

    public init(sourceAssetID: UUID, trackID: UUID, atTime: Rational,
                sourceIn: Rational, sourceOut: Rational) {
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.atTime = atTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

public struct OverwriteEditCommand: Command {
    public static let typeIdentifier = "editing.overwriteEdit"
    public let sourceAssetID: UUID
    public let trackID: UUID
    public let atTime: Rational
    public let sourceIn: Rational
    public let sourceOut: Rational
    public var undoDescription: String { "Overwrite Edit" }
    public var isMutating: Bool { true }

    public init(sourceAssetID: UUID, trackID: UUID, atTime: Rational,
                sourceIn: Rational, sourceOut: Rational) {
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.atTime = atTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

public struct AddTrackCommand: Command {
    public static let typeIdentifier = "editing.addTrack"
    public let trackType: TrackType
    public let atIndex: Int
    public var undoDescription: String { "Add Track" }
    public var isMutating: Bool { true }

    public init(trackType: TrackType, atIndex: Int) {
        self.trackType = trackType
        self.atIndex = atIndex
    }
}

public struct RemoveTrackCommand: Command {
    public static let typeIdentifier = "editing.removeTrack"
    public let trackID: UUID
    public var undoDescription: String { "Remove Track" }
    public var isMutating: Bool { true }

    public init(trackID: UUID) {
        self.trackID = trackID
    }
}
