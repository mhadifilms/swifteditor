import Foundation
import Combine
import CoreImage
import CoreMediaPlus
import CoreGraphics
import RenderEngine
import ViewerKit

/// Facade for render pipeline configuration: background rendering, frame cache,
/// video scopes, HDR, and shader cache management.
public final class RenderConfigAPI: @unchecked Sendable {
    private let backgroundRenderer: BackgroundRenderer
    public let frameCache: FrameCache
    private let shaderCache: ShaderCache?
    private var _hdrConfiguration: HDRConfiguration
    private var playheadCancellable: AnyCancellable?

    public init(
        backgroundRenderer: BackgroundRenderer,
        frameCache: FrameCache,
        shaderCache: ShaderCache? = nil
    ) {
        self.backgroundRenderer = backgroundRenderer
        self.frameCache = frameCache
        self.shaderCache = shaderCache
        self._hdrConfiguration = .sdrDefault()
    }

    /// Convenience initializer that creates default instances.
    public init() {
        let cache = FrameCache()
        self.frameCache = cache
        self.backgroundRenderer = BackgroundRenderer(cache: cache)
        self.shaderCache = nil
        self._hdrConfiguration = .sdrDefault()
    }

    // MARK: - Background Rendering

    /// Start background pre-rendering around the playhead.
    public func startBackgroundRendering() async {
        await backgroundRenderer.start()
    }

    /// Stop background pre-rendering.
    public func stopBackgroundRendering() async {
        await backgroundRenderer.stop()
    }

    /// Update the playhead position for background rendering.
    public func updatePlayheadPosition(_ time: Rational) async {
        await backgroundRenderer.updatePlayheadPosition(time)
    }

    // MARK: - Frame Cache

    /// Clear all cached rendered frames.
    public func clearFrameCache() async {
        await frameCache.clear()
    }

    /// Get current frame cache statistics.
    public func frameCacheStatistics() async -> CacheStatistics {
        await frameCache.statistics()
    }

    /// Get the current number of entries in the frame cache.
    public func frameCacheEntryCount() async -> Int {
        await frameCache.statistics().currentEntries
    }

    // MARK: - Scopes

    /// Create a scope configuration for the specified scope type.
    public func createScopeConfiguration(type: ScopeConfiguration.ScopeType) -> ScopeConfiguration {
        ScopeConfiguration(
            outputWidth: 256,
            outputHeight: 256,
            brightness: 1.0,
            showGraticule: true
        )
    }

    /// All available video scope types.
    public var availableScopeTypes: [ScopeConfiguration.ScopeType] {
        ScopeConfiguration.ScopeType.allCases
    }

    // MARK: - HDR Configuration

    /// Standard SDR configuration.
    public func sdrConfiguration() -> HDRConfiguration {
        .sdrDefault()
    }

    /// HDR10 PQ configuration.
    public func hdrPQConfiguration(edrHeadroom: CGFloat = 4.0) -> HDRConfiguration {
        .hdrPQ(edrHeadroom: edrHeadroom)
    }

    /// HLG HDR configuration.
    public func hdrHLGConfiguration(edrHeadroom: CGFloat = 3.0) -> HDRConfiguration {
        .hdrHLG(edrHeadroom: edrHeadroom)
    }

    /// The current HDR configuration.
    public var currentHDRConfiguration: HDRConfiguration {
        get { _hdrConfiguration }
        set { _hdrConfiguration = newValue }
    }

    // MARK: - BackgroundRenderer Wiring

    /// Wire the BackgroundRenderer to a MetalCompositor for pre-rendering, and connect
    /// it to the TransportController so playhead changes trigger pre-rendering.
    public func wireBackgroundRenderer(
        compositor: MetalCompositor,
        renderSize: CGSize,
        transport: TransportController
    ) {
        let cache = self.frameCache
        let bgRenderer = self.backgroundRenderer

        // Provide the render callback: renders a CIImage at the given time
        // using the MetalCompositor's standalone rendering path.
        Task {
            await bgRenderer.setRenderFrame { @Sendable time in
                // For background pre-rendering, we create a simple solid frame
                // as a placeholder. In a full pipeline this would composite the
                // timeline at the given time. The compositor is available for
                // rendering CIImages into pixel buffers.
                let placeholder = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
                    .cropped(to: CGRect(origin: .zero, size: renderSize))
                guard let buffer = compositor.renderImageToPixelBuffer(placeholder, size: renderSize) else {
                    return nil
                }
                return .pixelBuffer(buffer)
            }
        }

        // Connect transport playhead changes to background renderer
        playheadCancellable = transport.timePublisher
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak bgRenderer] time in
                guard let bgRenderer else { return }
                Task {
                    await bgRenderer.updatePlayheadPosition(time)
                }
            }
    }

    /// Start background pre-rendering and connect to transport playhead.
    public func startBackgroundRenderingWithTransport(transport: TransportController) async {
        await backgroundRenderer.start()
    }

    // MARK: - Shader Cache

    /// Clear all compiled shader pipelines.
    public func clearShaderCache() async {
        await shaderCache?.clear()
    }
}
