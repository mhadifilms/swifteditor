import Foundation
import CoreMediaPlus
import MediaManager

/// Facade for proxy media generation.
public final class ProxyAPI: @unchecked Sendable {
    private let generator: ProxyGenerator

    public init() {
        self.generator = ProxyGenerator()
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

    /// List available proxy presets.
    public var proxyPresets: [ProxyPreset] {
        [.halfResolution, .quarterResolution, .proresProxy]
    }
}
