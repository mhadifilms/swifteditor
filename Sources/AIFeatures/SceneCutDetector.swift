// AIFeatures — Histogram-based scene boundary detection
import Accelerate
import AVFoundation
import CoreMedia
import CoreVideo

/// Detects scene cuts in video by comparing luminance histograms of consecutive frames.
/// Uses Accelerate/vDSP for efficient histogram correlation.
public struct SceneCutDetector: Sendable {
    /// Threshold for histogram correlation (0.0-1.0). Frames with correlation
    /// below this value are considered scene cuts. Lower = more sensitive.
    public let threshold: Float

    /// Number of bins in the luminance histogram.
    public static let binCount = 256

    public init(threshold: Float = 0.35) {
        self.threshold = threshold
    }

    /// Compute a normalized luminance histogram from a CVPixelBuffer (BGRA format).
    public static func computeHistogram(from pixelBuffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Array(repeating: 0, count: binCount)
        }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        var histogram = [Float](repeating: 0, count: binCount)
        let pixelCount = width * height

        // BGRA format: compute BT.709 luminance from RGB
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let b = Float(buffer[offset])
                let g = Float(buffer[offset + 1])
                let r = Float(buffer[offset + 2])
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let bin = min(255, Int(luma))
                histogram[bin] += 1.0
            }
        }

        // Normalize histogram so it sums to 1.0
        var total = Float(pixelCount)
        vDSP_vsdiv(histogram, 1, &total, &histogram, 1, vDSP_Length(binCount))
        return histogram
    }

    /// Returns the correlation coefficient between two histograms (1.0 = identical, 0.0 = uncorrelated).
    /// Uses vDSP for vectorized dot product computation.
    public static func correlate(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "Histograms must have equal length")
        let count = vDSP_Length(a.count)

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)
        vDSP_dotpr(a, 1, a, 1, &normA, count)
        vDSP_dotpr(b, 1, b, 1, &normB, count)

        let denom = sqrt(normA * normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }

    /// Analyze an entire AVAsset and return detected scene cut times.
    /// Reads all video frames sequentially and compares consecutive histogram correlations.
    public func detectCuts(in asset: AVAsset) async throws -> [CMTime] {
        let reader = try AVAssetReader(asset: asset)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return []
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var previousHistogram: [Float]?
        var cutPoints: [CMTime] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let currentHistogram = Self.computeHistogram(from: pixelBuffer)

            if let previous = previousHistogram {
                let correlation = Self.correlate(previous, currentHistogram)
                if correlation < threshold {
                    cutPoints.append(presentationTime)
                }
            }

            previousHistogram = currentHistogram
        }

        return cutPoints
    }
}
