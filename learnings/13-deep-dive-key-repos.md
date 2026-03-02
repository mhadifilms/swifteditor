# Deep-Dive Code Analysis: Cabbage, GPUImage3, and mini-cut

## Executive Summary

This document provides a code-level deep-dive into the three most architecturally significant open-source Swift video editing projects: **Cabbage** (AVFoundation composition framework), **GPUImage3** (Metal GPU processing pipeline), and **mini-cut** (complete NLE with timeline UI). Each section includes class/protocol diagrams, data flow analysis, and specific code patterns that are directly reusable for building a professional NLE.

---

## 1. Cabbage (VideoFlint/Cabbage) -- Deep Architecture Analysis

**Repository**: https://github.com/VideoFlint/Cabbage (1,575 stars)
**Purpose**: AVFoundation composition abstraction layer
**Key Insight**: The most mature and well-designed video composition framework in Swift. Provides the clearest blueprint for an NLE's composition engine.

### 1.1 Complete Class/Protocol Hierarchy

```
Protocols (CompositionProvider.swift):
────────────────────────────────────────
CompositionTimeRangeProvider (AnyObject)
├── startTime: CMTime
├── duration: CMTime
└── (Provides positioning on timeline)

VideoCompositionTrackProvider
├── numberOfVideoTracks() -> Int
└── videoCompositionTrack(for:at:preferredTrackID:) -> AVMutableCompositionTrack?

AudioCompositionTrackProvider
├── numberOfAudioTracks() -> Int
└── audioCompositionTrack(for:at:preferredTrackID:) -> AVMutableCompositionTrack?

AudioMixProvider
└── configure(bindTo:)   // Configure MTAudioProcessingTap for track

VideoCompositionProvider (AnyObject)
└── applyEffect(to:at:renderSize:) -> CIImage

AudioProvider: CompositionTimeRangeProvider
             + AudioCompositionTrackProvider
             + AudioMixProvider

VideoProvider: CompositionTimeRangeProvider
             + VideoCompositionTrackProvider
             + VideoCompositionProvider

TransitionableVideoProvider: VideoProvider
├── videoTransition: VideoTransition?
└── (Supports transitions between adjacent items)

TransitionableAudioProvider: AudioProvider
└── audioTransition: AudioTransition?

TransitionableVideoProvider ──┐
                              ├── TrackItem (central class)
TransitionableAudioProvider ──┘
```

```
Class Hierarchy:
────────────────
Resource (NSObject, NSCopying)
├── duration: CMTime
├── selectedTimeRange: CMTimeRange
├── scaledDuration: CMTime?          // Speed change support
├── size: CGSize
├── status: ResourceStatus (.noRecourse/.preparing/.avaliable/.unavaliable)
├── prepare(progressHandler:completion:) -> ResourceTask?
├── tracks(for: AVMediaType) -> [AVAssetTrack]
├── trackInfo(for:at:) -> ResourceTrackInfo
│
├── AVAssetTrackResource
│   ├── asset: AVAsset?
│   └── (Loads tracks/duration async, wraps AVAsset)
│
├── PHAssetTrackResource
│   ├── phAsset: PHAsset?
│   └── (Loads from Photos library)
│
├── ImageResource
│   ├── image: CIImage?
│   └── (Provides static image as video frame)
│
└── PHAssetImageResource
    └── (Loads image from PHAsset)

TrackItem (NSObject, NSCopying)
├── resource: Resource
├── configuration: TrackConfiguration
├── videoTransition: VideoTransition?
├── audioTransition: AudioTransition?
├── startTime: CMTime
├── duration: CMTime (computed from resource.scaledDuration ?? resource.selectedTimeRange.duration)
└── Implements: TransitionableVideoProvider, TransitionableAudioProvider

Timeline
├── videoChannel: [TransitionableVideoProvider]
├── audioChannel: [TransitionableAudioProvider]
├── overlays: [VideoProvider]
├── audios: [AudioProvider]
├── renderSize: CGSize
├── backgroundColor: CIColor
├── passingThroughVideoCompositionProvider: VideoCompositionProvider?
└── static reloadVideoStartTime(providers:) -- recalculates start times with transition overlaps

CompositionGenerator
├── timeline: Timeline
├── buildPlayerItem() -> AVPlayerItem
├── buildImageGenerator() -> AVAssetImageGenerator?
├── buildExportSession(presetName:) -> AVAssetExportSession?
└── Internal: buildComposition() / buildVideoComposition() / buildAudioMix()
```

### 1.2 Data Flow: From Timeline to Playback

```
User creates Timeline
        │
        ▼
CompositionGenerator.buildPlayerItem()
        │
        ├── 1. buildComposition() → AVMutableComposition
        │     ├── Create video tracks (max ~16 due to AVFoundation limit)
        │     ├── Create audio tracks
        │     ├── For each TrackItem: insert time range from resource
        │     └── Track ID recycling via mainVideoTrackIDs/mainAudioTrackIDs arrays
        │
        ├── 2. buildVideoComposition() → AVMutableVideoComposition
        │     ├── calculateSlices() → [CompositionGeneratorTimelineSlice]
        │     │   └── Slices partition timeline into non-overlapping ranges
        │     │       where each slice knows which providers are active
        │     ├── For each slice: create VideoCompositionInstruction
        │     │   ├── mainTrackIDs + layerInstructions (for main track)
        │     │   └── overlayTrackIDs + overlayLayerInstructions
        │     ├── Set customVideoCompositorClass = VideoCompositor.self
        │     └── renderSize, frameDuration from timeline
        │
        ├── 3. buildAudioMix() → AVMutableAudioMix
        │     ├── For each audio track: create AVMutableAudioMixInputParameters
        │     ├── Attach AudioProcessingTapHolder via MTAudioProcessingTap
        │     └── AudioProcessingChain processes volume/effects per-buffer
        │
        └── 4. Return AVPlayerItem(asset: composition)
              with .videoComposition and .audioMix set
```

### 1.3 Video Composition Pipeline (Frame Rendering)

The heart of Cabbage is its custom `VideoCompositor` class:

```swift
// VideoCompositor.swift - Custom AVVideoCompositing implementation
open class VideoCompositor: NSObject, AVFoundation.AVVideoCompositing {
    // Class-level CIContext for performance (reused across frames)
    public static var ciContext: CIContext = CIContext()

    // Required pixel buffer attributes
    public var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange  // Native camera format
    ]

    // Dedicated rendering queue
    private let renderingQueue = DispatchQueue(label: "com.cabbage.renderingqueue")
    private var shouldCancelAllRequests = false

    public func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async {
            if self.shouldCancelAllRequests { return }
            autoreleasepool {
                // Get our custom instruction
                guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction
                    as? VideoCompositionInstruction else { return }

                // Render via CIImage pipeline
                if let outputPixels = instruction.apply(request: asyncVideoCompositionRequest) {
                    asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputPixels)
                }
            }
        }
    }
}
```

