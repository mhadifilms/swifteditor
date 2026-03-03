import Foundation
import Observation
import CoreMediaPlus

/// Runtime model of a clip on the timeline.
@Observable
public final class ClipModel: @unchecked Sendable {
    public let id: UUID
    public let sourceAssetID: UUID
    public var trackID: UUID
    public var startTime: Rational
    public var sourceIn: Rational
    public var sourceOut: Rational
    public var speed: Double = 1.0
    public var isEnabled: Bool = true

    public var duration: Rational { sourceOut - sourceIn }

    public init(id: UUID = UUID(), sourceAssetID: UUID, trackID: UUID,
                startTime: Rational, sourceIn: Rational, sourceOut: Rational) {
        self.id = id
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.startTime = startTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }

    public struct Snapshot: Sendable {
        public let id: UUID
        public let sourceAssetID: UUID
        public let startTime: Rational
        public let sourceIn: Rational
        public let sourceOut: Rational
        public let speed: Double
    }

    public func snapshot() -> Snapshot {
        Snapshot(id: id, sourceAssetID: sourceAssetID, startTime: startTime,
                 sourceIn: sourceIn, sourceOut: sourceOut, speed: speed)
    }

    public convenience init(from snapshot: Snapshot, trackID: UUID) {
        self.init(id: snapshot.id, sourceAssetID: snapshot.sourceAssetID,
                  trackID: trackID, startTime: snapshot.startTime,
                  sourceIn: snapshot.sourceIn, sourceOut: snapshot.sourceOut)
        self.speed = snapshot.speed
    }
}

extension ClipModel: Identifiable {}
