import AVFoundation
import Foundation
import Observation

/// Enhanced audio meter providing peak, RMS, and peak-hold levels in dBFS.
@Observable
public final class AudioMeter: @unchecked Sendable {

    // MARK: - Published Levels

    /// Combined peak level in dBFS (max of left/right).
    public private(set) var peakLevel: Float = -.infinity
    /// Combined RMS level in dBFS.
    public private(set) var rmsLevel: Float = -.infinity
    /// Peak hold level in dBFS (decays over time).
    public private(set) var peakHold: Float = -.infinity

    /// Left channel peak in dBFS.
    public private(set) var leftPeak: Float = -.infinity
    /// Right channel peak in dBFS.
    public private(set) var rightPeak: Float = -.infinity
    /// Left channel RMS in dBFS.
    public private(set) var leftRMS: Float = -.infinity
    /// Right channel RMS in dBFS.
    public private(set) var rightRMS: Float = -.infinity

    /// True when peak exceeds 0 dBFS.
    public private(set) var clipping: Bool = false

    // MARK: - Configuration

    /// Peak hold decay rate in dB per second.
    public var decayRate: Float = 3.0

    // MARK: - Private State

    private var lastUpdateTime: TimeInterval = 0

    public init() {}

    // MARK: - Update

    /// Update meter levels from an audio buffer.
    /// Call this from an audio tap callback.
    public func update(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var leftPeakLinear: Float = 0
        var rightPeakLinear: Float = 0
        var leftSumSquares: Float = 0
        var rightSumSquares: Float = 0

        // Left channel (or mono).
        if channelCount > 0 {
            let samples = channelData[0]
            for i in 0..<frameCount {
                let s = abs(samples[i])
                if s > leftPeakLinear { leftPeakLinear = s }
                leftSumSquares += samples[i] * samples[i]
            }
        }

        // Right channel (mirrors left if mono).
        if channelCount > 1 {
            let samples = channelData[1]
            for i in 0..<frameCount {
                let s = abs(samples[i])
                if s > rightPeakLinear { rightPeakLinear = s }
                rightSumSquares += samples[i] * samples[i]
            }
        } else {
            rightPeakLinear = leftPeakLinear
            rightSumSquares = leftSumSquares
        }

        let count = Float(frameCount)
        let leftRMSLinear = (leftSumSquares / count).squareRoot()
        let rightRMSLinear = (rightSumSquares / count).squareRoot()

        let lp = Self.linearToDBFS(leftPeakLinear)
        let rp = Self.linearToDBFS(rightPeakLinear)
        let lr = Self.linearToDBFS(leftRMSLinear)
        let rr = Self.linearToDBFS(rightRMSLinear)
        let combinedPeak = max(lp, rp)
        let combinedRMS = max(lr, rr)

        // Peak hold with decay.
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastUpdateTime > 0 ? Float(now - lastUpdateTime) : 0
        lastUpdateTime = now

        var newPeakHold = peakHold - decayRate * elapsed
        if combinedPeak > newPeakHold {
            newPeakHold = combinedPeak
        }

        leftPeak = lp
        rightPeak = rp
        leftRMS = lr
        rightRMS = rr
        peakLevel = combinedPeak
        rmsLevel = combinedRMS
        peakHold = newPeakHold
        clipping = leftPeakLinear >= 1.0 || rightPeakLinear >= 1.0
    }

    /// Reset all levels to silence.
    public func reset() {
        peakLevel = -.infinity
        rmsLevel = -.infinity
        peakHold = -.infinity
        leftPeak = -.infinity
        rightPeak = -.infinity
        leftRMS = -.infinity
        rightRMS = -.infinity
        clipping = false
        lastUpdateTime = 0
    }

    // MARK: - Conversion

    /// Convert a linear amplitude (0...1+) to dBFS.
    public static func linearToDBFS(_ linear: Float) -> Float {
        guard linear > 0 else { return -.infinity }
        return 20.0 * log10(linear)
    }
}