**VideoCompositionInstruction rendering flow** (VideoCompositionInstruction.swift):

```swift
// Simplified rendering logic inside VideoCompositionInstruction
func apply(request: AVAsynchronousVideoCompositionRequest) -> CVPixelBuffer? {
    let renderSize = request.renderContext.size
    let time = request.compositionTime

    // 1. Render main track layers
    var mainImage: CIImage? = nil
    if isTransitionInstruction {
        // Two main layers overlapping = transition
        let foreground = layerInstructions[0].sourceImage(from: request, renderSize: renderSize)
        let background = layerInstructions[1].sourceImage(from: request, renderSize: renderSize)
        let tweenFactor = calculateTweenFactor(at: time)
        mainImage = transition.renderImage(
            foregroundImage: foreground,
            backgroundImage: background,
            forTweenFactor: tweenFactor,
            renderSize: renderSize
        )
    } else {
        // Single main layer
        mainImage = layerInstructions[0].sourceImage(from: request, renderSize: renderSize)
    }

    // 2. Apply main track effects
    mainImage = mainImage.flatMap {
        layerInstructions[0].provider?.applyEffect(to: $0, at: time, renderSize: renderSize)
    }

    // 3. Composite overlays on top
    for overlayInstruction in overlayLayerInstructions {
        let overlayImage = overlayInstruction.sourceImage(from: request, renderSize: renderSize)
        if let overlay = overlayImage {
            mainImage = overlay.composited(over: mainImage ?? CIImage())
        }
    }

    // 4. Apply global passing-through provider
    if let passingProvider = passingThroughVideoCompositionProvider {
        mainImage = passingProvider.applyEffect(to: mainImage!, at: time, renderSize: renderSize)
    }

    // 5. Render CIImage to CVPixelBuffer
    let pixelBuffer = request.renderContext.newPixelBuffer()
    VideoCompositor.ciContext.render(mainImage!, to: pixelBuffer!)
    return pixelBuffer
}
```

### 1.4 Audio Pipeline

```
AudioProcessingTapHolder
├── Wraps MTAudioProcessingTap (low-level audio tap)
├── audioProcessingChain: AudioProcessingChain
│
AudioProcessingChain
├── nodes: [AudioProcessingNode]
├── process(timeRange:bufferListInOut:)
│   └── Iterates through nodes, each modifies bufferList in-place
│
AudioProcessingNode (protocol)
├── process(timeRange:bufferListInOut:)
│
VolumeAudioConfiguration : AudioConfigurationProtocol, AudioProcessingNode
├── timeRange: CMTimeRange
├── startVolume: Float, endVolume: Float
├── timingFunction: (Float) -> Float  // From TimingFunctionFactory
└── Uses vDSP_vsmul (Accelerate) for efficient buffer-level volume changes

AudioMixer (static utility)
├── changeVolume(for bufferList:, volume:)
└── Uses vDSP_vsmul per audio buffer
```

### 1.5 Configuration System

```swift
// TrackConfiguration.swift
public class TrackConfiguration: NSObject, NSCopying {
    public var videoConfiguration: VideoConfiguration = .createDefaultConfiguration()
    public var audioConfiguration: AudioConfiguration = .createDefaultConfiguration()
}

public class VideoConfiguration: NSObject, NSCopying {
    public enum ContentMode { case aspectFit, aspectFill, custom }
    public var contentMode: ContentMode = .aspectFit
    public var frame: CGRect?                              // Custom frame position
    public var transform: CGAffineTransform?               // Custom transform
    public var opacity: Float = 1.0
    public var configurations: [VideoConfigurationProtocol] = []  // Chainable effects

    // Applies content mode transform + custom transforms + effect chain
    func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage
}

// KeyframeVideoConfiguration.swift - Generic keyframe animation
public class KeyframeVideoConfiguration<Value: KeyframeValue>: VideoConfigurationProtocol {
    public var keyframes: [Keyframe<Value>] = []

    public class Keyframe<Value> {
        var time: CMTime
        var value: Value
        var timingFunction: ((Float) -> Float)?
    }

    // Interpolates between keyframes using tween factor + timing function
    func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage {
        // Find surrounding keyframes, calculate tween, apply value
    }
}

// Built-in keyframe value types:
public class TransformKeyframeValue: KeyframeValue {
    var scale: CGFloat = 1, rotation: CGFloat = 0, translationX: CGFloat = 0, translationY: CGFloat = 0
}
public class OpacityKeyframeValue: KeyframeValue {
    var opacity: CGFloat = 1.0
}
```

### 1.6 Transition System

```swift
// VideoTransition.swift
public protocol VideoTransition: AnyObject {
    var duration: CMTime { get set }
    func renderImage(foregroundImage: CIImage, backgroundImage: CIImage,
                     forTweenFactor tween: Float, renderSize: CGSize) -> CIImage
}

// Built-in transitions (all CIImage-based):
// - CrossDissolveTransition: CIFilter("CIDissolveTransition")
// - SwipeTransition: Crops and composites based on direction
// - PushTransition: Translates both images in direction
// - BoundingUpTransition: Scale-based transition with spring
// - FadeTransition: Alpha-based fade through black

// AudioTransition.swift
public protocol AudioTransition: AnyObject {
    var duration: CMTime { get set }
    func applyNextAudioMixInputParameters(bindTo: AVMutableAudioMixInputParameters, ...)
    func applyPreviousAudioMixInputParameters(bindTo: AVMutableAudioMixInputParameters, ...)
}
// FadeInOutAudioTransition: Uses VolumeAudioConfiguration with timing functions
```

### 1.7 Reusable Patterns from Cabbage

1. **Protocol-based composition providers** -- Clean separation between video/audio/timeline concerns
2. **Resource abstraction with async loading** -- ResourceTask cancellation pattern
3. **CIImage pipeline for video effects** -- Chainable, composable effects via CIFilter
4. **Track ID recycling** -- Solves AVFoundation's ~16 track limit
5. **Time slice calculation** -- `calculateSlices()` partitions timeline into instruction ranges
6. **TimingFunctionFactory** -- Complete easing library (30+ functions)
7. **Keyframe animation system** -- Generic, reusable with custom value types
8. **MTAudioProcessingTap wrapper** -- Clean interface to low-level audio processing
9. **vDSP-based audio mixing** -- Efficient Accelerate framework usage for volume

