# Metal 4, Advanced GPU Compute & Debugging for NLE

## Table of Contents
1. [Metal 4 (WWDC 2025)](#1-metal-4-wwdc-2025)
2. [GPU Timeline & Async Compute](#2-gpu-timeline--async-compute)
3. [Indirect Command Buffers](#3-indirect-command-buffers)
4. [MPS Graph & ML Inference on GPU](#4-mps-graph--ml-inference-on-gpu)
5. [Tile-Based Rendering](#5-tile-based-rendering)
6. [Metal Debugging & Profiling](#6-metal-debugging--profiling)
7. [Multi-GPU Support](#7-multi-gpu-support)
8. [Metal-CoreVideo-IOSurface Integration](#8-metal-corevideo-iosurface-integration)
9. [Mesh / Object Shaders](#9-mesh--object-shaders)
10. [Resource Heaps & Residency Management](#10-resource-heaps--residency-management)

---

## 1. Metal 4 (WWDC 2025)

Metal 4 is a major API overhaul announced at WWDC 2025. It modernizes the command model, resource binding, memory management, and ML integration. Supported on Apple M1+ (macOS) and A14+ (iOS/iPadOS).

### 1.1 Unified Command Encoder

Metal 4 consolidates the encoder model. Instead of separate render, compute, and blit encoders:

- **MTL4ComputeCommandEncoder** handles compute dispatches, blit operations, and acceleration structure builds in a single encoder, all running concurrently without additional synchronization.
- **MTL4RenderCommandEncoder** adds color attachment mapping for remapping shader outputs to physical render targets mid-pass.

**Command hierarchy changes:**
```
Metal 3:   MTLDevice -> MTLCommandQueue   -> MTLCommandBuffer   -> {Render,Compute,Blit}CommandEncoder
Metal 4:   MTLDevice -> MTL4CommandQueue  -> MTL4CommandBuffer  -> {MTL4Render,MTL4Compute}CommandEncoder
```

**Unified Compute Encoder Example (Swift):**
```swift
// Metal 4: single compute encoder handles dispatches AND blits
guard let commandBuffer = mtl4Queue.makeCommandBuffer() else { return }
guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

// Blit operation (texture upload) -- same encoder
computeEncoder.copy(from: stagingBuffer, sourceOffset: 0,
                    sourceBytesPerRow: bytesPerRow,
                    sourceBytesPerImage: bytesPerImage,
                    sourceSize: MTLSize(width: w, height: h, depth: 1),
                    to: destinationTexture,
                    destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))

// Barrier to ensure blit completes before compute reads
computeEncoder.barrier(resources: [destinationTexture],
                       after: .blit, before: .dispatch)

// Compute dispatch (e.g., color correction kernel)
computeEncoder.setComputePipelineState(colorCorrectionPipeline)
computeEncoder.setTexture(destinationTexture, index: 0)
computeEncoder.setTexture(outputTexture, index: 1)
computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)

computeEncoder.endEncoding()
commandBuffer.commit()
```

### 1.2 Argument Tables

Metal 4 replaces traditional per-resource bind points with **MTL4ArgumentTable** -- flexible tables that hold buffer addresses and texture references. This is the foundation for bindless rendering.

```swift
// Create an argument table descriptor
let argTableDescriptor = MTL4ArgumentTableDescriptor()
argTableDescriptor.maxBufferBindCount = 32
argTableDescriptor.maxTextureBindCount = 64
argTableDescriptor.maxSamplerBindCount = 8

// Create the argument table from the device
let argumentTable = device.makeArgumentTable(descriptor: argTableDescriptor)!

// Bind a buffer using its GPU address
argumentTable.setAddress(frameParamsBuffer.gpuAddress, index: 0)

// Bind a buffer at an offset
argumentTable.setAddress(layerDataBuffer.gpuAddress + UInt64(layerOffset), index: 1)

// Bind textures
argumentTable.setTexture(videoFrameTexture, index: 0)
argumentTable.setTexture(lutTexture, index: 1)

// Set argument table on encoder
computeEncoder.setArgumentTable(argumentTable, at: .kernel)
```

For bindless rendering (e.g., compositing many layers), a single argument table with one buffer binding can reference all resources:

```swift
// GPU-side: access resources via argument table indices
// kernel void compositeLayer(
//     argument_table<0> args [[argument_table(0)]],
//     uint2 gid [[thread_position_in_grid]])
// {
//     texture2d<half> layerTex = args.textures[layerIndex];
//     ...
// }
```

### 1.3 Color Attachment Mapping

MTL4RenderCommandEncoder can dynamically remap logical shader outputs to physical color attachments within the same render pass. This eliminates the need to create new encoders when switching render targets.

```swift
guard let rpd = view.currentMTL4RenderPassDescriptor else { return }
let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)!

// Configure color attachment pixel format
let pipelineDescriptor = MTL4RenderPipelineDescriptor()
pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

// Remap attachment mid-pass (conceptual)
// renderEncoder.setAttachmentMap(mapping)
// Draw first set of geometry to attachment 0
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)

// Remap to write to a different attachment without ending the pass
// renderEncoder.setAttachmentMap(newMapping)
// Draw second set of geometry
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount2)

renderEncoder.endEncoding()
```

### 1.4 Barriers API

Metal 4 replaces fences with a lightweight Barriers API for stage-to-stage synchronization:

```swift
// After writing to a texture in a dispatch, barrier before fragment reads
computeEncoder.barrier(resources: [processedTexture],
                       after: .dispatch,   // wait for dispatch writes
                       before: .dispatch)  // before next dispatch reads

// In render encoder: barrier between vertex writes and fragment reads
renderEncoder.barrier(resources: [vertexOutputBuffer],
                      after: .vertex,
                      before: .fragment)
```

### 1.5 MTL4Compiler Interface

Dedicated compilation context separate from the Metal device. The compiler inherits thread priority for QoS. Flexible render pipeline states allow creating an unspecialized pipeline once and specializing for different color states, reusing compiled IR across pipelines.

```swift
// Create a compiler (separate from device)
let compiler = device.makeCompiler()!

// Compile a library
let compileOptions = MTLCompileOptions()
let library = try compiler.makeLibrary(source: shaderSource, options: compileOptions)

// Create unspecialized pipeline, then specialize per-target
let basePipelineDesc = MTL4RenderPipelineDescriptor()
basePipelineDesc.vertexFunction = library.makeFunction(name: "vertexShader")
basePipelineDesc.fragmentFunction = library.makeFunction(name: "fragmentShader")

// Specialize for .rgba16Float output
basePipelineDesc.colorAttachments[0].pixelFormat = .rgba16Float
let hdrPipeline = try device.makeRenderPipelineState(descriptor: basePipelineDesc)

// Specialize for .bgra8Unorm output -- reuses compiled IR
basePipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
let sdrPipeline = try device.makeRenderPipelineState(descriptor: basePipelineDesc)
```

### 1.6 Metal 4 ML Integration

Two approaches for ML inference on the GPU timeline:

**A) Machine Learning Command Encoder (large networks):**
```swift
// MTL4MachineLearningCommandEncoder runs entire networks on the GPU timeline
// alongside draws and dispatches
let mlEncoder = commandBuffer.makeMachineLearningCommandEncoder()!
// Encode inference operations...
mlEncoder.endEncoding()
```

**B) Shader ML (small networks embedded in shaders):**
Metal 4 introduces first-class **MTLTensor** as a resource type alongside buffers and textures. Shader ML embeds ML operations directly in Metal Shading Language, eliminating data copies between device memory and shaders.

**C) Neural Material Evaluation:**
Combines sampling, inference, and shading into a single shader dispatch, sharing thread memory for better performance. Useful for neural upscaling, denoising, or style transfer effects in video.

### 1.7 Gradual Adoption Strategy

Metal 4 supports incremental migration in three phases:
1. **Phase 1 (Compilation):** Adopt MTL4Compiler for pipeline creation
2. **Phase 2 (Command Encoding):** Switch to MTL4CommandQueue/MTL4CommandBuffer
3. **Phase 3 (Resource Management):** Move to argument tables and residency sets

You can mix traditional Metal queues with MTL4CommandQueues using MTLEvent for cross-queue synchronization.

---

## 2. GPU Timeline & Async Compute

### 2.1 Multiple Command Queues

Metal supports multiple command queues per device. By using separate queues for render and compute, you overlap GPU work:

```swift
let device = MTLCreateSystemDefaultDevice()!

// Separate queues for async compute
let renderQueue = device.makeCommandQueue()!
let computeQueue = device.makeCommandQueue()!
let blitQueue = device.makeCommandQueue()!
```

### 2.2 MTLEvent for GPU-GPU Synchronization

MTLEvent synchronizes operations between command buffers on the same device. MTLSharedEvent extends this across command queues and even between CPU and GPU.

```swift
let event = device.makeEvent()!
var eventValue: UInt64 = 0

// --- Compute Queue: process video frame ---
let computeBuffer = computeQueue.makeCommandBuffer()!
let computeEncoder = computeBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(effectPipeline)
computeEncoder.setTexture(inputTexture, index: 0)
computeEncoder.setTexture(processedTexture, index: 1)
computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
computeEncoder.endEncoding()

// Signal event after compute finishes
eventValue += 1
computeBuffer.encodeSignalEvent(event, value: eventValue)
computeBuffer.commit()

// --- Render Queue: display processed frame ---
let renderBuffer = renderQueue.makeCommandBuffer()!

// Wait for compute to finish before rendering
renderBuffer.encodeWaitForEvent(event, value: eventValue)

let renderEncoder = renderBuffer.makeRenderCommandEncoder(descriptor: rpd)!
renderEncoder.setFragmentTexture(processedTexture, index: 0)
// Draw fullscreen quad with processed video frame
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
renderEncoder.endEncoding()
renderBuffer.commit()
```

### 2.3 MTLSharedEvent for CPU-GPU Sync

```swift
let sharedEvent = device.makeSharedEvent()!
let listener = MTLSharedEventListener(dispatchQueue: DispatchQueue.global())

// GPU signals when frame is ready
eventValue += 1
commandBuffer.encodeSignalEvent(sharedEvent, value: eventValue)

// CPU listens for completion
sharedEvent.notify(listener, atValue: eventValue) { event, value in
    // Frame is ready -- trigger UI update or export write
    DispatchQueue.main.async {
        self.presentProcessedFrame()
    }
}
```

### 2.4 Async Blit for Texture Uploads

Use a dedicated blit queue to upload textures without blocking render/compute:

```swift
let blitBuffer = blitQueue.makeCommandBuffer()!
let blitEncoder = blitBuffer.makeBlitCommandEncoder()!

// Upload new video frame texture while GPU renders previous frame
blitEncoder.copy(from: cpuStagingBuffer, sourceOffset: 0,
                 sourceBytesPerRow: bytesPerRow,
                 sourceBytesPerImage: bytesPerImage,
                 sourceSize: MTLSize(width: w, height: h, depth: 1),
                 to: nextFrameTexture,
                 destinationSlice: 0, destinationLevel: 0,
                 destinationOrigin: .init())
blitEncoder.endEncoding()

// Signal when upload is done
blitBuffer.encodeSignalEvent(event, value: uploadEventValue)
blitBuffer.commit()

// Render queue waits for upload before using this texture
renderBuffer.encodeWaitForEvent(event, value: uploadEventValue)
```

### 2.5 NLE Pipeline: Overlapping Decode, Process, Display

```
Frame N:   [Decode]---->[Compute Effects]---->[Render/Display]
Frame N+1:              [Decode]---->[Compute Effects]---->[Render/Display]
Frame N+2:                           [Decode]---->[Compute Effects]---->...

Timeline:  |------|------|------|------|------|------|
           Decode1 Decode2 Decode3
                  Compute1 Compute2 Compute3
                          Render1  Render2  Render3
```

Each stage runs on its own queue, synchronized with MTLEvent signals.

---

## 3. Indirect Command Buffers

### 3.1 Overview

MTLIndirectCommandBuffer allows the GPU to encode draw and compute commands, eliminating CPU bottlenecks for per-frame command generation.

### 3.2 Creating an Indirect Command Buffer

```swift
let icbDescriptor = MTLIndirectCommandBufferDescriptor()
icbDescriptor.commandTypes = [.draw, .drawIndexed]
icbDescriptor.inheritBuffers = false
icbDescriptor.inheritPipelineState = false
icbDescriptor.maxVertexBufferBindCount = 4
icbDescriptor.maxFragmentBufferBindCount = 4

let indirectCommandBuffer = device.makeIndirectCommandBuffer(
    descriptor: icbDescriptor,
    maxCommandCount: maxLayerCount,
    options: .storageModePrivate
)!
```

### 3.3 GPU-Driven Compositing for NLE

A compute kernel decides which layers are visible, sets up draw commands for each visible layer, and the render pass executes them all:

```swift
// Compute pass: GPU determines visible layers and encodes draw commands
let computeEncoder = computeBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(cullAndEncodePipeline)
computeEncoder.setBuffer(layerDataBuffer, offset: 0, index: 0)      // timeline layer info
computeEncoder.setBuffer(icb.buffer, offset: 0, index: 1)           // ICB backing buffer
computeEncoder.useResource(indirectCommandBuffer, usage: .write)
computeEncoder.dispatchThreads(
    MTLSize(width: layerCount, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
)
computeEncoder.endEncoding()

// Render pass: execute GPU-encoded draw commands
let renderEncoder = renderBuffer.makeRenderCommandEncoder(descriptor: rpd)!
renderEncoder.executeCommandsInBuffer(indirectCommandBuffer, range: 0..<maxLayerCount)
renderEncoder.endEncoding()
```

**Compute kernel for GPU-driven compositing (MSL):**
```metal
kernel void encodeLayerDrawCommands(
    device LayerData *layers        [[buffer(0)]],
    render_command   cmd            [[render_command(0)]],
    uint             layerIndex     [[thread_position_in_grid]])
{
    LayerData layer = layers[layerIndex];

    // Visibility/occlusion test on GPU
    if (layer.opacity <= 0.0 || !layer.visible ||
        layer.timeRange.end < currentTime || layer.timeRange.start > currentTime) {
        cmd.reset();  // skip this layer
        return;
    }

    // Encode draw command for this layer
    cmd.set_render_pipeline_state(layer.blendMode == BlendModeAdd
                                   ? addBlendPipeline
                                   : normalBlendPipeline);
    cmd.set_vertex_buffer(layer.vertexBuffer, 0);
    cmd.set_fragment_buffer(layer.fragmentParamsBuffer, 0);
    cmd.set_fragment_texture(layer.texture, 0);
    cmd.draw_primitives(primitive_type::triangle, 0, 6, 1, layerIndex);
}
```

### 3.4 Compute Indirect Command Buffers (Metal 3+)

Metal 3 added support for GPU-encoded compute dispatches:

```swift
let computeICBDescriptor = MTLIndirectCommandBufferDescriptor()
computeICBDescriptor.commandTypes = .concurrentDispatch
computeICBDescriptor.maxKernelBufferBindCount = 8

let computeICB = device.makeIndirectCommandBuffer(
    descriptor: computeICBDescriptor,
    maxCommandCount: maxEffectCount,
    options: .storageModePrivate
)!
```

A GPU kernel can decide which effects to apply and encode only the necessary compute dispatches, enabling a fully GPU-driven effect pipeline.

### 3.5 Benefits for NLE

- **Reusability:** ICBs can be re-executed across frames when the timeline hasn't changed
- **CPU offload:** Layer visibility, blend mode selection, and draw encoding all happen on GPU
- **Scalability:** Hundreds of layers composited without CPU intervention per frame

---

## 4. MPS Graph & ML Inference on GPU

### 4.1 MPSGraph Overview

MPSGraph sits on top of Metal Performance Shaders, extending support to multi-dimensional tensor operations. It provides GPU acceleration for Core ML and TensorFlow.

### 4.2 Real-Time Video Processing with MPSGraph

```swift
import MetalPerformanceShadersGraph

let graph = MPSGraph()
let device = MPSGraphDevice(mtlDevice: mtlDevice)

// Define input placeholder matching video frame dimensions
let inputPlaceholder = graph.placeholder(
    shape: [1, 1080, 1920, 3],  // batch, height, width, channels
    dataType: .float16,
    name: "videoFrame"
)

// Convolution weights for a learned denoising filter
let weightsData = MPSGraphTensorData(
    device: device,
    data: denoiseWeightsData,
    shape: [3, 3, 3, 16],  // kH, kW, inC, outC
    dataType: .float16
)
let weightsTensor = graph.constant(weightsData)

// Convolution layer
let convDesc = MPSGraphConvolution2DOpDescriptor(
    strideInX: 1, strideInY: 1,
    dilationRateInX: 1, dilationRateInY: 1,
    groups: 1,
    paddingStyle: .TF_SAME,
    dataLayout: .NHWC,
    weightsLayout: .HWIO
)!

let conv1 = graph.convolution2D(inputPlaceholder, weights: weightsTensor,
                                 descriptor: convDesc, name: "denoise_conv1")
let relu1 = graph.reLU(with: conv1, name: "relu1")

// ... additional layers ...

// Run inference on a video frame
let inputTensorData = MPSGraphTensorData(
    mtlBuffer: frameBuffer,        // GPU buffer with frame data
    shape: [1, 1080, 1920, 3],
    dataType: .float16
)

let results = graph.run(
    with: device.makeCommandQueue()!,
    feeds: [inputPlaceholder: inputTensorData],
    targetTensors: [relu1],
    targetOperations: nil
)

let outputTensorData = results[relu1]!
```

### 4.3 Fused Scaled Dot-Product Attention (SDPA)

For transformer-based models (super resolution, style transfer):

```swift
// MPSGraph fused SDPA operation -- single kernel, much more efficient
let attention = graph.scaledDotProductAttention(
    queryTensor: queryTensor,
    keyTensor: keyTensor,
    valueTensor: valueTensor,
    scale: Float(1.0 / sqrt(Float(headDim))),
    name: "sdpa"
)
```

### 4.4 Metal 4 Tensors and ML Command Encoder

Metal 4 adds first-class MTLTensor alongside buffers and textures:

```swift
// Metal 4: Create a tensor resource
let tensorDescriptor = MTLTensorDescriptor()
tensorDescriptor.dataType = .float16
tensorDescriptor.shape = [1, 64, 270, 480]  // batch, channels, H, W

let tensor = device.makeTensor(descriptor: tensorDescriptor)!

// Machine Learning Command Encoder for large networks
let mlEncoder = commandBuffer.makeMachineLearningCommandEncoder()!
// Encode inference operations that run on the GPU timeline
// alongside render and compute work
mlEncoder.endEncoding()
```

### 4.5 Shader ML (Embedded in Metal Shading Language)

For small networks that need to run inside a shader (e.g., per-pixel neural denoising):

```metal
// Metal 4 Shader ML: embed small neural networks directly in shaders
// Combines sampling, inference, and shading in a single dispatch
// sharing thread memory for better performance

kernel void neuralDenoise(
    texture2d<half, access::read>  input   [[texture(0)]],
    texture2d<half, access::write> output  [[texture(1)]],
    // Metal 4 tensor parameter for weights
    // metal::tensor<half, 4> weights       [[tensor(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Read neighborhood pixels
    half4 center = input.read(gid);
    // ... gather neighborhood ...

    // Run small neural network inference inline
    // half4 denoised = neural_infer(neighborhood, weights);

    output.write(center, gid); // placeholder
}
```

### 4.6 Practical NLE Applications

| Use Case | Approach | Framework |
|----------|----------|-----------|
| Video super resolution | Large network | MPSGraph / ML Encoder |
| Real-time denoising | Medium network | MPSGraph |
| Per-pixel style transfer | Small network | Shader ML (Metal 4) |
| Scene detection | Transformer | MPSGraph SDPA |
| Object segmentation | U-Net | Core ML -> MPSGraph |
| Auto color matching | Small CNN | Shader ML (Metal 4) |

---

## 5. Tile-Based Rendering

### 5.1 Apple GPU Architecture (TBDR)

Apple GPUs use Tile-Based Deferred Rendering with two phases:
1. **Tiling:** All geometry is processed, binned into screen-space tiles
2. **Rendering:** Each tile's pixels are processed entirely in fast on-chip tile memory

This architecture uniquely enables **tile shaders** and **imageblocks** -- features not available on discrete GPUs.

### 5.2 Imageblocks

An imageblock is a 2D data structure in tile memory. It has a width, height, depth, and customizable format. Both fragment functions and tile (kernel) functions can access imageblocks.

```metal
// Define a custom imageblock structure
struct FragmentData {
    half4 color   [[color(0)]];
    float depth   [[color(1)]];
    half4 normal  [[color(2)]];
};

// Tile shader can access the ENTIRE imageblock (not just one pixel)
kernel void tileShaderComposite(
    imageblock<FragmentData> imgBlock,
    ushort2 tid [[thread_position_in_threadgroup]])
{
    FragmentData data = imgBlock.read(tid);
    // Process -- blend, sort, accumulate
    // All happens in fast tile memory, no bandwidth cost
    data.color = /* composited result */;
    imgBlock.write(data, tid);
}
```

### 5.3 Memoryless Render Targets

Render targets that exist only in tile memory, with zero device memory backing. Critical for memory-constrained video processing:

```swift
let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .depth32Float,
    width: width, height: height,
    mipmapped: false
)
depthDesc.usage = .renderTarget
depthDesc.storageMode = .memoryless  // no device memory allocated

let memorylessDepth = device.makeTexture(descriptor: depthDesc)!

// Use in render pass -- only exists in tile memory
let rpd = MTLRenderPassDescriptor()
rpd.depthAttachment.texture = memorylessDepth
rpd.depthAttachment.storeAction = .dontCare  // never written to device memory
```

### 5.4 Tile Shaders for Video Compositing

Tile shaders execute compute dispatches inline within render passes, sharing data through tile memory. This is extremely efficient for multi-pass compositing:

```swift
let rpd = MTLRenderPassDescriptor()
rpd.colorAttachments[0].texture = outputTexture
rpd.colorAttachments[0].loadAction = .clear
rpd.tileWidth = 32
rpd.tileHeight = 32

let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)!

// Pass 1: Draw background layer
renderEncoder.setRenderPipelineState(backgroundPipeline)
renderEncoder.setFragmentTexture(backgroundTexture, index: 0)
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

// Tile dispatch: blend/composite in tile memory (no bandwidth!)
renderEncoder.setTileBuffer(blendParamsBuffer, offset: 0, index: 0)
renderEncoder.dispatchThreadsPerTile(MTLSize(width: 32, height: 32, depth: 1))

// Pass 2: Draw overlay layer
renderEncoder.setRenderPipelineState(overlayPipeline)
renderEncoder.setFragmentTexture(overlayTexture, index: 0)
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

// Another tile dispatch for final tonemapping
renderEncoder.setTileBuffer(tonemapParamsBuffer, offset: 0, index: 0)
renderEncoder.dispatchThreadsPerTile(MTLSize(width: 32, height: 32, depth: 1))

renderEncoder.endEncoding()
```

### 5.5 NLE Benefits

- **Memory savings:** Intermediate compositing buffers can be memoryless
- **Bandwidth reduction:** Multi-layer compositing in tile memory avoids round-trips to device memory
- **Single-pass compositing:** Draw layers, blend in tile memory, tonemap -- all in one render pass
- **Power efficiency:** Less memory traffic = less power on laptops/mobile

---

## 6. Metal Debugging & Profiling

### 6.1 GPU Capture Workflow

1. In Xcode, click the **camera icon** in the debug bar, or call `MTLCaptureManager.shared().startCapture()`
2. Frame is captured with all command buffers, encoders, and resources
3. **Dependency Viewer** shows the full render graph
4. Click any encoder to inspect bound resources, pipeline states, textures

```swift
// Programmatic GPU capture for automated debugging
let captureManager = MTLCaptureManager.shared()
let captureDescriptor = MTLCaptureDescriptor()
captureDescriptor.captureObject = device
captureDescriptor.destination = .gpuTraceDocument
captureDescriptor.outputURL = URL(fileURLWithPath: "/tmp/video_pipeline_capture.gputrace")

try captureManager.startCapture(with: captureDescriptor)

// ... encode your video processing pipeline ...

captureManager.stopCapture()
```

### 6.2 Shader Debugger

- Click any pixel in the Metal Debugger to jump to the shader executing at that pixel
- Step through shader code line-by-line, inspect variable values
- **Edit and reload** shaders to test fixes without recompiling the app
- View per-line execution cost

### 6.3 Metal System Trace (Instruments)

For profiling over time (not just a single frame):

1. Open Instruments -> **Game Performance** template (includes Metal System Trace)
2. Record your NLE during playback
3. Timeline shows:
   - CPU encode timing (are you CPU-bound?)
   - GPU execution timing per encoder (are you GPU-bound?)
   - Memory allocation/deallocation
   - Dropped frames and stalls

**Key metrics to watch for NLE video processing:**

| Metric | Healthy | Problem |
|--------|---------|---------|
| GPU idle time between frames | Minimal | Too much = CPU bottleneck |
| GPU utilization | 60-80% | 100% = GPU bound, add compute overlap |
| Memory bandwidth | Below peak | Near peak = optimize texture formats |
| Encoder count per frame | Low (2-5) | High (20+) = consolidate passes |
| Frame completion time | < 16.6ms (60fps) | Above = profile individual passes |

### 6.4 GPU Performance Counters

Available at encoder granularity in Xcode, and a subset per-draw-call:

```swift
// Enable GPU counter sampling in the command buffer descriptor
let counterSampleBuffer = device.makeCounterSampleBuffer(
    descriptor: counterSampleBufferDescriptor
)!

// Attach to command buffer for per-encoder counters
commandBuffer.sampleCounters(
    sampleBuffer: counterSampleBuffer,
    sampleIndex: 0,
    barrier: true
)
```

**Counters relevant to video processing:**
- **Shader ALU utilization:** Are compute kernels math-bound?
- **Texture sample throughput:** Bottleneck on texture reads?
- **Memory bandwidth utilization:** Too many large texture copies?
- **Occupancy:** Are threadgroups sized correctly?
- **Limiter tracks:** Vertex, Fragment, Compute stage limiters

### 6.5 Performance Heat Maps (M3/A17+)

New in Xcode 15+: Shader cost graphs and performance heat maps overlay shader execution costs directly in your source code.

### 6.6 Shader Execution History

View the exact sequence of shader invocations for a pixel, including which draw call, which shader instance, and the data flowing through.

### 6.7 Video Processing Debugging Tips

1. **Capture a "problem frame":** Use programmatic capture triggered by a condition (e.g., frame drop)
2. **Check texture formats:** Ensure you're not accidentally using float32 where float16 suffices
3. **Verify threadgroup sizes:** Use `maxTotalThreadsPerThreadgroup` and tune for occupancy
4. **Monitor texture cache hits:** High cache misses indicate poor memory access patterns
5. **Profile the full pipeline:** Use Metal System Trace to see decode -> compute -> render overlap

---

## 7. Multi-GPU Support

### 7.1 GPU Device Discovery

```swift
// macOS: discover all available GPUs
import Metal

let allDevices = MTLCopyAllDevices()

for device in allDevices {
    print("GPU: \(device.name)")
    print("  Removable (eGPU): \(device.isRemovable)")
    print("  Low power: \(device.isLowPower)")
    print("  Headless: \(device.isHeadless)")
    print("  Unified memory: \(device.hasUnifiedMemory)")
    print("  Recommended: \(device.recommendedMaxWorkingSetSize / 1_073_741_824) GB")
}

// Select the best GPU for compute workloads
func selectComputeGPU() -> MTLDevice {
    let devices = MTLCopyAllDevices()

    // Prefer eGPU if available (most compute power)
    if let eGPU = devices.first(where: { $0.isRemovable }) {
        return eGPU
    }
    // Then discrete GPU
    if let discrete = devices.first(where: { !$0.isLowPower && !$0.isRemovable }) {
        return discrete
    }
    // Fallback to system default
    return MTLCreateSystemDefaultDevice()!
}
```

### 7.2 Distributing Work Across GPUs

```swift
class MultiGPUVideoProcessor {
    let displayGPU: MTLDevice    // GPU driving the display
    let computeGPU: MTLDevice    // eGPU for heavy processing

    let displayQueue: MTLCommandQueue
    let computeQueue: MTLCommandQueue

    init() {
        let allDevices = MTLCopyAllDevices()

        // Assign GPUs
        computeGPU = allDevices.first(where: { $0.isRemovable })
                     ?? MTLCreateSystemDefaultDevice()!
        displayGPU = MTLCreateSystemDefaultDevice()!

        displayQueue = displayGPU.makeCommandQueue()!
        computeQueue = computeGPU.makeCommandQueue()!
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // 1. Compute-heavy effects on eGPU
        let computeBuffer = computeQueue.makeCommandBuffer()!
        // ... encode effects on computeGPU ...
        computeBuffer.commit()
        computeBuffer.waitUntilCompleted()

        // 2. Transfer result via IOSurface (shared across GPUs)
        let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)!.takeUnretainedValue()
        let displayTexture = displayGPU.makeTexture(
            descriptor: textureDesc,
            iosurface: ioSurface,
            plane: 0
        )!

        // 3. Display on the GPU driving the monitor
        let renderBuffer = displayQueue.makeCommandBuffer()!
        let renderEncoder = renderBuffer.makeRenderCommandEncoder(descriptor: rpd)!
        renderEncoder.setFragmentTexture(displayTexture, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()
        renderBuffer.commit()
    }
}
```

### 7.3 eGPU Hot-Plug Handling

```swift
// Register for GPU addition/removal notifications
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleGPUAdded(_:)),
    name: .MTLDeviceWasAdded,
    object: nil
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleGPURemoved(_:)),
    name: .MTLDeviceRemovalRequested,
    object: nil
)

@objc func handleGPUAdded(_ notification: Notification) {
    guard let device = notification.object as? MTLDevice else { return }
    if device.isRemovable {
        // Migrate heavy compute to eGPU
        reconfigureComputePipeline(with: device)
    }
}

@objc func handleGPURemoved(_ notification: Notification) {
    guard let device = notification.object as? MTLDevice else { return }
    // Gracefully migrate work back to internal GPU
    migrateWorkFromDevice(device)
}
```

### 7.4 Important Notes

- Apple Silicon Macs have a single unified GPU -- multi-GPU is only relevant for Intel Macs with discrete GPUs or eGPUs
- IOSurface is the primary mechanism for sharing data between GPUs
- eGPU support was deprecated for Apple Silicon but remains functional on Intel Macs
- For Apple Silicon, focus on async compute overlap rather than multi-GPU

---

## 8. Metal-CoreVideo-IOSurface Integration

### 8.1 Zero-Copy Pipeline Architecture

The ideal NLE pipeline has zero copies between decode, process, and display:

```
VideoToolbox Decode -> CVPixelBuffer (IOSurface-backed)
                           |
                    CVMetalTextureCache
                           |
                      MTLTexture (zero-copy view of same memory)
                           |
                    Metal Compute/Render (effects, compositing)
                           |
                      MTLTexture -> IOSurface
                           |
                    CAMetalLayer / VideoToolbox Encode
```

### 8.2 CVMetalTextureCache Setup

```swift
var textureCache: CVMetalTextureCache?

// Create the cache once at initialization
let cacheAttributes: [String: Any] = [:]
let textureAttributes: [String: Any] = [:]

CVMetalTextureCacheCreate(
    kCFAllocatorDefault,
    cacheAttributes as CFDictionary,
    device,
    textureAttributes as CFDictionary,
    &textureCache
)
```

### 8.3 CVPixelBuffer to MTLTexture (Zero-Copy)

```swift
func metalTexture(from pixelBuffer: CVPixelBuffer,
                  textureCache: CVMetalTextureCache,
                  pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    var cvMetalTexture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        textureCache,
        pixelBuffer,
        nil,            // texture attributes
        pixelFormat,
        width, height,
        0,              // plane index
        &cvMetalTexture
    )

    guard status == kCVReturnSuccess, let cvTexture = cvMetalTexture else {
        return nil
    }

    return CVMetalTextureGetTexture(cvTexture)
}
```

### 8.4 YCbCr (Bi-Planar) Handling

Most video decoders output bi-planar YCbCr (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`). Create separate textures for each plane:

```swift
func metalTexturesFromBiPlanar(pixelBuffer: CVPixelBuffer,
                                cache: CVMetalTextureCache) -> (MTLTexture, MTLTexture)? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // Y plane (full resolution, r8Unorm)
    var yTextureCv: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pixelBuffer, nil,
        .r8Unorm, width, height, 0, &yTextureCv
    )

    // CbCr plane (half resolution, rg8Unorm)
    var cbcrTextureCv: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pixelBuffer, nil,
        .rg8Unorm, width / 2, height / 2, 1, &cbcrTextureCv
    )

    guard let yTex = yTextureCv, let cbcrTex = cbcrTextureCv else { return nil }

    return (CVMetalTextureGetTexture(yTex)!, CVMetalTextureGetTexture(cbcrTex)!)
}
```

### 8.5 IOSurface for Cross-Process and Cross-API Sharing

```swift
// Create an IOSurface-backed pixel buffer for zero-copy sharing
let surfaceProperties: [String: Any] = [
    kIOSurfaceWidth as String: 1920,
    kIOSurfaceHeight as String: 1080,
    kIOSurfaceBytesPerElement as String: 4,
    kIOSurfacePixelFormat as String: kCVPixelFormatType_32BGRA
]

let ioSurface = IOSurfaceCreate(surfaceProperties as CFDictionary)!

// Create Metal texture backed by IOSurface
let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm,
    width: 1920, height: 1080,
    mipmapped: false
)

let metalTexture = device.makeTexture(
    descriptor: textureDesc,
    iosurface: ioSurface,
    plane: 0
)!

// This texture is a LIVE view of the IOSurface
// Changes to the texture are immediately visible via the IOSurface
// and vice versa -- true zero-copy
```

### 8.6 CVPixelBufferPool for Efficient Recycling

```swift
let poolAttributes: [String: Any] = [
    kCVPixelBufferPoolMinimumBufferCountKey as String: 3
]

let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: 1920,
    kCVPixelBufferHeightKey as String: 1080,
    kCVPixelBufferMetalCompatibilityKey as String: true,  // ensures IOSurface backing
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
]

var pool: CVPixelBufferPool?
CVPixelBufferPoolCreate(
    kCFAllocatorDefault,
    poolAttributes as CFDictionary,
    pixelBufferAttributes as CFDictionary,
    &pool
)

// Allocate from pool -- reuses IOSurface memory when previous buffers are released
var pixelBuffer: CVPixelBuffer?
CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &pixelBuffer)
```

### 8.7 Complete NLE Zero-Copy Pipeline

```swift
class ZeroCopyVideoPipeline {
    let device: MTLDevice
    let textureCache: CVMetalTextureCache
    let computeQueue: MTLCommandQueue
    let renderQueue: MTLCommandQueue
    let pixelBufferPool: CVPixelBufferPool

    func processAndDisplay(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Step 1: Zero-copy texture from decoded frame
        let inputTexture = metalTexture(from: pixelBuffer,
                                         textureCache: textureCache)!

        // Step 2: Allocate output from pool (IOSurface-backed)
        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)
        let outputTexture = metalTexture(from: outputPixelBuffer!,
                                          textureCache: textureCache)!

        // Step 3: GPU processing (effects, color grading)
        let computeBuffer = computeQueue.makeCommandBuffer()!
        let computeEncoder = computeBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(effectsPipeline)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        computeEncoder.endEncoding()
        computeBuffer.commit()

        // Step 4: Display (same IOSurface, zero copy)
        // The outputTexture is a live view of outputPixelBuffer's IOSurface
        // Display it directly via CAMetalLayer or pass to VideoToolbox for encode
    }
}
```

### 8.8 Texture Cache Maintenance

```swift
// Flush stale textures periodically (e.g., on memory warning or frame boundary)
CVMetalTextureCacheFlush(textureCache, 0)
```

---

## 9. Mesh / Object Shaders

### 9.1 Overview

Mesh shaders (Metal 3, WWDC 2022) replace the vertex pipeline with two new programmable stages:
- **Object Shader:** Processes coarse-grained objects, outputs payloads to mesh shaders
- **Mesh Shader:** Generates actual geometry (vertices, triangles) for rasterization

### 9.2 Pipeline Setup

```swift
let meshPipelineDescriptor = MTLMeshRenderPipelineDescriptor()

// Object function -- per-object processing
meshPipelineDescriptor.objectFunction = library.makeFunction(name: "particleObjectShader")
meshPipelineDescriptor.meshFunction = library.makeFunction(name: "particleMeshShader")
meshPipelineDescriptor.fragmentFunction = library.makeFunction(name: "particleFragment")

// Configure payload and threadgroups
meshPipelineDescriptor.maxTotalThreadsPerObjectThreadgroup = 64
meshPipelineDescriptor.maxTotalThreadsPerMeshThreadgroup = 128
meshPipelineDescriptor.maxTotalThreadgroupsPerMeshGrid = 256

// Color attachment format
meshPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

let meshPipeline = try device.makeRenderPipelineState(
    descriptor: meshPipelineDescriptor,
    options: []
)
```

### 9.3 Particle System for Video Effects (MSL)

```metal
// Payload struct passed from object shader to mesh shader
struct ParticlePayload {
    float4 positions[64];
    float4 colors[64];
    float  sizes[64];
    uint   count;
};

// Object shader: determines which particles are visible
[[object]]
void particleObjectShader(
    object_data ParticlePayload &payload     [[payload]],
    device const ParticleData *particles     [[buffer(0)]],
    constant FrameParams &frame              [[buffer(1)]],
    uint objectIndex [[threadgroup_position_in_grid]],
    uint threadIndex [[thread_index_in_threadgroup]])
{
    uint particleIndex = objectIndex * 64 + threadIndex;
    ParticleData p = particles[particleIndex];

    // Animate particle based on video timeline
    float t = frame.currentTime - p.spawnTime;
    float3 pos = p.position + p.velocity * t + 0.5 * frame.gravity * t * t;
    float alpha = saturate(1.0 - t / p.lifetime);

    // Frustum cull
    if (alpha > 0.01 && isInFrustum(pos, frame.viewProjection)) {
        uint idx = atomic_fetch_add_explicit(&payload.count, 1, memory_order_relaxed);
        payload.positions[idx] = float4(pos, 1.0);
        payload.colors[idx] = p.color * alpha;
        payload.sizes[idx] = p.size * alpha;
    }

    // Set mesh grid size based on visible particle count
    if (threadIndex == 0) {
        uint meshCount = (payload.count + 3) / 4; // 4 particles per mesh threadgroup
        set_meshthreadgroups_per_grid(uint3(meshCount, 1, 1));
    }
}

// Mesh shader: generates quad geometry for each visible particle
[[mesh]]
void particleMeshShader(
    object_data const ParticlePayload &payload  [[payload]],
    mesh<VertexOut, void, 4, 2, topology::triangle> outputMesh,
    uint threadIndex [[thread_index_in_threadgroup]],
    uint groupIndex  [[threadgroup_position_in_grid]])
{
    uint particleIdx = groupIndex * 4 + threadIndex;
    if (particleIdx >= payload.count) return;

    float4 center = payload.positions[particleIdx];
    float  size = payload.sizes[particleIdx];
    float4 color = payload.colors[particleIdx];

    // Generate billboard quad (2 triangles, 4 vertices)
    uint vertexBase = threadIndex * 4;
    outputMesh.set_vertex(vertexBase + 0, makeVertex(center, float2(-1,-1), size, color));
    outputMesh.set_vertex(vertexBase + 1, makeVertex(center, float2( 1,-1), size, color));
    outputMesh.set_vertex(vertexBase + 2, makeVertex(center, float2( 1, 1), size, color));
    outputMesh.set_vertex(vertexBase + 3, makeVertex(center, float2(-1, 1), size, color));

    uint indexBase = threadIndex * 6;
    outputMesh.set_index(indexBase + 0, vertexBase + 0);
    outputMesh.set_index(indexBase + 1, vertexBase + 1);
    outputMesh.set_index(indexBase + 2, vertexBase + 2);
    outputMesh.set_index(indexBase + 3, vertexBase + 0);
    outputMesh.set_index(indexBase + 4, vertexBase + 2);
    outputMesh.set_index(indexBase + 5, vertexBase + 3);

    outputMesh.set_primitive_count(2);
}
```

### 9.4 Drawing with Mesh Pipeline

```swift
let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)!
renderEncoder.setRenderPipelineState(meshPipeline)
renderEncoder.setObjectBuffer(particleBuffer, offset: 0, index: 0)
renderEncoder.setObjectBuffer(frameParamsBuffer, offset: 0, index: 1)

