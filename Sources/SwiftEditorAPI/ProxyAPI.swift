import Foundation
import CoreMediaPlus
import MediaManager

/// Facade for proxy media generation and proxy/original toggling.
public final class ProxyAPI: @unchecked Sendable {
    private let generator: ProxyGenerator
    public let manager: ProxyManager

    public init() {
        self.generator = ProxyGenerator()
        self.manager = ProxyManager()
    }

    /// Generate a proxy file for the given source URL.
    public func generateProxy(
        for sourceURL: URL,
        preset: ProxyPreset,
        outputDirectory: URL
    ) async throws -> URL {
        try await generator.generateProxy(
            for: sourceURL,
            preset: preset,
            outputDirectory: outputDirectory
        )
    }

    /// Generate a proxy and automatically register it with the ProxyManager.
    public func generateAndRegisterProxy(
        for sourceURL: URL,
        preset: ProxyPreset,
        outputDirectory: URL
    ) async throws -> URL {
        await manager.markGenerating(original: sourceURL)
        let proxyURL = try await generator.generateProxy(
            for: sourceURL,
            preset: preset,
            outputDirectory: outputDirectory
        )
        await manager.registerProxy(original: sourceURL, proxy: proxyURL)
        return proxyURL
    }

    /// Stream proxy generation progress and yield the final URL.
    public func generateProxyWithProgress(
        for sourceURL: URL,
        preset: ProxyPreset,
        outputDirectory: URL
    ) async -> AsyncStream<ProxyStatus> {
        await generator.generateProxyWithProgress(
            for: sourceURL,
            preset: preset,
            outputDirectory: outputDirectory
        )
    }

    /// Toggle proxy mode on or off. When on, the render pipeline resolves
    /// asset URLs through ProxyManager, using proxy files where available.
    public func setUseProxy(_ enabled: Bool) async {
        await manager.setUseProxy(enabled)
    }

    /// Whether proxy mode is currently active.
    public var isProxyModeActive: Bool {
        get async { await manager.useProxy }
    }

    /// Resolve a URL through the proxy manager (proxy if available, otherwise original).
    public func resolveURL(_ original: URL) async -> URL {
        await manager.resolveURL(original)
    }

    /// Get the proxy status for a specific asset URL.
    public func proxyStatus(for original: URL) async -> ProxyClipStatus {
        await manager.status(for: original)
    }

    /// List available proxy presets.
    public var proxyPresets: [ProxyPreset] {
        [.halfResolution, .quarterResolution, .proresProxy]
    }
}
