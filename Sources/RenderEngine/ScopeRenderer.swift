@preconcurrency import Metal
import CoreVideo
import CoreMediaPlus

/// Renders video scope visualizations (histogram, waveform, RGB parade, vectorscope)
/// using Metal compute shaders. Reuses the shared `MetalRenderingDevice`.
public final class ScopeRenderer: @unchecked Sendable {

    // MARK: - Types

    public typealias ScopeType = ScopeConfiguration.ScopeType

    // MARK: - Metal state

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let library: any MTLLibrary

    // Accumulate pipelines
    private let histogramAccPipeline: any MTLComputePipelineState
    private let waveformAccPipeline: any MTLComputePipelineState
    private let rgbParadeAccPipeline: any MTLComputePipelineState
    private let vectorscopeAccPipeline: any MTLComputePipelineState

    // Visualize pipelines
    private let histogramVisPipeline: any MTLComputePipelineState
    private let waveformVisPipeline: any MTLComputePipelineState
    private let rgbParadeVisPipeline: any MTLComputePipelineState
    private let vectorscopeVisPipeline: any MTLComputePipelineState

    // Pre-allocated buffers (sized for common use; recreated if needed)
    private var histBufferR: any MTLBuffer
    private var histBufferG: any MTLBuffer
    private var histBufferB: any MTLBuffer
    private var histBufferLuma: any MTLBuffer

    private var waveformBuffer: any MTLBuffer
    private var waveformColumnCount: Int

    private var paradeBufferR: any MTLBuffer
    private var paradeBufferG: any MTLBuffer
    private var paradeBufferB: any MTLBuffer
    private var paradeColumnCount: Int

    private var vectorscopeBuffer: any MTLBuffer
    private var vectorscopeSize: Int

    private var textureCache: CVMetalTextureCache?

    // MARK: - Init