// Launch object threadgroups -- one per particle batch
let objectThreadgroups = MTLSize(width: particleBatchCount, height: 1, depth: 1)
let objectThreads = MTLSize(width: 64, height: 1, depth: 1)
let meshThreads = MTLSize(width: 128, height: 1, depth: 1)

renderEncoder.drawMeshThreadgroups(
    objectThreadgroups,
    threadsPerObjectThreadgroup: objectThreads,
    threadsPerMeshThreadgroup: meshThreads
)

renderEncoder.endEncoding()
```

### 9.5 NLE Applications

| Effect | How Mesh Shaders Help |
|--------|----------------------|
| Particle systems | GPU-generated billboard quads, animated per frame |
| Procedural text effects | Generate 3D text geometry on GPU |
| Hair/fur rendering | Procedural hair strands without pre-computed geometry |
| Motion trails | Generate ribbon geometry following tracked objects |
| Procedural transitions | Geometric distortion effects (shatter, explode) |
| LOD-based effects | Object shader selects detail level per particle/element |

---

## 10. Resource Heaps & Residency Management

### 10.1 MTLHeap for Video Texture Pools

Resource heaps enable fast sub-allocation and memory aliasing:

```swift
// Calculate heap size for video frame texture pool
let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba16Float,
    width: 1920, height: 1080,
    mipmapped: false
)
textureDesc.usage = [.shaderRead, .shaderWrite]