### 1.8 Limitations and Gaps

- **Single main video channel** -- videoChannel is a flat array, not true multi-track
- **CIImage-only rendering** -- No Metal compute pipeline, limiting performance for complex effects
- **No undo/redo** -- No command pattern or state management
- **No timeline UI** -- Pure composition engine, no visual editing
- **iOS-only** -- UIKit dependencies throughout (UIScreen.main.scale, UIImage)
- **No HDR color management** -- HDRVideoCompositor exists but is basic (just format change)

---

## 2. GPUImage3 (BradLarson/GPUImage3) -- Deep Architecture Analysis

**Repository**: https://github.com/BradLarson/GPUImage3 (2,858 stars)
**Purpose**: Metal-based GPU image/video processing pipeline
**Key Insight**: The gold-standard pattern for building composable GPU processing chains in Swift. The Source/Consumer pipeline with operator overloading is elegant and proven.

### 2.1 Complete Protocol/Class Hierarchy

```
Core Protocols (Pipeline.swift):
─────────────────────────────────
ImageSource
├── targets: TargetContainer          // Weak references to consumers
├── transmitPreviousImage(to:atIndex:)
└── Extension: addTarget(_:atIndex:) / removeAllTargets()
    └── updateTargetsWithTexture(_:)  // Broadcasts texture to all targets

ImageConsumer
├── sources: SourceContainer          // Strong references to sources
├── maximumInputs: UInt
└── newTextureAvailable(_:fromSourceIndex:)  // Receives new texture

ImageProcessingOperation: ImageSource & ImageConsumer
└── (Combines both -- a filter node in the pipeline)

Thread-Safe Containers:
───────────────────────
TargetContainer
├── targets: [UInt: (ImageConsumer, UInt)]  // index → (consumer, targetIndex)
├── dispatchQueue: DispatchQueue (serial)   // Thread safety
└── Weak references (auto-cleanup)

SourceContainer
├── sources: [UInt: ImageSource]            // sourceIndex → source
└── Strong references
```

```
Class Hierarchy:
────────────────
ImageSource implementations:
├── PictureInput             // CGImage/UIImage/NSImage → Texture
│   ├── Uses MTKTextureLoader for GPU upload
│   ├── processImage(synchronously:)
│   └── Caches texture after first load
│
├── Camera                   // AVCaptureSession → Texture
│   ├── YUV → RGB conversion via Metal shader
│   ├── CVMetalTextureCache (zero-copy GPU textures)
│   ├── frameRenderingSemaphore (backpressure)
│   └── Supports full-range and video-range YUV
│
├── MovieInput               // AVAssetReader → Texture
│   ├── YUV → RGB conversion (same as Camera)
│   ├── CVMetalTextureCache for zero-copy
│   ├── Actual-speed playback timing
│   └── Audio passthrough via AVAssetReaderTrackOutput
│
└── ImageRelay               // Passthrough node (used in OperationGroup)
    └── Simply forwards textures to targets

ImageConsumer implementations:
├── PictureOutput            // Texture → CGImage/UIImage/NSImage/Data
│   ├── onlyCaptureNextFrame: Bool
│   ├── imageAvailableCallback / encodedImageAvailableCallback
│   └── Supports PNG and JPEG output
│
├── MovieOutput              // Texture → AVAssetWriter (file)
│   ├── AVAssetWriterInputPixelBufferAdaptor
│   ├── CGContext-based texture → pixel buffer conversion
│   ├── startTime / previousFrameTime tracking
│   └── AudioEncodingTarget protocol for audio recording
│
└── RenderView (MTKView)     // Texture → Screen display
    ├── Renders directly to MTKView drawable
    └── Handles fillMode (preserveAspectRatio / stretch / etc.)

ImageProcessingOperation implementations:
├── BasicOperation           // Core filter base class (MOST IMPORTANT)
│   ├── renderPipelineState: MTLRenderPipelineState
│   ├── uniformSettings: ShaderUniformSettings
│   ├── textureInputSemaphore: DispatchSemaphore
│   ├── inputTextures: [UInt: Texture]
│   ├── useMetalPerformanceShaders: Bool
│   └── metalPerformanceShaderPathway: ((MTLCommandBuffer, [UInt:Texture], Texture) -> Void)?
│
├── OperationGroup           // Encapsulates sub-pipeline
│   ├── inputImageRelay: ImageRelay
│   ├── outputImageRelay: ImageRelay
│   └── configureGroup { input, output in ... }
│
└── 90+ built-in operations:
    ├── Color: Brightness, Contrast, Saturation, Exposure, RGB, Hue, Vibrance, WhiteBalance,
    │          Gamma, Levels, ColorMatrix, Highlights&Shadows, SepiaTone, Monochrome, FalseColor,
    │          Posterize, Solarize, ColorInversion, Luminance
    ├── Blur: GaussianBlur (MPS), BoxBlur, MotionBlur, ZoomBlur, TiltShift, MedianFilter
    ├── Edge: SobelEdgeDetection, PrewittEdgeDetection, Laplacian, Sketch, ThresholdSketch
    ├── Distortion: BulgeDistortion, PinchDistortion, SphereRefraction, GlassSphere,
    │               SwirlDistortion, StretchDistortion
    ├── Stylize: Crosshatch, HalfTone, PolkaDot, Pixellate, PolarPixellate, CGAColorspace,
    │            KuwaharaFilter, Toon, SmoothToon, Emboss, Vignette, Haze
    ├── Blend (2-input): Add, Alpha, ChromaKey, Color, ColorBurn, ColorDodge, Darken, Difference,
    │          Dissolve, Divide, Exclusion, HardLight, Hue, Lighten, LinearBurn, Luminosity,
    │          Multiply, Normal, Overlay, Saturation, Screen, SoftLight, SourceOver, Subtract
    ├── Threshold: LuminanceThreshold, AdaptiveThreshold, LuminanceRangeReduction
    └── LUT: LookupFilter (3D LUT via image texture)
```

### 2.2 Pipeline Data Flow

```
Source (Camera/MovieInput/PictureInput)
    │
    │ newTextureAvailable(texture, fromSourceIndex: 0)
    ▼
BasicOperation (Filter)
    │ 1. textureInputSemaphore.wait() -- thread safety
    │ 2. inputTextures[sourceIndex] = texture
    │ 3. If all inputs received (inputTextures.count == maximumInputs):
    │    a. Create outputTexture = Texture(device:, orientation:, width:, height:)
    │    b. commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer()
    │    c. commandBuffer.renderQuad(
    │         pipelineState: renderPipelineState,
    │         uniformSettings: uniformSettings,
    │         inputTextures: inputTextures,
    │         outputTexture: outputTexture
    │       )
    │    d. commandBuffer.commit()
    │    e. textureInputSemaphore.signal()
    │    f. updateTargetsWithTexture(outputTexture)
    │
    │ newTextureAvailable(outputTexture, fromSourceIndex: N)
    ▼
Consumer (RenderView/MovieOutput/PictureOutput)
    └── Process final texture (display/save/capture)
```

