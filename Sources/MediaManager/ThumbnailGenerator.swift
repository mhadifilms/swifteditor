import Foundation
import AVFoundation
import CoreMediaPlus

/// Generates thumbnail images from video assets.
public final class ThumbnailGenerator: @unchecked Sendable {

    public init() {}

    /// Generate a single thumbnail at the given time.
    public func generateThumbnail(for url: URL, at time: Rational,
                                   size: CGSize = CGSize(width: 160, height: 90)) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let (image, _) = try await generator.image(at: time.cmTime)
        return image
    }

    /// Generate a strip of thumbnails at regular intervals.
    public func generateThumbnailStrip(
        for url: URL,
        count: Int,
        size: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true

        let interval = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(count))
        var times: [CMTime] = []
        for i in 0..<count {
            times.append(CMTimeMultiplyByFloat64(interval, multiplier: Double(i)))
        }

        var images: [CGImage] = []
        for time in times {
            if let (image, _) = try? await generator.image(at: time) {
                images.append(image)
            }
        }
        return images
    }
}