let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: textureDesc)
let textureSize = alignUp(sizeAndAlign.size, to: sizeAndAlign.align)

// Heap for 8 video frame textures
let heapDescriptor = MTLHeapDescriptor()
heapDescriptor.size = textureSize * 8
heapDescriptor.storageMode = .private
heapDescriptor.type = .automatic  // or .placement for manual control

let textureHeap = device.makeHeap(descriptor: heapDescriptor)!
textureHeap.label = "Video Frame Texture Pool"

// Sub-allocate textures from the heap
var frameTextures: [MTLTexture] = []
for i in 0..<8 {
    let texture = textureHeap.makeTexture(descriptor: textureDesc)!
    texture.label = "Frame Texture \(i)"
    frameTextures.append(texture)
}

func alignUp(_ size: Int, to alignment: Int) -> Int {
    return ((size + alignment - 1) / alignment) * alignment
}
```

### 10.2 Memory Aliasing for Temporary Buffers

Temporary effect buffers can alias (share) the same heap memory when they don't overlap in time:

```swift
let heapDescriptor = MTLHeapDescriptor()
heapDescriptor.size = maxTempBufferSize
heapDescriptor.storageMode = .private
heapDescriptor.hazardTrackingMode = .untracked  // we manage dependencies

let aliasHeap = device.makeHeap(descriptor: heapDescriptor)!

