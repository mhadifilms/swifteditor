import Foundation

/// Actor-based cache for generated waveform data, keyed by asset URL and resolution.
public actor WaveformCache {

    private struct CacheKey: Hashable {
        let url: URL
        let samplesPerSecond: Int
    }

    private var cache: [CacheKey: WaveformData] = [:]
    private let diskDirectory: URL?

    /// Create a waveform cache.
    /// - Parameter diskDirectory: Optional directory for disk persistence. Pass nil to disable.
    public init(diskDirectory: URL? = nil) {
        self.diskDirectory = diskDirectory
        if let dir = diskDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Retrieve cached waveform data.
    public func get(for url: URL, samplesPerSecond: Int) -> WaveformData? {
        let key = CacheKey(url: url, samplesPerSecond: samplesPerSecond)
        if let data = cache[key] {
            return data
        }
        // Try loading from disk.
        if let diskData = loadFromDisk(key: key) {
            cache[key] = diskData
            return diskData
        }
        return nil
    }

    /// Store waveform data in the cache.
    public func store(_ data: WaveformData, for url: URL, samplesPerSecond: Int) {
        let key = CacheKey(url: url, samplesPerSecond: samplesPerSecond)
        cache[key] = data
        saveToDisk(data, key: key)
    }

    /// Remove all entries for a given URL (all resolutions).
    public func invalidate(url: URL) {
        let keysToRemove = cache.keys.filter { $0.url == url }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            removeDiskFile(key: key)
        }
    }

    /// Remove all cached entries.
    public func clear() {
        cache.removeAll()
        if let dir = diskDirectory {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Disk Persistence

    private func diskFileURL(key: CacheKey) -> URL? {
        guard let dir = diskDirectory else { return nil }
        let hash = key.url.absoluteString.hashValue ^ key.samplesPerSecond.hashValue
        let filename = "waveform_\(abs(hash)).bin"
        return dir.appendingPathComponent(filename)
    }

    private func saveToDisk(_ data: WaveformData, key: CacheKey) {
        guard let fileURL = diskFileURL(key: key) else { return }
        var bytes: [UInt8] = []

        // Header: channelCount (4 bytes), sampleRate (4 bytes)
        withUnsafeBytes(of: Int32(data.channelCount)) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(data.sampleRate)) { bytes.append(contentsOf: $0) }

        for channel in data.samples {
            // Sample count for this channel (4 bytes).
            withUnsafeBytes(of: Int32(channel.count)) { bytes.append(contentsOf: $0) }
            for sample in channel {
                withUnsafeBytes(of: sample.minValue) { bytes.append(contentsOf: $0) }
                withUnsafeBytes(of: sample.maxValue) { bytes.append(contentsOf: $0) }
                withUnsafeBytes(of: sample.rmsValue) { bytes.append(contentsOf: $0) }
            }
        }

        try? Data(bytes).write(to: fileURL)
    }

    private func loadFromDisk(key: CacheKey) -> WaveformData? {
        guard let fileURL = diskFileURL(key: key),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }

        var offset = 0

        func readInt32() -> Int32? {
            let size = MemoryLayout<Int32>.size
            guard offset + size <= data.count else { return nil }
            let value = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: Int32.self)
            }
            offset += size
            return value
        }

        func readFloat() -> Float? {
            let size = MemoryLayout<Float>.size
            guard offset + size <= data.count else { return nil }
            let value = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: Float.self)
            }
            offset += size
            return value
        }

        guard let channelCount = readInt32(), let sampleRate = readInt32() else { return nil }

        var samples: [[WaveformSample]] = []
        for _ in 0..<channelCount {
            guard let count = readInt32() else { return nil }
            var channel: [WaveformSample] = []
            channel.reserveCapacity(Int(count))
            for _ in 0..<count {
                guard let minVal = readFloat(),
                      let maxVal = readFloat(),
                      let rmsVal = readFloat()
                else { return nil }
                channel.append(WaveformSample(minValue: minVal, maxValue: maxVal, rmsValue: rmsVal))
            }
            samples.append(channel)
        }

        return WaveformData(
            channelCount: Int(channelCount),
            sampleRate: Int(sampleRate),
            samples: samples
        )
    }

    private func removeDiskFile(key: CacheKey) {
        guard let fileURL = diskFileURL(key: key) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
