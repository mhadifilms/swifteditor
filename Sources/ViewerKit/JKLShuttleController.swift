import Foundation
import Observation
import CoreMediaPlus

/// JKL shuttle control for professional-style playback speed control.
@Observable
public final class JKLShuttleController: @unchecked Sendable {

    /// Speed ladder used for forward and reverse shuttle.
    public static let speedLadder: [Double] = [1, 2, 4, 8, 16, 32]

    /// Current shuttle speed. Positive = forward, negative = reverse, 0 = stopped.
    public private(set) var currentSpeed: Double = 0

    private let transport: TransportController
    private let frameStepper = FrameStepper()

    public init(transport: TransportController) {
        self.transport = transport
    }

    /// J key: start or increase reverse shuttle speed.
    public func pressJ() {
        if currentSpeed > 0 {
            // Was going forward — stop and start reverse at 1x
            setSpeed(-Self.speedLadder[0])
        } else if currentSpeed == 0 {
            // Stopped — start reverse at 1x
            setSpeed(-Self.speedLadder[0])
        } else {
            // Already going reverse — increase speed
            let absCurrent = Swift.abs(currentSpeed)
            if let nextSpeed = Self.speedLadder.first(where: { $0 > absCurrent }) {
                setSpeed(-nextSpeed)
            }
            // Already at max reverse speed — stay there
        }
    }

    /// K key: stop playback.
    public func pressK() {
        setSpeed(0)
        transport.pause()
    }

    /// L key: start or increase forward shuttle speed.
    public func pressL() {
        if currentSpeed < 0 {
            // Was going reverse — stop and start forward at 1x
            setSpeed(Self.speedLadder[0])
        } else if currentSpeed == 0 {
            // Stopped — start forward at 1x
            setSpeed(Self.speedLadder[0])
        } else {
            // Already going forward — increase speed
            if let nextSpeed = Self.speedLadder.first(where: { $0 > currentSpeed }) {
                setSpeed(nextSpeed)
            }
            // Already at max forward speed — stay there
        }
    }

    /// K+J held: step backward one frame.
    public func pressKJ(frameRate: Rational = Rational(24, 1)) {
        setSpeed(0)
        transport.stepBackward(frames: 1, frameRate: frameRate)
    }

    /// K+L held: step forward one frame.
    public func pressKL(frameRate: Rational = Rational(24, 1)) {
        setSpeed(0)
        transport.stepForward(frames: 1, frameRate: frameRate)
    }

    private func setSpeed(_ speed: Double) {
        currentSpeed = speed
        if speed == 0 {
            transport.pause()
        } else {
            transport.shuttle(speed: speed)
        }
    }
}