// Pass A uses tempTexture1
let tempTexture1 = aliasHeap.makeTexture(descriptor: tempDesc)!
// Encode pass A...

// Pass B can reuse the same memory (aliasing) since pass A is complete
let tempTexture2 = aliasHeap.makeTexture(descriptor: tempDesc, offset: 0)!
// These occupy the SAME memory -- safe because passes don't overlap
```

### 10.3 Placement Heaps (Manual Control)

```swift
let placementHeapDesc = MTLHeapDescriptor()
placementHeapDesc.size = heapSize
placementHeapDesc.type = .placement
placementHeapDesc.storageMode = .private

let placementHeap = device.makeHeap(descriptor: placementHeapDesc)!

// Manual placement at specific offsets
let buffer1 = placementHeap.makeBuffer(length: 4096, options: .storageModePrivate, offset: 0)!
let texture1 = placementHeap.makeTexture(descriptor: texDesc, offset: 4096)!
```

### 10.4 Residency Sets (Metal 3.2+ / Metal 4)

Residency sets control which resources are available to GPU commands. In Metal 4, they are the **only** way to manage resource residency.

```swift
// Create a residency set
let residencyDescriptor = MTLResidencySetDescriptor()
residencyDescriptor.initialCapacity = 64
let residencySet = try device.makeResidencySet(descriptor: residencyDescriptor)

