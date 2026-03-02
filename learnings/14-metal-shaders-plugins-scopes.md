# Metal Shader Library Design, Plugin Systems, Scopes & Text Rendering

## Table of Contents
1. [Shader Library Architecture](#1-shader-library-architecture)
2. [Shader Compilation Pipeline](#2-shader-compilation-pipeline)
3. [Function Constants & Specialization](#3-function-constants--specialization)
4. [Metal Dynamic Libraries](#4-metal-dynamic-libraries)
5. [MTLBinaryArchive for Pipeline Caching](#5-mtlbinaryarchive-for-pipeline-caching)
6. [Custom Effect Plugin System Design](#6-custom-effect-plugin-system-design)
7. [Plugin Parameter Declaration System](#7-plugin-parameter-declaration-system)
8. [FxPlug (Apple's Plugin Architecture Reference)](#8-fxplug-apples-plugin-architecture-reference)
9. [Node-Based Compositing Graph](#9-node-based-compositing-graph)
10. [Render Graph Implementation](#10-render-graph-implementation)
11. [Real-Time Video Scopes Overview](#11-real-time-video-scopes-overview)
12. [Histogram Compute Shader](#12-histogram-compute-shader)
13. [Waveform Monitor Compute Shader](#13-waveform-monitor-compute-shader)
14. [RGB Parade Compute Shader](#14-rgb-parade-compute-shader)
15. [Vectorscope Compute Shader](#15-vectorscope-compute-shader)
16. [Scope Visualization Renderer](#16-scope-visualization-renderer)
17. [Text Rendering Approaches](#17-text-rendering-approaches)
18. [CoreGraphics to Metal Text Rendering](#18-coregraphics-to-metal-text-rendering)
19. [Signed Distance Field Text Rendering](#19-signed-distance-field-text-rendering)
20. [Animated Titles & Lower Thirds](#20-animated-titles--lower-thirds)
21. [Complete Architecture Integration](#21-complete-architecture-integration)

---

## 1. Shader Library Architecture

### File Organization for 50+ Shaders

Organize Metal shaders by category, mirroring the logical effect grouping users see in the UI:

```
Shaders/
├── Common/
│   ├── ShaderTypes.h              // Shared structs between Swift and MSL
│   ├── VertexShaders.metal        // oneInputVertex, twoInputVertex, transformVertex
│   ├── ColorSpaceUtils.metal      // YUV/RGB conversion, BT.601/709/2020
│   └── MathUtils.metal            // clamp, remap, smoothstep helpers
├── ColorCorrection/
│   ├── Brightness.metal
│   ├── Contrast.metal
│   ├── Saturation.metal
│   ├── Exposure.metal
│   ├── WhiteBalance.metal
│   ├── Levels.metal
│   ├── Curves.metal
│   ├── HueSaturation.metal
│   └── LUTLookup.metal
├── Blur/
│   ├── GaussianBlur.metal
│   ├── BoxBlur.metal
│   ├── MotionBlur.metal
│   ├── RadialBlur.metal
│   └── ZoomBlur.metal
├── Keying/
│   ├── ChromaKey.metal
│   ├── LumaKey.metal
│   └── DifferenceKey.metal
├── Blend/
│   ├── NormalBlend.metal
│   ├── MultiplyBlend.metal
│   ├── ScreenBlend.metal
│   ├── OverlayBlend.metal
│   ├── AddBlend.metal
│   └── SourceOverBlend.metal
├── Distortion/
│   ├── BulgeDistortion.metal
│   ├── PinchDistortion.metal
│   ├── SwirlDistortion.metal
│   └── WaveDistortion.metal
├── Stylize/
│   ├── Pixellate.metal
│   ├── Posterize.metal
│   ├── Vignette.metal
│   ├── Sharpen.metal
│   └── EdgeDetect.metal
├── Transitions/
│   ├── CrossDissolve.metal
│   ├── DiagonalWipe.metal
│   ├── PushSlide.metal
│   └── LumaWipe.metal
├── Generate/
│   ├── SolidColor.metal
│   ├── Gradient.metal
│   ├── Checkerboard.metal
│   └── Noise.metal
├── Scopes/
│   ├── Histogram.metal
│   ├── Waveform.metal
│   ├── Vectorscope.metal
│   └── RGBParade.metal
└── Text/
    └── SDFText.metal
```

### Shared Types Header (ShaderTypes.h)

This header is shared between Swift and Metal code via a bridging header:

```metal
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Vertex I/O for single-texture effects
struct SingleInputVertexIO {
    simd_float4 position;     // [[position]]
    simd_float2 texCoord;     // [[user(texturecoord)]]
};

// Vertex I/O for two-texture effects (blends, transitions)
struct TwoInputVertexIO {
    simd_float4 position;
    simd_float2 texCoord;
    simd_float2 texCoord2;
};

// Per-frame rendering uniforms
struct RenderUniforms {
    simd_float4x4 transform;
    float opacity;
    float time;              // For animated effects
    float aspectRatio;
    float pad;               // 16-byte alignment
};

// Color correction parameters
struct ColorCorrectionUniforms {
    float brightness;    // -1.0 to 1.0
    float contrast;      // 0.0 to 4.0
    float saturation;    // 0.0 to 2.0
    float exposure;      // -10.0 to 10.0
    float temperature;   // white balance
    float tint;
    float highlights;
    float shadows;
};

// Histogram / scope output
struct ScopeData {
    uint bins[256];
};

// Effect parameter metadata (used by plugin system)
enum ParameterType : uint {
    ParameterTypeFloat  = 0,
    ParameterTypeColor  = 1,
    ParameterTypePoint  = 2,
    ParameterTypeInt    = 3,
    ParameterTypeBool   = 4,
};

#endif
```

### Metal Library Loading Patterns

```swift
class ShaderLibraryManager {
    let device: MTLDevice
    private var libraries: [String: MTLLibrary] = [:]
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var computeCache: [String: MTLComputePipelineState] = [:]

    init(device: MTLDevice) {
        self.device = device
        // Load default library from app bundle
        if let defaultLib = device.makeDefaultLibrary() {
            libraries["default"] = defaultLib
        }
    }

    /// Load a .metallib from a URL (for plugins or dynamic loading)
    func loadLibrary(from url: URL, name: String) throws {
        let library = try device.makeLibrary(URL: url)
        libraries[name] = library
    }

    /// Load a library from compiled source at runtime
    func compileLibrary(source: String, name: String) throws {
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        let library = try device.makeLibrary(source: source, options: options)
        libraries[name] = library
    }

    /// Get or create a render pipeline state (cached)
    func renderPipeline(
        vertex: String,
        fragment: String,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        blendingEnabled: Bool = false,
        libraryName: String = "default"
    ) throws -> MTLRenderPipelineState {
        let key = "\(libraryName)/\(vertex)/\(fragment)/\(pixelFormat.rawValue)/\(blendingEnabled)"

        if let cached = pipelineCache[key] {
            return cached
        }

        guard let library = libraries[libraryName] else {
            throw ShaderError.libraryNotFound(libraryName)
        }
        guard let vertexFn = library.makeFunction(name: vertex) else {
            throw ShaderError.functionNotFound(vertex)
        }
        guard let fragmentFn = library.makeFunction(name: fragment) else {
            throw ShaderError.functionNotFound(fragment)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        if blendingEnabled {
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        let state = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelineCache[key] = state
        return state
    }

    /// Get or create a compute pipeline state (cached)
    func computePipeline(
        function: String,
        libraryName: String = "default"
    ) throws -> MTLComputePipelineState {
        let key = "\(libraryName)/\(function)"

        if let cached = computeCache[key] {
            return cached
        }

        guard let library = libraries[libraryName] else {
            throw ShaderError.libraryNotFound(libraryName)
        }
        guard let fn = library.makeFunction(name: function) else {
            throw ShaderError.functionNotFound(function)
        }

        let state = try device.makeComputePipelineState(function: fn)
        computeCache[key] = state
        return state
    }

    enum ShaderError: Error {
        case libraryNotFound(String)
        case functionNotFound(String)
    }
}
```

---

## 2. Shader Compilation Pipeline

### Build-Time Compilation (.metal -> .air -> .metallib)

```bash
# Step 1: Compile .metal source files to AIR (Apple Intermediate Representation)
xcrun -sdk macosx metal -c Brightness.metal -o Brightness.air
xcrun -sdk macosx metal -c Contrast.metal -o Contrast.air
xcrun -sdk macosx metal -c Saturation.metal -o Saturation.air

# Step 2: Create a metal archive from AIR files
xcrun -sdk macosx metal-ar rcs ColorEffects.metalar \
    Brightness.air Contrast.air Saturation.air

# Step 3: Build the final metallib
xcrun -sdk macosx metallib ColorEffects.metalar -o ColorEffects.metallib

# Alternative: Direct compilation (skip archive step)
xcrun -sdk macosx metal \
    Brightness.metal Contrast.metal Saturation.metal \
    -o ColorEffects.metallib
```

### Loading a Pre-Compiled metallib at Runtime

```swift
// Load from app bundle
let url = Bundle.main.url(forResource: "ColorEffects", withExtension: "metallib")!
let library = try device.makeLibrary(URL: url)

// Load from an arbitrary path (plugins)
let pluginURL = URL(fileURLWithPath: "/path/to/plugin/Effects.metallib")
let pluginLibrary = try device.makeLibrary(URL: pluginURL)
```

### Runtime Compilation from Source

```swift
// Compile Metal source code at runtime (slower but enables hot-reload)
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

fragment half4 customEffect(
    SingleInputVertexIO in [[stage_in]],
    texture2d<half> tex [[texture(0)]],
    constant float &param [[buffer(0)]]
) {
    constexpr sampler s;
    half4 color = tex.sample(s, in.textureCoordinate);
    return half4(color.rgb * half(param), color.a);
}
"""

let options = MTLCompileOptions()
options.fastMathEnabled = true
options.languageVersion = .version3_1

let library = try device.makeLibrary(source: shaderSource, options: options)
```

### Shared Headers Between Swift and Metal

Use `#ifdef __METAL_VERSION__` to share structs:

```c
// SharedTypes.h - included by both Swift (via bridging header) and .metal files
#ifdef __METAL_VERSION__
// Metal-only code
#include <metal_stdlib>
using namespace metal;
#else
// Swift/C/ObjC-only code
#include <simd/simd.h>
#endif

struct EffectUniforms {
    simd_float4x4 transform;
    float brightness;
    float contrast;
    float saturation;
    float exposure;
};
```

---

## 3. Function Constants & Specialization

Function constants allow compiling a single "uber-shader" and then specializing it at pipeline creation time. Dead code from disabled features is eliminated by the compiler.

### Metal Shader with Function Constants

```metal
#include <metal_stdlib>
using namespace metal;

// Declare function constants
constant bool HAS_COLOR_CORRECTION [[function_constant(0)]];
constant bool HAS_BLUR            [[function_constant(1)]];
constant bool HAS_VIGNETTE        [[function_constant(2)]];
constant bool HAS_LUT             [[function_constant(3)]];
constant int  BLUR_KERNEL_SIZE    [[function_constant(4)]];

struct EffectParams {
    float brightness;
    float contrast;
    float saturation;
    float vignetteStrength;
    float vignetteRadius;
    float lutIntensity;
    float blurRadius;
};

fragment half4 universalEffectFragment(
    SingleInputVertexIO fragmentInput [[stage_in]],
    texture2d<half> inputTexture [[texture(0)]],
    texture2d<half> lutTexture [[texture(1)]],    // Only used if HAS_LUT
    constant EffectParams& params [[buffer(0)]]
) {
    constexpr sampler s;
    half4 color = inputTexture.sample(s, fragmentInput.textureCoordinate);

    // These branches are eliminated at compile time when the constant is false
    if (HAS_COLOR_CORRECTION) {
        // Brightness
        color.rgb += half(params.brightness);
        // Contrast
        color.rgb = (color.rgb - half3(0.5)) * half(params.contrast) + half3(0.5);
        // Saturation
        half lum = dot(color.rgb, half3(0.2125, 0.7154, 0.0721));
        color.rgb = mix(half3(lum), color.rgb, half(params.saturation));
    }

    if (HAS_BLUR) {
        // Simplified box blur using function constant for kernel size
        half4 blurAccum = half4(0.0);
        float2 texelSize = float2(1.0 / inputTexture.get_width(),
                                   1.0 / inputTexture.get_height());
        int halfSize = BLUR_KERNEL_SIZE / 2;
        for (int y = -halfSize; y <= halfSize; y++) {
            for (int x = -halfSize; x <= halfSize; x++) {
                float2 offset = float2(x, y) * texelSize * params.blurRadius;
                blurAccum += inputTexture.sample(s, fragmentInput.textureCoordinate + offset);
            }
        }
        color = blurAccum / half(BLUR_KERNEL_SIZE * BLUR_KERNEL_SIZE);
    }

    if (HAS_VIGNETTE) {
        float2 uv = fragmentInput.textureCoordinate;
        float dist = distance(uv, float2(0.5));
        float vignette = smoothstep(params.vignetteRadius, params.vignetteRadius - 0.3, dist);
        color.rgb *= half(mix(1.0 - params.vignetteStrength, 1.0, vignette));
    }

    if (HAS_LUT) {
        // LUT lookup (abbreviated - see full version in 02-metal-rendering-pipeline.md)
        half blueColor = color.b * 63.0h;
        // ... LUT sampling logic ...
    }

    return color;
}
```

### Swift: Creating Specialized Pipeline Variants

```swift
class ShaderSpecializer {
    let device: MTLDevice
    let library: MTLLibrary

    /// Create a specialized pipeline for a specific effect combination
    func makeSpecializedPipeline(
        hasColorCorrection: Bool,
        hasBlur: Bool,
        hasVignette: Bool,
        hasLUT: Bool,
        blurKernelSize: Int = 5
    ) throws -> MTLRenderPipelineState {

        // Set function constant values
        let constants = MTLFunctionConstantValues()

        var cc = hasColorCorrection
        var blur = hasBlur
        var vig = hasVignette
        var lut = hasLUT
        var kernelSize = Int32(blurKernelSize)

        constants.setConstantValue(&cc, type: .bool, index: 0)
        constants.setConstantValue(&blur, type: .bool, index: 1)
        constants.setConstantValue(&vig, type: .bool, index: 2)
        constants.setConstantValue(&lut, type: .bool, index: 3)
        constants.setConstantValue(&kernelSize, type: .int, index: 4)

        // Create specialized function (compiler eliminates dead code paths)
        let fragmentFn = try library.makeFunction(
            name: "universalEffectFragment",
            constantValues: constants
        )

        let vertexFn = library.makeFunction(name: "oneInputVertex")!

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
```

### Variant Management for NLE

```swift
class EffectVariantManager {
    struct VariantKey: Hashable {
        let colorCorrection: Bool
        let blur: Bool
        let vignette: Bool
        let lut: Bool
        let blurKernelSize: Int
    }

    private var variants: [VariantKey: MTLRenderPipelineState] = [:]
    private let specializer: ShaderSpecializer
    private let lock = NSLock()

    /// Get or create a specialized variant
    func pipeline(for key: VariantKey) throws -> MTLRenderPipelineState {
        lock.lock()
        defer { lock.unlock() }

        if let cached = variants[key] {
            return cached
        }

        let pipeline = try specializer.makeSpecializedPipeline(
            hasColorCorrection: key.colorCorrection,
            hasBlur: key.blur,
            hasVignette: key.vignette,
            hasLUT: key.lut,
            blurKernelSize: key.blurKernelSize
        )
        variants[key] = pipeline
        return pipeline
    }

    /// Pre-warm common variants at launch
    func prewarmCommonVariants() {
        let common: [VariantKey] = [
            VariantKey(colorCorrection: true, blur: false, vignette: false, lut: false, blurKernelSize: 5),
            VariantKey(colorCorrection: true, blur: false, vignette: false, lut: true, blurKernelSize: 5),
            VariantKey(colorCorrection: true, blur: true, vignette: false, lut: false, blurKernelSize: 5),
            VariantKey(colorCorrection: true, blur: false, vignette: true, lut: true, blurKernelSize: 5),
        ]
        for key in common {
            _ = try? pipeline(for: key)
        }
    }
}
```

---

## 4. Metal Dynamic Libraries

Metal Dynamic Libraries (introduced WWDC 2020) enable plugin architectures where third-party developers can provide custom shader code that is loaded at runtime.

### Creating a Dynamic Library

```swift
// Plugin developer creates a dynamic library
let source = """
#include <metal_stdlib>
using namespace metal;

// Utility function that other shaders can call
float3 tonemapACES(float3 color) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}
"""

let options = MTLCompileOptions()
options.libraryType = .dynamic
options.installName = "@executable_path/libTonemapping.metallib"

let library = try device.makeLibrary(source: source, options: options)
let dynamicLib = try device.makeDynamicLibrary(library: library)

// Serialize to disk for distribution
try dynamicLib.serialize(to: URL(fileURLWithPath: "libTonemapping.metallib"))
```

### Loading and Linking Dynamic Libraries at Runtime

```swift
// Host application loads a plugin's dynamic library
let pluginURL = URL(fileURLWithPath: "/path/to/plugin/libCustomEffect.metallib")
let dynamicLib = try device.makeDynamicLibrary(url: pluginURL)

// Compile an executable shader that links against the dynamic library
let executableSource = """
#include <metal_stdlib>
using namespace metal;

// Declare the external function from the dynamic library
extern float3 tonemapACES(float3 color);

kernel void applyTonemap(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float4 color = inTex.read(gid);
    color.rgb = tonemapACES(color.rgb);
    outTex.write(color, gid);
}
"""

let execOptions = MTLCompileOptions()
execOptions.libraryType = .executable
execOptions.libraries = [dynamicLib]  // Link against the dynamic lib

let executableLib = try device.makeLibrary(source: executableSource, options: execOptions)

// Create pipeline with preloaded libraries
let function = executableLib.makeFunction(name: "applyTonemap")!
let descriptor = MTLComputePipelineDescriptor()
descriptor.computeFunction = function
descriptor.preloadedLibraries = [dynamicLib]  // Ensure dylib is loaded

let pipeline = try device.makeComputePipelineState(
    descriptor: descriptor,
    options: [],
    reflection: nil
)
```

### Command-Line Compilation of Dynamic Libraries

```bash
# Compile a dynamic metal library
xcrun -sdk macosx metal -dynamiclib \
    -install_name "@executable_path/libMyUtils.metallib" \
    MyUtils.metal -o libMyUtils.metallib

# Compile an executable that links against it
xcrun -sdk macosx metal \
    -L /path/to/libs -lMyUtils \
    MyShader.metal -o MyShader.metallib
```

---

## 5. MTLBinaryArchive for Pipeline Caching

Binary archives pre-compile pipeline state objects to machine code, eliminating shader compilation hitches at runtime.

### Creating and Using Binary Archives

```swift
class PipelineArchiveManager {
    let device: MTLDevice
    var archive: MTLBinaryArchive?

    let archiveURL: URL

    init(device: MTLDevice) {
        self.device = device
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.archiveURL = cacheDir.appendingPathComponent("ShaderCache.metallib")
    }

    /// Load existing archive or create new one
    func loadOrCreateArchive() throws {
        let descriptor = MTLBinaryArchiveDescriptor()

        if FileManager.default.fileExists(atPath: archiveURL.path) {
            descriptor.url = archiveURL
        }

        archive = try device.makeBinaryArchive(descriptor: descriptor)
    }

    /// Add a render pipeline to the archive (triggers backend compilation)
    func cacheRenderPipeline(_ descriptor: MTLRenderPipelineDescriptor) throws {
        try archive?.addRenderPipelineFunctions(descriptor: descriptor)
    }

    /// Add a compute pipeline to the archive
    func cacheComputePipeline(_ descriptor: MTLComputePipelineDescriptor) throws {
        try archive?.addComputePipelineFunctions(descriptor: descriptor)
    }

    /// Serialize archive to disk
    func save() throws {
        try archive?.serialize(to: archiveURL)
    }

    /// Create a pipeline using the archive for fast loading
    func makeRenderPipeline(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        // Set the archive as the source for pre-compiled binaries
        descriptor.binaryArchives = [archive].compactMap { $0 }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
```

---

## 6. Custom Effect Plugin System Design

### Plugin Protocol

```swift
/// Protocol that all effect plugins must conform to
protocol VideoEffectPlugin: AnyObject {
    /// Unique identifier for this effect
    static var identifier: String { get }

    /// Display name shown in effect browser
    static var displayName: String { get }

    /// Category for grouping in UI
    static var category: EffectCategory { get }

    /// Thumbnail image for the effect browser
    static var thumbnailName: String { get }

    /// Declare parameters with metadata
    var parameters: [EffectParameter] { get }

    /// The Metal library containing shader functions
    var metalLibrary: MTLLibrary { get }

    /// Fragment (or compute) function name in the Metal library
    var shaderFunctionName: String { get }

    /// Whether this effect uses compute pipeline (vs render pipeline)
    var usesComputePipeline: Bool { get }

    /// Number of input textures required
    var inputCount: Int { get }

    /// Initialize the plugin with a Metal device
    init(device: MTLDevice) throws

    /// Apply the effect. The plugin encodes GPU work into the command buffer.
    func apply(
        commandBuffer: MTLCommandBuffer,
        inputTextures: [MTLTexture],
        outputTexture: MTLTexture,
        parameters: [String: Any],
        time: Double
    )
}

enum EffectCategory: String, CaseIterable {
    case colorCorrection = "Color Correction"
    case blur = "Blur"
    case stylize = "Stylize"
    case distortion = "Distortion"
    case keying = "Keying"
    case generate = "Generate"
    case transition = "Transition"
    case custom = "Custom"
}
```

### Parameter Declaration

```swift
struct EffectParameter {
    let identifier: String
    let displayName: String
    let type: ParameterValueType
    let defaultValue: Any
    let minValue: Any?
    let maxValue: Any?
    let uiHint: UIHint

    enum ParameterValueType {
        case float
        case int
        case bool
        case color       // RGBA
        case point       // 2D position
        case angle       // Radians with circular UI
        case enumeration([String])
    }

    enum UIHint {
        case slider
        case colorWell
        case checkbox
        case point2D
        case angleDial
        case dropdown
        case hidden     // Not shown in UI, programmatic only
    }
}
```

### Plugin Discovery and Registration

```swift
class PluginRegistry {
    static let shared = PluginRegistry()

    private var registeredPlugins: [String: VideoEffectPlugin.Type] = [:]
    private var pluginInstances: [String: VideoEffectPlugin] = [:]

    /// Register a built-in effect
    func register(_ pluginType: VideoEffectPlugin.Type) {
        registeredPlugins[pluginType.identifier] = pluginType
    }

    /// Discover plugins from a directory (third-party)
    func discoverPlugins(in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        for item in contents where item.pathExtension == "bundle" {
            guard let bundle = Bundle(url: item),
                  bundle.load() else { continue }

            // Look for plugin principal class
            if let pluginClass = bundle.principalClass as? VideoEffectPlugin.Type {
                register(pluginClass)
            }
        }
    }

    /// Discover plugins packaged as .metallib files with a manifest
    func discoverMetalPlugins(in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        for item in contents where item.pathExtension == "effectpkg" {
            // Each .effectpkg is a directory containing:
            //   manifest.json  - metadata, parameters, shader function names
            //   effect.metallib - compiled Metal shaders
            //   thumbnail.png  - preview image
            let manifest = item.appendingPathComponent("manifest.json")
            let metallib = item.appendingPathComponent("effect.metallib")

            guard FileManager.default.fileExists(atPath: manifest.path),
                  FileManager.default.fileExists(atPath: metallib.path) else { continue }

            let metadata = try JSONDecoder().decode(EffectManifest.self,
                from: Data(contentsOf: manifest))

            // Register as a generic Metal-based plugin
            // The GenericMetalPlugin class handles loading and applying
            let plugin = try GenericMetalPlugin(
                device: sharedDevice,
                manifest: metadata,
                metallibURL: metallib
            )
            pluginInstances[metadata.identifier] = plugin
        }
    }

    func allEffects() -> [String: VideoEffectPlugin.Type] {
        return registeredPlugins
    }

    func effectsByCategory() -> [EffectCategory: [String]] {
        var result: [EffectCategory: [String]] = [:]
        for (id, type) in registeredPlugins {
            result[type.category, default: []].append(id)
        }
        return result
    }
}
```

### Effect Manifest (JSON)

```json
{
    "identifier": "com.example.glow-effect",
    "displayName": "Glow",
    "category": "stylize",
    "version": "1.0",
    "author": "Example Developer",
    "shaderFunction": "glowFragment",
    "vertexFunction": "oneInputVertex",
    "usesComputePipeline": false,
    "inputCount": 1,
    "parameters": [
        {
            "identifier": "intensity",
            "displayName": "Intensity",
            "type": "float",
            "default": 0.5,
            "min": 0.0,
            "max": 2.0,
            "uiHint": "slider"
        },
        {
            "identifier": "radius",
            "displayName": "Radius",
            "type": "float",
            "default": 10.0,
            "min": 0.0,
            "max": 50.0,
            "uiHint": "slider"
        },
        {
            "identifier": "color",
            "displayName": "Glow Color",
            "type": "color",
            "default": [1.0, 1.0, 1.0, 1.0],
            "uiHint": "colorWell"
        }
    ]
}
```

### Thumbnail Preview Generation

```swift
class EffectThumbnailGenerator {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let sampleTexture: MTLTexture  // Pre-loaded sample frame

    /// Generate a thumbnail by applying the effect to a sample frame
    func generateThumbnail(
        for plugin: VideoEffectPlugin,
        size: CGSize = CGSize(width: 120, height: 68)
    ) -> MTLTexture {
        // Create scaled-down output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: descriptor)!

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return output
        }

        // Apply the effect with default parameters
        let defaults = Dictionary(uniqueKeysWithValues:
            plugin.parameters.map { ($0.identifier, $0.defaultValue) }
        )

        plugin.apply(
            commandBuffer: commandBuffer,
            inputTextures: [sampleTexture],
            outputTexture: output,
            parameters: defaults,
            time: 0
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return output
    }
}
```

---

## 7. Plugin Parameter Declaration System

### Uniform Buffer Assembly from Parameters

```swift
class ParameterBufferAssembler {
    /// Pack parameter values into a Metal buffer for shader consumption
    func assembleBuffer(
        parameters: [EffectParameter],
        values: [String: Any],
        device: MTLDevice
    ) -> MTLBuffer? {
        var data = Data()

        for param in parameters {
            let value = values[param.identifier] ?? param.defaultValue

            switch param.type {
            case .float:
                var f = (value as? Float) ?? 0.0
                data.append(Data(bytes: &f, count: MemoryLayout<Float>.size))

            case .int:
                var i = Int32((value as? Int) ?? 0)
                data.append(Data(bytes: &i, count: MemoryLayout<Int32>.size))

            case .bool:
                var b: Int32 = (value as? Bool) == true ? 1 : 0
                data.append(Data(bytes: &b, count: MemoryLayout<Int32>.size))

            case .color:
                if let rgba = value as? [Float], rgba.count == 4 {
                    var color = simd_float4(rgba[0], rgba[1], rgba[2], rgba[3])
                    data.append(Data(bytes: &color, count: MemoryLayout<simd_float4>.size))
                }

            case .point:
                if let pt = value as? [Float], pt.count == 2 {
                    var point = simd_float2(pt[0], pt[1])
                    data.append(Data(bytes: &point, count: MemoryLayout<simd_float2>.size))
                }

            case .angle:
                var a = (value as? Float) ?? 0.0
                data.append(Data(bytes: &a, count: MemoryLayout<Float>.size))

            case .enumeration:
                var idx = Int32((value as? Int) ?? 0)
                data.append(Data(bytes: &idx, count: MemoryLayout<Int32>.size))
            }

            // Pad to 4-byte alignment
            let alignment = 4
            let remainder = data.count % alignment
            if remainder != 0 {
                data.append(Data(count: alignment - remainder))
            }
        }

        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { ptr in
            device.makeBuffer(bytes: ptr.baseAddress!, length: data.count, options: .storageModeShared)
        }
    }
}
```

### Keyframeable Parameters

```swift
struct KeyframedParameter {
    let parameterID: String
    var keyframes: [Keyframe]

    struct Keyframe {
        let time: Double
        let value: Any
        let interpolation: InterpolationType
    }

    enum InterpolationType {
        case linear
        case bezier(controlPoint1: CGPoint, controlPoint2: CGPoint)
        case hold     // Step function
    }

    /// Evaluate the parameter value at a given time
    func value(at time: Double) -> Any {
        guard !keyframes.isEmpty else { return 0 }
        guard keyframes.count > 1 else { return keyframes[0].value }

        // Find surrounding keyframes
        let sorted = keyframes.sorted { $0.time < $1.time }

        if time <= sorted.first!.time { return sorted.first!.value }
        if time >= sorted.last!.time { return sorted.last!.value }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]

            if time >= a.time && time <= b.time {
                let t = (time - a.time) / (b.time - a.time)

                switch b.interpolation {
                case .linear:
                    return interpolateLinear(from: a.value, to: b.value, t: t)
                case .hold:
                    return a.value
                case .bezier(let cp1, let cp2):
                    let bezierT = evaluateBezier(t: t, cp1: cp1, cp2: cp2)
                    return interpolateLinear(from: a.value, to: b.value, t: bezierT)
                }
            }
        }
        return sorted.last!.value
    }

    private func interpolateLinear(from: Any, to: Any, t: Double) -> Any {
        if let a = from as? Float, let b = to as? Float {
            return a + Float(t) * (b - a)
        }
        // Handle other types (color, point, etc.)
        return from
    }

    private func evaluateBezier(t: Double, cp1: CGPoint, cp2: CGPoint) -> Double {
        // Cubic bezier evaluation for easing curves
        let p0 = 0.0, p3 = 1.0
        let oneMinusT = 1.0 - t
        return oneMinusT * oneMinusT * oneMinusT * p0
            + 3 * oneMinusT * oneMinusT * t * cp1.y
            + 3 * oneMinusT * t * t * cp2.y
            + t * t * t * p3
    }
}
```

---

## 8. FxPlug (Apple's Plugin Architecture Reference)

FxPlug is Apple's official plugin SDK for Final Cut Pro and Motion. Key learnings for our own plugin system:

### FxPlug 4 Key Features
- **Metal rendering support** (first introduced in FxPlug 4)
- **Swift-compatible** API
- **Parameter types**: Slider, angle, popup menu, color picker, point picker, custom UI
- **FxRemoteWindowAPI**: Custom floating windows within the host app
- **FxTimingAPI**: Access to clip timing information
- **Thumbnail generation**: Automatic preview rendering

### Design Patterns to Adopt
- **Parameter declaration via protocol**: Effects declare their parameters at initialization
- **Rendering callback**: Host calls effect's render method with input textures
- **Timing information**: Effects receive current frame time, duration, frame rate
- **Custom UI**: Effects can provide custom parameter editing views
- **On-screen controls**: Effects can draw interactive controls in the viewer

---

## 9. Node-Based Compositing Graph

### Concept (DaVinci Resolve Fusion Model)

A node graph represents compositing operations as a directed acyclic graph (DAG):

```
[MediaIn 1] ──> [ColorCorrect] ──> [Merge] ──> [MediaOut]
                                      ^
[MediaIn 2] ──> [ChromaKey] ──────────┘
```

Key principles:
- **Nodes** are operations (effects, generators, merge/composite, transform)
- **Edges** connect outputs to inputs (data flow)
- **Evaluation order** is determined by topological sort of the DAG
- **Non-destructive**: Source media is never modified
- **Reusable nodes**: One node output can feed multiple downstream nodes

### Node Graph Data Structure

```swift
class CompositeNode: Identifiable {
    let id: UUID
    var type: NodeType
    var name: String
    var position: CGPoint     // Position in the node editor UI

    /// Input connections
    var inputs: [InputSlot]
    /// Output connections
    var outputs: [OutputSlot]

    /// Parameters for this node's effect
    var parameters: [String: Any]
    /// The effect plugin instance
    var effect: VideoEffectPlugin?

    /// Cached output texture (invalidated when inputs change)
    var cachedOutput: MTLTexture?
    var cacheValid: Bool = false
}

struct InputSlot {
    let name: String
    let index: Int
    var connection: Connection?
}

struct OutputSlot {
    let name: String
    let index: Int
    var connections: [Connection]
}

struct Connection {
    let sourceNodeID: UUID
    let sourceOutputIndex: Int
    let targetNodeID: UUID
    let targetInputIndex: Int
}

enum NodeType {
    case mediaInput          // Source footage
    case mediaOutput         // Final output / viewer
    case effect              // Single-input effect
    case merge               // Two-input compositing (foreground/background)
    case transform           // Position, scale, rotation
    case generator           // Creates from nothing (solid, gradient, text)
    case transition          // Time-based blend between two inputs
}
```

### Topological Sort for Evaluation Order

```swift
class NodeGraph {
    var nodes: [UUID: CompositeNode] = [:]

    /// Topological sort using Kahn's algorithm
    /// Returns nodes in evaluation order (sources first, outputs last)
    func evaluationOrder() -> [CompositeNode] {
        // Calculate in-degree for each node
        var inDegree: [UUID: Int] = [:]
        for (id, node) in nodes {
            inDegree[id] = node.inputs.compactMap { $0.connection }.count
        }

        // Start with nodes that have no inputs (sources)
        var queue: [UUID] = inDegree.filter { $0.value == 0 }.map { $0.key }
        var result: [CompositeNode] = []

        while !queue.isEmpty {
            let nodeID = queue.removeFirst()
            guard let node = nodes[nodeID] else { continue }
            result.append(node)

            // For each downstream node connected to this node's outputs
            for output in node.outputs {
                for connection in output.connections {
                    let targetID = connection.targetNodeID
                    inDegree[targetID]! -= 1
                    if inDegree[targetID] == 0 {
                        queue.append(targetID)
                    }
                }
            }
        }

        return result
    }

    /// Evaluate the entire graph for a given time
    func evaluate(at time: Double, canvasSize: MTLSize, device: MTLDevice,
                  commandQueue: MTLCommandQueue, texturePool: TexturePool) -> MTLTexture? {
        let order = evaluationOrder()
        var nodeOutputs: [UUID: MTLTexture] = [:]

        for node in order {
            // Gather input textures from upstream nodes
            var inputTextures: [MTLTexture] = []
            for input in node.inputs {
                if let conn = input.connection,
                   let tex = nodeOutputs[conn.sourceNodeID] {
                    inputTextures.append(tex)
                }
            }

            // Check cache
            if node.cacheValid, let cached = node.cachedOutput {
                nodeOutputs[node.id] = cached
                continue
            }

            // Allocate output texture
            let output = texturePool.acquire(
                width: canvasSize.width,
                height: canvasSize.height
            )

            // Execute the node's operation
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }

            switch node.type {
            case .mediaInput:
                // Decode video frame at `time`
                decodeFrame(node: node, time: time, output: output, commandBuffer: commandBuffer)

            case .effect:
                node.effect?.apply(
                    commandBuffer: commandBuffer,
                    inputTextures: inputTextures,
                    outputTexture: output,
                    parameters: node.parameters,
                    time: time
                )

            case .merge:
                // Composite foreground over background
                compositeLayers(
                    background: inputTextures.first,
                    foreground: inputTextures.count > 1 ? inputTextures[1] : nil,
                    output: output,
                    commandBuffer: commandBuffer,
                    parameters: node.parameters
                )

            case .mediaOutput:
                // Copy to output (or display)
                if let input = inputTextures.first {
                    blitCopy(from: input, to: output, commandBuffer: commandBuffer)
                }

            default:
                break
            }

            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            nodeOutputs[node.id] = output
            node.cachedOutput = output
            node.cacheValid = true
        }

        // Return the output of the MediaOut node
        let outputNode = nodes.values.first { $0.type == .mediaOutput }
        return outputNode.flatMap { nodeOutputs[$0.id] }
    }

    /// Invalidate cache for a node and all its downstream dependents
    func invalidate(nodeID: UUID) {
        guard let node = nodes[nodeID] else { return }
        node.cacheValid = false

        for output in node.outputs {
            for connection in output.connections {
                invalidate(nodeID: connection.targetNodeID)
            }
        }
    }

    private func decodeFrame(node: CompositeNode, time: Double,
                             output: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Implementation: use AVAssetReader or VideoToolbox
    }

    private func compositeLayers(background: MTLTexture?, foreground: MTLTexture?,
                                  output: MTLTexture, commandBuffer: MTLCommandBuffer,
                                  parameters: [String: Any]) {
        // Source-over blend
    }

    private func blitCopy(from: MTLTexture, to: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: from, to: to)
        blit.endEncoding()
    }
}
```

---

## 10. Render Graph Implementation

A render graph automatically manages resource lifetimes, barriers, and pass ordering:

```swift
class RenderGraph {
    struct PassResource {
        let name: String
        let texture: MTLTexture?
        var readBy: [Int] = []     // Pass indices that read this resource
        var writtenBy: Int = -1     // Pass index that writes this resource
    }

    struct RenderPass {
        let name: String
        let reads: [String]         // Resource names read
        let writes: [String]        // Resource names written
        let execute: (MTLCommandBuffer, [String: MTLTexture]) -> Void
    }

    var passes: [RenderPass] = []
    var resources: [String: PassResource] = [:]

    func addPass(
        name: String,
        reads: [String],
        writes: [String],
        execute: @escaping (MTLCommandBuffer, [String: MTLTexture]) -> Void
    ) {
        let index = passes.count
        passes.append(RenderPass(name: name, reads: reads, writes: writes, execute: execute))

        for read in reads {
            resources[read, default: PassResource(name: read, texture: nil)].readBy.append(index)
        }
        for write in writes {
            resources[write, default: PassResource(name: write, texture: nil)].writtenBy = index
        }
    }

    /// Compile and execute the render graph
    func execute(commandQueue: MTLCommandQueue, texturePool: TexturePool,
                 canvasWidth: Int, canvasHeight: Int) {
        // Topological sort passes based on read/write dependencies
        let sortedPasses = topologicalSort()

        // Allocate textures for transient resources
        var textures: [String: MTLTexture] = [:]
        for (name, resource) in resources {
            if resource.texture == nil {
                textures[name] = texturePool.acquire(width: canvasWidth, height: canvasHeight)
            } else {
                textures[name] = resource.texture
            }
        }

        // Execute passes in order
        for pass in sortedPasses {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
            pass.execute(commandBuffer, textures)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        // Release transient textures whose last reader has completed
        // (In practice, track lifetimes more precisely)
    }

    private func topologicalSort() -> [RenderPass] {
        // Build dependency graph and sort
        // Similar to the node graph topological sort
        return passes  // Simplified; real implementation needs proper sort
    }
}
```

---

## 11. Real-Time Video Scopes Overview

Professional NLEs provide four essential video scopes:

| Scope | Purpose | Algorithm |
|-------|---------|-----------|
| **Histogram** | Distribution of luminance/color values | Bin counting with atomic operations |
| **Waveform** | Luminance vs. horizontal position | Per-column luminance plotting |
| **RGB Parade** | Separate R/G/B waveforms side by side | Three independent waveforms |
| **Vectorscope** | Color hue/saturation on circular plot | YCbCr polar coordinate mapping |

All scopes are best implemented as Metal compute shaders for real-time performance on every frame.

---

## 12. Histogram Compute Shader

### Two-Phase Parallel Histogram (Metal)

```metal
#include <metal_stdlib>
using namespace metal;

// Phase 1: Accumulate local histograms per threadgroup
kernel void histogramAccumulate(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *globalHistR [[buffer(0)]],
    device atomic_uint *globalHistG [[buffer(1)]],
    device atomic_uint *globalHistB [[buffer(2)]],
    device atomic_uint *globalHistLuma [[buffer(3)]],
    threadgroup atomic_uint *localHistR [[threadgroup(0)]],
    threadgroup atomic_uint *localHistG [[threadgroup(1)]],
    threadgroup atomic_uint *localHistB [[threadgroup(2)]],
    threadgroup atomic_uint *localHistLuma [[threadgroup(3)]],
    uint2 gid [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]],
    uint2 tgSize [[threads_per_threadgroup]]
) {
    // Initialize local histogram bins to zero
    uint threadsPerGroup = tgSize.x * tgSize.y;
    for (uint i = tid; i < 256; i += threadsPerGroup) {
        atomic_store_explicit(&localHistR[i], 0, memory_order_relaxed);
        atomic_store_explicit(&localHistG[i], 0, memory_order_relaxed);
        atomic_store_explicit(&localHistB[i], 0, memory_order_relaxed);
        atomic_store_explicit(&localHistLuma[i], 0, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Bounds check
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    // Read pixel and compute bins
    half4 color = inputTexture.read(gid);
    uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
    uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
    uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);

    // Luma using BT.709
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    uint binLuma = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);

    // Accumulate to threadgroup-local histograms
    atomic_fetch_add_explicit(&localHistR[binR], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistG[binG], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistB[binB], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&localHistLuma[binLuma], 1, memory_order_relaxed);

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Phase 2: Merge local histogram into global histogram
    for (uint i = tid; i < 256; i += threadsPerGroup) {
        uint localVal;

        localVal = atomic_load_explicit(&localHistR[i], memory_order_relaxed);
        if (localVal > 0) atomic_fetch_add_explicit(&globalHistR[i], localVal, memory_order_relaxed);

        localVal = atomic_load_explicit(&localHistG[i], memory_order_relaxed);
        if (localVal > 0) atomic_fetch_add_explicit(&globalHistG[i], localVal, memory_order_relaxed);

        localVal = atomic_load_explicit(&localHistB[i], memory_order_relaxed);
        if (localVal > 0) atomic_fetch_add_explicit(&globalHistB[i], localVal, memory_order_relaxed);

        localVal = atomic_load_explicit(&localHistLuma[i], memory_order_relaxed);
        if (localVal > 0) atomic_fetch_add_explicit(&globalHistLuma[i], localVal, memory_order_relaxed);
    }
}
```

### Histogram Visualization Shader

```metal
// Render histogram as vertical bars
kernel void histogramVisualize(
    device uint *histData [[buffer(0)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &maxCount [[buffer(1)]],
    constant half4 &barColor [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) return;

    // Map x position to histogram bin
    uint bin = gid.x * 256 / width;
    uint count = histData[bin];

    // Normalize height
    float normalizedHeight = float(count) / float(maxCount);
    float pixelHeight = 1.0 - float(gid.y) / float(height);  // Flip Y

    if (pixelHeight <= normalizedHeight) {
        outputTexture.write(barColor, gid);
    } else {
        outputTexture.write(half4(0.05, 0.05, 0.05, 1.0), gid);  // Dark background
    }
}
```

### Swift Host Code for Histogram

```swift
class HistogramScope {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let accumulatePipeline: MTLComputePipelineState
    let visualizePipeline: MTLComputePipelineState

    // 4 channels x 256 bins
    let histBufferR: MTLBuffer
    let histBufferG: MTLBuffer
    let histBufferB: MTLBuffer
    let histBufferLuma: MTLBuffer

    init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        let library = device.makeDefaultLibrary()!
        accumulatePipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "histogramAccumulate")!
        )
        visualizePipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "histogramVisualize")!
        )

        let bufferSize = 256 * MemoryLayout<UInt32>.size
        histBufferR = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        histBufferG = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        histBufferB = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        histBufferLuma = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
    }

    func compute(from inputTexture: MTLTexture, to outputTexture: MTLTexture) {
        // Clear histogram buffers
        memset(histBufferR.contents(), 0, histBufferR.length)
        memset(histBufferG.contents(), 0, histBufferG.length)
        memset(histBufferB.contents(), 0, histBufferB.length)
        memset(histBufferLuma.contents(), 0, histBufferLuma.length)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Phase 1+2: Accumulate histogram
        let accEncoder = commandBuffer.makeComputeCommandEncoder()!
        accEncoder.setComputePipelineState(accumulatePipeline)
        accEncoder.setTexture(inputTexture, index: 0)
        accEncoder.setBuffer(histBufferR, offset: 0, index: 0)
        accEncoder.setBuffer(histBufferG, offset: 0, index: 1)
        accEncoder.setBuffer(histBufferB, offset: 0, index: 2)
        accEncoder.setBuffer(histBufferLuma, offset: 0, index: 3)

        // Threadgroup memory for local histograms
        let tgMemSize = 256 * MemoryLayout<UInt32>.size
        accEncoder.setThreadgroupMemoryLength(tgMemSize, index: 0)
        accEncoder.setThreadgroupMemoryLength(tgMemSize, index: 1)
        accEncoder.setThreadgroupMemoryLength(tgMemSize, index: 2)
        accEncoder.setThreadgroupMemoryLength(tgMemSize, index: 3)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(
            width: inputTexture.width,
            height: inputTexture.height,
            depth: 1
        )
        accEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        accEncoder.endEncoding()

        // Find max for normalization
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let lumaPtr = histBufferLuma.contents().bindMemory(to: UInt32.self, capacity: 256)
        var maxCount: UInt32 = 1
        for i in 0..<256 {
            maxCount = max(maxCount, lumaPtr[i])
        }

        // Visualize
        guard let cb2 = commandQueue.makeCommandBuffer(),
              let vizEncoder = cb2.makeComputeCommandEncoder() else { return }

        vizEncoder.setComputePipelineState(visualizePipeline)
        vizEncoder.setBuffer(histBufferLuma, offset: 0, index: 0)
        var mc = maxCount
        vizEncoder.setBytes(&mc, length: MemoryLayout<UInt32>.size, index: 1)
        var color = simd_half4(0.8, 0.8, 0.8, 1.0)
        vizEncoder.setBytes(&color, length: MemoryLayout<simd_half4>.size, index: 2)
        vizEncoder.setTexture(outputTexture, index: 0)

        let vizGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
        vizEncoder.dispatchThreads(vizGrid, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        vizEncoder.endEncoding()

        cb2.commit()
    }
}
```

---

## 13. Waveform Monitor Compute Shader

The waveform monitor plots luminance values per column of the image.

```metal
// Waveform accumulation: for each column, count how many pixels have each luma value
kernel void waveformAccumulate(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *waveformData [[buffer(0)]],  // [width * 256]
    constant uint &scopeWidth [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgWidth = inputTexture.get_width();
    uint imgHeight = inputTexture.get_height();

    if (gid.x >= imgWidth || gid.y >= imgHeight) return;

    half4 color = inputTexture.read(gid);
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    uint lumaBin = uint(clamp(luma, 0.0h, 1.0h) * 255.0h);

    // Map image column to scope column
    uint scopeCol = gid.x * scopeWidth / imgWidth;

    // Increment the count for this column+luma combination
    uint index = scopeCol * 256 + lumaBin;
    atomic_fetch_add_explicit(&waveformData[index], 1, memory_order_relaxed);
}

// Waveform visualization
kernel void waveformVisualize(
    device uint *waveformData [[buffer(0)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &scopeWidth [[buffer(1)]],
    constant uint &maxCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) return;

    uint col = gid.x * scopeWidth / width;
    // Map Y to luma (bottom = 0, top = 255)
    uint lumaBin = (height - 1 - gid.y) * 256 / height;

    uint index = col * 256 + lumaBin;
    uint count = waveformData[index];

    if (count > 0) {
        // Intensity based on count (logarithmic for better visibility)
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0), 0.0, 1.0);
        // Green tint like traditional waveform monitors
        outputTexture.write(half4(intensity * 0.3h, intensity * 1.0h, intensity * 0.3h, 1.0h), gid);
    } else {
        outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
    }
}
```

---

## 14. RGB Parade Compute Shader

RGB Parade displays three separate waveforms for R, G, B side by side.

```metal
kernel void rgbParadeAccumulate(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *paradeDataR [[buffer(0)]],  // [paradeWidth * 256]
    device atomic_uint *paradeDataG [[buffer(1)]],
    device atomic_uint *paradeDataB [[buffer(2)]],
    constant uint &paradeWidth [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgWidth = inputTexture.get_width();
    uint imgHeight = inputTexture.get_height();

    if (gid.x >= imgWidth || gid.y >= imgHeight) return;

    half4 color = inputTexture.read(gid);

    uint binR = uint(clamp(color.r, 0.0h, 1.0h) * 255.0h);
    uint binG = uint(clamp(color.g, 0.0h, 1.0h) * 255.0h);
    uint binB = uint(clamp(color.b, 0.0h, 1.0h) * 255.0h);

    // Map image column to parade column (each channel gets 1/3 of the width)
    uint col = gid.x * paradeWidth / imgWidth;

    atomic_fetch_add_explicit(&paradeDataR[col * 256 + binR], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&paradeDataG[col * 256 + binG], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&paradeDataB[col * 256 + binB], 1, memory_order_relaxed);
}

kernel void rgbParadeVisualize(
    device uint *paradeDataR [[buffer(0)]],
    device uint *paradeDataG [[buffer(1)]],
    device uint *paradeDataB [[buffer(2)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &paradeWidth [[buffer(3)]],
    constant uint &maxCount [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) return;

    // Determine which channel (R, G, or B) based on x position
    uint thirdWidth = width / 3;
    uint channelIndex = gid.x / thirdWidth;  // 0=R, 1=G, 2=B
    uint localX = gid.x % thirdWidth;

    uint col = localX * paradeWidth / thirdWidth;
    uint valueBin = (height - 1 - gid.y) * 256 / height;

    uint index = col * 256 + valueBin;
    uint count = 0;
    half4 channelColor;

    if (channelIndex == 0) {
        count = paradeDataR[index];
        channelColor = half4(1.0, 0.2, 0.2, 1.0);  // Red
    } else if (channelIndex == 1) {
        count = paradeDataG[index];
        channelColor = half4(0.2, 1.0, 0.2, 1.0);  // Green
    } else {
        count = paradeDataB[index];
        channelColor = half4(0.2, 0.2, 1.0, 1.0);  // Blue
    }

    if (count > 0) {
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0), 0.0, 1.0);
        outputTexture.write(channelColor * half(intensity), gid);
    } else {
        // Subtle separator lines between channels
        if (gid.x == thirdWidth || gid.x == thirdWidth * 2) {
            outputTexture.write(half4(0.15h, 0.15h, 0.15h, 1.0h), gid);
        } else {
            outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
        }
    }
}
```

---

## 15. Vectorscope Compute Shader

The vectorscope plots Cb vs Cr on a circular color wheel.

```metal
kernel void vectorscopeAccumulate(
    texture2d<half, access::read> inputTexture [[texture(0)]],
    device atomic_uint *scopeData [[buffer(0)]],  // [scopeSize * scopeSize]
    constant uint &scopeSize [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint imgWidth = inputTexture.get_width();
    uint imgHeight = inputTexture.get_height();

    if (gid.x >= imgWidth || gid.y >= imgHeight) return;

    half4 color = inputTexture.read(gid);

    // RGB to YCbCr (BT.709)
    half Y  =  0.2126h * color.r + 0.7152h * color.g + 0.0722h * color.b;
    half Cb = -0.1146h * color.r - 0.3854h * color.g + 0.5000h * color.b;
    half Cr =  0.5000h * color.r - 0.4542h * color.g - 0.0458h * color.b;

    // Map Cb, Cr (-0.5 to 0.5) to scope coordinates (0 to scopeSize-1)
    uint x = uint(clamp((Cb + 0.5h) * half(scopeSize), 0.0h, half(scopeSize - 1)));
    uint y = uint(clamp((0.5h - Cr) * half(scopeSize), 0.0h, half(scopeSize - 1)));
    // Note: Cr is inverted (negative Y) to match traditional vectorscope orientation

    uint index = y * scopeSize + x;
    atomic_fetch_add_explicit(&scopeData[index], 1, memory_order_relaxed);
}

kernel void vectorscopeVisualize(
    device uint *scopeData [[buffer(0)]],
    texture2d<half, access::write> outputTexture [[texture(0)]],
    constant uint &scopeSize [[buffer(1)]],
    constant uint &maxCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) return;

    // Map output pixel to scope coordinate
    uint scopeX = gid.x * scopeSize / width;
    uint scopeY = gid.y * scopeSize / height;

    // Draw circular boundary and graticule
    float2 center = float2(width / 2.0, height / 2.0);
    float2 pos = float2(gid.x, gid.y);
    float dist = distance(pos, center);
    float radius = float(min(width, height)) / 2.0;

    // Outside the circle
    if (dist > radius) {
        outputTexture.write(half4(0.0h, 0.0h, 0.0h, 1.0h), gid);
        return;
    }

    // Circle outline
    if (abs(dist - radius) < 1.5) {
        outputTexture.write(half4(0.3h, 0.3h, 0.3h, 1.0h), gid);
        return;
    }

    // Crosshair at center
    if (abs(float(gid.x) - center.x) < 0.5 || abs(float(gid.y) - center.y) < 0.5) {
        outputTexture.write(half4(0.15h, 0.15h, 0.15h, 1.0h), gid);
        return;
    }

    // Draw scope data
    uint index = scopeY * scopeSize + scopeX;
    uint count = scopeData[index];

    if (count > 0) {
        float intensity = clamp(log2(float(count) + 1.0) / log2(float(maxCount) + 1.0), 0.0, 1.0);

        // Color the dot based on its position (matching the hue it represents)
        float2 normalized = float2(gid.x, gid.y) / float2(width, height);
        float Cb = normalized.x - 0.5;
        float Cr = 0.5 - normalized.y;

        // Approximate hue color from CbCr position
        float3 hueColor = float3(
            clamp(0.5 + 1.402 * Cr, 0.0, 1.0),
            clamp(0.5 - 0.344 * Cb - 0.714 * Cr, 0.0, 1.0),
            clamp(0.5 + 1.772 * Cb, 0.0, 1.0)
        );

        half4 finalColor = half4(half3(hueColor) * half(intensity), 1.0h);
        outputTexture.write(finalColor, gid);
    } else {
        outputTexture.write(half4(0.02h, 0.02h, 0.02h, 1.0h), gid);
    }
}
```

---

## 16. Scope Visualization Renderer

### Unified Scope Manager

```swift
class VideoScopeManager {
    enum ScopeType {
        case histogram
        case waveform
        case rgbParade
        case vectorscope
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    private var accumulatePipelines: [ScopeType: MTLComputePipelineState] = [:]
    private var visualizePipelines: [ScopeType: MTLComputePipelineState] = [:]
    private var scopeBuffers: [ScopeType: [MTLBuffer]] = [:]
    private var scopeTextures: [ScopeType: MTLTexture] = [:]

    let scopeSize: Int = 256  // Resolution of scope output

    init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        let library = device.makeDefaultLibrary()!

        // Load all pipelines
        for type in [ScopeType.histogram, .waveform, .rgbParade, .vectorscope] {
            let (accName, vizName) = shaderNames(for: type)
            accumulatePipelines[type] = try device.makeComputePipelineState(
                function: library.makeFunction(name: accName)!
            )
            visualizePipelines[type] = try device.makeComputePipelineState(
                function: library.makeFunction(name: vizName)!
            )
        }

        allocateBuffers()
    }

    private func shaderNames(for type: ScopeType) -> (String, String) {
        switch type {
        case .histogram:   return ("histogramAccumulate", "histogramVisualize")
        case .waveform:    return ("waveformAccumulate", "waveformVisualize")
        case .rgbParade:   return ("rgbParadeAccumulate", "rgbParadeVisualize")
        case .vectorscope: return ("vectorscopeAccumulate", "vectorscopeVisualize")
        }
    }

    private func allocateBuffers() {
        // Histogram: 4 channels x 256 bins
        let histBufSize = 256 * MemoryLayout<UInt32>.size
        scopeBuffers[.histogram] = (0..<4).map { _ in
            device.makeBuffer(length: histBufSize, options: .storageModeShared)!
        }

        // Waveform: scopeSize columns x 256 luma bins
        let waveformBufSize = scopeSize * 256 * MemoryLayout<UInt32>.size
        scopeBuffers[.waveform] = [
            device.makeBuffer(length: waveformBufSize, options: .storageModeShared)!
        ]

        // RGB Parade: 3 channels x scopeSize columns x 256 bins
        scopeBuffers[.rgbParade] = (0..<3).map { _ in
            device.makeBuffer(length: waveformBufSize, options: .storageModeShared)!
        }

        // Vectorscope: scopeSize x scopeSize grid
        let vscopeBufSize = scopeSize * scopeSize * MemoryLayout<UInt32>.size
        scopeBuffers[.vectorscope] = [
            device.makeBuffer(length: vscopeBufSize, options: .storageModeShared)!
        ]
    }

    /// Update all active scopes for a new video frame
    func update(with videoTexture: MTLTexture, activeScopes: Set<ScopeType>) {
        for type in activeScopes {
            clearBuffers(for: type)
            accumulate(type: type, from: videoTexture)
            visualize(type: type)
        }
    }

    private func clearBuffers(for type: ScopeType) {
        guard let buffers = scopeBuffers[type] else { return }
        for buffer in buffers {
            memset(buffer.contents(), 0, buffer.length)
        }
    }

    private func accumulate(type: ScopeType, from texture: MTLTexture) {
        guard let pipeline = accumulatePipelines[type],
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)

        if let buffers = scopeBuffers[type] {
            for (i, buf) in buffers.enumerated() {
                encoder.setBuffer(buf, offset: 0, index: i)
            }
        }

        var size = UInt32(scopeSize)
        encoder.setBytes(&size, length: MemoryLayout<UInt32>.size, index: buffers(for: type))

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: texture.width, height: texture.height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func buffers(for type: ScopeType) -> Int {
        return scopeBuffers[type]?.count ?? 0
    }

    private func visualize(type: ScopeType) {
        // Similar pattern: set up compute encoder with visualization pipeline
        // Write to the scope's output texture
    }

    /// Get the output texture for a scope type (for display in UI)
    func texture(for type: ScopeType) -> MTLTexture? {
        return scopeTextures[type]
    }
}
```

---

## 17. Text Rendering Approaches

Three main approaches for rendering text onto video frames, each with different tradeoffs:

| Approach | Quality | Performance | Flexibility | Complexity |
|----------|---------|-------------|-------------|------------|
| CoreGraphics rasterization | Good | Medium | High (full text layout) | Low |
| Signed Distance Field (SDF) | Excellent (any scale) | Very High | Medium | High |
| Multi-Channel SDF (MSDF) | Excellent (sharp corners) | Very High | Medium | Higher |

### Recommendation for NLE
- **CoreGraphics rasterization** for static titles and lower thirds (re-rasterize only when text changes)
- **SDF/MSDF** for animated text that scales, rotates, or moves during playback

---

## 18. CoreGraphics to Metal Text Rendering

### Shared Memory Approach

Create a CGContext that shares its backing store with a MTLTexture:

```swift
class TextRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    /// Render styled text to a Metal texture using CoreGraphics
    func renderText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        size: CGSize,
        alignment: NSTextAlignment = .center,
        backgroundColor: NSColor = .clear
    ) -> MTLTexture? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 4

        // Create a shared MTLBuffer for zero-copy CGContext -> MTLTexture
        let bufferSize = bytesPerRow * height
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return nil
        }

        // Create CGContext backed by the Metal buffer's memory
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: buffer.contents(),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Clear with background color
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Flip coordinate system (CoreGraphics is bottom-left origin)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw text using NSAttributedString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: 0, y: 0, width: width, height: height)

        // Use NSStringDrawing for proper layout
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        attrString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()

        // Create MTLTexture from the same buffer (zero-copy)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        let texture = buffer.makeTexture(
            descriptor: textureDescriptor,
            offset: 0,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    /// Composite text texture over video frame
    func overlayText(
        textTexture: MTLTexture,
        videoTexture: MTLTexture,
        outputTexture: MTLTexture,
        position: CGPoint,         // Normalized 0..1
        scale: Float,
        opacity: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        // Use a render pass with alpha blending enabled
        // Draw the video frame first, then draw the text quad on top
        // with appropriate transform for position and scale
    }
}
```

### Core Text for Advanced Typography

```swift
class CoreTextRenderer {
    /// Render multi-line styled text with Core Text
    func renderAttributedText(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        to texture: MTLTexture,
        context: CGContext
    ) {
        // Create CTFramesetter for multi-line layout
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        // Calculate text bounds
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            nil
        )

        // Create path for text frame
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: suggestedSize))

        // Create and draw the text frame
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )

        CTFrameDraw(frame, context)
    }
}
```

---

## 19. Signed Distance Field Text Rendering

### SDF Font Atlas Generation

```swift
class SDFFontAtlasGenerator {
    /// Generate an SDF atlas from a font using Core Text
    func generateAtlas(
        font: CTFont,
        characters: String,
        atlasSize: Int = 4096,
        spread: Int = 8        // Distance field spread in pixels
    ) -> (texture: MTLTexture, glyphs: [Character: GlyphInfo])? {

        var glyphInfos: [Character: GlyphInfo] = [:]

        // Step 1: Get glyph metrics for each character
        let glyphScale: CGFloat = 64.0  // Render at large size for SDF
        let padding = CGFloat(spread * 2)

        var glyphBitmaps: [(Character, CGImage, CGRect)] = []

        for char in characters {
            let str = String(char) as CFString
            let attrStr = CFAttributedStringCreate(nil, str, [
                kCTFontAttributeName: font
            ] as CFDictionary)!

            let line = CTLineCreateWithAttributedString(attrStr)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let height = ascent + descent

            // Render glyph to bitmap
            let bitmapWidth = Int(ceil(width + padding * 2))
            let bitmapHeight = Int(ceil(height + padding * 2))

            guard let ctx = CGContext(
                data: nil,
                width: bitmapWidth,
                height: bitmapHeight,
                bitsPerComponent: 8,
                bytesPerRow: bitmapWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { continue }

            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))

            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.textPosition = CGPoint(x: padding, y: padding + descent)
            CTLineDraw(line, ctx)

            if let image = ctx.makeImage() {
                let rect = CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight)
                glyphBitmaps.append((char, image, rect))
            }
        }

        // Step 2: Pack glyphs into atlas
        // Step 3: Compute signed distance field for each glyph
        // Step 4: Upload to MTLTexture

        return nil  // Full implementation would be substantial
    }

    struct GlyphInfo {
        let character: Character
        let atlasRect: CGRect      // UV coordinates in atlas
        let size: CGSize           // Size in points
        let bearing: CGPoint       // Offset from baseline
        let advance: CGFloat       // Horizontal advance
    }
}
```

### SDF Fragment Shader

```metal
struct TextVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct TextUniforms {
    float4 textColor;
    float4 outlineColor;
    float smoothing;        // Anti-aliasing smoothness (0.1 typical)
    float outlineWidth;     // 0.0 = no outline, 0.2 = thick outline
    float shadowOffset;
    float shadowSoftness;
    float4 shadowColor;
};

fragment half4 sdfTextFragment(
    TextVertexOut in [[stage_in]],
    texture2d<half> atlas [[texture(0)]],
    constant TextUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler s(filter::linear);

    // Sample the distance field
    float dist = float(atlas.sample(s, in.texCoord).r);

    // Edge detection with screen-space derivatives for resolution-independent AA
    float edgeDistance = 0.5;
    float edgeWidth = uniforms.smoothing * length(float2(dfdx(dist), dfdy(dist)));

    // Main text fill
    float textAlpha = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, dist);

    // Outline
    float outlineAlpha = 0.0;
    if (uniforms.outlineWidth > 0.0) {
        float outlineEdge = edgeDistance - uniforms.outlineWidth;
        outlineAlpha = smoothstep(outlineEdge - edgeWidth, outlineEdge + edgeWidth, dist);
    }

    // Combine fill and outline
    half4 fillColor = half4(uniforms.textColor) * half(textAlpha);
    half4 outlineColorFinal = half4(uniforms.outlineColor) * half(outlineAlpha * (1.0 - textAlpha));

    // Shadow (optional)
    half4 shadowColorFinal = half4(0);
    if (uniforms.shadowOffset > 0.0) {
        float2 shadowUV = in.texCoord - float2(uniforms.shadowOffset * 0.005);
        float shadowDist = float(atlas.sample(s, shadowUV).r);
        float shadowAlpha = smoothstep(
            edgeDistance - uniforms.shadowSoftness,
            edgeDistance,
            shadowDist
        );
        shadowColorFinal = half4(uniforms.shadowColor) * half(shadowAlpha * (1.0 - textAlpha));
    }

    return shadowColorFinal + outlineColorFinal + fillColor;
}
```

---

## 20. Animated Titles & Lower Thirds

### Title Animation System

```swift
class TitleAnimator {
    struct TitleProperties {
        var text: String
        var font: NSFont
        var color: NSColor
        var position: CGPoint         // Normalized center position
        var scale: Float = 1.0
        var rotation: Float = 0.0     // Radians
        var opacity: Float = 1.0
        var tracking: Float = 0.0     // Letter spacing
    }

    struct AnimationKeyframe {
        let time: Double              // Seconds from clip start
        let properties: TitleProperties
        let easing: EasingFunction
    }

    enum EasingFunction {
        case linear
        case easeIn
        case easeOut
        case easeInOut

        func evaluate(_ t: Float) -> Float {
            switch self {
            case .linear: return t
            case .easeIn: return t * t
            case .easeOut: return 1.0 - (1.0 - t) * (1.0 - t)
            case .easeInOut:
                return t < 0.5
                    ? 2.0 * t * t
                    : 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
            }
        }
    }

    /// Pre-built lower third template
    static func lowerThird(
        name: String,
        title: String,
        duration: Double = 5.0,
        fadeIn: Double = 0.3,
        fadeOut: Double = 0.3
    ) -> [AnimationKeyframe] {
        let baseProps = TitleProperties(
            text: "\(name)\n\(title)",
            font: NSFont.systemFont(ofSize: 24, weight: .bold),
            color: .white,
            position: CGPoint(x: 0.15, y: 0.85),
            opacity: 0.0
        )

        var visibleProps = baseProps
        visibleProps.opacity = 1.0

        var slideInProps = baseProps
        slideInProps.position.x = 0.05  // Slide from left

        return [
            AnimationKeyframe(time: 0, properties: slideInProps, easing: .easeOut),
            AnimationKeyframe(time: fadeIn, properties: visibleProps, easing: .easeOut),
            AnimationKeyframe(time: duration - fadeOut, properties: visibleProps, easing: .easeIn),
            AnimationKeyframe(time: duration, properties: baseProps, easing: .easeIn),
        ]
    }

    /// Evaluate animated properties at a given time
    func evaluate(keyframes: [AnimationKeyframe], at time: Double) -> TitleProperties {
        guard !keyframes.isEmpty else {
            return TitleProperties(text: "", font: .systemFont(ofSize: 12),
                                   color: .white, position: .zero)
        }

        let sorted = keyframes.sorted { $0.time < $1.time }

        if time <= sorted.first!.time { return sorted.first!.properties }
        if time >= sorted.last!.time { return sorted.last!.properties }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]

            if time >= a.time && time <= b.time {
                let rawT = Float((time - a.time) / (b.time - a.time))
                let easedT = b.easing.evaluate(rawT)
                return interpolate(from: a.properties, to: b.properties, t: easedT)
            }
        }

        return sorted.last!.properties
    }

    private func interpolate(from a: TitleProperties, to b: TitleProperties, t: Float) -> TitleProperties {
        var result = b  // Use b's text/font
        result.position = CGPoint(
            x: CGFloat(Float(a.position.x) + t * Float(b.position.x - a.position.x)),
            y: CGFloat(Float(a.position.y) + t * Float(b.position.y - a.position.y))
        )
        result.scale = a.scale + t * (b.scale - a.scale)
        result.rotation = a.rotation + t * (b.rotation - a.rotation)
        result.opacity = a.opacity + t * (b.opacity - a.opacity)
        return result
    }
}
```

---

## 21. Complete Architecture Integration

### How These Systems Fit Together in the NLE

```
+------------------+     +-------------------+     +-----------------+
| Shader Library   |     | Plugin Registry   |     | Effect Manifest |
| Manager          |     | (discovers &      |     | (.effectpkg)    |
| (loads .metallib |---->| registers plugins)|<----| JSON + metallib |
| pipeline cache)  |     |                   |     | + thumbnail     |
+--------+---------+     +--------+----------+     +-----------------+
         |                         |
         v                         v
+--------+---------+     +--------+----------+
| Function         |     | Parameter Buffer  |
| Constants &      |     | Assembler         |
| Specialization   |     | (params -> GPU    |
| (uber shaders)   |     |  uniform buffer)  |
+--------+---------+     +--------+----------+
         |                         |
         +------------+------------+
                      |
                      v
              +-------+-------+
              | Node Graph    |
              | (DAG of       |
              |  compositing  |
              |  operations)  |
              +-------+-------+
                      |
         +------------+------------+
         |            |            |
         v            v            v
   +---------+  +---------+  +---------+
   | Effects |  | Compose |  | Scopes  |
   | Chain   |  | Layers  |  | (histo, |
   |         |  |         |  |  wave,  |
   |         |  |         |  |  vector)|
   +---------+  +---------+  +---------+
         |            |            |
         +-----+------+           |
               |                   |
               v                   v
        +------+------+    +------+------+
        | Text/Title  |    | Scope View  |
        | Overlay     |    | Panel       |
        | (CG or SDF) |    |             |
        +------+------+    +-------------+
               |
               v
        +------+------+
        | Display     |
        | (MTKView /  |
        | CAMetalDL)  |
        +-------------+
```

### Key Integration Points
1. **ShaderLibraryManager** loads both built-in and plugin .metallib files
2. **Function constants** enable uber-shaders that specialize per-effect-combination
3. **MTLBinaryArchive** caches compiled pipelines for instant loading
4. **MTLDynamicLibrary** enables third-party shader plugins
5. **Plugin Registry** discovers .effectpkg bundles containing manifests + metallibs
6. **Node Graph** evaluates compositing DAG with topological sort
7. **Render Graph** manages resource lifetimes and pass ordering automatically
8. **Video Scopes** run as compute shaders on every displayed frame
9. **Text Renderer** uses CoreGraphics for static text, SDF for animated titles
10. **All systems share** the same MTLDevice, MTLCommandQueue, and texture pool