    public init() throws {
        let renderDevice = MetalRenderingDevice.shared
        self.device = renderDevice.device
        self.commandQueue = renderDevice.commandQueue

        self.library = try Self.compileLibrary(device: device)

        // Build pipelines
        histogramAccPipeline   = try Self.makePipeline(library: library, name: "histogramKernel", device: device)
        waveformAccPipeline    = try Self.makePipeline(library: library, name: "waveformKernel", device: device)
        rgbParadeAccPipeline   = try Self.makePipeline(library: library, name: "rgbParadeKernel", device: device)
        vectorscopeAccPipeline = try Self.makePipeline(library: library, name: "vectorscopeKernel", device: device)

        histogramVisPipeline   = try Self.makePipeline(library: library, name: "histogramVisualizeKernel", device: device)
        waveformVisPipeline    = try Self.makePipeline(library: library, name: "waveformVisualizeKernel", device: device)
        rgbParadeVisPipeline   = try Self.makePipeline(library: library, name: "rgbParadeVisualizeKernel", device: device)
        vectorscopeVisPipeline = try Self.makePipeline(library: library, name: "vectorscopeVisualizeKernel", device: device)

        // Histogram: 4 channels x 256 bins
        let histSize = 256 * MemoryLayout<UInt32>.size
        histBufferR    = device.makeBuffer(length: histSize, options: .storageModeShared)!
        histBufferG    = device.makeBuffer(length: histSize, options: .storageModeShared)!
        histBufferB    = device.makeBuffer(length: histSize, options: .storageModeShared)!
        histBufferLuma = device.makeBuffer(length: histSize, options: .storageModeShared)!

        // Waveform: scopeWidth * 256
        let defaultCols = 256
        waveformColumnCount = defaultCols
        let wfSize = defaultCols * 256 * MemoryLayout<UInt32>.size
        waveformBuffer = device.makeBuffer(length: wfSize, options: .storageModeShared)!

        // Parade: paradeWidth * 256 x 3 channels
        paradeColumnCount = defaultCols
        let paradeSize = defaultCols * 256 * MemoryLayout<UInt32>.size
        paradeBufferR = device.makeBuffer(length: paradeSize, options: .storageModeShared)!
        paradeBufferG = device.makeBuffer(length: paradeSize, options: .storageModeShared)!
        paradeBufferB = device.makeBuffer(length: paradeSize, options: .storageModeShared)!

        // Vectorscope: scopeSize^2
        vectorscopeSize = defaultCols
        let vsSize = defaultCols * defaultCols * MemoryLayout<UInt32>.size
        vectorscopeBuffer = device.makeBuffer(length: vsSize, options: .storageModeShared)!

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    // MARK: - Public API

    /// Render a scope of the given type from an input texture.
    /// Returns a new output `MTLTexture` containing the scope visualization,
    /// or `nil` if rendering fails.
    public func renderScope(
        type: ScopeType,
        input: any MTLTexture,
        configuration: ScopeConfiguration = ScopeConfiguration()
    ) -> (any MTLTexture)? {
        let outputSize = MTLSize(
            width: configuration.outputWidth,
            height: configuration.outputHeight,
            depth: 1
        )
        guard let output = makeOutputTexture(width: outputSize.width, height: outputSize.height) else {
            return nil
        }

        switch type {
        case .histogram:
            return renderHistogram(input: input, output: output, config: configuration)
        case .waveform:
            return renderWaveform(input: input, output: output, config: configuration)
        case .rgbParade:
            return renderRGBParade(input: input, output: output, config: configuration)
        case .vectorscope:
            return renderVectorscope(input: input, output: output, config: configuration)
        }
    }

    /// Convenience: render a scope from a `CVPixelBuffer`.
    public func renderScope(
        type: ScopeType,
        input pixelBuffer: CVPixelBuffer,
        configuration: ScopeConfiguration = ScopeConfiguration()
    ) -> (any MTLTexture)? {
        guard let texture = makeTexture(from: pixelBuffer) else { return nil }
        return renderScope(type: type, input: texture, configuration: configuration)
    }

    // MARK: - Histogram

    private func renderHistogram(
        input: any MTLTexture,
        output: any MTLTexture,
        config: ScopeConfiguration
    ) -> (any MTLTexture)? {
        // Clear buffers
        clearBuffer(histBufferR)
        clearBuffer(histBufferG)
        clearBuffer(histBufferB)
        clearBuffer(histBufferLuma)

        guard let cb = commandQueue.makeCommandBuffer() else { return nil }

        // Phase 1+2: accumulate
        if let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(histogramAccPipeline)
            enc.setTexture(input, index: 0)
            enc.setBuffer(histBufferR,    offset: 0, index: 0)
            enc.setBuffer(histBufferG,    offset: 0, index: 1)
            enc.setBuffer(histBufferB,    offset: 0, index: 2)
            enc.setBuffer(histBufferLuma, offset: 0, index: 3)

            let tgMemSize = 256 * MemoryLayout<UInt32>.size
            enc.setThreadgroupMemoryLength(tgMemSize, index: 0)
            enc.setThreadgroupMemoryLength(tgMemSize, index: 1)
            enc.setThreadgroupMemoryLength(tgMemSize, index: 2)
            enc.setThreadgroupMemoryLength(tgMemSize, index: 3)

            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let grid   = MTLSize(width: input.width, height: input.height, depth: 1)
            enc.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
        }

        cb.commit()
        cb.waitUntilCompleted()

        // Find max across all channels for normalization
        let maxCount = findMaxHistogramValue()

        // Visualize
        guard let cb2 = commandQueue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else { return nil }

        enc2.setComputePipelineState(histogramVisPipeline)
        enc2.setBuffer(histBufferR,    offset: 0, index: 0)
        enc2.setBuffer(histBufferG,    offset: 0, index: 1)
        enc2.setBuffer(histBufferB,    offset: 0, index: 2)
        enc2.setBuffer(histBufferLuma, offset: 0, index: 3)
        enc2.setTexture(output, index: 0)

        var mc = maxCount
        enc2.setBytes(&mc, length: MemoryLayout<UInt32>.size, index: 4)
        var brightness = config.brightness
        enc2.setBytes(&brightness, length: MemoryLayout<Float>.size, index: 5)

        let vizGrid = MTLSize(width: output.width, height: output.height, depth: 1)
        enc2.dispatchThreads(vizGrid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc2.endEncoding()

        cb2.commit()
        cb2.waitUntilCompleted()
        return output
    }

    // MARK: - Waveform

    private func renderWaveform(
        input: any MTLTexture,
        output: any MTLTexture,
        config: ScopeConfiguration
    ) -> (any MTLTexture)? {
        let colCount = config.outputWidth
        ensureWaveformBuffer(columnCount: colCount)
        clearBuffer(waveformBuffer)

        guard let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }

        enc.setComputePipelineState(waveformAccPipeline)
        enc.setTexture(input, index: 0)
        enc.setBuffer(waveformBuffer, offset: 0, index: 0)
        var sw = UInt32(colCount)
        enc.setBytes(&sw, length: MemoryLayout<UInt32>.size, index: 1)

        let grid = MTLSize(width: input.width, height: input.height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding()

        cb.commit()
        cb.waitUntilCompleted()

        let maxCount = findMaxInBuffer(waveformBuffer, count: colCount * 256)

        guard let cb2 = commandQueue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else { return nil }

        enc2.setComputePipelineState(waveformVisPipeline)
        enc2.setBuffer(waveformBuffer, offset: 0, index: 0)
        enc2.setTexture(output, index: 0)
        enc2.setBytes(&sw, length: MemoryLayout<UInt32>.size, index: 1)
        var mc = maxCount
        enc2.setBytes(&mc, length: MemoryLayout<UInt32>.size, index: 2)
        var brightness = config.brightness
        enc2.setBytes(&brightness, length: MemoryLayout<Float>.size, index: 3)

        let vizGrid = MTLSize(width: output.width, height: output.height, depth: 1)
        enc2.dispatchThreads(vizGrid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc2.endEncoding()

        cb2.commit()
        cb2.waitUntilCompleted()
        return output
    }

    // MARK: - RGB Parade

    private func renderRGBParade(
        input: any MTLTexture,
        output: any MTLTexture,
        config: ScopeConfiguration
    ) -> (any MTLTexture)? {
        let colCount = config.paradeColumnCount
        ensureParadeBuffers(columnCount: colCount)
        clearBuffer(paradeBufferR)
        clearBuffer(paradeBufferG)
        clearBuffer(paradeBufferB)

        guard let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }

        enc.setComputePipelineState(rgbParadeAccPipeline)
        enc.setTexture(input, index: 0)
        enc.setBuffer(paradeBufferR, offset: 0, index: 0)
        enc.setBuffer(paradeBufferG, offset: 0, index: 1)
        enc.setBuffer(paradeBufferB, offset: 0, index: 2)
        var pw = UInt32(colCount)
        enc.setBytes(&pw, length: MemoryLayout<UInt32>.size, index: 3)

        let grid = MTLSize(width: input.width, height: input.height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding()

        cb.commit()
        cb.waitUntilCompleted()

        let maxR = findMaxInBuffer(paradeBufferR, count: colCount * 256)
        let maxG = findMaxInBuffer(paradeBufferG, count: colCount * 256)
        let maxB = findMaxInBuffer(paradeBufferB, count: colCount * 256)
        let maxCount = max(maxR, max(maxG, maxB))

        guard let cb2 = commandQueue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else { return nil }

        enc2.setComputePipelineState(rgbParadeVisPipeline)
        enc2.setBuffer(paradeBufferR, offset: 0, index: 0)
        enc2.setBuffer(paradeBufferG, offset: 0, index: 1)
        enc2.setBuffer(paradeBufferB, offset: 0, index: 2)
        enc2.setTexture(output, index: 0)
        enc2.setBytes(&pw, length: MemoryLayout<UInt32>.size, index: 3)
        var mc = maxCount
        enc2.setBytes(&mc, length: MemoryLayout<UInt32>.size, index: 4)
        var brightness = config.brightness
        enc2.setBytes(&brightness, length: MemoryLayout<Float>.size, index: 5)

        let vizGrid = MTLSize(width: output.width, height: output.height, depth: 1)
        enc2.dispatchThreads(vizGrid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc2.endEncoding()

        cb2.commit()
        cb2.waitUntilCompleted()
        return output
    }

    // MARK: - Vectorscope

    private func renderVectorscope(
        input: any MTLTexture,
        output: any MTLTexture,
        config: ScopeConfiguration
    ) -> (any MTLTexture)? {
        let scopeSz = config.vectorscopeSize
        ensureVectorscopeBuffer(size: scopeSz)
        clearBuffer(vectorscopeBuffer)

        guard let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }

        enc.setComputePipelineState(vectorscopeAccPipeline)
        enc.setTexture(input, index: 0)
        enc.setBuffer(vectorscopeBuffer, offset: 0, index: 0)
        var sz = UInt32(scopeSz)
        enc.setBytes(&sz, length: MemoryLayout<UInt32>.size, index: 1)

        let grid = MTLSize(width: input.width, height: input.height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding()

        cb.commit()
        cb.waitUntilCompleted()

        let maxCount = findMaxInBuffer(vectorscopeBuffer, count: scopeSz * scopeSz)

        guard let cb2 = commandQueue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else { return nil }

        enc2.setComputePipelineState(vectorscopeVisPipeline)
        enc2.setBuffer(vectorscopeBuffer, offset: 0, index: 0)
        enc2.setTexture(output, index: 0)
        enc2.setBytes(&sz, length: MemoryLayout<UInt32>.size, index: 1)
        var mc = maxCount
        enc2.setBytes(&mc, length: MemoryLayout<UInt32>.size, index: 2)
        var brightness = config.brightness
        enc2.setBytes(&brightness, length: MemoryLayout<Float>.size, index: 3)
        var skinTone: UInt32 = config.showSkinToneLine ? 1 : 0
        enc2.setBytes(&skinTone, length: MemoryLayout<UInt32>.size, index: 4)
        var graticule: UInt32 = config.showGraticule ? 1 : 0
        enc2.setBytes(&graticule, length: MemoryLayout<UInt32>.size, index: 5)

        let vizGrid = MTLSize(width: output.width, height: output.height, depth: 1)
        enc2.dispatchThreads(vizGrid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc2.endEncoding()

        cb2.commit()
        cb2.waitUntilCompleted()
        return output
    }

    // MARK: - Buffer management

    private func ensureWaveformBuffer(columnCount: Int) {
        guard columnCount != waveformColumnCount else { return }
        let size = columnCount * 256 * MemoryLayout<UInt32>.size
        if let buf = device.makeBuffer(length: size, options: .storageModeShared) {
            waveformBuffer = buf
            waveformColumnCount = columnCount
        }
    }

    private func ensureParadeBuffers(columnCount: Int) {
        guard columnCount != paradeColumnCount else { return }
        let size = columnCount * 256 * MemoryLayout<UInt32>.size
        if let r = device.makeBuffer(length: size, options: .storageModeShared),
           let g = device.makeBuffer(length: size, options: .storageModeShared),
           let b = device.makeBuffer(length: size, options: .storageModeShared) {
            paradeBufferR = r
            paradeBufferG = g
            paradeBufferB = b
            paradeColumnCount = columnCount
        }
    }

    private func ensureVectorscopeBuffer(size: Int) {
        guard size != vectorscopeSize else { return }
        let byteCount = size * size * MemoryLayout<UInt32>.size
        if let buf = device.makeBuffer(length: byteCount, options: .storageModeShared) {
            vectorscopeBuffer = buf
            vectorscopeSize = size
        }
    }

    private func clearBuffer(_ buffer: any MTLBuffer) {
        memset(buffer.contents(), 0, buffer.length)
    }

    // MARK: - Helpers

    private func findMaxHistogramValue() -> UInt32 {
        var maxVal: UInt32 = 1
        for buf in [histBufferR, histBufferG, histBufferB, histBufferLuma] {
            let ptr = buf.contents().bindMemory(to: UInt32.self, capacity: 256)
            for i in 0..<256 {
                maxVal = max(maxVal, ptr[i])
            }
        }
        return maxVal
    }

    private func findMaxInBuffer(_ buffer: any MTLBuffer, count: Int) -> UInt32 {
        let ptr = buffer.contents().bindMemory(to: UInt32.self, capacity: count)
        var maxVal: UInt32 = 1
        for i in 0..<count {
            maxVal = max(maxVal, ptr[i])
        }
        return maxVal
    }

    private func makeOutputTexture(width: Int, height: Int) -> (any MTLTexture)? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> (any MTLTexture)? {
        guard let cache = textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTex)
    }

    // MARK: - Shader compilation

    private static func makePipeline(
        library: any MTLLibrary,
        name: String,
        device: any MTLDevice
    ) throws -> any MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else {
            throw ScopeRendererError.functionNotFound(name)
        }
        return try device.makeComputePipelineState(function: fn)
    }

    private static func compileLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        return try device.makeLibrary(source: metalShaderSource, options: options)
    }

    public enum ScopeRendererError: Error {
        case functionNotFound(String)
        case compilationFailed
    }
}

// MARK: - Embedded Metal shader source

/// Metal shader source compiled at runtime.
/// SPM does not process .metal files, so the source is embedded here for compilation via
/// `MTLDevice.makeLibrary(source:options:)`. The canonical .metal file is kept alongside
/// for documentation and Xcode-based builds.
extension ScopeRenderer {
    static let metalShaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    // ─── Histogram ──────────────────────────────────────────────────────────────