// Add resources to the set
residencySet.addAllocation(textureHeap)           // add entire heap
residencySet.addAllocation(frameBuffer)            // add individual buffer
residencySet.addAllocation(lutTexture)             // add individual texture

// Commit makes allocations resident
residencySet.commit()

// Attach to command queue -- all command buffers automatically include resources
mtl4Queue.addResidencySet(residencySet)

// Or attach to a single command buffer
commandBuffer.useResidencySet(residencySet)
```

### 10.5 Sparse Textures for Large Video Resources

Sparse textures allow virtual textures larger than physical memory, with tiles mapped on demand:

```swift
// Check sparse texture support
guard device.supportsFamily(.apple6) else { return }

// Create sparse heap
let sparseHeapDesc = MTLHeapDescriptor()
sparseHeapDesc.type = .sparse
sparseHeapDesc.size = sparseHeapSize
sparseHeapDesc.storageMode = .private

let sparseHeap = device.makeHeap(descriptor: sparseHeapDesc)!

// Create a sparse texture (larger than physical memory)
let sparseTexDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba16Float,
    width: 8192, height: 4320,  // 8K resolution
    mipmapped: true
)

let sparseTexture = sparseHeap.makeTexture(descriptor: sparseTexDesc)!

// Map tiles on demand using resource state encoder
let stateEncoder = commandBuffer.makeResourceStateCommandEncoder()!