### 2.3 Core Rendering: `renderQuad()` (MetalRendering.swift)

This is the fundamental GPU rendering function:

```swift
// Simplified from MetalRendering.swift
func renderQuad(pipelineState: MTLRenderPipelineState,
                uniformSettings: ShaderUniformSettings?,
                inputTextures: [UInt: Texture],
                outputTexture: Texture) {

    let renderPass = MTLRenderPassDescriptor()
    renderPass.colorAttachments[0].texture = outputTexture.texture
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    renderPass.colorAttachments[0].storeAction = .store
    renderPass.colorAttachments[0].loadAction = .clear

    guard let renderEncoder = self.makeRenderCommandEncoder(descriptor: renderPass) else { return }
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setRenderPipelineState(pipelineState)

    // Set vertex buffer (quad vertices)
    renderEncoder.setVertexBuffer(
        sharedMetalRenderingDevice.standardImageVBO, offset: 0, index: 0)

    // Set texture coordinates based on orientation
    for (index, texture) in inputTextures {
        let textureCoordinates = texture.textureCoordinates(for: outputTexture.orientation)
        // Upload texture coordinate buffer
        renderEncoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1 + Int(index))
        renderEncoder.setFragmentTexture(texture.texture, index: Int(index))
    }

    // Set uniforms
    uniformSettings?.restoreShaderSettings(renderEncoder: renderEncoder)

    renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    renderEncoder.endEncoding()
}
```

### 2.4 Texture System (Texture.swift)

```swift
public class Texture {
    public var texture: MTLTexture                    // The actual GPU texture
    public var orientation: ImageOrientation           // Portrait/landscape/flipped
    public var timingStyle: TextureTimingStyle         // .stillImage or .videoFrame(timestamp)

    // Generates texture coordinates for all 8 rotation/flip variants
    // This solves the orientation mismatch between camera/video and display
    public func textureCoordinates(for outputRotation: ImageOrientation) -> [Float] {
        let inputRotation = self.orientation
        let rotationNeeded = inputRotation.rotationNeeded(for: outputRotation)
        // Returns appropriate vertex coordinates based on rotation enum
    }

    // Convert texture back to CGImage (for PictureOutput)
    public func cgImage() -> CGImage {
        // Uses color swizzle render pass (BGRA → RGBA) then reads bytes
    }
}

// Orientation handling is crucial for video:
public enum ImageOrientation {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    func rotationNeeded(for target: ImageOrientation) -> Rotation {
        // Complete lookup table for all 4x4 orientation combinations
    }
}

public enum Rotation {
    case noRotation, rotateCounterclockwise, rotateClockwise, rotate180
    case flipHorizontally, flipVertically
    case rotateClockwiseAndFlipVertically, rotateClockwiseAndFlipHorizontally

    func flipsDimensions() -> Bool  // Whether width/height swap
}
```

### 2.5 Shader Uniform System (ShaderUniformSettings.swift)

```swift
public class ShaderUniformSettings {
    private var uniformValues: [Float] = []                    // Raw bytes for uniform buffer
    private var uniformLookupTable: [String: (Int, MTLStructMember)] = [:]  // name → (offset, member)

    // Populated via Metal pipeline reflection at init:
    // generateRenderPipelineState() introspects the vertex function's
    // "uniform" argument to discover all uniform names, offsets, sizes

    // Subscript access by string name:
    public subscript(key: String) -> Float { set { ... } }
    public subscript(key: String) -> Color { set { ... } }
    public subscript(key: String) -> Position { set { ... } }
    public subscript(key: String) -> Matrix3x3 { set { ... } }
    // ... etc

    // Applied to render encoder:
    func restoreShaderSettings(renderEncoder: MTLRenderCommandEncoder) {
        // Copies uniformValues into vertex buffer at index 1
        renderEncoder.setVertexBytes(&uniformValues, length: bufferSize, index: 1)
    }
}
```

**Usage pattern in operations** (extremely clean):

```swift
// BrightnessAdjustment.swift -- Typical 1-input filter
public class BrightnessAdjustment: BasicOperation {
    public var brightness: Float = 0.0 {
        didSet { uniformSettings["brightness"] = brightness }
    }
    public init() {
        super.init(fragmentFunctionName: "brightnessFragment", numberOfInputs: 1)
        ({ brightness = 0.0 })()  // Trigger didSet to initialize uniform
    }
}

// ChromaKeyBlend.swift -- Typical 2-input blend
public class ChromaKeyBlend: BasicOperation {
    public var thresholdSensitivity: Float = 0.4 {
        didSet { uniformSettings["thresholdSensitivity"] = thresholdSensitivity }
    }
    public var smoothing: Float = 0.1 {
        didSet { uniformSettings["smoothing"] = smoothing }
    }
    public var colorToReplace: Color = Color.green {
        didSet { uniformSettings["colorToReplace"] = colorToReplace }
    }
    public init() {
        super.init(fragmentFunctionName: "chromaKeyBlendFragment", numberOfInputs: 2)
    }
}

// GaussianBlur.swift -- MPS pathway
public class GaussianBlur: BasicOperation {
    public var blurRadiusInPixels: Float = 2.0 {
        didSet {
            internalMPSImageGaussianBlur = MPSImageGaussianBlur(
                device: sharedMetalRenderingDevice.device, sigma: blurRadiusInPixels)
        }
    }
    public init() {
        super.init(fragmentFunctionName: "passthroughFragment")
        self.useMetalPerformanceShaders = true
        self.metalPerformanceShaderPathway = usingMPSImageGaussianBlur
    }
}

// LookupFilter.swift -- LUT via texture
public class LookupFilter: BasicOperation {
    public var intensity: Float = 1.0 { didSet { uniformSettings["intensity"] = intensity } }
    public var lookupImage: PictureInput? {
        didSet {
            lookupImage?.addTarget(self, atTargetIndex: 1)  // LUT as 2nd input texture
            lookupImage?.processImage()
        }
    }
    public init() {
        super.init(fragmentFunctionName: "lookupFragment", numberOfInputs: 2)
    }
}
```

### 2.6 Camera/Video Input Pipeline (Zero-Copy)

