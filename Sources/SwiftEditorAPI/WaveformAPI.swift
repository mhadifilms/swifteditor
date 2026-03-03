import Foundation
import AudioEngine

/// Facade for waveform generation, caching, and audio metering.
public final class WaveformAPI: @unchecked Sendable {
    private let generator: WaveformGenerator
    private let cache: WaveformCache

    public init(generator: WaveformGenerator = WaveformGenerator(),
                cache: WaveformCache = WaveformCache()) {
        self.generator = generator
        self.cache = cache
    }

    // MARK: - Waveform Generation

    /// Generate waveform data for the audio file at the given URL.
    public func generateWaveform(for url: URL, samplesPerSecond: Int = 100) async throws -> WaveformData {
        // Check cache first.
        if let cached = await cache.get(for: url, samplesPerSecond: samplesPerSecond) {
            return cached
        }
        let data = try await generator.generateWaveform(for: url, samplesPerSecond: samplesPerSecond)
        await cache.store(data, for: url, samplesPerSecond: samplesPerSecond)
        return data
    }

    // MARK: - Cache Management

    /// Retrieve cached waveform data, if available.
    public func cachedWaveform(for url: URL, samplesPerSecond: Int = 100) async -> WaveformData? {
        await cache.get(for: url, samplesPerSecond: samplesPerSecond)
    }

    /// Store waveform data in the cache.
    public func cacheWaveform(_ data: WaveformData, for url: URL, samplesPerSecond: Int = 100) async {
        await cache.store(data, for: url, samplesPerSecond: samplesPerSecond)
    }

    /// Invalidate cached waveforms for a specific URL.
    public func invalidateWaveform(for url: URL) async {
        await cache.invalidate(url: url)
    }

    /// Clear all cached waveform data.
    public func clearWaveformCache() async {
        await cache.clear()
    }

    // MARK: - Audio Metering

    /// Create a new audio meter instance.
    public func createMeter() -> AudioMeter {
        AudioMeter()
    }

    /// Read the current peak level from a meter.
    public func peakLevel(for meter: AudioMeter) -> Float {
        meter.peakLevel
    }

    /// Read the current RMS level from a meter.
    public func rmsLevel(for meter: AudioMeter) -> Float {
        meter.rmsLevel
    }
}