    kernel void histogramKernel(
        texture2d<half, access::read> inputTexture [[texture(0)]],
        device atomic_uint *globalHistR    [[buffer(0)]],
        device atomic_uint *globalHistG    [[buffer(1)]],
        device atomic_uint *globalHistB    [[buffer(2)]],
        device atomic_uint *globalHistLuma [[buffer(3)]],
        threadgroup atomic_uint *localHistR    [[threadgroup(0)]],
        threadgroup atomic_uint *localHistG    [[threadgroup(1)]],
        threadgroup atomic_uint *localHistB    [[threadgroup(2)]],
        threadgroup atomic_uint *localHistLuma [[threadgroup(3)]],
        uint2 gid [[thread_position_in_grid]],
        uint  tid [[thread_index_in_threadgroup]],
        uint2 tgSize [[threads_per_threadgroup]]
    ) {
        uint threadsPerGroup = tgSize.x * tgSize.y;
        for (uint i = tid; i < 256; i += threadsPerGroup) {
            atomic_store_explicit(&localHistR[i],    0, memory_order_relaxed);
            atomic_store_explicit(&localHistG[i],    0, memory_order_relaxed);
            atomic_store_explicit(&localHistB[i],    0, memory_order_relaxed);
            atomic_store_explicit(&localHistLuma[i], 0, memory_order_relaxed);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
            threadgroup_barrier(mem_flags::mem_threadgroup);
            for (uint i = tid; i < 256; i += threadsPerGroup) {
                uint v;
                v = atomic_load_explicit(&localHistR[i], memory_order_relaxed);
                if (v > 0) atomic_fetch_add_explicit(&globalHistR[i], v, memory_order_relaxed);
                v = atomic_load_explicit(&localHistG[i], memory_order_relaxed);
                if (v > 0) atomic_fetch_add_explicit(&globalHistG[i], v, memory_order_relaxed);
                v = atomic_load_explicit(&localHistB[i], memory_order_relaxed);
                if (v > 0) atomic_fetch_add_explicit(&globalHistB[i], v, memory_order_relaxed);
                v = atomic_load_explicit(&localHistLuma[i], memory_order_relaxed);
                if (v > 0) atomic_fetch_add_explicit(&globalHistLuma[i], v, memory_order_relaxed);
            }
            return;
        }

        half4 color = inputTexture.read(gid);
        uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
        uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
        uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);
        half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
        uint binLuma = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);

