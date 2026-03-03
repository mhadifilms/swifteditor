@preconcurrency import Metal
import CoreVideo
import CoreImage
import Observation
import CoreMediaPlus

/// Provides scope texture data for the UI by bridging video frames to the ScopeRenderer.
/// Captures CIImage or CVPixelBuffer frames and produces scope output textures.
@Observable
public final class ScopeDataProvider: @unchecked Sendable {

    // MARK: - Public state

    /// The most recently rendered scope texture as raw BGRA pixel data.
    /// Updated each time a new frame is processed.
    public private(set) var histogramPixels: [UInt8]?
    public private(set) var waveformPixels: [UInt8]?
    public private(set) var rgbParadePixels: [UInt8]?
    public private(set) var vectorscopePixels: [UInt8]?

    /// Width/height of the output scope textures.
    public private(set) var scopeWidth: Int = 256
    public private(set) var scopeHeight: Int = 256

    /// Configuration used for rendering.
    public var configuration: ScopeConfiguration {
        didSet { needsRerender = true }
    }

    // MARK: - Private state

    private let renderer: ScopeRenderer?
    private let device: any MTLDevice
    private var textureCache: CVMetalTextureCache?
    private var needsRerender = false
    private var lastPixelBuffer: CVPixelBuffer?

    // MARK: - Init

    public init(configuration: ScopeConfiguration = ScopeConfiguration()) {
        self.configuration = configuration
        self.device = MetalRenderingDevice.shared.device

        do {
            self.renderer = try ScopeRenderer()
        } catch {
            self.renderer = nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    // MARK: - Frame Input

    /// Process a CVPixelBuffer from the viewer's video output.
    /// Call this from the viewer's draw loop or a periodic timer.
    public func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let renderer else { return }
        lastPixelBuffer = pixelBuffer

        let config = ScopeConfiguration(
            outputWidth: configuration.outputWidth,
            outputHeight: configuration.outputHeight,
            brightness: configuration.brightness,
            showGraticule: configuration.showGraticule,
            paradeColumnCount: configuration.paradeColumnCount,
            vectorscopeSize: configuration.vectorscopeSize,
            showSkinToneLine: configuration.showSkinToneLine
        )

        // Render all four scopes
        if let tex = renderer.renderScope(type: .histogram, input: pixelBuffer, configuration: config) {
            histogramPixels = extractPixels(from: tex)
        }
        if let tex = renderer.renderScope(type: .waveform, input: pixelBuffer, configuration: config) {
            waveformPixels = extractPixels(from: tex)
        }
        if let tex = renderer.renderScope(type: .rgbParade, input: pixelBuffer, configuration: config) {
            rgbParadePixels = extractPixels(from: tex)
        }

        // Vectorscope uses square config
        var vsConfig = config
        vsConfig.outputWidth = config.vectorscopeSize
        vsConfig.outputHeight = config.vectorscopeSize
        if let tex = renderer.renderScope(type: .vectorscope, input: pixelBuffer, configuration: vsConfig) {
            vectorscopePixels = extractPixels(from: tex)
        }

        scopeWidth = config.outputWidth
        scopeHeight = config.outputHeight
        needsRerender = false
    }

    /// Returns the pixel data for the requested scope type.
    public func pixels(for scopeType: ScopeConfiguration.ScopeType) -> [UInt8]? {
        switch scopeType {
        case .histogram: return histogramPixels
        case .waveform: return waveformPixels
        case .rgbParade: return rgbParadePixels
        case .vectorscope: return vectorscopePixels
        }
    }

    /// The output size for a given scope type.
    public func outputSize(for scopeType: ScopeConfiguration.ScopeType) -> (width: Int, height: Int) {
        switch scopeType {
        case .vectorscope:
            let s = configuration.vectorscopeSize
            return (s, s)
        default:
            return (scopeWidth, scopeHeight)
        }
    }

    // MARK: - Pixel Extraction

    private func extractPixels(from texture: any MTLTexture) -> [UInt8] {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
        return pixels
    }
}
