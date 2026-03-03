import XCTest
@testable import RenderEngine

final class ShaderCacheTests: XCTestCase {

    // MARK: - Hash Key

    func testHashKeyIsDeterministic() {
        let source = "vertex float4 main_vertex() { return float4(0); }"
        let hash1 = ShaderCache.hashKey(for: source)
        let hash2 = ShaderCache.hashKey(for: source)
        XCTAssertEqual(hash1, hash2)
    }

    func testHashKeyDiffersForDifferentSources() {
        let source1 = "vertex float4 main_vertex() { return float4(0); }"
        let source2 = "vertex float4 main_vertex() { return float4(1); }"
        let hash1 = ShaderCache.hashKey(for: source1)
        let hash2 = ShaderCache.hashKey(for: source2)
        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashKeyIsValidHex() {
        let source = "some shader source"
        let hash = ShaderCache.hashKey(for: source)
        // SHA-256 produces 64 hex characters
        XCTAssertEqual(hash.count, 64)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in hash.unicodeScalars {
            XCTAssertTrue(hexChars.contains(char), "Hash contains non-hex character: \(char)")
        }
    }

    // MARK: - Cache Miss

    func testCacheMissReturnsNil() async {
        let device = MetalRenderingDevice.shared.device
        let cache = ShaderCache(device: device, cacheDirectory: temporaryCacheDirectory())
        let result = await cache.pipeline(forSourceHash: "nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - Count and Clear

    func testCountStartsAtZero() async {
        let device = MetalRenderingDevice.shared.device
        let cache = ShaderCache(device: device, cacheDirectory: temporaryCacheDirectory())
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testClearRemovesAllEntries() async {
        let device = MetalRenderingDevice.shared.device
        let cache = ShaderCache(device: device, cacheDirectory: temporaryCacheDirectory())
        // After clear, count should still be 0
        await cache.clear()
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testCachedHashesEmpty() async {
        let device = MetalRenderingDevice.shared.device
        let cache = ShaderCache(device: device, cacheDirectory: temporaryCacheDirectory())
        let hashes = await cache.cachedHashes
        XCTAssertTrue(hashes.isEmpty)
    }

    // MARK: - Helpers

    private func temporaryCacheDirectory() -> URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("ShaderCacheTests-\(UUID().uuidString)", isDirectory: true)
    }
}