```
CVPixelBuffer (from camera/video frame)
    │
    │ CVMetalTextureCacheCreateTextureFromImage()  -- ZERO COPY to GPU
    ▼
CVMetalTexture → MTLTexture
    │
    │ For YUV input (camera/H.264 native):
    │ ├── Plane 0: luminance texture (r8Unorm, full width x height)
    │ ├── Plane 1: chrominance texture (rg8Unorm, half width x half height)
    │ └── convertYUVToRGB() -- Metal shader converts to RGB output texture
    │     Uses colorConversionMatrix601FullRange or colorConversionMatrix601Default
    │
    │ For BGRA input:
    │ └── Direct texture use (single plane)
    ▼
Texture (wrapped in GPUImage3 Texture class)
    │
    │ updateTargetsWithTexture()
    ▼
Processing pipeline...
```

### 2.7 Operator Chaining (`-->`)

```swift
// Pipeline.swift
precedencegroup ProcessingOperationPrecedence {
    associativity: left
}
infix operator -->: ProcessingOperationPrecedence

@discardableResult
public func --><T: ImageConsumer>(source: ImageSource, destination: T) -> T {
    source.addTarget(destination)
    return destination
}

// Usage:
let camera = try Camera(sessionPreset: .hd1920x1080)
let brightness = BrightnessAdjustment()
let saturation = SaturationAdjustment()
let renderView = RenderView()

camera --> brightness --> saturation --> renderView

// OperationGroup for reusable sub-pipelines:
let filterGroup = OperationGroup()
filterGroup.configureGroup { input, output in
    input --> brightness --> saturation --> output
}
camera --> filterGroup --> renderView
```

### 2.8 Reusable Patterns from GPUImage3

1. **Source/Consumer pipeline protocol** -- Composable, type-safe GPU processing chain
2. **`-->` operator** -- Elegant, readable pipeline construction
3. **TargetContainer weak references** -- Prevents retain cycles in pipeline
4. **Semaphore-based multi-input collection** -- Thread-safe waiting for all inputs
5. **CVMetalTextureCache zero-copy** -- Essential for real-time video performance
6. **YUV→RGB Metal shader** -- Required for native camera/H.264 format handling
7. **Reflection-based uniform management** -- ShaderUniformSettings discovers uniforms from Metal pipeline
8. **MPS fallback pathway** -- BasicOperation supports both custom shaders and Metal Performance Shaders
9. **Texture orientation system** -- Complete handling of all rotation/flip variants
10. **PlatformImageType typealias** -- Cross-platform UIImage/NSImage abstraction

### 2.9 Limitations and Gaps

- **No compute shaders** -- Only render pipeline (fragment/vertex), no MTLComputeCommandEncoder
- **Single command queue** -- Everything goes through `sharedMetalRenderingDevice.commandQueue`
- **Synchronous texture creation** -- Output textures allocated per-frame (could pool)
- **No HDR/wide color** -- Fixed to 8-bit formats
- **Singleton device** -- `sharedMetalRenderingDevice` makes testing harder
- **No timeline/composition** -- Pure filter pipeline, no multi-clip or time-based operations

---

## 3. mini-cut (fwcd/mini-cut) -- Deep Architecture Analysis

**Repository**: https://github.com/fwcd/mini-cut (86 stars)
**Purpose**: Complete NLE implementation (WWDC 2021 Swift Student Challenge winner)
**Key Insight**: The only open-source Swift project that implements a complete NLE with multi-track timeline, drag-n-drop, trimming, inspector, and video preview -- all within a Swift Playground using SpriteKit.

### 3.1 Complete Model/ViewModel/View Hierarchy

```
Model Layer:
────────────
Library
└── clips: [Clip]

Timeline
├── tracks: [Track]
├── maxOffset: TimeInterval    // Total timeline duration
└── playingClips(at:) → [(trackId, clip, zIndex)]

Track
├── clips: [UUID: OffsetClip]   // UUID-keyed for O(1) access
├── name: String, isMuted: Bool, isSolo: Bool
├── subscript[clipId] → OffsetClip?
└── cut(clipId:at:) → (leftId, rightId)  // Split clip at time

OffsetClip (Identifiable)
├── offset: TimeInterval       // Position on timeline
├── clip: Clip
├── clipOffset(for cursor:) → TimeInterval  // Convert timeline time to clip time
└── isPlaying(at:) → Bool

Clip
├── id: UUID, name: String, color: Color
├── content: ClipContent
├── start: TimeInterval, length: TimeInterval
├── volume: Double
├── Visual properties: visualScale, visualAlpha, visualOffsetDx, visualOffsetDy
└── category: ClipCategory (.video/.audio/.other)

ClipContent (enum)
├── .audiovisual(AudiovisualContent)  // AVAsset wrapper
├── .text(TextContent)                // Text overlay with font, size, color
├── .image(ImageContent)              // Static image (unused in practice)
└── .color(ColorContent)              // Solid color block
```

```
ViewModel Layer:
────────────────
MiniCutState (central observable state)
├── library: Library                     + libraryDidChange: ListenerList<Library>
├── timeline: Timeline                   + timelineDidChange: ListenerList<Timeline>
├── cursor: TimeInterval                 + cursorDidChange: ListenerList<TimeInterval>
├── selection: Selection?                + selectionDidChange: ListenerList<Selection?>
├── timelineZoom: CGFloat                + timelineZoomDidChange: ListenerList<CGFloat>
├── timelineOffset: TimeInterval         + timelineOffsetDidChange: ListenerList<TimeInterval>
├── isPlaying: Bool                      + isPlayingDidChange: ListenerList<Bool>
└── subscript[trackId] → Track?          (convenience access)

Selection
├── trackId: UUID
└── clipId: UUID
```

```
View Layer (all SpriteKit-based):
─────────────────────────────────
MiniCutScene (SKScene)
├── VideoView                            // Composited video preview
│   ├── videoClipNodes: [UUID: VideoClipView]
│   ├── Playback via SKAction.repeatForever
│   ├── diffUpdate() for efficient view recycling
│   └── Handles clip dragging/resizing in preview
│
├── LibraryView                          // Media browser sidebar
│   ├── LibraryClipsView                 // Dynamic clips from library
│   │   └── LibraryClipView (DragSource) // Draggable clip thumbnails
│   └── LibraryStaticClipsView           // Built-in generators (text, color)
│
├── InspectorView                        // Property inspector sidebar
│   └── InspectorClipView               // Per-clip property form
│       ├── For .text: Text field + Size slider
│       ├── For .audiovisual: Volume slider
│       └── For all: X, Y, Scale, Alpha sliders
│
├── Toolbar                              // Play/pause, cut, add track
│   └── Button nodes
│
└── TimelineView (DropTarget)            // Multi-track timeline
    ├── TrackView[]                      // Individual tracks
    │   ├── TrackControlsView            // Name, mute/solo buttons
    │   └── TrackClipView[]              // Clip rectangles with trim handles
    │       ├── TrimHandle (left/right)
    │       └── Thumbnail + label
    ├── TimelineCursor                   // Playhead line
    ├── TimelineMark[]                   // Time markers
    └── DragState machine:
        ├── .scrolling(startPoint, startOffset)
        ├── .cursor(startPoint, startCursor)
        ├── .clip(clipId, trackId, startOffset, startPoint)
        ├── .trimming(TrackClipView)
        └── .inactive
```

