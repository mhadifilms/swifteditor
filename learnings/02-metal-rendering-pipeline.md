# Metal Rendering Pipeline for Real-Time Video

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Core Metal Objects & Setup](#2-core-metal-objects--setup)
3. [CVPixelBuffer to MTLTexture Pipeline](#3-cvpixelbuffer-to-mtltexture-pipeline)
4. [YUV to RGB Conversion](#4-yuv-to-rgb-conversion)
5. [Render Pipeline: Vertex & Fragment Shaders](#5-render-pipeline-vertex--fragment-shaders)
6. [Compute Pipeline: Kernel Shaders](#6-compute-pipeline-kernel-shaders)
7. [Triple Buffering for Smooth Playback](#7-triple-buffering-for-smooth-playback)
8. [Video Compositing & Layer Blending](#8-video-compositing--layer-blending)
9. [Video Effects & Color Correction Shaders](#9-video-effects--color-correction-shaders)
10. [LUT-Based Color Grading](#10-lut-based-color-grading)
11. [Video Transitions](#11-video-transitions)
12. [Custom CIFilter with Metal Kernels](#12-custom-cifilter-with-metal-kernels)
13. [Metal Performance Shaders (MPS)](#13-metal-performance-shaders-mps)
14. [HDR & Extended Dynamic Range (EDR)](#14-hdr--extended-dynamic-range-edr)
15. [Display Synchronization](#15-display-synchronization)
16. [Memory Management & Texture Pools](#16-memory-management--texture-pools)
17. [IOSurface & Zero-Copy Rendering](#17-iosurface--zero-copy-rendering)
18. [Metal 4 (WWDC 2025)](#18-metal-4-wwdc-2025)
19. [Complete NLE Rendering Architecture](#19-complete-nle-rendering-architecture)
20. [Performance Optimization Techniques](#20-performance-optimization-techniques)
21. [Open Source Reference Frameworks](#21-open-source-reference-frameworks)
22. [Key WWDC Sessions](#22-key-wwdc-sessions)

---

## 1. Architecture Overview

A professional NLE (Non-Linear Editor) Metal rendering pipeline processes video frames through these stages:

```
Video Decode (AVAssetReader / VideoToolbox)
    |
    v
CVPixelBuffer (backed by IOSurface)
    |
    v
CVMetalTextureCache (zero-copy mapping)
    |
    v
MTLTexture (YUV planes: luminance + chrominance)
    |
    v
YUV -> RGB Conversion (fragment shader)
    |
    v
Effects Processing Pipeline (compute/fragment shaders)
    |  - Color correction (brightness, contrast, saturation)
    |  - LUT color grading
    |  - Blur, sharpen, chroma key
    |  - Custom CIFilter kernels
    |
    v
Compositing (layer blending, alpha compositing)
    |  - Back-to-front layer rendering
    |  - Blend modes (normal, multiply, screen, overlay, etc.)
    |  - Opacity & transform per layer
    |
    v
Transitions (dissolve, wipe, push)
    |
    v
Final Composite (to CAMetalLayer drawable)
    |
    v
Display (via CAMetalDisplayLink / MTKView)
```

### Key Design Principles
- **Zero-copy where possible**: CVPixelBuffer -> IOSurface -> MTLTexture mapping avoids CPU copies
- **Triple buffering**: Keeps CPU 1-2 frames ahead of GPU to prevent stalls
- **Texture pools**: Reuse intermediate textures to minimize allocations
- **Pipeline caching**: Cache MTLRenderPipelineState and MTLComputePipelineState objects
- **Async GPU work**: Use command buffer completion handlers, never block the main thread

---

## 2. Core Metal Objects & Setup

### MetalRenderingDevice (Singleton Pattern)

This pattern (from GPUImage3) creates a shared device, command queue, and shader library:

```swift
import Metal
import MetalPerformanceShaders

public let sharedMetalRenderingDevice = MetalRenderingDevice()

public class MetalRenderingDevice {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let shaderLibrary: MTLLibrary
    public let metalPerformanceShadersAreSupported: Bool

    lazy var passthroughRenderState: MTLRenderPipelineState = {
        let (pipelineState, _, _) = generateRenderPipelineState(
            device: self,
            vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "passthroughFragment",
            operationName: "Passthrough"
        )
        return pipelineState
    }()

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Could not create Metal Device")
        }
        self.device = device

        guard let queue = self.device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue

        if #available(iOS 9, macOS 10.13, *) {
            self.metalPerformanceShadersAreSupported = MPSSupportsMTLDevice(device)
        } else {
            self.metalPerformanceShadersAreSupported = false
        }

        guard let defaultLibrary = try? device.makeDefaultLibrary(bundle: .main) else {
            fatalError("Could not load library")
        }
        self.shaderLibrary = defaultLibrary
    }
}
```

### Generating a Render Pipeline State

```swift
func generateRenderPipelineState(
    device: MetalRenderingDevice,
    vertexFunctionName: String,
    fragmentFunctionName: String,
    operationName: String
) -> (MTLRenderPipelineState, [String: (Int, MTLStructMember)], Int) {
    guard let vertexFunction = device.shaderLibrary.makeFunction(name: vertexFunctionName) else {
        fatalError("\(operationName): could not compile vertex function \(vertexFunctionName)")
    }
    guard let fragmentFunction = device.shaderLibrary.makeFunction(name: fragmentFunctionName) else {
        fatalError("\(operationName): could not compile fragment function \(fragmentFunctionName)")
    }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.rasterSampleCount = 1
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction

    do {
        var reflection: MTLAutoreleasedRenderPipelineReflection?
        let pipelineState = try device.device.makeRenderPipelineState(
            descriptor: descriptor,
            options: [.bufferTypeInfo, .argumentInfo],
            reflection: &reflection
        )

        // Build uniform lookup table from reflection
        var uniformLookupTable: [String: (Int, MTLStructMember)] = [:]
        var bufferSize: Int = 0
        if let fragmentArguments = reflection?.fragmentArguments {
            for fragmentArgument in fragmentArguments where fragmentArgument.type == .buffer {
                if fragmentArgument.bufferDataType == .struct,
                   let members = fragmentArgument.bufferStructType?.members.enumerated() {
                    bufferSize = fragmentArgument.bufferDataSize
                    for (index, uniform) in members {
                        uniformLookupTable[uniform.name] = (index, uniform)
                    }
                }
            }
        }
        return (pipelineState, uniformLookupTable, bufferSize)
    } catch {
        fatalError("Could not create render pipeline state: \(error)")
    }
}
```

### Generating a Compute Pipeline State

```swift
func makeComputePipeline(functionName: String) -> MTLComputePipelineState {
    let device = sharedMetalRenderingDevice.device
    let library = sharedMetalRenderingDevice.shaderLibrary

    guard let function = library.makeFunction(name: functionName) else {
        fatalError("Could not find compute function: \(functionName)")
    }
    do {
        return try device.makeComputePipelineState(function: function)
    } catch {
        fatalError("Could not create compute pipeline: \(error)")
    }
}
```

---

## 3. CVPixelBuffer to MTLTexture Pipeline

### Creating and Using CVMetalTextureCache

This is the critical zero-copy path from video decode to GPU texture:

```swift
import CoreVideo
import Metal

class VideoTextureConverter {
    private var textureCache: CVMetalTextureCache?
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device

        // Create the texture cache
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,               // cache attributes
            device,
            nil,               // texture attributes
            &cache
        )
        guard status == kCVReturnSuccess, let validCache = cache else {
            fatalError("Failed to create CVMetalTextureCache: \(status)")
        }
        self.textureCache = validCache
    }

    /// Convert a BGRA CVPixelBuffer to a single MTLTexture
    func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,                    // texture attributes
            .bgra8Unorm,           // pixel format
            width,
            height,
            0,                     // plane index
            &cvMetalTexture
        )

        guard status == kCVReturnSuccess,
              let metalTexture = cvMetalTexture,
              let texture = CVMetalTextureGetTexture(metalTexture) else {
            return nil
        }

        // IMPORTANT: Keep a strong reference to cvMetalTexture until
        // the GPU is done using it (use command buffer completion handler)
        return texture
    }

    /// Convert a YUV (NV12 / 420YpCbCr8BiPlanarFullRange) CVPixelBuffer to two textures
    func yuvTextures(from pixelBuffer: CVPixelBuffer) -> (luminance: MTLTexture, chrominance: MTLTexture)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Luminance plane (Y) - full resolution, single channel
        var luminanceRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            .r8Unorm,          // Single channel for Y
            width,
            height,
            0,                 // Plane 0 = luminance
            &luminanceRef
        )

        // Chrominance plane (CbCr) - half resolution, two channels
        var chrominanceRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            .rg8Unorm,         // Two channels for CbCr
            width / 2,
            height / 2,
            1,                 // Plane 1 = chrominance
            &chrominanceRef
        )

        guard let lumRef = luminanceRef, let chromRef = chrominanceRef,
              let lumTex = CVMetalTextureGetTexture(lumRef),
              let chromTex = CVMetalTextureGetTexture(chromRef) else {
            return nil
        }

        return (lumTex, chromTex)
    }

    /// Flush the cache periodically to release unused textures
    func flush() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
}
```

### Output Settings for Metal-Compatible Decode

When reading video with AVAssetReader, request Metal-compatible pixel buffers:

```swift
let outputSettings: [String: Any] = [
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferPixelFormatTypeKey as String: NSNumber(
        value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    )
]

let readerOutput = AVAssetReaderTrackOutput(
    track: videoTrack,
    outputSettings: outputSettings
)
readerOutput.alwaysCopiesSampleData = false  // Zero-copy
```

---

## 4. YUV to RGB Conversion

Video codecs (H.264, HEVC, ProRes) typically output YUV color space. The GPU converts to RGB for rendering.

### Metal Shader (MSL)

```metal
#include <metal_stdlib>
using namespace metal;

// Vertex I/O structures
struct SingleInputVertexIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
};

struct TwoInputVertexIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
    float2 textureCoordinate2 [[user(texturecoord2)]];
};

// Color conversion matrices
typedef struct {
    float3x3 colorConversionMatrix;
} YUVConversionUniform;

// BT.601 Full Range -> RGB
// Commonly used for consumer video (SD)
constant float3x3 kColorConversion601FullRange = float3x3(
    float3(1.0,    1.0,    1.0),
    float3(0.0,   -0.343,  1.765),
    float3(1.4,   -0.711,  0.0)
);

// BT.709 -> RGB
// Used for HD video (720p, 1080p)
constant float3x3 kColorConversion709 = float3x3(
    float3(1.164,  1.164,  1.164),
    float3(0.0,   -0.213,  2.112),
    float3(1.793, -0.533,  0.0)
);

// BT.2020 -> RGB
// Used for UHD/4K HDR video
constant float3x3 kColorConversion2020 = float3x3(
    float3(1.164,  1.164,  1.164),
    float3(0.0,   -0.187,  2.141),
    float3(1.678, -0.650,  0.0)
);

// Full-range YUV to RGB conversion (no offset needed for Y)
fragment half4 yuvConversionFullRangeFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> luminanceTexture [[texture(0)]],
    texture2d<half> chrominanceTexture [[texture(1)]],
    constant YUVConversionUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half3 yuv;
    yuv.x = luminanceTexture.sample(quadSampler, fragmentInput.textureCoordinate).r;
    yuv.yz = chrominanceTexture.sample(quadSampler, fragmentInput.textureCoordinate).rg - half2(0.5, 0.5);

    half3 rgb = half3x3(uniform.colorConversionMatrix) * yuv;
    return half4(rgb, 1.0);
}

// Video-range YUV to RGB conversion (Y offset by 16/255)
fragment half4 yuvConversionVideoRangeFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> luminanceTexture [[texture(0)]],
    texture2d<half> chrominanceTexture [[texture(1)]],
    constant YUVConversionUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half3 yuv;
    yuv.x = luminanceTexture.sample(quadSampler, fragmentInput.textureCoordinate).r - (16.0/255.0);
    yuv.yz = chrominanceTexture.sample(quadSampler, fragmentInput.textureCoordinate).ra - half2(0.5, 0.5);

    half3 rgb = half3x3(uniform.colorConversionMatrix) * yuv;
    return half4(rgb, 1.0);
}
```

### Swift Host Code for YUV Conversion

```swift
func convertYUVToRGB(
    pipelineState: MTLRenderPipelineState,
    lookupTable: [String: (Int, MTLStructMember)],
    bufferSize: Int,
    luminanceTexture: Texture,
    chrominanceTexture: Texture,
    resultTexture: Texture,
    colorConversionMatrix: Matrix3x3
) {
    guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else {
        return
    }

    let uniformSettings = ShaderUniformSettings(
        uniformLookupTable: lookupTable,
        bufferSize: bufferSize
    )
    uniformSettings["colorConversionMatrix"] = colorConversionMatrix

    commandBuffer.renderQuad(
        pipelineState: pipelineState,
        uniformSettings: uniformSettings,
        inputTextures: [0: luminanceTexture, 1: chrominanceTexture],
        outputTexture: resultTexture
    )
    commandBuffer.commit()
}
```

---

## 5. Render Pipeline: Vertex & Fragment Shaders

### Standard Vertex Shaders for Video Quad Rendering

```metal
#include <metal_stdlib>
using namespace metal;

// Luminance constants (ITU-R BT.709)
constant half3 luminanceWeighting = half3(0.2125, 0.7154, 0.0721);

struct SingleInputVertexIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
};

struct TwoInputVertexIO {
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
    float2 textureCoordinate2 [[user(texturecoord2)]];
};

// Single-input vertex shader (for effects with one input texture)
vertex SingleInputVertexIO oneInputVertex(
    const device packed_float2 *position [[buffer(0)]],
    const device packed_float2 *texturecoord [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    SingleInputVertexIO outputVertices;
    outputVertices.position = float4(position[vid], 0, 1.0);
    outputVertices.textureCoordinate = texturecoord[vid];
    return outputVertices;
}

// Two-input vertex shader (for blend operations, transitions)
vertex TwoInputVertexIO twoInputVertex(
    const device packed_float2 *position [[buffer(0)]],
    const device packed_float2 *texturecoord [[buffer(1)]],
    const device packed_float2 *texturecoord2 [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    TwoInputVertexIO outputVertices;
    outputVertices.position = float4(position[vid], 0, 1.0);
    outputVertices.textureCoordinate = texturecoord[vid];
    outputVertices.textureCoordinate2 = texturecoord2[vid];
    return outputVertices;
}

// Passthrough fragment shader (renders texture as-is)
fragment half4 passthroughFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    return color;
}
```

### Standard Image Vertices (Full-Screen Quad)

```swift
// OpenGL uses bottom-left origin, Metal uses top-left origin
public let standardImageVertices: [Float] = [
    -1.0,  1.0,    // top-left
     1.0,  1.0,    // top-right
    -1.0, -1.0,    // bottom-left
     1.0, -1.0     // bottom-right
]
```

### Rendering a Textured Quad

```swift
extension MTLCommandBuffer {
    func renderQuad(
        pipelineState: MTLRenderPipelineState,
        uniformSettings: ShaderUniformSettings? = nil,
        inputTextures: [UInt: Texture],
        useNormalizedTextureCoordinates: Bool = true,
        imageVertices: [Float] = standardImageVertices,
        outputTexture: Texture,
        outputOrientation: ImageOrientation = .portrait
    ) {
        let vertexBuffer = sharedMetalRenderingDevice.device.makeBuffer(
            bytes: imageVertices,
            length: imageVertices.count * MemoryLayout<Float>.size,
            options: []
        )!

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture.texture
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].loadAction = .clear

        guard let renderEncoder = self.makeRenderCommandEncoder(descriptor: renderPass) else {
            fatalError("Could not create render encoder")
        }
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Bind each input texture
        for textureIndex in 0..<inputTextures.count {
            let currentTexture = inputTextures[UInt(textureIndex)]!
            let texCoords = currentTexture.textureCoordinates(
                for: outputOrientation,
                normalized: useNormalizedTextureCoordinates
            )
            let textureBuffer = sharedMetalRenderingDevice.device.makeBuffer(
                bytes: texCoords,
                length: texCoords.count * MemoryLayout<Float>.size,
                options: []
            )!
            renderEncoder.setVertexBuffer(textureBuffer, offset: 0, index: 1 + textureIndex)
            renderEncoder.setFragmentTexture(currentTexture.texture, index: textureIndex)
        }

        // Apply uniform settings (brightness, contrast, etc.)
        uniformSettings?.restoreShaderSettings(renderEncoder: renderEncoder)

        // Draw the quad as a triangle strip (4 vertices)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
    }
}
```

---

## 6. Compute Pipeline: Kernel Shaders

Compute shaders are preferred for pixel-independent image processing operations because they can be more efficient than render passes for certain workloads.

### Compute Kernel for Saturation Adjustment

```metal
#include <metal_stdlib>
using namespace metal;

struct AdjustSaturationUniforms {
    float saturationFactor;
};

kernel void adjust_saturation(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);
    // Weighted luminance (ITU-R BT.709)
    float value = dot(inColor.rgb, float3(0.2125, 0.7154, 0.0721));
    float4 grayColor(value, value, value, 1.0);
    float4 outColor = mix(grayColor, inColor, uniforms.saturationFactor);
    outTexture.write(outColor, gid);
}
```

### Compute Kernel for Gaussian Blur

```metal
kernel void gaussian_blur_2d(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    texture2d<float, access::read> weights [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    int size = weights.get_width();
    int radius = size / 2;
    float4 accumColor(0, 0, 0, 0);

    for (int j = 0; j < size; ++j) {
        for (int i = 0; i < size; ++i) {
            uint2 kernelIndex(i, j);
            uint2 textureIndex(gid.x + (i - radius), gid.y + (j - radius));
            float4 color = inTexture.read(textureIndex).rgba;
            float4 weight = weights.read(kernelIndex).rrrr;
            accumColor += weight * color;
        }
    }

    outTexture.write(float4(accumColor.rgb, 1), gid);
}
```

### Optimized Separable Gaussian Blur (Two-Pass)

```metal
// Horizontal pass
kernel void gaussian_blur_horizontal(
    texture2d<half, access::read> inTexture [[texture(0)]],
    texture2d<half, access::write> outTexture [[texture(1)]],
    constant float *weights [[buffer(0)]],
    constant int &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;

    half4 accumColor = half4(0.0);
    for (int i = -radius; i <= radius; ++i) {
        uint2 samplePos = uint2(clamp(int(gid.x) + i, 0, int(inTexture.get_width()) - 1), gid.y);
        half4 color = inTexture.read(samplePos);
        accumColor += color * half(weights[i + radius]);
    }
    outTexture.write(accumColor, gid);
}

// Vertical pass
kernel void gaussian_blur_vertical(
    texture2d<half, access::read> inTexture [[texture(0)]],
    texture2d<half, access::write> outTexture [[texture(1)]],
    constant float *weights [[buffer(0)]],
    constant int &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;

    half4 accumColor = half4(0.0);
    for (int j = -radius; j <= radius; ++j) {
        uint2 samplePos = uint2(gid.x, clamp(int(gid.y) + j, 0, int(inTexture.get_height()) - 1));
        half4 color = inTexture.read(samplePos);
        accumColor += color * half(weights[j + radius]);
    }
    outTexture.write(accumColor, gid);
}
```

### Swift Host Code for Dispatching Compute Work

```swift
class ComputeShaderProcessor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLComputePipelineState

    init(functionName: String) {
        self.device = sharedMetalRenderingDevice.device
        self.commandQueue = sharedMetalRenderingDevice.commandQueue

        let library = sharedMetalRenderingDevice.shaderLibrary
        guard let function = library.makeFunction(name: functionName) else {
            fatalError("Could not find function: \(functionName)")
        }
        self.pipeline = try! device.makeComputePipelineState(function: function)
    }

    func process(input: MTLTexture, output: MTLTexture, uniforms: UnsafeRawPointer? = nil, uniformSize: Int = 0) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)

        if let uniforms = uniforms {
            encoder.setBytes(uniforms, length: uniformSize, index: 0)
        }

        // Calculate optimal threadgroup size
        let threadgroupSize = MTLSize(
            width: min(pipeline.threadExecutionWidth, output.width),
            height: min(pipeline.maxTotalThreadsPerThreadgroup / pipeline.threadExecutionWidth, output.height),
            depth: 1
        )
        let threadgroups = MTLSize(
            width: (output.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (output.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
    }
}
```

---

## 7. Triple Buffering for Smooth Playback

Triple buffering prevents CPU/GPU synchronization stalls by maintaining three sets of dynamic buffers.

### Why Triple Buffering?
- **One buffer**: CPU and GPU fight over the same memory (severe stalls)
- **Two buffers**: CPU can work one frame ahead, but sometimes still stalls
- **Three buffers**: CPU can work 1-2 frames ahead of GPU, ideal balance of latency vs. throughput
- **Four+ buffers**: Diminishing returns, increased memory and latency

### Complete Swift Implementation

```swift
import Metal
import Dispatch

class TripleBufferedRenderer {
    static let maxInflightBuffers = 3

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let frameBoundarySemaphore: DispatchSemaphore
    private var currentFrameIndex: Int = 0

    // Triple-buffered dynamic data
    private var dynamicBuffers: [MTLBuffer] = []

    struct FrameUniforms {
        var time: Float
        var brightness: Float
        var contrast: Float
        var saturation: Float
    }

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        // Semaphore limits in-flight frames
        self.frameBoundarySemaphore = DispatchSemaphore(value: Self.maxInflightBuffers)

        // Pre-allocate triple buffers
        for i in 0..<Self.maxInflightBuffers {
            let buffer = device.makeBuffer(
                length: MemoryLayout<FrameUniforms>.size,
                options: .storageModeShared
            )!
            buffer.label = "DynamicBuffer-\(i)"
            dynamicBuffers.append(buffer)
        }
    }

    func render(
        inputTexture: MTLTexture,
        outputDrawable: CAMetalDrawable,
        pipelineState: MTLRenderPipelineState,
        uniforms: FrameUniforms
    ) {
        // Wait until a buffer slot is available (blocks if all 3 are in-flight)
        frameBoundarySemaphore.wait()

        // Advance frame index (0 -> 1 -> 2 -> 0 -> ...)
        currentFrameIndex = (currentFrameIndex + 1) % Self.maxInflightBuffers
        let currentBuffer = dynamicBuffers[currentFrameIndex]

        // Update buffer contents (safe because GPU is not reading this buffer)
        var mutableUniforms = uniforms
        currentBuffer.contents().copyMemory(
            from: &mutableUniforms,
            byteCount: MemoryLayout<FrameUniforms>.size
        )

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameBoundarySemaphore.signal()
            return
        }

        // Set up render pass
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputDrawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            frameBoundarySemaphore.signal()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(inputTexture, index: 0)
        encoder.setFragmentBuffer(currentBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(outputDrawable)

        // Signal semaphore when GPU finishes this frame
        let semaphore = frameBoundarySemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        commandBuffer.commit()
    }
}
```

### Frame Timeline Visualization

```
Frame 0: CPU writes Buffer[0] -> GPU reads Buffer[0]
Frame 1: CPU writes Buffer[1] -> GPU reads Buffer[0] | GPU reads Buffer[1]
Frame 2: CPU writes Buffer[2] -> GPU reads Buffer[1] | GPU reads Buffer[2]
Frame 3: CPU writes Buffer[0] (recycled) -> GPU reads Buffer[2] | GPU reads Buffer[0]
...
```

---

## 8. Video Compositing & Layer Blending

### Alpha Blend Shader (Two Layers)

```metal
typedef struct {
    float mixturePercent;
} AlphaBlendUniform;

fragment half4 alphaBlendFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    texture2d<half> inputTexture2 [[texture(1)]],
    constant AlphaBlendUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 base = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    half4 overlay = inputTexture2.sample(quadSampler, fragmentInput.textureCoordinate2);

    // Mix based on overlay alpha and mixture percentage
    return half4(
        mix(base.rgb, overlay.rgb, overlay.a * half(uniform.mixturePercent)),
        base.a
    );
}
```

### Source-Over Blend (Standard Alpha Compositing)

```metal
// Porter-Duff Source Over: result = src + dst * (1 - src.a)
fragment half4 sourceOverBlendFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> dstTexture [[texture(0)]],
    texture2d<half> srcTexture [[texture(1)]]
) {
    constexpr sampler quadSampler;
    half4 dst = dstTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    half4 src = srcTexture.sample(quadSampler, fragmentInput.textureCoordinate2);

    return mix(dst, src, src.a);
}
```

### Hardware Blending Configuration (Pipeline State)

For performance-critical multi-layer compositing, use Metal's hardware blending:

```swift
func makeBlendingPipelineState(
    blendMode: BlendMode,
    vertexFunction: String = "oneInputVertex",
    fragmentFunction: String = "passthroughFragment"
) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = sharedMetalRenderingDevice.shaderLibrary.makeFunction(name: vertexFunction)
    descriptor.fragmentFunction = sharedMetalRenderingDevice.shaderLibrary.makeFunction(name: fragmentFunction)
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    // Enable blending
    let colorAttachment = descriptor.colorAttachments[0]!
    colorAttachment.isBlendingEnabled = true

    switch blendMode {
    case .normal:
        // Source Over: result = src * src.a + dst * (1 - src.a)
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

    case .additive:
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .one
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .one

    case .multiply:
        colorAttachment.sourceRGBBlendFactor = .destinationColor
        colorAttachment.destinationRGBBlendFactor = .zero
        colorAttachment.sourceAlphaBlendFactor = .destinationAlpha
        colorAttachment.destinationAlphaBlendFactor = .zero

    case .screen:
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceColor
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    return try! sharedMetalRenderingDevice.device.makeRenderPipelineState(descriptor: descriptor)
}

enum BlendMode {
    case normal
    case additive
    case multiply
    case screen
}
```

### Multi-Layer Compositing Engine

```swift
class CompositingEngine {
    struct CompositeLayer {
        let texture: MTLTexture
        let opacity: Float
        let transform: simd_float4x4     // Position/scale/rotation
        let blendMode: BlendMode
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineStates: [BlendMode: MTLRenderPipelineState] = [:]

    func composite(
        layers: [CompositeLayer],
        canvasSize: MTLSize,
        outputTexture: MTLTexture
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        // Render layers back-to-front
        for layer in layers {
            guard let pipeline = pipelineStates[layer.blendMode] else { continue }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(layer.texture, index: 0)

            // Set transform and opacity uniforms
            var uniforms = LayerUniforms(
                transform: layer.transform,
                opacity: layer.opacity
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.commit()
    }

    struct LayerUniforms {
        var transform: simd_float4x4
        var opacity: Float
    }
}
```

---

## 9. Video Effects & Color Correction Shaders

### Brightness Adjustment

```metal
typedef struct {
    float brightness;  // Range: -1.0 to 1.0
} BrightnessUniform;

fragment half4 brightnessFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant BrightnessUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    return half4(color.rgb + half(uniform.brightness), color.a);
}
```

### Contrast Adjustment

```metal
typedef struct {
    float contrast;  // Range: 0.0 to 4.0, default 1.0
} ContrastUniform;

fragment half4 contrastFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant ContrastUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    return half4(((color.rgb - half3(0.5)) * half(uniform.contrast) + half3(0.5)), color.a);
}
```

### Saturation Adjustment

```metal
typedef struct {
    float saturation;  // Range: 0.0 (grayscale) to 2.0 (oversaturated)
} SaturationUniform;

fragment half4 saturationFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant SaturationUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    // Luminance using ITU-R BT.709 weights
    half luminance = dot(color.rgb, luminanceWeighting);
    return half4(mix(half3(luminance), color.rgb, half(uniform.saturation)), color.a);
}
```

### Exposure Adjustment

```metal
typedef struct {
    float exposure;  // Range: -10.0 to 10.0, default 0.0
} ExposureUniform;

fragment half4 exposureFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant ExposureUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    return half4(color.rgb * pow(2.0h, half(uniform.exposure)), color.a);
}
```

### White Balance

```metal
typedef struct {
    float temperature;  // In Kelvin-like units
    float tint;
} WhiteBalanceUniform;

fragment half4 whiteBalanceFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant WhiteBalanceUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    // Temperature shift (warm/cool)
    half temp = half(uniform.temperature);
    half tint = half(uniform.tint);

    color.r += temp;
    color.b -= temp;
    color.g += tint;

    return half4(clamp(color.rgb, half3(0.0), half3(1.0)), color.a);
}
```

### Chroma Key (Green/Blue Screen)

```metal
typedef struct {
    float thresholdSensitivity;
    float smoothing;
    float4 colorToReplace;
} ChromaKeyUniform;

fragment half4 chromaKeyFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant ChromaKeyUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    // Convert key color and sample to YCbCr for better keying
    half maskY = 0.2989h * uniform.colorToReplace.r + 0.5866h * uniform.colorToReplace.g + 0.1145h * uniform.colorToReplace.b;
    half maskCr = 0.7132h * (uniform.colorToReplace.r - maskY);
    half maskCb = 0.5647h * (uniform.colorToReplace.b - maskY);

    half Y = 0.2989h * color.r + 0.5866h * color.g + 0.1145h * color.b;
    half Cr = 0.7132h * (color.r - Y);
    half Cb = 0.5647h * (color.b - Y);

    half blendValue = smoothstep(
        half(uniform.thresholdSensitivity),
        half(uniform.thresholdSensitivity + uniform.smoothing),
        distance(half2(Cr, Cb), half2(maskCr, maskCb))
    );

    return half4(color.rgb, color.a * blendValue);
}
```

### Sharpen

```metal
typedef struct {
    float sharpness;    // Range: -4.0 to 4.0
    float imageWidth;
    float imageHeight;
} SharpenUniform;

fragment half4 sharpenFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    constant SharpenUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    float2 texCoord = fragmentInput.textureCoordinate;
    float2 texelSize = float2(1.0 / uniform.imageWidth, 1.0 / uniform.imageHeight);

    half4 center = inputTexture.sample(quadSampler, texCoord);
    half4 left   = inputTexture.sample(quadSampler, texCoord - float2(texelSize.x, 0.0));
    half4 right  = inputTexture.sample(quadSampler, texCoord + float2(texelSize.x, 0.0));
    half4 top    = inputTexture.sample(quadSampler, texCoord - float2(0.0, texelSize.y));
    half4 bottom = inputTexture.sample(quadSampler, texCoord + float2(0.0, texelSize.y));

    // Unsharp mask: center + sharpness * (center - average_of_neighbors)
    half4 average = (left + right + top + bottom) * 0.25h;
    half4 sharpened = center + half(uniform.sharpness) * (center - average);

    return half4(clamp(sharpened.rgb, half3(0.0), half3(1.0)), center.a);
}
```

---

## 10. LUT-Based Color Grading

LUT (Look-Up Table) color grading uses a 3D color cube encoded as a 2D texture (typically 512x512 for a 64x64x64 LUT).

### LUT Lookup Fragment Shader

```metal
typedef struct {
    float intensity;  // 0.0 = original, 1.0 = fully graded
} LUTIntensityUniform;

fragment half4 lookupFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    texture2d<half> lutTexture [[texture(1)]],
    constant LUTIntensityUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 base = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    // LUT is 8x8 grid of 64x64 cells = 512x512 texture for 64-level LUT
    half blueColor = base.b * 63.0h;

    // Calculate which two blue "slices" to interpolate between
    half2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0h);
    quad1.x = floor(blueColor) - (quad1.y * 8.0h);

    half2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0h);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0h);

    // Map red and green to position within cell
    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
    texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

    float2 texPos2;
    texPos2.x = (quad2.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
    texPos2.y = (quad2.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

    // Sample both slices and interpolate
    half4 newColor1 = lutTexture.sample(quadSampler, texPos1);
    half4 newColor2 = lutTexture.sample(quadSampler, texPos2);
    half4 newColor = mix(newColor1, newColor2, fract(blueColor));

    // Mix original with graded based on intensity
    return half4(mix(base, half4(newColor.rgb, base.w), half(uniform.intensity)));
}
```

### Loading a LUT Texture in Swift

```swift
func loadLUTTexture(named name: String) -> MTLTexture? {
    let textureLoader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
    let options: [MTKTextureLoader.Option: Any] = [
        .SRGB: false,      // LUTs should be loaded in linear space
        .origin: MTKTextureLoader.Origin.topLeft
    ]

    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let texture = try? textureLoader.newTexture(URL: url, options: options) else {
        return nil
    }
    return texture
}
```

---

## 11. Video Transitions

### Cross Dissolve (from Apple AVCustomEdit sample)

```metal
typedef struct {
    float progress;  // 0.0 = fully clip A, 1.0 = fully clip B
} TransitionUniform;

fragment half4 crossDissolveFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> textureA [[texture(0)]],
    texture2d<half> textureB [[texture(1)]],
    constant TransitionUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 colorA = textureA.sample(quadSampler, fragmentInput.textureCoordinate);
    half4 colorB = textureB.sample(quadSampler, fragmentInput.textureCoordinate2);

    return mix(colorA, colorB, half(uniform.progress));
}
```

### Diagonal Wipe Transition

```metal
fragment half4 diagonalWipeFragment(
    TwoInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> textureA [[texture(0)]],
    texture2d<half> textureB [[texture(1)]],
    constant TransitionUniform& uniform [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    half4 colorA = textureA.sample(quadSampler, fragmentInput.textureCoordinate);
    half4 colorB = textureB.sample(quadSampler, fragmentInput.textureCoordinate2);

    float2 uv = fragmentInput.textureCoordinate;
    float diagonal = (uv.x + uv.y) / 2.0;  // 0..1 along diagonal
    float edge = uniform.progress;
    float smoothEdge = 0.02;  // feather width

    float mask = smoothstep(edge - smoothEdge, edge + smoothEdge, diagonal);
    return mix(colorB, colorA, half(mask));
}
```

### Push Transition (Slide)

```metal
fragment half4 pushTransitionFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> textureA [[texture(0)]],
    texture2d<half> textureB [[texture(1)]],
    constant TransitionUniform& uniform [[buffer(1)]]
) {
    constexpr sampler clampSampler(address::clamp_to_edge);
    float2 uv = fragmentInput.textureCoordinate;
    float progress = uniform.progress;

    // Slide A to the left, B comes from the right
    float2 uvA = float2(uv.x + progress, uv.y);
    float2 uvB = float2(uv.x + progress - 1.0, uv.y);

    half4 colorA = textureA.sample(clampSampler, uvA);
    half4 colorB = textureB.sample(clampSampler, uvB);

    // Show A when UV is still valid, B when it has scrolled in
    if (uv.x + progress < 1.0) {
        return colorA;
    }
    return colorB;
}
```

### Swift Transition Controller

```swift
class TransitionRenderer {
    enum TransitionType {
        case crossDissolve
        case diagonalWipe
        case push
    }

    private var pipelineStates: [TransitionType: MTLRenderPipelineState] = [:]

    init() {
        pipelineStates[.crossDissolve] = makeTransitionPipeline(fragment: "crossDissolveFragment")
        pipelineStates[.diagonalWipe] = makeTransitionPipeline(fragment: "diagonalWipeFragment")
        pipelineStates[.push] = makeTransitionPipeline(fragment: "pushTransitionFragment")
    }

    func render(
        from textureA: MTLTexture,
        to textureB: MTLTexture,
        progress: Float,
        type: TransitionType,
        output: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let pipeline = pipelineStates[type] else { return }

        var uniforms = TransitionUniforms(progress: progress)
        // Encode render pass with both textures and the transition shader
        // ... (similar to renderQuad pattern shown in Section 5)
    }

    struct TransitionUniforms {
        var progress: Float
    }

    private func makeTransitionPipeline(fragment: String) -> MTLRenderPipelineState {
        let (state, _, _) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice,
            vertexFunctionName: "twoInputVertex",
            fragmentFunctionName: fragment,
            operationName: "Transition"
        )
        return state
    }
}
```

---

## 12. Custom CIFilter with Metal Kernels

### Build Settings Required
- **Other Metal Compiler Flags**: `-fcikernel`
- **Other Metal Linker Flags**: `-cikernel`

### Metal Kernel File (MyFilter.ci.metal)

Note: CIKernel Metal files use the `.ci.metal` extension.

```metal
#include <CoreImage/CoreImage.h>  // Required for CIKernel

extern "C" {
    namespace coreimage {

        // Color kernel: operates on a single pixel
        float4 vignetteEffect(sample_t s, float2 coord, float2 center, float radius, float strength) {
            float dist = distance(coord, center);
            float vignette = smoothstep(radius, radius - 0.3, dist);
            return float4(s.rgb * mix(1.0 - strength, 1.0, vignette), s.a);
        }

        // Warp kernel: operates on coordinates
        float2 swirlWarp(float2 coord, float2 center, float radius, float angle) {
            float2 delta = coord - center;
            float dist = length(delta);

            if (dist < radius) {
                float percent = (radius - dist) / radius;
                float theta = percent * percent * angle;
                float sinTheta = sin(theta);
                float cosTheta = cos(theta);
                delta = float2(
                    delta.x * cosTheta - delta.y * sinTheta,
                    delta.x * sinTheta + delta.y * cosTheta
                );
            }
            return center + delta;
        }

        // General kernel with neighbor sampling
        float4 edgeDetect(sampler src) {
            float2 dc = src.coord();
            float2 d = 1.0 / src.size();

            float4 center = src.sample(dc);
            float4 left   = src.sample(dc + float2(-d.x, 0));
            float4 right  = src.sample(dc + float2(d.x, 0));
            float4 top    = src.sample(dc + float2(0, -d.y));
            float4 bottom = src.sample(dc + float2(0, d.y));

            float4 h = right - left;
            float4 v = bottom - top;
            float4 edge = sqrt(h * h + v * v);

            return float4(edge.rgb, center.a);
        }
    }
}
```

### Swift CIFilter Subclass

```swift
import CoreImage

class VignetteMetalFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var inputRadius: CGFloat = 0.8
    @objc dynamic var inputStrength: CGFloat = 0.5

    // Load kernel once (static)
    private static let kernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? CIColorKernel(functionName: "vignetteEffect", fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage? {
        guard let input = inputImage,
              let kernel = Self.kernel else { return nil }

        let extent = input.extent
        let center = CIVector(x: extent.midX, y: extent.midY)

        return kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [
                input,
                center,
                inputRadius,
                inputStrength
            ]
        )
    }
}

// Warp kernel example
class SwirlFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var inputCenter: CIVector = CIVector(x: 150, y: 150)
    @objc dynamic var inputRadius: CGFloat = 150.0
    @objc dynamic var inputAngle: CGFloat = 3.0

    private static let kernel: CIWarpKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? CIWarpKernel(functionName: "swirlWarp", fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage? {
        guard let input = inputImage,
              let kernel = Self.kernel else { return nil }

        return kernel.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            image: input,
            arguments: [inputCenter, inputRadius, inputAngle]
        )
    }
}
```

### Applying CIFilter Chain to Video in Real-Time

```swift
class CIFilterVideoProcessor {
    let ciContext: CIContext
    let metalCommandQueue: MTLCommandQueue
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        let device = sharedMetalRenderingDevice.device
        metalCommandQueue = device.makeCommandQueue()!
        // Create CIContext backed by Metal for optimal performance
        ciContext = CIContext(
            mtlCommandQueue: metalCommandQueue,
            options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .cacheIntermediates: false  // For real-time, avoid caching
            ]
        )
    }

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        filters: [CIFilter],
        outputDrawable: CAMetalDrawable
    ) {
        var image = CIImage(cvPixelBuffer: pixelBuffer)

        // Chain filters
        for filter in filters {
            filter.setValue(image, forKey: kCIInputImageKey)
            guard let output = filter.outputImage else { continue }
            image = output
        }

        // Render to Metal drawable
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

        let drawBounds = CGRect(
            x: 0, y: 0,
            width: outputDrawable.texture.width,
            height: outputDrawable.texture.height
        )

        ciContext.render(
            image,
            to: outputDrawable.texture,
            commandBuffer: commandBuffer,
            bounds: drawBounds,
            colorSpace: colorSpace
        )

        commandBuffer.present(outputDrawable)
        commandBuffer.commit()
    }
}
```

---

## 13. Metal Performance Shaders (MPS)

MPS provides optimized, Apple-tuned GPU shaders for common operations.

### Key MPS Classes for Video Processing

| Class | Purpose |
|-------|---------|
| `MPSImageGaussianBlur` | Fast Gaussian blur |
| `MPSImageBox` | Box blur |
| `MPSImageMedian` | Median filter (noise reduction) |
| `MPSImageSobel` | Edge detection |
| `MPSImageLaplacian` | Laplacian edge detection |
| `MPSImageThresholdBinary` | Binary threshold |
| `MPSImageConvolution` | General convolution |
| `MPSImageLanczosScale` | High-quality image scaling |
| `MPSImageBilinearScale` | Fast image scaling |
| `MPSImageHistogram` | Compute histogram |
| `MPSImageHistogramEqualization` | Auto levels |
| `MPSImageTranspose` | Fast image transpose |
| `MPSImageConversion` | Color space/format conversion |

### Using MPS for Gaussian Blur

```swift
import MetalPerformanceShaders

class MPSBlurProcessor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    func gaussianBlur(input: MTLTexture, output: MTLTexture, sigma: Float) {
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.edgeMode = .clamp

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        blur.encode(commandBuffer: commandBuffer, sourceTexture: input, destinationTexture: output)
        commandBuffer.commit()
    }

    func lanczosScale(input: MTLTexture, output: MTLTexture) {
        let scale = MPSImageLanczosScale(device: device)

        // Calculate scale transform
        var scaleTransform = MPSScaleTransform(
            scaleX: Double(output.width) / Double(input.width),
            scaleY: Double(output.height) / Double(input.height),
            translateX: 0,
            translateY: 0
        )

        withUnsafePointer(to: &scaleTransform) { ptr in
            scale.scaleTransform = ptr
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            scale.encode(commandBuffer: commandBuffer, sourceTexture: input, destinationTexture: output)
            commandBuffer.commit()
        }
    }

    func sobelEdgeDetect(input: MTLTexture, output: MTLTexture) {
        let sobel = MPSImageSobel(device: device)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        sobel.encode(commandBuffer: commandBuffer, sourceTexture: input, destinationTexture: output)
        commandBuffer.commit()
    }
}
```

### MPS Image Histogram for Color Analysis

```swift
func computeHistogram(texture: MTLTexture) -> MPSImageHistogramInfo {
    var histogramInfo = MPSImageHistogramInfo(
        numberOfHistogramEntries: 256,
        histogramForAlpha: false,
        minPixelValue: vector_float4(0, 0, 0, 0),
        maxPixelValue: vector_float4(1, 1, 1, 1)
    )

    let histogram = MPSImageHistogram(device: device, histogramInfo: &histogramInfo)

    let bufferLength = histogram.histogramSize(forSourceFormat: texture.pixelFormat)
    guard let histogramBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
          let commandBuffer = commandQueue.makeCommandBuffer() else {
        return histogramInfo
    }

    histogram.encode(
        to: commandBuffer,
        sourceTexture: texture,
        histogram: histogramBuffer,
        histogramOffset: 0
    )
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return histogramInfo
}
```

---

## 14. HDR & Extended Dynamic Range (EDR)

### Configuring CAMetalLayer for EDR

```swift
import QuartzCore
import Metal

class HDRMetalView: NSView {
    var metalLayer: CAMetalLayer!
    let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
        super.init(frame: .zero)
        setupMetalLayer()
    }

    func setupMetalLayer() {
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // EDR Configuration
        metalLayer.wantsExtendedDynamicRangeContent = true

        // Use float16 pixel format for EDR (values > 1.0 = HDR)
        metalLayer.pixelFormat = .rgba16Float

        // Set extended linear color space (rec2020 for wide gamut + HDR)
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        // Alternative: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)

        self.layer = metalLayer
        self.wantsLayer = true
    }

    /// Query maximum EDR headroom available on current display
    var maxEDRHeadroom: CGFloat {
        if #available(macOS 13.0, *) {
            // Dynamic headroom based on current display brightness
            return NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
        }
        return NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
    }
}
```

### HDR Tone Mapping Shader

```metal
typedef struct {
    float maxEDR;          // Maximum EDR headroom from display
    float exposure;        // Exposure adjustment
    float hdrIntensity;    // HDR effect intensity
} HDRUniforms;

// PQ (Perceptual Quantizer) EOTF - converts PQ encoded values to linear light
float3 PQ_EOTF(float3 pq) {
    float m1 = 0.1593017578125;
    float m2 = 78.84375;
    float c1 = 0.8359375;
    float c2 = 18.8515625;
    float c3 = 18.6875;

    float3 Np = pow(pq, 1.0 / m2);
    float3 num = max(Np - c1, 0.0);
    float3 den = c2 - c3 * Np;
    return pow(num / den, 1.0 / m1) * 10000.0;  // Returns nits
}

// Simple Reinhard tone mapping for HDR to EDR
float3 reinhardToneMap(float3 hdr, float maxLuminance) {
    float3 mapped = hdr / (hdr + float3(1.0));
    return mapped * maxLuminance;
}

// Convert BT.2020 to Display P3
float3 bt2020ToDisplayP3(float3 color) {
    // BT.2020 to XYZ to Display P3 matrix
    float3x3 matrix = float3x3(
        float3(1.3435, -0.2822, -0.0476),
        float3(-0.0654,  1.0761, -0.0087),
        float3(0.0028, -0.0196,  1.0211)
    );
    return matrix * color;
}

fragment float4 hdrRenderFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant HDRUniforms& uniforms [[buffer(1)]]
) {
    constexpr sampler quadSampler;
    float4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    // Apply exposure
    color.rgb *= pow(2.0, uniforms.exposure);

    // Tone map to EDR range
    float3 mapped = reinhardToneMap(color.rgb, uniforms.maxEDR);

    return float4(mapped, color.a);
}
```

### Reading HDR Video with AVFoundation

```swift
import AVFoundation

class HDRVideoReader {
    func configureHDROutput() -> [String: Any] {
        return [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            // Or for HDR10:
            // kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        ]
    }

    /// Check if video track has HDR content
    func isHDR(track: AVAssetTrack) -> Bool {
        let formatDescriptions = track.formatDescriptions as! [CMFormatDescription]
        for desc in formatDescriptions {
            let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]
            if let colorPrimaries = extensions?[kCVImageBufferColorPrimariesKey as String] as? String {
                if colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                    return true
                }
            }
        }
        return false
    }
}
```

---

## 15. Display Synchronization

### Using CAMetalDisplayLink (macOS 14+ / iOS 17+)

```swift
import QuartzCore

@available(macOS 14.0, *)
class MetalDisplayLinkRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var displayLink: CAMetalDisplayLink?
    var metalLayer: CAMetalLayer

    func setupDisplayLink() {
        displayLink = CAMetalDisplayLink(metalLayer: metalLayer)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 24,
            maximum: 120,
            preferred: 60  // Target frame rate
        )
        displayLink?.delegate = self
        displayLink?.isPaused = false
        displayLink?.add(to: .main, forMode: .common)
    }
}

@available(macOS 14.0, *)
extension MetalDisplayLinkRenderer: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(
        _ link: CAMetalDisplayLink,
        needsUpdate update: CAMetalDisplayLink.Update
    ) {
        let drawable = update.drawable

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Render your frame to drawable.texture
        renderFrame(to: drawable.texture, commandBuffer: commandBuffer)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

### Using MTKView for Video Playback

```swift
import MetalKit

class VideoPlaybackView: MTKView, MTKViewDelegate {
    let commandQueue: MTLCommandQueue
    var currentVideoTexture: MTLTexture?
    var renderPipelineState: MTLRenderPipelineState!

    override init(frame: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = metalDevice.makeCommandQueue()!
        super.init(frame: frame, device: metalDevice)

        // Configure for video playback
        self.delegate = self
        self.isPaused = true           // We drive updates manually
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false   // Allow reading back
        self.preferredFramesPerSecond = 60
        self.colorPixelFormat = .bgra8Unorm  // Or .rgba16Float for HDR

        // Build passthrough pipeline
        let (state, _, _) = generateRenderPipelineState(
            device: sharedMetalRenderingDevice,
            vertexFunctionName: "oneInputVertex",
            fragmentFunctionName: "passthroughFragment",
            operationName: "VideoPlayback"
        )
        self.renderPipelineState = state
    }

    /// Called by the video decode thread when a new frame is ready
    func displayFrame(_ texture: MTLTexture) {
        currentVideoTexture = texture
        self.draw()  // Trigger immediate redraw
    }

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let videoTexture = currentVideoTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .dontCare
        renderPass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setFragmentTexture(videoTexture, index: 0)

        // Set vertex/texture coordinate buffers...
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    required init(coder: NSCoder) { fatalError() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
```

---

## 16. Memory Management & Texture Pools

### Texture Pool for Intermediate Rendering

```swift
class TexturePool {
    private let device: MTLDevice
    private var pool: [TextureDescriptorKey: [MTLTexture]] = [:]
    private let lock = NSLock()

    struct TextureDescriptorKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
        let usage: MTLTextureUsage
    }

    init(device: MTLDevice) {
        self.device = device
    }

    /// Acquire a texture from the pool (or create one if empty)
    func acquire(width: Int, height: Int,
                 pixelFormat: MTLPixelFormat = .bgra8Unorm,
                 usage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite]) -> MTLTexture {
        let key = TextureDescriptorKey(width: width, height: height,
                                        pixelFormat: pixelFormat, usage: usage)
        lock.lock()
        defer { lock.unlock() }

        if var textures = pool[key], !textures.isEmpty {
            let texture = textures.removeLast()
            pool[key] = textures
            return texture
        }

        // Create new texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private  // GPU-only for intermediates

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create texture \(width)x\(height)")
        }
        return texture
    }

    /// Return a texture to the pool for reuse
    func release(_ texture: MTLTexture) {
        let key = TextureDescriptorKey(
            width: texture.width,
            height: texture.height,
            pixelFormat: texture.pixelFormat,
            usage: texture.usage
        )
        lock.lock()
        defer { lock.unlock() }

        if pool[key] == nil {
            pool[key] = []
        }
        pool[key]!.append(texture)
    }

    /// Clear all pooled textures (call on memory warning)
    func drain() {
        lock.lock()
        pool.removeAll()
        lock.unlock()
    }
}
```

### Using MTLHeap for Efficient Memory Management

```swift
class HeapAllocator {
    let device: MTLDevice
    var heap: MTLHeap?

    init(device: MTLDevice) {
        self.device = device
    }

    func createHeap(forTextureCount count: Int, width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        // Query size needed for one texture
        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
        let totalSize = sizeAndAlign.size * count

        // Create heap
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = totalSize
        heapDescriptor.storageMode = .private
        heapDescriptor.hazardTrackingMode = .tracked

        self.heap = device.makeHeap(descriptor: heapDescriptor)
    }

    func allocateTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        return heap?.makeTexture(descriptor: descriptor)
    }
}
```

---

## 17. IOSurface & Zero-Copy Rendering

### CVPixelBufferPool with IOSurface Backing

```swift
import CoreVideo

class VideoBufferPool {
    var pixelBufferPool: CVPixelBufferPool?

    func createPool(width: Int, height: Int) {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            // ^ IOSurface properties enable zero-copy Metal texture mapping
        ]

        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )
    }

    func acquireBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool!,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }
}
```

### IOSurface Use Count Management

When using IOSurface-backed buffers with Metal, you must prevent the pool from recycling them while the GPU is still reading:

```swift
import IOSurface

func renderWithIOSurfaceProtection(
    pixelBuffer: CVPixelBuffer,
    commandBuffer: MTLCommandBuffer
) {
    // Get the underlying IOSurface
    guard let surface = CVPixelBufferGetIOSurface(pixelBuffer) else { return }
    let ioSurface = surface.takeUnretainedValue()

    // Increment use count to prevent pool recycling
    IOSurfaceIncrementUseCount(ioSurface)

    // Set up Metal rendering...
    // ... encode render commands ...

    // Decrement use count when GPU is done
    commandBuffer.addCompletedHandler { _ in
        IOSurfaceDecrementUseCount(ioSurface)
    }

    commandBuffer.commit()
}
```

---

## 18. Metal 4 (WWDC 2025)

Metal 4 introduces significant improvements relevant to NLE apps:

### Unified Command Encoder

Metal 4 consolidates compute, blit, and acceleration structure encoding into a single encoder:

```swift
// Metal 3 approach (multiple encoders):
let computeEncoder = commandBuffer.makeComputeCommandEncoder()
// ... dispatch compute work ...
computeEncoder.endEncoding()

let blitEncoder = commandBuffer.makeBlitCommandEncoder()
// ... blit operations ...
blitEncoder.endEncoding()

// Metal 4 approach (single unified encoder):
// All compute, blit, and acceleration structure work in one encoder
// Commands without dependencies run concurrently automatically
```

### Color Attachment Mapping

Instead of switching render encoders when output attachments change, Metal 4 lets you remap color outputs:

```swift
// Metal 4: Change render target mapping without creating new encoder
// Useful for multi-pass effects where you ping-pong between textures
```

### MTL4ArgumentTable

New type for efficient bind point management:

```swift
// Metal 4: Shared argument tables across stages
// Reduces binding overhead for complex pipelines
```

### Key Features for NLE Apps
- **Unified compute encoder**: Simplifies effect chains (blur, color correction, compositing) into one encoder
- **Color attachment mapping**: Efficient multi-pass rendering for complex effects
- **MetalFX Frame Interpolation**: Could enable higher perceived frame rates during playback
- **Neural rendering support**: ML-based effects (super resolution, denoising) integrated into render pipeline

---

## 19. Complete NLE Rendering Architecture

### High-Level Architecture

```
                     +-------------------+
                     | Timeline Engine   |
                     | (what to render)  |
                     +--------+----------+
                              |
                              v
                     +-------------------+
                     | Frame Compositor  |
                     | (orchestrator)    |
                     +--------+----------+
                              |
              +---------------+---------------+
              |               |               |
              v               v               v
        +-----------+  +-----------+  +-----------+
        | Track 1   |  | Track 2   |  | Track 3   |
        | Renderer  |  | Renderer  |  | Renderer  |
        +-----------+  +-----------+  +-----------+
              |               |               |
              v               v               v
     +--------+--------+     |       +--------+--------+
     | Decode  | Effects|    ...     | Decode  | Effects|
     | (AVF/VT)| Chain  |           | (AVF/VT)| Chain  |
     +--------+--------+           +--------+--------+
              |               |               |
              +-------+-------+-------+-------+
                      |
                      v
              +-------+-------+
              |  Compositing  |
              |  (back-to-    |
              |   front blend)|
              +-------+-------+
                      |
                      v
              +-------+-------+
              |  Transitions  |
              +-------+-------+
                      |
                      v
              +-------+-------+
              |   Final       |
              |   Output      |
              +-------+-------+
                    /       \
                   /         \
                  v           v
           +----------+  +----------+
           | Display  |  | Export   |
           | (MTKView)|  | (writer) |
           +----------+  +----------+
```

### Frame Compositor Implementation

```swift
import Metal
import AVFoundation

class FrameCompositor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let texturePool: TexturePool
    let effectsProcessor: EffectsProcessor
    let compositingEngine: CompositingEngine
    let transitionRenderer: TransitionRenderer

    struct RenderRequest {
        let time: CMTime
        let tracks: [TrackRenderInfo]
        let canvasSize: MTLSize
        let transitions: [TransitionInfo]
    }

    struct TrackRenderInfo {
        let videoClip: AVAsset
        let clipTime: CMTime          // Time within the clip
        let effects: [VideoEffect]     // Chain of effects to apply
        let opacity: Float
        let transform: simd_float4x4
        let blendMode: BlendMode
    }

    struct TransitionInfo {
        let type: TransitionRenderer.TransitionType
        let progress: Float
        let trackA: Int
        let trackB: Int
    }

    func renderFrame(_ request: RenderRequest) -> MTLTexture {
        // 1. Decode each track's frame at the given time
        var trackTextures: [MTLTexture] = []

        for track in request.tracks {
            // Decode video frame -> CVPixelBuffer -> MTLTexture
            let decodedTexture = decodeFrame(track: track)

            // Apply effects chain (color correction, blur, etc.)
            let processedTexture = effectsProcessor.applyChain(
                effects: track.effects,
                input: decodedTexture,
                pool: texturePool
            )

            trackTextures.append(processedTexture)
        }

        // 2. Apply transitions between tracks
        for transition in request.transitions {
            let transitionOutput = texturePool.acquire(
                width: request.canvasSize.width,
                height: request.canvasSize.height
            )
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }

            transitionRenderer.render(
                from: trackTextures[transition.trackA],
                to: trackTextures[transition.trackB],
                progress: transition.progress,
                type: transition.type,
                output: transitionOutput,
                commandBuffer: commandBuffer
            )
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            trackTextures[transition.trackA] = transitionOutput
        }

        // 3. Composite all visible layers (back to front)
        let compositeOutput = texturePool.acquire(
            width: request.canvasSize.width,
            height: request.canvasSize.height
        )

        let layers = zip(request.tracks, trackTextures).map { track, texture in
            CompositingEngine.CompositeLayer(
                texture: texture,
                opacity: track.opacity,
                transform: track.transform,
                blendMode: track.blendMode
            )
        }

        compositingEngine.composite(
            layers: layers,
            canvasSize: request.canvasSize,
            outputTexture: compositeOutput
        )

        return compositeOutput
    }

    private func decodeFrame(track: TrackRenderInfo) -> MTLTexture {
        // Implementation uses AVAssetReader or VideoToolbox
        // to decode a single frame and convert via CVMetalTextureCache
        fatalError("Implementation specific to decode strategy")
    }
}
```

### Effects Processor Chain

```swift
class EffectsProcessor {
    var effectPipelines: [String: MTLRenderPipelineState] = [:]
    var computePipelines: [String: MTLComputePipelineState] = [:]

    struct VideoEffect {
        let name: String
        let parameters: [String: Float]
        let usesCompute: Bool
    }

    func applyChain(
        effects: [VideoEffect],
        input: MTLTexture,
        pool: TexturePool
    ) -> MTLTexture {
        var currentTexture = input

        for effect in effects {
            let output = pool.acquire(
                width: currentTexture.width,
                height: currentTexture.height
            )

            if effect.usesCompute {
                applyComputeEffect(effect, input: currentTexture, output: output)
            } else {
                applyRenderEffect(effect, input: currentTexture, output: output)
            }

            // Return previous intermediate texture to pool
            if currentTexture !== input {
                pool.release(currentTexture)
            }

            currentTexture = output
        }

        return currentTexture
    }

    private func applyComputeEffect(_ effect: VideoEffect, input: MTLTexture, output: MTLTexture) {
        guard let pipeline = computePipelines[effect.name],
              let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)

        // Set uniform parameters
        var params = effect.parameters.values.map { Float($0) }
        encoder.setBytes(&params, length: params.count * MemoryLayout<Float>.size, index: 0)

        let threadgroupSize = MTLSize(
            width: min(pipeline.threadExecutionWidth, output.width),
            height: min(pipeline.maxTotalThreadsPerThreadgroup / pipeline.threadExecutionWidth, output.height),
            depth: 1
        )
        let threadgroups = MTLSize(
            width: (output.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (output.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func applyRenderEffect(_ effect: VideoEffect, input: MTLTexture, output: MTLTexture) {
        // Uses renderQuad pattern from Section 5
    }
}
```

---

## 20. Performance Optimization Techniques

### 1. Minimize State Changes

```swift
// BAD: Changing pipeline state for every draw call
for layer in layers {
    encoder.setRenderPipelineState(pipelineForBlendMode(layer.blendMode))
    encoder.drawPrimitives(...)
}

// GOOD: Sort layers by blend mode, batch draw calls
let sortedLayers = layers.sorted { $0.blendMode.rawValue < $1.blendMode.rawValue }
var currentBlendMode: BlendMode?
for layer in sortedLayers {
    if layer.blendMode != currentBlendMode {
        encoder.setRenderPipelineState(pipelineForBlendMode(layer.blendMode))
        currentBlendMode = layer.blendMode
    }
    encoder.drawPrimitives(...)
}
```

### 2. Use Private Storage for GPU-Only Textures

```swift
let descriptor = MTLTextureDescriptor()
descriptor.storageMode = .private  // GPU-only, fastest
// Use .shared only when CPU needs to read back
```

### 3. Prefer `dispatchThreads` over `dispatchThreadgroups`

```swift
// Metal 2+: Let the system handle partial threadgroups
if device.supportsFamily(.apple4) {
    encoder.dispatchThreads(
        MTLSize(width: texture.width, height: texture.height, depth: 1),
        threadsPerThreadgroup: threadgroupSize
    )
} else {
    // Fallback: manual threadgroup calculation
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
}
```

### 4. Use `half` Precision in Shaders

```metal
// GOOD: half precision is 2x faster on Apple GPUs for many operations
fragment half4 myFragment(/* ... */) {
    half4 color = inputTexture.sample(sampler, coord);
    return color;
}

// AVOID: float when half suffices for color operations
fragment float4 myFragment(/* ... */) {
    float4 color = inputTexture.sample(sampler, coord);
    return color;
}
```

### 5. Minimize Command Buffer Creation

```swift
// BAD: One command buffer per effect
for effect in effectChain {
    let cb = commandQueue.makeCommandBuffer()!
    // encode effect...
    cb.commit()
    cb.waitUntilCompleted()  // Sync stall!
}

// GOOD: One command buffer for entire frame
let commandBuffer = commandQueue.makeCommandBuffer()!
for effect in effectChain {
    // encode all effects into same command buffer
}
commandBuffer.commit()
// Only wait when absolutely needed, or use completion handler
```

### 6. Render Pass Load/Store Actions

```swift
// Specify load/store actions to minimize memory bandwidth
renderPass.colorAttachments[0].loadAction = .dontCare  // When you'll overwrite everything
renderPass.colorAttachments[0].storeAction = .store     // When you need the result
// Use .dontCare for store when the attachment is only used within this pass
```

### 7. Profile with Metal GPU Capture

```swift
// Trigger a GPU capture programmatically
let captureManager = MTLCaptureManager.shared()
let captureDescriptor = MTLCaptureDescriptor()
captureDescriptor.captureObject = device
captureDescriptor.destination = .gpuTraceDocument
captureDescriptor.outputURL = URL(fileURLWithPath: "/tmp/capture.gputrace")

try? captureManager.startCapture(with: captureDescriptor)
// ... render frames ...
captureManager.stopCapture()
```

### 8. Avoid Unnecessary Texture Copies

```swift
// BAD: Copy pixel buffer data to a new texture
let region = MTLRegionMake2D(0, 0, width, height)
texture.replace(region: region, mipmapLevel: 0, withBytes: ptr, bytesPerRow: stride)

// GOOD: Use CVMetalTextureCache for zero-copy mapping
let mtlTexture = CVMetalTextureGetTexture(cvMetalTexture)
```

---

## 21. Open Source Reference Frameworks

### GPUImage3 (Brad Larson)
- **URL**: https://github.com/BradLarson/GPUImage3
- **License**: BSD
- **Architecture**: Pipeline pattern (ImageSource -> ImageProcessingOperation -> ImageConsumer)
- **Key patterns**: Render quad abstraction, shader uniform reflection, texture coordinate management
- **100+ shader effects**: Brightness, contrast, saturation, blur, blend modes, distortion, etc.
- **Best for**: Understanding Metal render pipeline patterns and shader design

### MetalPetal
- **URL**: https://github.com/MetalPetal/MetalPetal
- **License**: MIT
- **Features**: CVMetalTextureCache integration, programmable blending, resource heaps
- **Key patterns**: Lazy evaluation, automatic kernel state caching, transient texture policy
- **Best for**: Production-quality Metal image/video processing

### MetalVideoProcess
- **URL**: https://github.com/wangrenzhu/MetalVideoProcess
- **Built on**: GPUImage3 + Cabbage + AVFoundation
- **Features**: Multiple video clip rendering, async processing
- **Best for**: Understanding NLE-specific Metal pipelines

### BBMetalImage
- **URL**: https://github.com/Silence-GitHub/BBMetalImage
- **License**: MIT
- **Features**: High-performance Metal image/video processing
- **Best for**: Clean, modern Swift Metal video processing examples

---

## 22. Key WWDC Sessions

| Session | Year | Topic |
|---------|------|-------|
| Metal for Pro Apps | WWDC 2019 | IOSurface zero-copy, multi-GPU, pro app patterns |
| Harness Apple GPUs with Metal | WWDC 2020 | Apple Silicon GPU architecture, tile memory |
| Build Metal-based Core Image kernels with Xcode | WWDC 2020 | Custom CIKernel with Metal |
| Explore Core Image kernel improvements | WWDC 2021 | CIKernel enhancements |
| Create image processing apps powered by Apple silicon | WWDC 2021 | Unified memory, GPU processing |
| Explore HDR rendering with EDR | WWDC 2021 | EDR, HDR on macOS |
| Optimize for variable refresh rate displays | WWDC 2021 | ProMotion, frame pacing |
| Display HDR video in EDR with AVFoundation and Metal | WWDC 2022 | HDR video decode + render |
| Display EDR content with Core Image, Metal, and SwiftUI | WWDC 2022 | EDR with CI/Metal/SwiftUI |
| Explore EDR on iOS | WWDC 2022 | iOS EDR support |
| Discover Metal 3 | WWDC 2022 | Mesh shaders, MetalFX |
| Discover Metal 4 | WWDC 2025 | Unified encoder, neural rendering, argument tables |

---

## Summary: Critical Path for NLE Implementation

1. **Set up shared Metal device** with command queue and shader library
2. **Create CVMetalTextureCache** for zero-copy video frame conversion
3. **Implement YUV-to-RGB conversion** shader for decoded video frames
4. **Build render quad abstraction** for drawing textured quads (the workhorse of 2D video)
5. **Create effects pipeline** with fragment shaders for color correction and compute shaders for convolution effects
6. **Implement compositing engine** with hardware blending for multi-layer composition
7. **Add transition shaders** (dissolve, wipe, push) between clips
8. **Use triple buffering** with dispatch semaphore for smooth playback
9. **Configure EDR/HDR** with rgba16Float pixel format and extended color spaces
10. **Synchronize with display** using CAMetalDisplayLink (macOS 14+) or MTKView
11. **Pool and reuse textures** to minimize allocations during playback
12. **Profile with Metal GPU Capture** in Xcode to identify bottlenecks
