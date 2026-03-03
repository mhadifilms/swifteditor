import Testing
import Foundation
import CoreGraphics
@testable import MediaManager
@testable import CoreMediaPlus

@Suite("ThumbnailCache Tests")
struct ThumbnailCacheTests {

    @Test("Cache returns nil for missing entry")
    func cacheMissReturnsNil() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let result = await cache.get(url: url, time: .zero, size: CGSize(width: 160, height: 90))
        #expect(result == nil)
    }

    @Test("Cache stores and retrieves image")
    func cacheStoreAndGet() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let time = Rational(5, 1)
        let size = CGSize(width: 160, height: 90)

        // Create a 1x1 CGImage for testing
        let image = createTestImage()

        await cache.store(image, url: url, time: time, size: size)
        let retrieved = await cache.get(url: url, time: time, size: size)
        #expect(retrieved != nil)
        #expect(retrieved?.width == image.width)
        #expect(retrieved?.height == image.height)
    }

    @Test("Cache distinguishes different URLs")
    func cacheDifferentURLs() async {
        let cache = ThumbnailCache()
        let url1 = URL(fileURLWithPath: "/tmp/video1.mov")
        let url2 = URL(fileURLWithPath: "/tmp/video2.mov")
        let time = Rational(0, 1)
        let size = CGSize(width: 160, height: 90)

        let image = createTestImage()
        await cache.store(image, url: url1, time: time, size: size)

        let result1 = await cache.get(url: url1, time: time, size: size)
        let result2 = await cache.get(url: url2, time: time, size: size)
        #expect(result1 != nil)
        #expect(result2 == nil)
    }

    @Test("Cache distinguishes different times")
    func cacheDifferentTimes() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let size = CGSize(width: 160, height: 90)

        let image = createTestImage()
        await cache.store(image, url: url, time: Rational(0, 1), size: size)

        let result0 = await cache.get(url: url, time: Rational(0, 1), size: size)
        let result5 = await cache.get(url: url, time: Rational(5, 1), size: size)
        #expect(result0 != nil)
        #expect(result5 == nil)
    }

    @Test("Cache distinguishes different sizes")
    func cacheDifferentSizes() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let time = Rational(0, 1)

        let image = createTestImage()
        await cache.store(image, url: url, time: time, size: CGSize(width: 160, height: 90))

        let resultSmall = await cache.get(url: url, time: time, size: CGSize(width: 160, height: 90))
        let resultLarge = await cache.get(url: url, time: time, size: CGSize(width: 320, height: 180))
        #expect(resultSmall != nil)
        #expect(resultLarge == nil)
    }

    @Test("Cache clear removes all entries")
    func cacheClear() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let size = CGSize(width: 160, height: 90)

        let image = createTestImage()
        await cache.store(image, url: url, time: Rational(0, 1), size: size)
        await cache.store(image, url: url, time: Rational(5, 1), size: size)

        await cache.clear()

        let result = await cache.get(url: url, time: Rational(0, 1), size: size)
        #expect(result == nil)
    }

    // Helper to create a minimal test CGImage
    private func createTestImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 2, height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }
}

@Suite("ThumbnailGenerator Tests")
struct ThumbnailGeneratorTests {

    @Test("ThumbnailGenerator initializes")
    func generatorInitializes() {
        let generator = ThumbnailGenerator()
        // Just verify it creates without crashing
        _ = generator
    }

    @Test("ThumbnailGenerator clearCache does not crash")
    func clearCacheDoesNotCrash() async {
        let generator = ThumbnailGenerator()
        await generator.clearCache()
    }
}

@Suite("AssetImporter Tests")
struct AssetImporterTests {

    @Test("AssetImporter initializes")
    func importerInitializes() {
        let importer = AssetImporter()
        // Just verify it creates without crashing
        _ = importer
    }

    @Test("ImportedAsset has correct properties")
    func importedAssetProperties() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let asset = ImportedAsset(
            id: UUID(),
            url: url,
            name: "test",
            duration: Rational(120, 1),
            videoParams: VideoParams(width: 1920, height: 1080),
            audioParams: AudioParams(sampleRate: 48000, channelCount: 2)
        )

        #expect(asset.name == "test")
        #expect(asset.duration == Rational(120, 1))
        #expect(asset.videoParams?.width == 1920)
        #expect(asset.videoParams?.height == 1080)
        #expect(asset.audioParams?.sampleRate == 48000)
        #expect(asset.audioParams?.channelCount == 2)
    }

    @Test("ImportedAsset without video params")
    func importedAssetAudioOnly() {
        let asset = ImportedAsset(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/audio.wav"),
            name: "audio",
            duration: Rational(60, 1),
            videoParams: nil,
            audioParams: AudioParams(sampleRate: 44100, channelCount: 1)
        )

        #expect(asset.videoParams == nil)
        #expect(asset.audioParams != nil)
    }
}
