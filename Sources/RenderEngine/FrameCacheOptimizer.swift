import Foundation
import CoreMediaPlus

/// Enhanced frame cache with configurable memory budget, LRU eviction policy,
/// and pre-warming around the playhead position.
public actor FrameCacheOptimizer {

    /// Configuration for the cache optimizer.
    public struct Configuration: Sendable {
        /// Maximum memory budget in bytes. Defaults to 512 MB.
        public var memoryBudgetBytes: Int
        /// Number of frames to pre-warm ahead of the playhead.
        public var prewarmAhead: Int
        /// Number of frames to pre-warm behind the playhead.
        public var prewarmBehind: Int
        /// Frame duration for computing pre-warm time offsets.
        public var frameDuration: Rational
        /// Fraction of memory budget at which eviction begins (0.0 - 1.0).
        public var evictionThreshold: Double

        public init(
            memoryBudgetBytes: Int = 512 * 1024 * 1024,
            prewarmAhead: Int = 30,
            prewarmBehind: Int = 10,
            frameDuration: Rational = Rational(1, 30),
            evictionThreshold: Double = 0.9
        ) {
            self.memoryBudgetBytes = memoryBudgetBytes
            self.prewarmAhead = prewarmAhead
            self.prewarmBehind = prewarmBehind
            self.frameDuration = frameDuration
            self.evictionThreshold = evictionThreshold
        }
    }

    /// Tracks estimated memory usage of a cached entry.
    private struct CacheEntry {
        let frame: FrameCache.CachedFrame
        let estimatedBytes: Int
        var lastAccess: UInt64
        let insertionTime: UInt64
    }

    private var entries: [FrameHash: CacheEntry] = [:]
    private var accessCounter: UInt64 = 0
    private var currentMemoryUsage: Int = 0
    private var stats = CacheStatistics()
    private let config: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // MARK: - Cache Operations

    /// Look up a cached frame by its hash.
    public func hit(for hash: FrameHash) -> FrameCache.CachedFrame? {
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

    /// Store a frame in the cache with an estimated memory cost.
    /// Triggers LRU eviction if the memory budget threshold is exceeded.
    public func store(
        _ frame: FrameCache.CachedFrame,
        for hash: FrameHash,
        estimatedBytes: Int
    ) {
        // Evict if we would exceed the threshold
        let threshold = Int(Double(config.memoryBudgetBytes) * config.evictionThreshold)
        while currentMemoryUsage + estimatedBytes > threshold && !entries.isEmpty {
            evictLRU()
        }

        // If a single frame exceeds the entire budget, skip caching
        if estimatedBytes > config.memoryBudgetBytes {
            return
        }

        accessCounter += 1
        let entry = CacheEntry(
            frame: frame,
            estimatedBytes: estimatedBytes,
            lastAccess: accessCounter,
            insertionTime: accessCounter
        )

        // Replace existing entry if present
        if let existing = entries[hash] {
            currentMemoryUsage -= existing.estimatedBytes
        }

        entries[hash] = entry
        currentMemoryUsage += estimatedBytes
        stats.currentEntries = entries.count
    }

    /// Invalidate all entries for a specific clip.
    public func invalidate(clipID: UUID) {
        let keysToRemove = entries.keys.filter { $0.clipID == clipID }
        for key in keysToRemove {
            if let entry = entries.removeValue(forKey: key) {
                currentMemoryUsage -= entry.estimatedBytes
                stats.evictions += 1
            }
        }
        stats.currentEntries = entries.count
    }

    /// Remove all cached frames.
    public func clear() {
        entries.removeAll()
        currentMemoryUsage = 0
        stats.currentEntries = 0
    }

    /// Current cache statistics.
    public func statistics() -> CacheStatistics {
        stats
    }

    /// Current estimated memory usage in bytes.
    public func memoryUsage() -> Int {
        currentMemoryUsage
    }

    /// Number of entries currently cached.
    public func entryCount() -> Int {
        entries.count
    }

    // MARK: - Pre-warming

    /// Compute the list of frame hashes that should be pre-warmed around the
    /// current playhead position.
    public func prewarmHashes(
        around playhead: Rational,
        hashForTime: (Rational) -> FrameHash
    ) -> [FrameHash] {
        var hashes: [FrameHash] = []
        let behind = config.prewarmBehind
        let ahead = config.prewarmAhead
        let duration = config.frameDuration

        for i in (-behind)...ahead {
            let time = playhead + duration * Rational(Int64(i), 1)
            guard time >= .zero else { continue }
            let hash = hashForTime(time)
            // Only include hashes not already cached
            if entries[hash] == nil {
                hashes.append(hash)
            }
        }
        return hashes
    }

    /// Evict entries that are far from the current playhead to make room for
    /// upcoming frames. Keeps entries within the pre-warm window and evicts
    /// those outside it, starting with the least recently used.
    public func evictDistant(
        playhead: Rational,
        hashForTime: (Rational) -> FrameHash
    ) {
        // Build the set of hashes in the pre-warm window
        var keepSet = Set<FrameHash>()
        let behind = config.prewarmBehind
        let ahead = config.prewarmAhead
        let duration = config.frameDuration

        for i in (-behind)...ahead {
            let time = playhead + duration * Rational(Int64(i), 1)
            guard time >= .zero else { continue }
            keepSet.insert(hashForTime(time))
        }

        // Evict entries not in the keep set, oldest first
        let distantEntries = entries
            .filter { !keepSet.contains($0.key) }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }

        for (key, entry) in distantEntries {
            entries.removeValue(forKey: key)
            currentMemoryUsage -= entry.estimatedBytes
            stats.evictions += 1
        }
        stats.currentEntries = entries.count
    }

    // MARK: - Private

    private func evictLRU() {
        guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
            return
        }
        entries.removeValue(forKey: oldest.key)
        currentMemoryUsage -= oldest.value.estimatedBytes
        stats.evictions += 1
        stats.currentEntries = entries.count
    }
}
