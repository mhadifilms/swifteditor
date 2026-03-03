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

    /// Optional speed ramp curve for variable speed effects.
    /// When set, overrides the scalar `speed` property for time remapping.
    public var speedRamp: TimeRemapCurve?

    public var duration: Rational { sourceOut - sourceIn }

    /// The effective output duration of this clip, accounting for speed ramp if present.
    public var outputDuration: Rational {
        if let ramp = speedRamp, let outDuration = ramp.outputDuration {
            return Rational(seconds: outDuration)
        }
        return duration
    }

    /// Maps an output time (relative to clip start on timeline) to source time.
    /// Uses speed ramp if present, otherwise applies scalar speed.
    public func sourceTime(atOutputOffset outputOffset: Rational) -> Rational {
        if let ramp = speedRamp {
            let sourceSeconds = ramp.sourceTime(at: outputOffset.seconds)
            return sourceIn + Rational(seconds: sourceSeconds)
        }
        // Scalar speed: source advances faster/slower
        return sourceIn + Rational(seconds: outputOffset.seconds * speed)
    }

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
        public let speedRamp: TimeRemapCurve?
    }

    public func snapshot() -> Snapshot {
        Snapshot(id: id, sourceAssetID: sourceAssetID, startTime: startTime,
                 sourceIn: sourceIn, sourceOut: sourceOut, speed: speed,
                 speedRamp: speedRamp)
    }

    public convenience init(from snapshot: Snapshot, trackID: UUID) {
        self.init(id: snapshot.id, sourceAssetID: snapshot.sourceAssetID,
                  trackID: trackID, startTime: snapshot.startTime,
                  sourceIn: snapshot.sourceIn, sourceOut: snapshot.sourceOut)
        self.speed = snapshot.speed
        self.speedRamp = snapshot.speedRamp
    }
}

extension ClipModel: Identifiable {}
