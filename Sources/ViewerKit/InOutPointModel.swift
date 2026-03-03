import Foundation
import Observation
import CoreMediaPlus

/// Manages in/out point marking for source viewer and timeline.
@Observable
public final class InOutPointModel: @unchecked Sendable {
    public var inPoint: Rational?
    public var outPoint: Rational?

    public init(inPoint: Rational? = nil, outPoint: Rational? = nil) {
        self.inPoint = inPoint
        self.outPoint = outPoint
    }

    public func setIn(_ time: Rational) {
        inPoint = time
    }

    public func setOut(_ time: Rational) {
        outPoint = time
    }

    public func clearIn() {
        inPoint = nil
    }

    public func clearOut() {
        outPoint = nil
    }

    public func clearBoth() {
        inPoint = nil
        outPoint = nil
    }

    /// The duration between in and out points, if both are set.
    public var markedDuration: Rational? {
        guard let inPt = inPoint, let outPt = outPoint else { return nil }
        let dur = outPt - inPt
        return dur > .zero ? dur : nil
    }

    /// Whether the given time falls within the in/out range (inclusive of in, exclusive of out).
    public func contains(_ time: Rational) -> Bool {
        guard let inPt = inPoint, let outPt = outPoint else { return false }
        return time >= inPt && time < outPt
    }
}