### 3.2 Bijection Coordinate Transform System

This is mini-cut's most elegant pattern -- type-safe, composable coordinate transforms:

```swift
// Bijection.swift -- Core protocol
protocol Bijection {
    associatedtype Input
    associatedtype Output
    func apply(_ value: Input) -> Output
    func inverseApply(_ value: Output) -> Input
}

// ComposedBijection.swift -- Composition
struct ComposedBijection<Outer, Inner>: Bijection
    where Outer: Bijection, Inner: Bijection, Inner.Output == Outer.Input {
    let outer: Outer
    let inner: Inner
    func apply(_ value: Inner.Input) -> Outer.Output {
        outer.apply(inner.apply(value))
    }
    func inverseApply(_ value: Outer.Output) -> Inner.Input {
        inner.inverseApply(outer.inverseApply(value))
    }
}

// Scaling.swift -- Linear scaling bijection
struct Scaling<Value: Scalable>: Bijection {
    let factor: Value.Factor
    func apply(_ value: Value) -> Value { value * factor }
    func inverseApply(_ value: Value) -> Value { value / factor }
}

// Translation.swift -- Offset bijection
struct Translation<Value: Translatable>: Bijection {
    let offset: Value.Offset
    func apply(_ value: Value) -> Value { value + offset }
    func inverseApply(_ value: Value) -> Value { value - offset }
}

// Operator overloads enable algebraic composition:
extension Bijection where Output: Scalable {
    static func *(lhs: Self, rhs: Output.Factor) -> ComposedBijection<Scaling<Output>, Self>
    static func /(lhs: Self, rhs: Output.Factor) -> ComposedBijection<InverseScaling<Output>, Self>
}
extension Bijection where Output: Translatable {
    static func +(lhs: Self, rhs: Output.Offset) -> ComposedBijection<Translation<Output>, Self>
    static func -(lhs: Self, rhs: Output.Offset) -> ComposedBijection<InverseTranslation<Output>, Self>
}
```

**Usage in TimelineView** (the payoff):

```swift
// TrackClipView.swift -- Time ↔ Pixel coordinate conversion
private var toViewScale: AnyBijection<TimeInterval, CGFloat> {
    Scaling(factor: state.timelineZoom)
        .then(AnyBijection(CGFloat.init(_:), TimeInterval.init(_:)))
        .erase()
}
private var toViewX: AnyBijection<TimeInterval, CGFloat> {
    (toViewScale + (ViewDefaults.trackControlsWidth - (parentWidth / 2)
        - toViewScale.apply(state.timelineOffset))).erase()
}

// Convert time to pixel X:
let pixelX = toViewX.apply(clip.offset)

// Convert pixel X back to time:
let time = toViewX.inverseApply(mouseX)

// Convert pixel width to duration:
let duration = toViewScale.inverseApply(pixelWidth)
```

### 3.3 Pub-Sub State Management (ListenerList)

```swift
// ListenerList.swift
class ListenerList<Event> {
    private var listeners: [UUID: (Event) -> Void] = [:]
    private var recursivelyInvoked = Set<UUID>()   // Prevents infinite loops
    private var silenced = Set<UUID>()             // Prevents echo during programmatic updates

    func subscribe(_ listener: @escaping (Event) -> Void) -> Subscription
    func subscribeFiring(_ event: Event, _ listener: @escaping (Event) -> Void) -> Subscription
    func silencing(_ subscription: Subscription?, _ action: () -> Void)
    func fire(_ event: Event)
}

// Subscription.swift -- RAII cleanup
class Subscription: Identifiable {
    let id: UUID
    private let handleEnd: () -> Void
    deinit { handleEnd() }  // Auto-unsubscribe when dropped
}
```

**Usage pattern** -- silencing prevents update loops:

```swift
// InspectorClipView.swift
Slider(value: clip.visualScale, range: 0..<4, width: $0) { [weak self] scale in
    // Silence the clip subscription while we update to prevent loop:
    state.timelineDidChange.silencing(self?.clipSubscription) {
        self?.clip?.clip.visualScale = scale
    }
}
```

### 3.4 Drag-and-Drop System

```swift
// DragNDropController.swift -- SpriteKit-based D&D
final class DragNDropController {
    private var nodes: [UUID: SKNode] = [:]  // All registered drag sources and drop targets
    private var inFlight: Any? = nil         // Currently dragged value (type-erased)
    private var hoverNode: SKNode? = nil     // Visual hover indicator

    func register<N: SKNode & DragSource>(source node: N) -> Subscription
    func register<N: SKNode & DropTarget>(target node: N) -> Subscription

    func handleInputDown(at:) -> Bool     // Start drag from DragSource
    func handleInputDragged(to:) -> Bool  // Track hover, notify DropTargets
    func handleInputUp(at:) -> Bool       // Complete drop on DropTarget
}

// DragSource.swift
protocol DragSource {
    var draggableValue: Any { get }       // Value to transfer
    func makeHoverNode() -> SKNode        // Visual during drag
}

// DropTarget.swift
protocol DropTarget {
    func onHover(value: Any, at: CGPoint)
    func onUnHover(value: Any, at: CGPoint)
    func onDrop(value: Any, at: CGPoint)
}
```

### 3.5 Timeline DragState Machine

```swift
// TimelineView.swift
private enum DragState {
    case scrolling(startPoint: CGPoint, startOffset: TimeInterval)
    case cursor(startPoint: CGPoint, startCursor: TimeInterval)
    case clip(clipId: UUID, trackId: UUID, startOffset: TimeInterval, startPoint: CGPoint)
    case trimming(TrackClipView)
    case inactive
}

// State transitions on input events:
func inputDown(at point: CGPoint) {
    if dndController.handleInputDown(at: point) { return }  // D&D takes priority

    for trackView in trackViews.values {
        if let clipView = trackView.clipAt(point) {
            clipView.tryBeginTrimming(at: point)
            if clipView.isTrimming {
                dragState = .trimming(clipView)
            } else {
                dragState = .clip(clipId: ..., trackId: ..., ...)
            }
            return
        }
    }

    if isInTimecodeArea(point) {
        dragState = .cursor(startPoint: point, startCursor: state.cursor)
    } else {
        dragState = .scrolling(startPoint: point, startOffset: state.timelineOffset)
    }
}
```