        atomic_fetch_add_explicit(&localHistR[binR],       1, memory_order_relaxed);
        atomic_fetch_add_explicit(&localHistG[binG],       1, memory_order_relaxed);
        atomic_fetch_add_explicit(&localHistB[binB],       1, memory_order_relaxed);
        atomic_fetch_add_explicit(&localHistLuma[binLuma], 1, memory_order_relaxed);

        threadgroup_barrier(mem_flags::mem_threadgroup);

        for (uint i = tid; i < 256; i += threadsPerGroup) {
            uint v;
            v = atomic_load_explicit(&localHistR[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistR[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistG[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistG[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistB[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistB[i], v, memory_order_relaxed);
            v = atomic_load_explicit(&localHistLuma[i], memory_order_relaxed);
            if (v > 0) atomic_fetch_add_explicit(&globalHistLuma[i], v, memory_order_relaxed);
        }
    }

    kernel void histogramVisualizeKernel(
        device uint *histR    [[buffer(0)]],
        device uint *histG    [[buffer(1)]],
        device uint *histB    [[buffer(2)]],
        device uint *histLuma [[buffer(3)]],
        texture2d<half, access::write> outputTexture [[texture(0)]],
        constant uint &maxCount    [[buffer(4)]],
        constant float &brightness [[buffer(5)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint width  = outputTexture.get_width();
        uint height = outputTexture.get_height();
        if (gid.x >= width || gid.y >= height) return;

        uint bin = gid.x * 256 / width;
        float pixelY = 1.0 - float(gid.y) / float(height);

        float normR = float(histR[bin])    / float(maxCount);
        float normG = float(histG[bin])    / float(maxCount);
        float normB = float(histB[bin])    / float(maxCount);
        float normL = float(histLuma[bin]) / float(maxCount);

        half4 color = half4(0.05h, 0.05h, 0.05h, 1.0h);
        if (pixelY <= normL * brightness) {
            color = half4(0.6h, 0.6h, 0.6h, 1.0h);
        }
        if (pixelY <= normR * brightness) {
            color.r = max(color.r, 0.85h);
        }
        if (pixelY <= normG * brightness) {
            color.g = max(color.g, 0.85h);
        }
        if (pixelY <= normB * brightness) {
            color.b = max(color.b, 0.85h);
        }

        outputTexture.write(color, gid);
    }

    // ─── Waveform ───────────────────────────────────────────────────────────────

    kernel void waveformKernel(
        texture2d<half, access::read> inputTexture [[texture(0)]],
        device atomic_uint *waveformData [[buffer(0)]],
        constant uint &scopeWidth [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint imgW = inputTexture.get_width();
        uint imgH = inputTexture.get_height();
        if (gid.x >= imgW || gid.y >= imgH) return;

        half4 color = inputTexture.read(gid);
        half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
        uint lumaBin = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);
        uint col = gid.x * scopeWidth / imgW;
        uint index = col * 256 + lumaBin;
        atomic_fetch_add_explicit(&waveformData[index], 1, memory_order_relaxed);
    }

    kernel void waveformVisualizeKernel(
        device uint *waveformData [[buffer(0)]],
        texture2d<half, access::write> outputTexture [[texture(0)]],
        constant uint &scopeWidth  [[buffer(1)]],
        constant uint &maxCount    [[buffer(2)]],
        constant float &brightness [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint width  = outputTexture.get_width();
        uint height = outputTexture.get_height();
        if (gid.x >= width || gid.y >= height) return;

        uint col     = gid.x * scopeWidth / width;
        uint lumaBin = (height - 1 - gid.y) * 256 / height;
        uint count   = waveformData[col * 256 + lumaBin];

        if (count > 0) {
            float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);
            outputTexture.write(half4(intensity * 0.3h, intensity * 1.0h, intensity * 0.3h, 1.0h), gid);
        } else {
            outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
        }
    }

    // ─── RGB Parade ─────────────────────────────────────────────────────────────

    kernel void rgbParadeKernel(
        texture2d<half, access::read> inputTexture [[texture(0)]],
        device atomic_uint *paradeR [[buffer(0)]],
        device atomic_uint *paradeG [[buffer(1)]],
        device atomic_uint *paradeB [[buffer(2)]],
        constant uint &paradeWidth [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint imgW = inputTexture.get_width();
        uint imgH = inputTexture.get_height();
        if (gid.x >= imgW || gid.y >= imgH) return;

        half4 color = inputTexture.read(gid);
        uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
        uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
        uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);
        uint col  = gid.x * paradeWidth / imgW;

        atomic_fetch_add_explicit(&paradeR[col * 256 + binR], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&paradeG[col * 256 + binG], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&paradeB[col * 256 + binB], 1, memory_order_relaxed);
    }

    kernel void rgbParadeVisualizeKernel(
        device uint *paradeR [[buffer(0)]],
        device uint *paradeG [[buffer(1)]],
        device uint *paradeB [[buffer(2)]],
        texture2d<half, access::write> outputTexture [[texture(0)]],
        constant uint &paradeWidth [[buffer(3)]],
        constant uint &maxCount    [[buffer(4)]],
        constant float &brightness [[buffer(5)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint width  = outputTexture.get_width();
        uint height = outputTexture.get_height();
        if (gid.x >= width || gid.y >= height) return;

        uint thirdWidth   = width / 3;
        uint channelIndex = min(gid.x / thirdWidth, 2u);
        uint localX       = gid.x - channelIndex * thirdWidth;

        uint col      = localX * paradeWidth / thirdWidth;
        uint valueBin = (height - 1 - gid.y) * 256 / height;
        uint index    = col * 256 + valueBin;

        uint count = 0;
        half4 channelColor;
        if (channelIndex == 0) {
            count = paradeR[index];
            channelColor = half4(1.0h, 0.2h, 0.2h, 1.0h);
        } else if (channelIndex == 1) {
            count = paradeG[index];
            channelColor = half4(0.2h, 1.0h, 0.2h, 1.0h);
        } else {
            count = paradeB[index];
            channelColor = half4(0.2h, 0.2h, 1.0h, 1.0h);
        }

        if (count > 0) {
            float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);
            outputTexture.write(channelColor * half(intensity), gid);
        } else {
            if (gid.x == thirdWidth || gid.x == thirdWidth * 2) {
                outputTexture.write(half4(0.15h, 0.15h, 0.15h, 1.0h), gid);
            } else {
                outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
            }
        }
    }

    // ─── Vectorscope ────────────────────────────────────────────────────────────

    kernel void vectorscopeKernel(
        texture2d<half, access::read> inputTexture [[texture(0)]],
        device atomic_uint *scopeData [[buffer(0)]],
        constant uint &scopeSize [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint imgW = inputTexture.get_width();
        uint imgH = inputTexture.get_height();
        if (gid.x >= imgW || gid.y >= imgH) return;

        half4 color = inputTexture.read(gid);

        half Cb = -0.1146h * color.r - 0.3854h * color.g + 0.5000h * color.b;
        half Cr =  0.5000h * color.r - 0.4542h * color.g - 0.0458h * color.b;

        uint x = uint(clamp((Cb + 0.5h) * half(scopeSize), 0.0h, half(scopeSize - 1)));
        uint y = uint(clamp((0.5h - Cr) * half(scopeSize), 0.0h, half(scopeSize - 1)));

        atomic_fetch_add_explicit(&scopeData[y * scopeSize + x], 1, memory_order_relaxed);
    }

    kernel void vectorscopeVisualizeKernel(
        device uint *scopeData [[buffer(0)]],
        texture2d<half, access::write> outputTexture [[texture(0)]],
        constant uint  &scopeSize      [[buffer(1)]],
        constant uint  &maxCount       [[buffer(2)]],
        constant float &brightness     [[buffer(3)]],
        constant uint  &showSkinTone   [[buffer(4)]],
        constant uint  &showGraticule  [[buffer(5)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint width  = outputTexture.get_width();
        uint height = outputTexture.get_height();
        if (gid.x >= width || gid.y >= height) return;

        float2 center = float2(width / 2.0, height / 2.0);
        float2 pos    = float2(gid.x, gid.y);
        float  dist   = distance(pos, center);
        float  radius = float(min(width, height)) / 2.0;

        if (dist > radius) {
            outputTexture.write(half4(0.0h, 0.0h, 0.0h, 1.0h), gid);
            return;
        }

        if (showGraticule != 0 && abs(dist - radius) < 1.5) {
            outputTexture.write(half4(0.3h, 0.3h, 0.3h, 1.0h), gid);
            return;
        }

        if (showGraticule != 0 &&
            (abs(float(gid.x) - center.x) < 0.5 || abs(float(gid.y) - center.y) < 0.5)) {
            outputTexture.write(half4(0.12h, 0.12h, 0.12h, 1.0h), gid);
            return;
        }

        if (showSkinTone != 0 && showGraticule != 0) {
            float2 fromCenter = pos - center;
            float angle = atan2(-fromCenter.y, fromCenter.x);
            float skinAngle = 2.147;
            if (abs(angle - skinAngle) < 0.015 && dist < radius) {
                outputTexture.write(half4(0.35h, 0.25h, 0.15h, 1.0h), gid);
                return;
            }
        }

        uint scopeX = gid.x * scopeSize / width;
        uint scopeY = gid.y * scopeSize / height;
        uint count  = scopeData[scopeY * scopeSize + scopeX];

        if (count > 0) {
            float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0) * brightness, 0.0, 1.0);

            float2 normalized = float2(gid.x, gid.y) / float2(width, height);
            float Cb = normalized.x - 0.5;
            float Cr = 0.5 - normalized.y;
            float3 hueColor = float3(
                clamp(0.5 + 1.402 * Cr, 0.0, 1.0),
                clamp(0.5 - 0.344 * Cb - 0.714 * Cr, 0.0, 1.0),
                clamp(0.5 + 1.772 * Cb, 0.0, 1.0)
            );

            outputTexture.write(half4(half3(hueColor) * half(intensity), 1.0h), gid);
        } else {
            outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
        }
    }
    """
}
