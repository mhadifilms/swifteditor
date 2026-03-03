import CoreVideo
import Foundation
import Vision

/// Wraps Vision's `VNGenerateOpticalFlowRequest` to compute dense motion vectors
/// between consecutive video frames.
///
/// Optical flow is useful for video stabilization, motion-aware effects, and
/// temporal interpolation (frame blending). The output is a pixel buffer where
/// each pixel encodes a 2D motion vector.
public final class OpticalFlowAnalyzer: Sendable {

    /// Accuracy level for optical flow computation.
    public let computationAccuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy

    public init(
        computationAccuracy: VNGenerateOpticalFlowRequest.ComputationAccuracy = .medium
    ) {
        self.computationAccuracy = computationAccuracy
    }

    /// Compute the optical flow from `frame1` to `frame2`.
    ///
    /// - Parameters:
    ///   - frame1: The reference (previous) frame.
    ///   - frame2: The target (current) frame.
    /// - Returns: A `VNPixelBufferObservation` containing the flow field.
    ///   Each pixel is a 2-component float vector (dx, dy) in normalized coordinates.
    /// - Throws: Vision framework errors if the request fails.
    public func analyzeFlow(
        frame1: CVPixelBuffer,
        frame2: CVPixelBuffer
    ) throws -> VNPixelBufferObservation {
        // VNGenerateOpticalFlowRequest is a targeted image request.
        // It is initialized with the target (frame2) and performed on the reference (frame1).
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: frame2)
        request.computationAccuracy = computationAccuracy

        let handler = VNImageRequestHandler(cvPixelBuffer: frame1)
        try handler.perform([request])

        guard let results = request.results,
              let observation = results.first else {
            throw OpticalFlowError.noResults
        }

        return observation
    }

    /// Compute optical flow for a sequence of frame pairs.
    ///
    /// - Parameter framePairs: Array of (previous, current) frame tuples.
    /// - Returns: Array of flow observations, one per pair.
    public func analyzeFlowSequence(
        framePairs: [(frame1: CVPixelBuffer, frame2: CVPixelBuffer)]
    ) throws -> [VNPixelBufferObservation] {
        try framePairs.map { pair in
            try analyzeFlow(frame1: pair.frame1, frame2: pair.frame2)
        }
    }
}

/// Errors specific to optical flow analysis.
public enum OpticalFlowError: Error, Sendable {
    case noResults
}