### 3.6 Efficient View Diffing

```swift
// ViewUtils.swift
extension SKNode {
    func diffUpdate<N: SKNode, I: Identifiable>(
        nodes: inout [I.ID: N],
        with items: [I],
        using factory: (I) -> N
    ) {
        let itemDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let nodeIds = Set(nodes.keys)
        let itemIds = Set(itemDict.keys)
        let removedIds = nodeIds.subtracting(itemIds)
        let addedIds = itemIds.subtracting(nodeIds)

        for id in removedIds {
            nodes[id]!.removeFromParent()
            nodes[id] = nil
        }
        for id in addedIds {
            let node = factory(itemDict[id]!)
            nodes[id] = node
            addChild(node)
        }
    }
}
```

### 3.7 Playback System

```swift
// VideoView.swift -- Playback via SpriteKit actions
isPlayingSubscription = state.isPlayingDidChange.subscribeFiring(state.isPlaying) {
    if $0 {
        startDate = Date()
        startCursor = state.cursor

        // Repeat: advance cursor based on wall clock time
        run(.repeatForever(.sequence([
            .run {
                state.cursor = startCursor! - startDate!.timeIntervalSinceNow
            },
            .wait(forDuration: 0.1)  // 10 FPS cursor update
        ])), withKey: cursorActionKey)
    } else {
        removeAction(forKey: cursorActionKey)
    }
}

// VideoClipView.swift -- Per-clip AVPlayer
let player = AVPlayer(playerItem: AVPlayerItem(asset: content.asset))
let video = SKVideoNode(avPlayer: player)

// Sync player position to cursor:
cursorSubscription = state.cursorDidChange.subscribeFiring(state.cursor) {
    let clipOffset = clip.clipOffset(for: state.cursor)
    player.seek(to: CMTime(seconds: clipOffset, preferredTimescale: 1000))
}

// Play/pause sync:
isPlayingSubscription = state.isPlayingDidChange.subscribeFiring(state.isPlaying) {
    if $0 {
        player.volume = Float(clip.clip.volume)
        player.play()
    } else {
        player.pause()
    }
}
```

### 3.8 Reusable Patterns from mini-cut

1. **Bijection coordinate transforms** -- Type-safe, composable time<->pixel mapping with inverse
2. **ListenerList pub-sub** -- Lightweight reactive state with auto-cleanup via Subscription
3. **Silencing pattern** -- Prevents update loops when programmatically setting values
4. **DragState enum machine** -- Clean multimodal input handling
5. **diffUpdate()** -- Efficient O(n) view reconciliation by ID
6. **LRUCache** -- Thumbnail caching with eviction
7. **UUID-keyed clips dictionary** -- O(1) clip lookup in tracks
8. **Corner enum for resize handles** -- 8-way direction vectors for resize operations
9. **SKNode position extensions** -- topLeft/centerRight/etc. computed properties
10. **Subscription RAII** -- Auto-unsubscribe on dealloc prevents stale listeners

### 3.9 Limitations and Gaps

- **SpriteKit rendering** -- Not suitable for production NLE (no hardware acceleration for video compositing)
- **SKVideoNode per clip** -- Each visible clip creates an AVPlayer (no shared composition)
- **No AVFoundation composition** -- Playback is multiple independent AVPlayers, not a single AVPlayerItem
- **No export** -- Cannot render to file
- **No effects/transitions** -- Pure cut editing only
- **No undo/redo** -- Direct state mutation without command history
- **10 FPS cursor updates** -- Coarse playback timing
- **iPad-only** -- Built for Swift Playgrounds
- **No audio waveforms** -- Tracks show solid color blocks only

---

## 4. Cross-Project Architecture Comparison

### 4.1 Timeline Model

| Aspect | Cabbage | GPUImage3 | mini-cut |
|--------|---------|-----------|----------|
| Model | Timeline class | N/A | Timeline struct |
| Tracks | Single videoChannel array | N/A | Multi-track dictionary |
| Clips | TrackItem class | N/A | Clip struct + OffsetClip |
| Resources | Resource class hierarchy | MovieInput/PictureInput | ClipContent enum |
| Transitions | VideoTransition protocol | Blend operations | None |
| Time representation | CMTime | Timestamp (Double) | TimeInterval |
| Mutability | Reference types (class) | Reference types (class) | Value types (struct) |

### 4.2 Rendering Pipeline

| Aspect | Cabbage | GPUImage3 | mini-cut |
|--------|---------|-----------|----------|
| Compositor | AVVideoCompositing | Metal render pipeline | SKVideoNode (SpriteKit) |
| Image type | CIImage | MTLTexture (via Texture) | N/A |
| GPU usage | CIContext (implicit Metal) | Direct Metal | SpriteKit (implicit Metal) |
| Frame delivery | AVPlayer callback | Source→Consumer chain | AVPlayer per-clip |
| Effect chain | CIFilter + provider protocol | BasicOperation chain | None |

### 4.3 State Management

| Aspect | Cabbage | GPUImage3 | mini-cut |
|--------|---------|-----------|----------|
| Pattern | None (composition-only) | None (processing-only) | Pub-sub ListenerList |
| Reactivity | N/A | N/A | subscribeFiring + silencing |
| Thread safety | Dispatch queues | Semaphores + serial queues | Main thread only |
| Undo/redo | None | None | None |

---

## 5. Synthesis: Building Blocks for Our NLE

### 5.1 What to Take from Each Project

**From Cabbage** (composition engine):
- Protocol hierarchy: VideoProvider, AudioProvider, TransitionableVideoProvider
- CompositionGenerator pattern: Timeline → AVComposition + AVVideoComposition + AVAudioMix
- Custom VideoCompositor (AVVideoCompositing) for CIImage-based rendering
- Track ID recycling for AVFoundation's track limit
- Keyframe animation system (KeyframeVideoConfiguration)
- Audio pipeline: MTAudioProcessingTap → AudioProcessingChain → AudioProcessingNode
- Transition protocol and built-in implementations
- TimingFunctionFactory easing library

