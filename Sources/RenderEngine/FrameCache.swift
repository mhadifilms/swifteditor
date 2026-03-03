@preconcurrency import CoreVideo
@preconcurrency import Metal
import Foundation
import CoreMediaPlus

/// Content-addressable hash combining clip identity, source time, and effect state.
public struct FrameHash: Hashable, Sendable {
    public let clipID: UUID
    public let sourceTime: Rational
    public let effectStackHash: Int

    public init(clipID: UUID, sourceTime: Rational, effectStackHash: Int = 0) {
        self.clipID = clipID
        self.sourceTime = sourceTime
        self.effectStackHash = effectStackHash
    }
}

/// Cache statistics for monitoring hit/miss rates.
public struct CacheStatistics: Sendable {
    public var hits: Int = 0
    public var misses: Int = 0
    public var evictions: Int = 0
    public var currentEntries: Int = 0

    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
}

/// Content-addressable frame cache with LRU eviction.
/// Stores rendered frames keyed by a hash of clip identity, time, and effect state.
public actor FrameCache {

    /// Cached entry holding either a pixel buffer or texture reference.
    public enum CachedFrame: @unchecked Sendable {
        case pixelBuffer(CVPixelBuffer)
        case texture(any MTLTexture)
    }

    private struct Entry {
        let frame: CachedFrame
        var lastAccess: UInt64
    }

    private var entries: [FrameHash: Entry] = [:]
    private var accessCounter: UInt64 = 0
    private let maxEntries: Int
    private var stats = CacheStatistics()

    public init(maxEntries: Int = 120) {
        self.maxEntries = maxEntries
    }

    /// Look up a cached frame by its hash.
    public func hit(for hash: FrameHash) -> CachedFrame? {
        guard var entry = entries[hash] else {
            stats.misses += 1
            return nil
        }
        stats.hits += 1
        accessCounter += 1
        entry.lastAccess = accessCounter
        entries[hash] = entry
        return entry.frame
    }

    /// Store a rendered frame in the cache, evicting LRU entries if needed.
    public func store(_ frame: CachedFrame, for hash: FrameHash) {
        if entries.count >= maxEntries {
            evictLRU()
        }
        accessCounter += 1
        entries[hash] = Entry(frame: frame, lastAccess: accessCounter)
        stats.currentEntries = entries.count
    }

    /// Invalidate all cached frames for a specific clip.
    public func invalidate(clipID: UUID) {
        let keysToRemove = entries.keys.filter { $0.clipID == clipID }
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
        stats.currentEntries = entries.count
    }

    /// Remove all cached frames.
    public func clear() {
        entries.removeAll()
        stats.currentEntries = 0
    }

    /// Current cache statistics.
    public func statistics() -> CacheStatistics {
        stats
    }

    // MARK: - Private

    private func evictLRU() {
        guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
            return
        }
        entries.removeValue(forKey: oldest.key)
        stats.evictions += 1
    }
}