// Map a specific tile region
let tileRegion = MTLRegion(
    origin: MTLOrigin(x: tileX * tileWidth, y: tileY * tileHeight, z: 0),
    size: MTLSize(width: tileWidth, height: tileHeight, depth: 1)
)
stateEncoder.update(sparseTexture, mode: .map, region: tileRegion,
                    mipLevel: 0, slice: 0)
stateEncoder.endEncoding()
```

### 10.6 Video Texture Pool Manager

A practical texture pool for NLE frame processing:

```swift
class VideoTexturePool {
    private let heap: MTLHeap
    private let textureDescriptor: MTLTextureDescriptor
    private var available: [MTLTexture] = []
    private var inUse: Set<ObjectIdentifier> = []
    private let lock = NSLock()

    init(device: MTLDevice, width: Int, height: Int,
         pixelFormat: MTLPixelFormat = .rgba16Float, poolSize: Int = 8) {

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private
        self.textureDescriptor = desc

        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: desc)
        let alignedSize = ((sizeAndAlign.size + sizeAndAlign.align - 1)
                           / sizeAndAlign.align) * sizeAndAlign.align

        let heapDesc = MTLHeapDescriptor()
        heapDesc.size = alignedSize * poolSize
        heapDesc.storageMode = .private

        self.heap = device.makeHeap(descriptor: heapDesc)!

