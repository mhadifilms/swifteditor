import Foundation
import CoreMediaPlus

/// Frame-accurate stepping and scrubbing utilities.
public struct FrameStepper: Sendable {

    public init() {}

    /// Step forward by a given number of frames from the current time.
    public func step(forward frames: Int, frameRate: Rational, from currentTime: Rational) -> Rational {
        let frameDuration = Rational(1, 1) / frameRate
        return currentTime + frameDuration * Rational(Int64(frames), 1)
    }

    /// Step backward by a given number of frames from the current time, clamped to zero.
    public func step(backward frames: Int, frameRate: Rational, from currentTime: Rational) -> Rational {
        let frameDuration = Rational(1, 1) / frameRate
        let result = currentTime - frameDuration * Rational(Int64(frames), 1)
        return result < .zero ? .zero : result
    }

    /// Snap a time value to the nearest frame boundary for the given frame rate.
    public func snapToFrame(_ time: Rational, frameRate: Rational) -> Rational {
        let frameNumber = time.frameNumber(at: frameRate)
        return timeForFrame(frameNumber, frameRate: frameRate)
    }

    /// Convert a frame number to its corresponding time value.
    public func timeForFrame(_ frame: Int64, frameRate: Rational) -> Rational {
        Rational(frame, 1) / frameRate
    }

    /// Convert a time value to a frame number at the given frame rate.
    public func frameForTime(_ time: Rational, frameRate: Rational) -> Int64 {
        time.frameNumber(at: frameRate)
    }
}
