import Foundation
@preconcurrency import AVFoundation
import CoreMediaPlus

/// Generates thumbnail images from video assets with caching support.
public final class ThumbnailGenerator: @unchecked Sendable {

    private let cache = ThumbnailCache()

    public init() {}

    /// Generate a single thumbnail at the given time.
    public func generateThumbnail(for url: URL, at time: Rational,
                                   size: CGSize = CGSize(width: 160, height: 90)) async throws -> CGImage {
        if let cached = await cache.get(url: url, time: time, size: size) {
            return cached
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let (image, _) = try await generator.image(at: time.cmTime)
        await cache.store(image, url: url, time: time, size: size)
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

        let interval = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(max(count, 1)))
        var times: [CMTime] = []
        for i in 0..<count {
            times.append(CMTimeMultiplyByFloat64(interval, multiplier: Double(i)))
        }

        var images: [CGImage] = []
        for time in times {
            let rational = Rational(time.value, Int64(time.timescale))
            if let cached = await cache.get(url: url, time: rational, size: size) {
                images.append(cached)
            } else if let (image, _) = try? await generator.image(at: time) {
                await cache.store(image, url: url, time: rational, size: size)
                images.append(image)
            }
        }
        return images
    }

    /// Generate thumbnails progressively, calling back as each one becomes available.
    /// Returns the final array of all generated thumbnails.
    public func generateThumbnailStripProgressively(
        for url: URL,
        count: Int,
        size: CGSize = CGSize(width: 160, height: 90),
        onThumbnail: @Sendable @escaping (Int, CGImage) -> Void
    ) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true

        let interval = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(max(count, 1)))
        var images: [CGImage] = []

        for i in 0..<count {
            let time = CMTimeMultiplyByFloat64(interval, multiplier: Double(i))
            let rational = Rational(time.value, Int64(time.timescale))

            if let cached = await cache.get(url: url, time: rational, size: size) {
                images.append(cached)
                onThumbnail(i, cached)
            } else if let (image, _) = try? await generator.image(at: time) {
                await cache.store(image, url: url, time: rational, size: size)
                images.append(image)
                onThumbnail(i, image)
            }
        }
        return images
    }

    /// Clear the thumbnail cache.
    public func clearCache() async {
        await cache.clear()
    }
}

// MARK: - Thumbnail Cache

/// Actor-based cache for thumbnail images, keyed by (URL, time, size).
actor ThumbnailCache {

    private struct CacheKey: Hashable {
        let url: URL
        let timeNumerator: Int64
        let timeDenominator: Int64
        let width: Int
        let height: Int
    }

    private var cache: [CacheKey: CGImage] = [:]
    private let maxEntries = 500

    func get(url: URL, time: Rational, size: CGSize) -> CGImage? {
        let key = makeKey(url: url, time: time, size: size)
        return cache[key]
    }

    func store(_ image: CGImage, url: URL, time: Rational, size: CGSize) {
        if cache.count >= maxEntries {
            // Evict oldest entries (simple strategy: remove first quarter)
            let keysToRemove = Array(cache.keys.prefix(maxEntries / 4))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        let key = makeKey(url: url, time: time, size: size)
        cache[key] = image
    }

    func clear() {
        cache.removeAll()
    }

    private func makeKey(url: URL, time: Rational, size: CGSize) -> CacheKey {
        CacheKey(
            url: url,
            timeNumerator: time.numerator,
            timeDenominator: time.denominator,
            width: Int(size.width),
            height: Int(size.height)
        )
    }
}
