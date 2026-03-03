import CoreMediaPlus
import CoreVideo
import Foundation
import Vision

/// Result of tracking an object in a single frame.
public struct TrackingResult: Sendable, Codable, Equatable {
    /// Bounding box in normalized coordinates (0...1).
    public var boundingBox: CGRect
    /// Confidence score from the tracker (0...1).
    public var confidence: Float
    /// Presentation time of this frame.
    public var time: Rational

    public init(boundingBox: CGRect, confidence: Float, time: Rational) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.time = time
    }
}

/// Wraps the Vision framework's sequence-based object tracking.
///
/// Use `trackObject(initialRegion:in:startTime:frameRate:)` to run object tracking
/// across an array of pixel buffers and receive an array of `TrackingResult` keyframes.
public final class MotionTracker: Sendable {

    /// Minimum confidence threshold below which the object is considered lost.
    public let confidenceThreshold: Float

    /// Tracking accuracy level passed to Vision requests.
    public let trackingLevel: VNRequestTrackingLevel

    public init(
        confidenceThreshold: Float = 0.3,
        trackingLevel: VNRequestTrackingLevel = .accurate
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.trackingLevel = trackingLevel
    }

    /// Track an object across a sequence of pixel buffers.
    ///
    /// - Parameters:
    ///   - initialRegion: Normalized bounding box (0...1) of the object in the first frame.
    ///   - pixelBuffers: Ordered array of frames to track through.
    ///   - startTime: Presentation time of the first pixel buffer.
    ///   - frameRate: Frame rate used to compute presentation times for subsequent frames.
    /// - Returns: Array of `TrackingResult`, one per successfully tracked frame.
    public func trackObject(
        initialRegion: CGRect,
        in pixelBuffers: [CVPixelBuffer],
        startTime: Rational,
        frameRate: Double
    ) throws -> [TrackingResult] {
        guard !pixelBuffers.isEmpty else { return [] }

        let sequenceHandler = VNSequenceRequestHandler()
        var currentObservation: VNDetectedObjectObservation = VNDetectedObjectObservation(
            boundingBox: initialRegion
        )
        var results: [TrackingResult] = []
        let frameDuration = frameRate > 0 ? Rational(seconds: 1.0 / frameRate) : Rational(1, 30)

        for (index, buffer) in pixelBuffers.enumerated() {
            let frameTime = startTime + Rational(Int64(index), 1) * frameDuration

            let request = VNTrackObjectRequest(detectedObjectObservation: currentObservation)
            request.trackingLevel = trackingLevel

            try sequenceHandler.perform([request], on: buffer)

            guard let observations = request.results as? [VNDetectedObjectObservation],
                  let tracked = observations.first else {
                break
            }

            if tracked.confidence < confidenceThreshold {
                break
            }

            let result = TrackingResult(
                boundingBox: tracked.boundingBox,
                confidence: tracked.confidence,
                time: frameTime
            )
            results.append(result)
            currentObservation = tracked
        }

        return results
    }
}
