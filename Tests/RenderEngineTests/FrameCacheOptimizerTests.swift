import XCTest
import CoreVideo
@testable import RenderEngine
@testable import CoreMediaPlus

final class FrameCacheOptimizerTests: XCTestCase {

    // MARK: - Basic Cache Operations

    func testCacheHitAndMiss() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))

        // Miss
        let miss = await cache.hit(for: hash)
        XCTAssertNil(miss)

        // Store a dummy entry
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 1024)

        // Hit
        let hit = await cache.hit(for: hash)
        XCTAssertNotNil(hit)
    }

    func testCacheStatistics() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))

        // Miss
        _ = await cache.hit(for: hash)
        var stats = await cache.statistics()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 0)

        // Store and hit
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 1024)
        _ = await cache.hit(for: hash)
        stats = await cache.statistics()
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.currentEntries, 1)
    }

    // MARK: - LRU Eviction

    func testLRUEvictionWhenBudgetExceeded() async {
        // Small budget: 3000 bytes. Each entry is 1024 bytes.
        // At 90% threshold (default), eviction starts at 2700 bytes.
        // So 3rd entry should trigger eviction of the oldest.
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 3000,
            evictionThreshold: 0.9
        )
        let cache = FrameCacheOptimizer(configuration: config)

        let clipID = UUID()
        let hash1 = FrameHash(clipID: clipID, sourceTime: Rational(0, 1))
        let hash2 = FrameHash(clipID: clipID, sourceTime: Rational(1, 1))
        let hash3 = FrameHash(clipID: clipID, sourceTime: Rational(2, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash1, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash2, estimatedBytes: 1024)
        // This should evict hash1 (oldest)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash3, estimatedBytes: 1024)

        // hash1 should have been evicted
        let result1 = await cache.hit(for: hash1)
        XCTAssertNil(result1)

        // hash2 and hash3 should still be present
        let result2 = await cache.hit(for: hash2)
        XCTAssertNotNil(result2)
        let result3 = await cache.hit(for: hash3)
        XCTAssertNotNil(result3)
    }

    func testLRUEvictsLeastRecentlyUsed() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 3000,
            evictionThreshold: 0.9
        )
        let cache = FrameCacheOptimizer(configuration: config)

        let clipID = UUID()
        let hash1 = FrameHash(clipID: clipID, sourceTime: Rational(0, 1))
        let hash2 = FrameHash(clipID: clipID, sourceTime: Rational(1, 1))
        let hash3 = FrameHash(clipID: clipID, sourceTime: Rational(2, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash1, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash2, estimatedBytes: 1024)

        // Access hash1 to make it recently used
        _ = await cache.hit(for: hash1)

        // Store hash3 - should evict hash2 (least recently used) not hash1
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash3, estimatedBytes: 1024)

        let result1 = await cache.hit(for: hash1)
        XCTAssertNotNil(result1, "hash1 was recently accessed, should not be evicted")

        let result2 = await cache.hit(for: hash2)
        XCTAssertNil(result2, "hash2 was least recently used, should be evicted")
    }

    // MARK: - Memory Budget

    func testSkipsCachingWhenSingleEntryExceedsBudget() async {
        let config = FrameCacheOptimizer.Configuration(memoryBudgetBytes: 100)
        let cache = FrameCacheOptimizer(configuration: config)

        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 200)

        let result = await cache.hit(for: hash)
        XCTAssertNil(result, "Should not cache an entry larger than the entire budget")
    }

    func testMemoryUsageTracking() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 5000)
        let usage = await cache.memoryUsage()
        XCTAssertEqual(usage, 5000)
    }

    // MARK: - Invalidation

    func testInvalidateByClipID() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let clipA = UUID()
        let clipB = UUID()

        let hashA1 = FrameHash(clipID: clipA, sourceTime: Rational(0, 1))
        let hashA2 = FrameHash(clipID: clipA, sourceTime: Rational(1, 1))
        let hashB1 = FrameHash(clipID: clipB, sourceTime: Rational(0, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hashA1, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hashA2, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hashB1, estimatedBytes: 1024)

        await cache.invalidate(clipID: clipA)

        let resultA1 = await cache.hit(for: hashA1)
        XCTAssertNil(resultA1)
        let resultA2 = await cache.hit(for: hashA2)
        XCTAssertNil(resultA2)
        let resultB1 = await cache.hit(for: hashB1)
        XCTAssertNotNil(resultB1)
    }

    func testClear() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 1024)
        await cache.clear()

        let result = await cache.hit(for: hash)
        XCTAssertNil(result)
        let usage = await cache.memoryUsage()
        XCTAssertEqual(usage, 0)
        let count = await cache.entryCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Pre-warming

    func testPrewarmHashesExcludesCachedEntries() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 1024 * 1024,
            prewarmAhead: 2,
            prewarmBehind: 1,
            frameDuration: Rational(1, 30)
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        let playhead = Rational(1, 1)

        // Pre-cache one of the frames in the window
        let cachedTime = playhead + Rational(1, 30)
        let cachedHash = FrameHash(clipID: clipID, sourceTime: cachedTime)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: cachedHash, estimatedBytes: 1024)

        let hashes = await cache.prewarmHashes(around: playhead) { time in
            FrameHash(clipID: clipID, sourceTime: time)
        }

        // The cached hash should not be in the prewarm list
        XCTAssertFalse(hashes.contains(cachedHash))
        // But other hashes in the window should be present
        XCTAssertTrue(hashes.count > 0)
    }

    func testPrewarmHashesSkipsNegativeTimes() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 1024 * 1024,
            prewarmAhead: 2,
            prewarmBehind: 5,
            frameDuration: Rational(1, 30)
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        // Playhead near the start - behind frames would be negative
        let playhead = Rational(1, 30)
        let hashes = await cache.prewarmHashes(around: playhead) { time in
            FrameHash(clipID: clipID, sourceTime: time)
        }

        // All returned hashes should correspond to non-negative times
        for hash in hashes {
            XCTAssertTrue(hash.sourceTime >= .zero)
        }
    }

    // MARK: - Distant Eviction

    func testEvictDistantRemovesEntriesOutsideWindow() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 1024 * 1024,
            prewarmAhead: 1,
            prewarmBehind: 1,
            frameDuration: Rational(1, 1)
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        // Store entries at times 0, 1, 2, 10
        let hash0 = FrameHash(clipID: clipID, sourceTime: Rational(0, 1))
        let hash1 = FrameHash(clipID: clipID, sourceTime: Rational(1, 1))
        let hash2 = FrameHash(clipID: clipID, sourceTime: Rational(2, 1))
        let hash10 = FrameHash(clipID: clipID, sourceTime: Rational(10, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash0, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash1, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash2, estimatedBytes: 1024)
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash10, estimatedBytes: 1024)

        // Playhead at time 1, window is [0, 2]
        await cache.evictDistant(playhead: Rational(1, 1)) { time in
            FrameHash(clipID: clipID, sourceTime: time)
        }

        // hash0, hash1, hash2 are in the window and should be kept
        let r0 = await cache.hit(for: hash0)
        XCTAssertNotNil(r0)
        let r1 = await cache.hit(for: hash1)
        XCTAssertNotNil(r1)
        let r2 = await cache.hit(for: hash2)
        XCTAssertNotNil(r2)

        // hash10 is far outside the window and should be evicted
        let r10 = await cache.hit(for: hash10)
        XCTAssertNil(r10)
    }

    // MARK: - Replacing Existing Entry

    func testReplacingExistingEntryUpdatesMemoryUsage() async {
        let cache = FrameCacheOptimizer(configuration: .init(memoryBudgetBytes: 1024 * 1024))
        let hash = FrameHash(clipID: UUID(), sourceTime: Rational(0, 1))

        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 1000)
        let usage1 = await cache.memoryUsage()
        XCTAssertEqual(usage1, 1000)

        // Replace with larger entry
        await cache.store(.pixelBuffer(createDummyPixelBuffer()), for: hash, estimatedBytes: 2000)
        let usage2 = await cache.memoryUsage()
        XCTAssertEqual(usage2, 2000)
        let count = await cache.entryCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Helpers

    private func createDummyPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            2, 2,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        return pixelBuffer!
    }
}