**From GPUImage3** (GPU processing):
- Source/Consumer pipeline protocol design
- `-->` operator for pipeline construction
- BasicOperation as the base filter class with uniform management
- CVMetalTextureCache zero-copy video frame to GPU texture
- YUV → RGB conversion via Metal shader
- ShaderUniformSettings reflection-based uniform discovery
- Texture orientation handling system
- MPS fallback pathway for complex operations (blur, etc.)

**From mini-cut** (NLE UI/UX):
- Bijection coordinate transform system (time ↔ pixel)
- ListenerList pub-sub with silencing pattern
- DragState enum machine for multimodal input
- diffUpdate() efficient view reconciliation
- Trim handle interaction pattern
- Inspector property editing with two-way binding
- Drag-and-drop from library to timeline
- Subscription RAII auto-cleanup pattern

### 5.2 Architecture Gaps None of These Projects Solve

1. **Multi-track AVFoundation composition** -- Cabbage is single-channel; mini-cut uses multiple AVPlayers
2. **Metal compute shaders** -- GPUImage3 only uses render pipeline, not compute
3. **Undo/redo** -- No project implements command pattern or state snapshots
4. **Audio waveform rendering** -- No project renders waveforms from audio data
5. **Thumbnail generation pipeline** -- No efficient background thumbnail strip generation
6. **Clip speed/reverse** -- Cabbage has basic scaledDuration; no reverse playback
7. **Color management / HDR workflow** -- Basic HDR format support in Cabbage only
8. **Project serialization** -- No project implements save/load of editing projects
9. **macOS-native UI** -- No project uses AppKit or SwiftUI on macOS
10. **Multi-format timeline** -- No project handles mixed frame rates/resolutions well

### 5.3 Recommended Architecture for Our NLE

Based on this analysis, the recommended architecture combines all three:

```
Our NLE Architecture:
═════════════════════

┌─ SwiftUI App Layer ───────────────────────────────────────┐
│  AppKit window management, menus, keyboard shortcuts       │
│  SwiftUI views for inspector, library, toolbar             │
└────────────┬──────────────────────────────────────────────┘
             │
┌─ Timeline UI Layer (from mini-cut patterns) ──────────────┐
│  Bijection coordinate transforms (time ↔ pixel)           │
│  DragState machine for timeline interaction                │
│  diffUpdate() for efficient clip view management           │
│  TrimHandle, ResizeHandle interaction patterns             │
│  NSView/CALayer-based (not SpriteKit)                      │
└────────────┬──────────────────────────────────────────────┘
             │
┌─ State Management Layer ──────────────────────────────────┐
│  ListenerList pub-sub (from mini-cut) OR Combine/Observation│
│  Command pattern for undo/redo (not in any project)        │
│  Project model: Timeline > Track[] > Clip[] > Resource     │
│  Silencing pattern to prevent update loops                 │
└────────────┬──────────────────────────────────────────────┘
             │
┌─ Composition Engine (from Cabbage patterns) ──────────────┐
│  Protocol hierarchy: VideoProvider, AudioProvider, etc.    │
│  CompositionGenerator: Timeline → AVComposition pipeline   │
│  Custom AVVideoCompositing for frame-level rendering       │
│  Transition system with protocol + built-in library        │
│  Keyframe animation with timing functions                  │
│  Track ID recycling for AVFoundation limits                │
└────────────┬──────────────────────────────────────────────┘
             │
┌─ GPU Processing Layer (from GPUImage3 patterns) ──────────┐
│  Source/Consumer pipeline with --> operator                 │
│  Metal render + compute pipeline for effects               │
│  CVMetalTextureCache zero-copy frame handling              │
│  ShaderUniformSettings for filter parameters               │
│  BasicOperation base class for all filters                 │
│  YUV/HDR color space handling                              │
└────────────┬──────────────────────────────────────────────┘
             │
┌─ Audio Engine (from Cabbage + gaps) ──────────────────────┐
│  MTAudioProcessingTap for real-time processing             │
│  AudioProcessingChain with pluggable nodes                 │
│  vDSP-based volume mixing (Accelerate framework)           │
│  Waveform generation (NOT in any project - must build)     │
└───────────────────────────────────────────────────────────┘
```

---

## 6. Key Code Snippets Worth Preserving

### 6.1 Cabbage: Track ID Recycling

```swift
// CompositionGenerator.swift
// AVFoundation has a practical limit of ~16 tracks
// Cabbage recycles track IDs by maintaining pools:
var mainVideoTrackIDs: [Int32] = []
var mainAudioTrackIDs: [Int32] = []

// When building composition tracks, it cycles through available IDs
// and reuses tracks that are no longer in use at the current time
```

### 6.2 GPUImage3: Zero-Copy Video Frame to GPU

```swift
// Camera.swift / MovieInput.swift
var videoTextureCache: CVMetalTextureCache?
CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)

// Per frame:
var luminanceTextureRef: CVMetalTexture? = nil
CVMetalTextureCacheCreateTextureFromImage(
    kCFAllocatorDefault, videoTextureCache!, pixelBuffer, nil,
    .r8Unorm, width, height, 0, &luminanceTextureRef)
let luminanceTexture = CVMetalTextureGetTexture(luminanceTextureRef!)
// Now luminanceTexture is an MTLTexture backed by the same memory -- zero copy
```

### 6.3 mini-cut: Bijection Time-to-Pixel

```swift
// Composable coordinate transform:
let toViewScale = Scaling(factor: zoom)
    .then(AnyBijection(CGFloat.init(_:), TimeInterval.init(_:)))
    .erase()
let toViewX = (toViewScale + (controlsWidth - (parentWidth / 2)
    - toViewScale.apply(offset))).erase()

// Forward: time → pixel
let px = toViewX.apply(clipTime)
// Inverse: pixel → time
let time = toViewX.inverseApply(mouseX)
// Scale only: duration → width
let width = toViewScale.apply(clipDuration)
```

### 6.4 Cabbage: CIImage Effect Chain

```swift
// VideoConfiguration applies effects in sequence:
func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage {
    var finalImage = sourceImage

    // 1. Apply content mode transform (aspectFit/aspectFill)
    let transform = CGAffineTransform.transform(by: sourceImage.extent.size,
                                                 aspectFitInSize: renderSize)
    finalImage = finalImage.transformed(by: transform)

    // 2. Apply custom transform
    if let customTransform = self.transform {
        finalImage = finalImage.transformed(by: customTransform)
    }

    // 3. Apply opacity
    if opacity < 1.0 {
        finalImage = finalImage.apply(alpha: CGFloat(opacity))
    }

    // 4. Chain through configuration protocols
    for config in configurations {
        finalImage = config.applyEffect(to: finalImage, at: time, renderSize: renderSize)
    }

    return finalImage
}
```