        // Pre-allocate textures
        for _ in 0..<poolSize {
            if let tex = heap.makeTexture(descriptor: desc) {
                available.append(tex)
            }
        }
    }

    func acquire() -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard let texture = available.popLast() else { return nil }
        inUse.insert(ObjectIdentifier(texture))
        return texture
    }

    func release(_ texture: MTLTexture) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(texture)
        if inUse.remove(id) != nil {
            available.append(texture)
        }
    }
}
```

### 10.7 NLE Resource Management Strategy

```
┌─────────────────────────────────────────────┐
│              Resource Heaps                  │
├─────────────┬───────────────┬───────────────┤
│ Frame Pool  │  Effect Pool  │   LUT Heap    │
│ (8 x 4K)   │  (temp, alias)│  (3D textures)│
├─────────────┼───────────────┼───────────────┤
│             Residency Set                    │
│   (attached to command queue)                │
├─────────────────────────────────────────────┤
│          MTL4CommandQueue                    │
│  All command buffers auto-see all resources  │
└─────────────────────────────────────────────┘
```

---

## Key WWDC Sessions & References

| Session | Topic |
|---------|-------|
| WWDC 2025 - Discover Metal 4 | Unified encoders, argument tables, barriers |
| WWDC 2025 - Combine Metal 4 ML and Graphics | MTLTensor, ML encoder, Shader ML |
| WWDC 2022 - Transform geometry with mesh shaders | Object/mesh shader pipeline |
| WWDC 2020 - Harness Apple GPUs with Metal | TBDR, tile shaders, imageblocks |
| WWDC 2020 - Optimize GPU counters | Performance counter analysis |
| WWDC 2021 - Create image processing apps | Memoryless targets, tile shaders |
| WWDC 2019 - Modern Rendering with Metal | Indirect command buffers |
| WWDC 2019 - Metal for Pro Apps | IOSurface, CVMetalTextureCache |
| WWDC 2020 - Decode ProRes with VideoToolbox | Zero-copy decode pipeline |
| WWDC 2024 - Accelerate ML with Metal | MPSGraph SDPA, transformer acceleration |
| Tech Talk - Discover Metal profiling tools M3 | Shader cost graphs, heat maps |
| Tech Talk - Explore Live GPU Profiling | Metal counters instrument |

---

## Summary: Recommended Architecture for NLE

```
┌─────────────────────────────────────────────────────────────┐
│                    Metal 4 NLE Pipeline                      │
│                                                              │
│  ┌──────────┐   ┌──────────────┐   ┌───────────────┐       │
│  │ Decode   │──>│ CVPixelBuffer │──>│ CVMetalTexture│       │
│  │ (VT/HW)  │   │ (IOSurface)  │   │ Cache         │       │
│  └──────────┘   └──────────────┘   └───────┬───────┘       │
│                                             │ zero-copy     │
│  ┌──────────────────────────────────────────▼──────────┐    │
│  │           MTL4ComputeCommandEncoder                  │    │
│  │  ┌─────────┐  ┌──────────┐  ┌────────────────┐     │    │
│  │  │ YUV->RGB│->│ Effects  │->│ Color Grading  │     │    │
│  │  │ (blit+  │  │ (compute │  │ (LUT, curves)  │     │    │
│  │  │ compute)│  │ dispatch)│  │                 │     │    │
│  │  └─────────┘  └──────────┘  └────────────────┘     │    │
│  │  Barriers between stages for synchronization        │    │
│  └─────────────────────────────────┬───────────────────┘    │
│                                     │                        │
│  ┌──────────────────────────────────▼──────────────────┐    │
│  │          MTL4RenderCommandEncoder                    │    │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────────┐   │    │
│  │  │ Compositing │  │ Tile     │  │ Display      │   │    │
│  │  │ (ICB-driven)│->│ Blend    │->│ (CAMetal     │   │    │
│  │  │             │  │ (on-chip)│  │  Layer)      │   │    │
│  │  └─────────────┘  └──────────┘  └──────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─────────────────────────────┐                            │
│  │ Resource Management         │                            │
│  │ - MTLHeap texture pools     │                            │
│  │ - MTLResidencySet           │                            │
│  │ - Argument tables (bindless)│                            │
│  └─────────────────────────────┘                            │
│                                                              │
│  ┌─────────────────────────────┐                            │
│  │ ML Pipeline                 │                            │
│  │ - MPSGraph (large nets)     │                            │
│  │ - Shader ML (per-pixel)     │                            │
│  │ - MTLTensor resources       │                            │
│  └─────────────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```
