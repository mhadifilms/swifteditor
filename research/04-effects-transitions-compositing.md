# Effects, Transitions & Compositing — Complete Reference

## 1. Core Image Filters by Category

### CICategoryColorAdjustment
Filters that change color distribution throughout an image.

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CIExposureAdjust | inputEV (Float, -10 to 10) | Exposure compensation |
| CIGammaAdjust | inputPower (Float, 0.25 to 4.0) | Gamma curve |
| CIHueAdjust | inputAngle (Float, radians) | Hue rotation |
| CIColorControls | inputSaturation, inputBrightness, inputContrast | Basic color controls |
| CITemperatureAndTint | inputNeutral (CIVector), inputTargetNeutral | White balance |
| CIToneCurve | inputPoint0-4 (CIVector) | 5-point tone curve |
| CIVibrance | inputAmount (Float, -1 to 1) | Smart saturation |
| CIWhitePointAdjust | inputColor (CIColor) | White point |
| CIColorMatrix | inputRVector, inputGVector, inputBVector, inputAVector, inputBiasVector | Full color matrix transform |
| CIColorPolynomial | inputRedCoefficients, inputGreenCoefficients, inputBlueCoefficients, inputAlphaCoefficients | Polynomial color remap |
| CIColorClamp | inputMinComponents, inputMaxComponents (CIVector) | Clamp color values |
| CILinearToSRGBToneCurve | (none) | Linear to sRGB conversion |
| CISRGBToneCurveToLinear | (none) | sRGB to linear conversion |

### CICategoryColorEffect
Subjective color changes and stylization.

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CIColorCube | inputCubeDimension, inputCubeData | 3D LUT application |
| CIColorCubeWithColorSpace | inputCubeDimension, inputCubeData, inputColorSpace | LUT with color space |
| CIColorCubesMixedWithMask | inputCubeDimension, inputCube0Data, inputCube1Data, inputMaskImage | Masked dual-LUT |
| CIColorCurves | inputCurvesData, inputCurvesDomain, inputColorSpace | RGB curves |
| CIColorMap | inputGradientImage | Map colors via gradient |
| CIColorMonochrome | inputColor, inputIntensity | Monochrome tint |
| CIColorPosterize | inputLevels | Reduce color levels |
| CIPhotoEffectChrome | (none) | Chrome film look |
| CIPhotoEffectFade | (none) | Faded film look |
| CIPhotoEffectInstant | (none) | Instant camera look |
| CIPhotoEffectMono | (none) | Monochrome |
| CIPhotoEffectNoir | (none) | High-contrast B&W |
| CIPhotoEffectProcess | (none) | Cross-process look |
| CIPhotoEffectTonal | (none) | Tonal B&W |
| CIPhotoEffectTransfer | (none) | Transfer film look |
| CISepiaTone | inputIntensity | Sepia effect |
| CIVignette | inputRadius, inputIntensity | Vignette darkening |
| CIVignetteEffect | inputCenter, inputRadius, inputIntensity, inputFalloff | Positioned vignette |

### CICategoryBlur
Blur and noise reduction filters.

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CIGaussianBlur | inputRadius (0-100) | Standard gaussian blur |
| CIBoxBlur | inputRadius | Box blur (fast) |
| CIDiscBlur | inputRadius | Disc/circle blur |
| CIMotionBlur | inputRadius, inputAngle | Directional motion blur |
| CIZoomBlur | inputCenter, inputAmount | Radial zoom blur |
| CIBokehBlur | inputRadius, inputRingAmount, inputRingSize, inputSoftness | Bokeh depth-of-field |
| CIMaskedVariableBlur | inputRadius, inputMask | Depth-based variable blur |
| CIMedianFilter | (none) | Noise reduction via median |
| CINoiseReduction | inputNoiseLevel, inputSharpness | Noise reduction |
| CIMorphologyGradient | inputRadius | Edge detection via morphology |
| CIMorphologyMaximum | inputRadius | Dilation |
| CIMorphologyMinimum | inputRadius | Erosion |

### CICategoryDistortionEffect
Geometric pixel displacement filters.

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CIBumpDistortion | inputCenter, inputRadius, inputScale | Spherical bump |
| CIBumpDistortionLinear | inputCenter, inputRadius, inputAngle, inputScale | Linear bump |
| CIPinchDistortion | inputCenter, inputRadius, inputScale | Pinch/expand |
| CITwirlDistortion | inputCenter, inputRadius, inputAngle | Spiral twist |
| CIVortexDistortion | inputCenter, inputRadius, inputAngle | Vortex swirl |
| CICircleSplashDistortion | inputCenter, inputRadius | Circular ripple |
| CIHoleDistortion | inputCenter, inputRadius | Hole/tunnel |
| CIGlassDistortion | inputTexture, inputCenter, inputScale | Glass refraction |
| CIDisplacementDistortion | inputDisplacementImage, inputScale | Displacement map |
| CIStretchCrop | inputSize, inputCropAmount, inputCenterStretchAmount | Stretch to fit |
| CITorusLensDistortion | inputCenter, inputRadius, inputWidth, inputRefraction | Torus lens |
| CICircularWrap | inputCenter, inputRadius, inputAngle | Wrap around cylinder |
| CIDroste | inputInsetPoint0, inputInsetPoint1, inputStrands, inputPeriodicity, inputRotation, inputZoom | Recursive Droste |

### CICategorySharpen

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CISharpenLuminance | inputSharpness, inputRadius | Luminance sharpening |
| CIUnsharpMask | inputRadius, inputIntensity | Unsharp mask sharpening |

### CICategoryStylize

| Filter | Key Parameters | Use Case |
|--------|---------------|----------|
| CIBloom | inputRadius, inputIntensity | Glow/bloom effect |
| CIGloom | inputRadius, inputIntensity | Dark glow |
| CIHighlightShadowAdjust | inputHighlightAmount, inputShadowAmount, inputRadius | Shadows/highlights |
| CIPixellate | inputCenter, inputScale | Pixelation |
| CIHexagonalPixellate | inputCenter, inputScale | Hex pixelation |
| CICrystallize | inputRadius, inputCenter | Crystal facets |
| CIPointillize | inputRadius, inputCenter | Pointillist dots |
| CIComicEffect | (none) | Comic book style |
| CIEdges | inputIntensity | Edge detection |
| CIEdgeWork | inputRadius | Edge threshold |
| CILineOverlay | inputNRNoiseLevel, inputNRSharpness, inputEdgeIntensity, inputThreshold, inputContrast | Line drawing |
| CIConvolution3X3 | inputWeights, inputBias | 3x3 custom convolution |
| CIConvolution5X5 | inputWeights, inputBias | 5x5 custom convolution |
| CIConvolution7X7 | inputWeights, inputBias | 7x7 custom convolution |
| CIBlendWithMask | inputMaskImage | Masked compositing |
| CIBlendWithAlphaMask | inputMaskImage | Alpha-based masking |
| CISpotLight | inputLightPosition, inputLightPointsAt, inputBrightness, inputConcentration, inputColor | Spotlight effect |
| CIDepthOfField | inputPoint0, inputPoint1, inputSaturation, inputUnsharpMaskRadius, inputUnsharpMaskIntensity, inputRadius | Tilt-shift DoF |
| CIMix | inputAmount | Mix two images |

### CICategoryGenerator (Video-Relevant)

| Filter | Use Case |
|--------|----------|
| CIConstantColorGenerator | Solid color frames |
| CICheckerboardGenerator | Test patterns |
| CIStripesGenerator | Stripe patterns |
| CIRandomGenerator | Noise/grain generation |
| CIStarShineGenerator | Star/lens flare |
| CISunbeamsGenerator | Light ray effect |
| CILenticularHaloGenerator | Halo/glow effect |

---

## 2. Custom CIKernel with Metal Backend

### Build Configuration

In Xcode Build Settings:
- **Other Metal Compiler Flags**: Add `-fcikernel`
- **Other Metal Linker Flags**: Add `-cikernel`
- Name Metal source files with `.ci.metal` extension

### CIColorKernel — Per-Pixel Color Transform

Metal shader (Desaturate.ci.metal):
```metal
#include <CoreImage/CoreImage.h>

extern "C" {
    float4 desaturateKernel(coreimage::sample_t pixel, float amount) {
        float luma = dot(pixel.rgb, float3(0.2126, 0.7152, 0.0722));
        float3 gray = float3(luma);
        float3 result = mix(pixel.rgb, gray, amount);
        return float4(result, pixel.a);
    }
}
```

Swift CIFilter subclass:
```swift
class DesaturateFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var inputAmount: Float = 0.5

    private static var kernel: CIColorKernel = {
        let url = Bundle.main.url(forResource: "default", withExtension: "ci.metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIColorKernel(functionName: "desaturateKernel",
                                   fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }
        return Self.kernel.apply(
            extent: input.extent,
            arguments: [input, inputAmount]
        )
    }
}
```

### CIWarpKernel — Per-Pixel Position Transform

Metal shader (Bulge.ci.metal):
```metal
#include <CoreImage/CoreImage.h>

extern "C" {
    float2 bulgeKernel(float2 position, float2 center, float radius, float scale) {
        float2 delta = position - center;
        float dist = length(delta);
        if (dist < radius) {
            float percent = 1.0 - (dist / radius);
            float bulge = percent * percent * scale;
            delta *= (1.0 + bulge);
        }
        return center + delta;
    }
}
```

Swift wrapper:
```swift
class BulgeFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var inputCenter = CIVector(x: 150, y: 150)
    @objc dynamic var inputRadius: Float = 100
    @objc dynamic var inputScale: Float = 0.5

    private static var kernel: CIWarpKernel = {
        let url = Bundle.main.url(forResource: "default", withExtension: "ci.metallib")!
        let data = try! Data(contentsOf: url)
        return try! CIWarpKernel(functionName: "bulgeKernel",
                                  fromMetalLibraryData: data)
    }()

    override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }
        return Self.kernel.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect },
            image: input,
            arguments: [inputCenter, inputRadius, inputScale]
        )
    }
}
```

### CIBlendKernel — Two-Image Compositing

Metal shader (CustomBlend.ci.metal):
```metal
#include <CoreImage/CoreImage.h>

extern "C" {
    float4 customBlendKernel(coreimage::sample_t foreground,
                              coreimage::sample_t background,
                              float opacity) {
        float3 blended = foreground.rgb * opacity + background.rgb * (1.0 - opacity);
        return float4(blended, max(foreground.a, background.a));
    }
}
```

### Built-in CIBlendKernel Modes (37+ Available)

Porter-Duff: `.source`, `.sourceOver`, `.sourceIn`, `.sourceOut`, `.sourceAtop`, `.destination`, `.destinationOver`, `.destinationIn`, `.destinationOut`, `.destinationAtop`, `.clear`, `.exclusiveOr`

Standard Blends: `.multiply`, `.screen`, `.overlay`, `.darken`, `.lighten`, `.darkerColor`, `.lighterColor`, `.colorDodge`, `.colorBurn`, `.softLight`, `.hardLight`, `.difference`, `.exclusion`, `.linearBurn`, `.linearDodge`, `.linearLight`, `.vividLight`, `.pinLight`, `.hardMix`, `.subtract`, `.divide`

HSL Component: `.hue`, `.saturation`, `.color`, `.luminosity`

Component: `.componentAdd`, `.componentMultiply`, `.componentMin`, `.componentMax`

Usage:
```swift
let blended = CIBlendKernel.overlay.apply(
    foreground: topImage,
    background: bottomImage
)
```

---

## 3. Blend Modes — Metal Shader Implementations

All standard blend modes translated to Metal Shading Language for use in compute/fragment shaders:

```metal
#include <metal_stdlib>
using namespace metal;

// ============================================================
// Separable Blend Modes (operate per-channel)
// ============================================================

// Normal: standard alpha compositing
float3 blendNormal(float3 base, float3 blend, float opacity) {
    return mix(base, blend, opacity);
}

// Multiply: darken by multiplying
float3 blendMultiply(float3 base, float3 blend) {
    return base * blend;
}

// Screen: lighten (inverse multiply)
float3 blendScreen(float3 base, float3 blend) {
    return base + blend - base * blend;
}

// Overlay: multiply darks, screen lights
float blendOverlayChannel(float base, float blend) {
    return (base <= 0.5)
        ? 2.0 * base * blend
        : 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
}
float3 blendOverlay(float3 base, float3 blend) {
    return float3(
        blendOverlayChannel(base.r, blend.r),
        blendOverlayChannel(base.g, blend.g),
        blendOverlayChannel(base.b, blend.b)
    );
}

// Soft Light: subtle dodging/burning
float blendSoftLightChannel(float base, float blend) {
    if (blend <= 0.5) {
        return base - (1.0 - 2.0 * blend) * base * (1.0 - base);
    } else {
        float d = (base <= 0.25)
            ? ((16.0 * base - 12.0) * base + 4.0) * base
            : sqrt(base);
        return base + (2.0 * blend - 1.0) * (d - base);
    }
}
float3 blendSoftLight(float3 base, float3 blend) {
    return float3(
        blendSoftLightChannel(base.r, blend.r),
        blendSoftLightChannel(base.g, blend.g),
        blendSoftLightChannel(base.b, blend.b)
    );
}

// Hard Light: like overlay but with blend/base swapped
float blendHardLightChannel(float base, float blend) {
    return (blend <= 0.5)
        ? 2.0 * base * blend
        : 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
}
float3 blendHardLight(float3 base, float3 blend) {
    return float3(
        blendHardLightChannel(base.r, blend.r),
        blendHardLightChannel(base.g, blend.g),
        blendHardLightChannel(base.b, blend.b)
    );
}

// Color Dodge: brighten base to reflect blend
float blendColorDodgeChannel(float base, float blend) {
    if (base <= 0.0) return 0.0;
    if (blend >= 1.0) return 1.0;
    return min(1.0, base / (1.0 - blend));
}
float3 blendColorDodge(float3 base, float3 blend) {
    return float3(
        blendColorDodgeChannel(base.r, blend.r),
        blendColorDodgeChannel(base.g, blend.g),
        blendColorDodgeChannel(base.b, blend.b)
    );
}

// Color Burn: darken base to reflect blend
float blendColorBurnChannel(float base, float blend) {
    if (base >= 1.0) return 1.0;
    if (blend <= 0.0) return 0.0;
    return 1.0 - min(1.0, (1.0 - base) / blend);
}
float3 blendColorBurn(float3 base, float3 blend) {
    return float3(
        blendColorBurnChannel(base.r, blend.r),
        blendColorBurnChannel(base.g, blend.g),
        blendColorBurnChannel(base.b, blend.b)
    );
}

// Difference: absolute difference
float3 blendDifference(float3 base, float3 blend) {
    return abs(base - blend);
}

// Exclusion: low-contrast difference
float3 blendExclusion(float3 base, float3 blend) {
    return base + blend - 2.0 * base * blend;
}

// ============================================================
// Non-Separable Blend Modes (require luminosity/saturation)
// ============================================================

float getLuminosity(float3 c) {
    return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
}

float getSaturation(float3 c) {
    return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

float3 clipColor(float3 c) {
    float l = getLuminosity(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0) c = l + (c - l) * l / (l - n);
    if (x > 1.0) c = l + (c - l) * (1.0 - l) / (x - l);
    return c;
}

float3 setLuminosity(float3 c, float l) {
    float d = l - getLuminosity(c);
    return clipColor(c + d);
}

float3 setSaturation(float3 c, float s) {
    float cMin = min(c.r, min(c.g, c.b));
    float cMax = max(c.r, max(c.g, c.b));
    float3 result = float3(0.0);
    if (cMax > cMin) {
        // Simplified: scale the color range to target saturation
        float currentSat = cMax - cMin;
        result = (c - cMin) * (s / currentSat);
    }
    return result;
}

// Hue: hue from blend, saturation+luminosity from base
float3 blendHue(float3 base, float3 blend) {
    return setLuminosity(
        setSaturation(blend, getSaturation(base)),
        getLuminosity(base)
    );
}

// Saturation: saturation from blend, hue+luminosity from base
float3 blendSaturation(float3 base, float3 blend) {
    return setLuminosity(
        setSaturation(base, getSaturation(blend)),
        getLuminosity(base)
    );
}

// Color: hue+saturation from blend, luminosity from base
float3 blendColor(float3 base, float3 blend) {
    return setLuminosity(blend, getLuminosity(base));
}

// Luminosity: luminosity from blend, hue+saturation from base
float3 blendLuminosity(float3 base, float3 blend) {
    return setLuminosity(base, getLuminosity(blend));
}

// ============================================================
// Dispatch function for compute kernel
// ============================================================

kernel void blendComposite(
    texture2d<float, access::read> base      [[texture(0)]],
    texture2d<float, access::read> blend     [[texture(1)]],
    texture2d<float, access::write> output   [[texture(2)]],
    constant int &blendMode                  [[buffer(0)]],
    constant float &opacity                  [[buffer(1)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 baseColor = base.read(gid);
    float4 blendColor = blend.read(gid);
    float3 result;

    switch (blendMode) {
        case 0:  result = blendMultiply(baseColor.rgb, blendColor.rgb); break;
        case 1:  result = blendScreen(baseColor.rgb, blendColor.rgb); break;
        case 2:  result = blendOverlay(baseColor.rgb, blendColor.rgb); break;
        case 3:  result = blendSoftLight(baseColor.rgb, blendColor.rgb); break;
        case 4:  result = blendHardLight(baseColor.rgb, blendColor.rgb); break;
        case 5:  result = blendColorDodge(baseColor.rgb, blendColor.rgb); break;
        case 6:  result = blendColorBurn(baseColor.rgb, blendColor.rgb); break;
        case 7:  result = blendDifference(baseColor.rgb, blendColor.rgb); break;
        case 8:  result = blendExclusion(baseColor.rgb, blendColor.rgb); break;
        case 9:  result = blendHue(baseColor.rgb, blendColor.rgb); break;
        case 10: result = blendSaturation(baseColor.rgb, blendColor.rgb); break;
        case 11: result = blendColor(baseColor.rgb, blendColor.rgb); break;
        case 12: result = blendLuminosity(baseColor.rgb, blendColor.rgb); break;
        default: result = blendColor.rgb; break;
    }

    // Apply opacity and alpha compositing
    float3 finalRGB = mix(baseColor.rgb, result, opacity * blendColor.a);
    float finalAlpha = baseColor.a + blendColor.a * (1.0 - baseColor.a);
    output.write(float4(finalRGB, finalAlpha), gid);
}
```

---

## 4. AVVideoComposition Transitions

### Two-Track Alternating Pattern

The standard approach for transitions in AVFoundation uses two video tracks. Clips alternate between tracks, with overlapping regions defining transition zones.

```swift
import AVFoundation

class TransitionEditor {

    func buildComposition(
        clips: [AVAsset],
        transitionDuration: CMTime
    ) -> (AVMutableComposition, AVMutableVideoComposition) {

        let composition = AVMutableComposition()

        // Create two alternating video and audio tracks
        let videoTrackA = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid)!
        let videoTrackB = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid)!
        let videoTracks = [videoTrackA, videoTrackB]

        let audioTrackA = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audioTrackB = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audioTracks = [audioTrackA, audioTrackB]

        // Track time ranges for pass-through and transitions
        var passThroughTimeRanges = [CMTimeRange](repeating: .zero, count: clips.count)
        var transitionTimeRanges = [CMTimeRange](repeating: .zero, count: clips.count)

        var nextClipStartTime = CMTime.zero

        // Insert clips alternating between tracks
        for i in 0..<clips.count {
            let trackIndex = i % 2
            let asset = clips[i]
            let assetVideoTrack = asset.tracks(withMediaType: .video).first!
            let timeRange = CMTimeRange(
                start: .zero,
                duration: asset.duration
            )

            try! videoTracks[trackIndex].insertTimeRange(
                timeRange, of: assetVideoTrack, at: nextClipStartTime)

            if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                try! audioTracks[trackIndex].insertTimeRange(
                    timeRange, of: assetAudioTrack, at: nextClipStartTime)
            }

            // Calculate pass-through and transition ranges
            passThroughTimeRanges[i] = CMTimeRange(
                start: nextClipStartTime, duration: asset.duration)

            if i > 0 {
                // Trim previous pass-through to end before transition
                passThroughTimeRanges[i - 1].duration = CMTimeSubtract(
                    passThroughTimeRanges[i - 1].duration, transitionDuration)
                // Current pass-through starts after transition
                passThroughTimeRanges[i].start = CMTimeAdd(
                    passThroughTimeRanges[i].start, transitionDuration)
                passThroughTimeRanges[i].duration = CMTimeSubtract(
                    passThroughTimeRanges[i].duration, transitionDuration)
                // Transition range overlaps both clips
                transitionTimeRanges[i - 1] = CMTimeRange(
                    start: nextClipStartTime,
                    duration: transitionDuration)
            }

            nextClipStartTime = CMTimeAdd(nextClipStartTime, asset.duration)
            nextClipStartTime = CMTimeSubtract(nextClipStartTime, transitionDuration)
        }

        // Build video composition instructions
        var instructions = [AVVideoCompositionInstructionProtocol]()

        for i in 0..<clips.count {
            let trackIndex = i % 2

            // Pass-through instruction: show single track
            if passThroughTimeRanges[i].duration > .zero {
                let passInstruction = AVMutableVideoCompositionInstruction()
                passInstruction.timeRange = passThroughTimeRanges[i]
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[trackIndex])
                passInstruction.layerInstructions = [layerInstruction]
                instructions.append(passInstruction)
            }

            // Transition instruction: blend two tracks
            if i < clips.count - 1 && transitionTimeRanges[i].duration > .zero {
                let transInstruction = AVMutableVideoCompositionInstruction()
                transInstruction.timeRange = transitionTimeRanges[i]

                let fromLayer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[trackIndex])
                fromLayer.setOpacityRamp(
                    fromStartOpacity: 1.0, toEndOpacity: 0.0,
                    timeRange: transitionTimeRanges[i])

                let toLayer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[(trackIndex + 1) % 2])
                toLayer.setOpacityRamp(
                    fromStartOpacity: 0.0, toEndOpacity: 1.0,
                    timeRange: transitionTimeRanges[i])

                transInstruction.layerInstructions = [fromLayer, toLayer]
                instructions.append(transInstruction)
            }
        }

        // Sort instructions by time
        instructions.sort {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = CGSize(width: 1920, height: 1080)

        return (composition, videoComposition)
    }
}
```

### Custom AVVideoCompositing Protocol

For custom transition rendering with Metal:

```swift
import AVFoundation
import Metal
import CoreVideo

class MetalVideoCompositor: NSObject, AVVideoCompositing {

    private let renderingQueue = DispatchQueue(label: "com.editor.metalCompositor")
    private var renderContext: AVVideoCompositionRenderContext?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?

    var sourcePixelBufferAttributes: [String: Any]? {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    override init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderingQueue.sync {
            self.renderContext = newRenderContext
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async { [weak self] in
            guard let self = self else { return }

            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction
                    as? TransitionInstruction else {
                    request.finish(with: NSError(domain: "compositor", code: -1))
                    return
                }

                if let result = self.renderTransition(request: request,
                                                       instruction: instruction) {
                    request.finish(withComposedVideoFrame: result)
                } else {
                    request.finish(with: NSError(domain: "compositor", code: -2))
                }
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderingQueue.sync {
            // Cancel pending work
        }
    }

    private func renderTransition(
        request: AVAsynchronousVideoCompositionRequest,
        instruction: TransitionInstruction
    ) -> CVPixelBuffer? {
        // Calculate progress through transition (0.0 to 1.0)
        let elapsed = CMTimeSubtract(
            request.compositionTime, instruction.timeRange.start)
        let progress = Float(CMTimeGetSeconds(elapsed) /
            CMTimeGetSeconds(instruction.timeRange.duration))

        // Get source pixel buffers
        let trackIDs = instruction.requiredSourceTrackIDs as! [CMPersistentTrackID]
        guard trackIDs.count >= 2,
              let fromBuffer = request.sourceFrame(byTrackID: trackIDs[0]),
              let toBuffer = request.sourceFrame(byTrackID: trackIDs[1]),
              let outputBuffer = renderContext?.newPixelBuffer() else {
            return nil
        }

        // Convert to Metal textures and render
        guard let fromTexture = makeTexture(from: fromBuffer),
              let toTexture = makeTexture(from: toBuffer),
              let outTexture = makeTexture(from: outputBuffer) else {
            return nil
        }

        // Dispatch Metal compute shader for the transition
        renderTransitionEffect(
            from: fromTexture, to: toTexture, output: outTexture,
            progress: progress, type: instruction.transitionType)

        return outputBuffer
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache!, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture)
        return cvTexture.flatMap { CVMetalTextureGetTexture($0) }
    }

    private func renderTransitionEffect(
        from: MTLTexture, to: MTLTexture, output: MTLTexture,
        progress: Float, type: TransitionType
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        let pipelineState = getTransitionPipeline(for: type)
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(from, index: 0)
        encoder.setTexture(to, index: 1)
        encoder.setTexture(output, index: 2)
        var prog = progress
        encoder.setBytes(&prog, length: MemoryLayout<Float>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (output.width + 15) / 16,
            height: (output.height + 15) / 16,
            depth: 1)
        encoder.dispatchThreadgroups(threadGroups,
                                      threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
```

Custom instruction:
```swift
class TransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweenedVideoInstruction: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var transitionType: TransitionType = .crossDissolve

    init(timeRange: CMTimeRange, fromTrackID: CMPersistentTrackID,
         toTrackID: CMPersistentTrackID, type: TransitionType) {
        self.timeRange = timeRange
        self.transitionType = type
        self.requiredSourceTrackIDs = [
            NSNumber(value: fromTrackID),
            NSNumber(value: toTrackID)
        ]
        super.init()
    }
}

enum TransitionType: Int {
    case crossDissolve = 0
    case wipeLeft = 1
    case wipeRight = 2
    case wipeUp = 3
    case wipeDown = 4
    case pushLeft = 5
    case slide = 6
    case zoom = 7
    case iris = 8
    case pageCurl = 9
}
```

---

## 5. Custom Transitions — Metal Shader Implementations

```metal
#include <metal_stdlib>
using namespace metal;

// Cross Dissolve
kernel void crossDissolveTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    outTex.write(mix(fromColor, toColor, progress), gid);
}

// Directional Wipe (configurable direction)
kernel void wipeTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    constant float2 &direction               [[buffer(1)]],  // e.g. (1,0) for left-to-right
    constant float &softness                 [[buffer(2)]],   // edge softness 0.0-0.1
    uint2 gid                                [[thread_position_in_grid]])
{
    float2 uv = float2(gid) / float2(outTex.get_width(), outTex.get_height());
    float edge = dot(uv, normalize(direction));
    float alpha = smoothstep(progress - softness, progress + softness, edge);

    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    outTex.write(mix(fromColor, toColor, alpha), gid);
}

// Push Transition
kernel void pushTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    int width = outTex.get_width();
    int offset = int(float(width) * progress);

    // From image slides out to left, To image slides in from right
    int fromX = int(gid.x) + offset;
    int toX = int(gid.x) - (width - offset);

    float4 color;
    if (fromX < width && fromX >= 0) {
        color = fromTex.read(uint2(fromX, gid.y));
    } else {
        color = float4(0);
    }
    if (toX >= 0 && toX < width) {
        color = toTex.read(uint2(toX, gid.y));
    }
    outTex.write(color, gid);
}

// Zoom Transition (zoom into from, zoom out from to)
kernel void zoomTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    float2 center = float2(0.5);

    // Zoom from image (scale up as progress increases)
    float fromScale = 1.0 + progress * 2.0;
    float2 fromUV = center + (uv - center) / fromScale;

    // Zoom to image (start scaled up, converge to 1.0)
    float toScale = 1.0 + (1.0 - progress) * 2.0;
    float2 toUV = center + (uv - center) / toScale;

    float4 fromColor = float4(0);
    if (all(fromUV >= 0.0) && all(fromUV <= 1.0)) {
        uint2 fromCoord = uint2(fromUV * size);
        fromColor = fromTex.read(fromCoord);
    }

    float4 toColor = float4(0);
    if (all(toUV >= 0.0) && all(toUV <= 1.0)) {
        uint2 toCoord = uint2(toUV * size);
        toColor = toTex.read(toCoord);
    }

    // Cross-fade between zoomed images
    outTex.write(mix(fromColor, toColor, smoothstep(0.3, 0.7, progress)), gid);
}

// Iris (circular reveal)
kernel void irisTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    float2 center = float2(0.5);

    float maxRadius = length(float2(0.5)); // ~0.707
    float radius = progress * maxRadius * 1.5;
    float dist = length(uv - center);

    float softness = 0.01;
    float alpha = smoothstep(radius - softness, radius + softness, dist);

    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    // Inside circle = toColor, outside = fromColor
    outTex.write(mix(toColor, fromColor, alpha), gid);
}

// Slide (to image slides over from image)
kernel void slideTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    int width = outTex.get_width();
    int cutoff = int(float(width) * progress);

    float4 color;
    if (int(gid.x) < cutoff) {
        // To image slides in from left
        int toX = int(gid.x) + (width - cutoff);
        toX = clamp(toX, 0, width - 1);
        color = toTex.read(uint2(toX, gid.y));
    } else {
        color = fromTex.read(gid);
    }
    outTex.write(color, gid);
}

// Radial Wipe (clock wipe)
kernel void radialWipeTransition(
    texture2d<float, access::read> fromTex   [[texture(0)]],
    texture2d<float, access::read> toTex     [[texture(1)]],
    texture2d<float, access::write> outTex   [[texture(2)]],
    constant float &progress                 [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]])
{
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    float2 center = float2(0.5);

    float angle = atan2(uv.y - center.y, uv.x - center.x);
    // Normalize angle from [-pi, pi] to [0, 1], starting from top
    float normalizedAngle = fmod((angle + M_PI_F * 2.5) / (M_PI_F * 2.0), 1.0);

    float softness = 0.005;
    float alpha = smoothstep(progress - softness, progress + softness, normalizedAngle);

    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    outTex.write(mix(toColor, fromColor, alpha), gid);
}
```

---

## 6. Keyframeable Parameters

### Data Model

```swift
// Interpolation types for keyframes
enum KeyframeInterpolation: Codable {
    case linear
    case bezier(controlIn: SIMD2<Float>, controlOut: SIMD2<Float>)
    case hold  // step function, no interpolation
}

// Supported parameter types
enum ParameterValue: Codable {
    case float(Float)
    case color(SIMD4<Float>)        // RGBA
    case point(SIMD2<Float>)        // XY
    case bool(Bool)
    case int(Int)
    case angle(Float)               // radians
}

// Single keyframe
struct Keyframe<T: Interpolatable>: Identifiable, Codable {
    let id: UUID
    var time: CMTime                // position on timeline
    var value: T
    var interpolation: KeyframeInterpolation

    init(time: CMTime, value: T,
         interpolation: KeyframeInterpolation = .linear) {
        self.id = UUID()
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }
}

// Track of keyframes for a single parameter
struct KeyframeTrack<T: Interpolatable>: Codable {
    var keyframes: [Keyframe<T>] = []

    mutating func addKeyframe(_ keyframe: Keyframe<T>) {
        keyframes.append(keyframe)
        keyframes.sort { CMTimeCompare($0.time, $1.time) < 0 }
    }

    mutating func removeKeyframe(at index: Int) {
        keyframes.remove(at: index)
    }

    /// Evaluate the interpolated value at a given time
    func evaluate(at time: CMTime) -> T? {
        guard !keyframes.isEmpty else { return nil }
        guard keyframes.count > 1 else { return keyframes.first?.value }

        // Before first keyframe
        if CMTimeCompare(time, keyframes.first!.time) <= 0 {
            return keyframes.first!.value
        }
        // After last keyframe
        if CMTimeCompare(time, keyframes.last!.time) >= 0 {
            return keyframes.last!.value
        }

        // Find surrounding keyframes
        for i in 0..<keyframes.count - 1 {
            let k0 = keyframes[i]
            let k1 = keyframes[i + 1]
            if CMTimeCompare(time, k0.time) >= 0 &&
               CMTimeCompare(time, k1.time) < 0 {
                return interpolate(from: k0, to: k1, at: time)
            }
        }
        return keyframes.last?.value
    }

    private func interpolate(from k0: Keyframe<T>, to k1: Keyframe<T>,
                              at time: CMTime) -> T {
        let duration = CMTimeGetSeconds(CMTimeSubtract(k1.time, k0.time))
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(time, k0.time))
        let linearT = Float(elapsed / duration)

        switch k1.interpolation {
        case .hold:
            return k0.value
        case .linear:
            return T.lerp(k0.value, k1.value, linearT)
        case .bezier(let controlIn, let controlOut):
            let t = cubicBezierSolve(x: linearT,
                                      p1: controlIn, p2: controlOut)
            return T.lerp(k0.value, k1.value, t)
        }
    }
}

// Protocol for values that can be interpolated
protocol Interpolatable: Codable {
    static func lerp(_ a: Self, _ b: Self, _ t: Float) -> Self
}

extension Float: Interpolatable {
    static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }
}

extension SIMD2<Float>: Interpolatable {
    static func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>,
                     _ t: Float) -> SIMD2<Float> {
        return a + (b - a) * t
    }
}

extension SIMD4<Float>: Interpolatable {
    static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>,
                     _ t: Float) -> SIMD4<Float> {
        return a + (b - a) * t
    }
}

// Cubic Bezier solver for easing curves
// Given x (time), solve for y (value) on the bezier curve
func cubicBezierSolve(x: Float, p1: SIMD2<Float>,
                       p2: SIMD2<Float>) -> Float {
    // Newton's method to find t for given x
    var t = x
    for _ in 0..<8 {
        let cx = cubicBezierEval(t: t, p1: p1.x, p2: p2.x) - x
        let dx = cubicBezierDerivative(t: t, p1: p1.x, p2: p2.x)
        if abs(dx) < 1e-6 { break }
        t -= cx / dx
        t = max(0, min(1, t))
    }
    return cubicBezierEval(t: t, p1: p1.y, p2: p2.y)
}

func cubicBezierEval(t: Float, p1: Float, p2: Float) -> Float {
    let oneMinusT = 1.0 - t
    return 3.0 * oneMinusT * oneMinusT * t * p1 +
           3.0 * oneMinusT * t * t * p2 +
           t * t * t
}

func cubicBezierDerivative(t: Float, p1: Float, p2: Float) -> Float {
    let oneMinusT = 1.0 - t
    return 3.0 * oneMinusT * oneMinusT * p1 +
           6.0 * oneMinusT * t * (p2 - p1) +
           3.0 * t * t * (1.0 - p2)
}
```

### Effect Parameter Definition

```swift
struct EffectParameterDefinition {
    let id: String
    let name: String
    let type: ParameterType
    let defaultValue: ParameterValue
    let minValue: ParameterValue?
    let maxValue: ParameterValue?
    let isKeyframeable: Bool

    enum ParameterType {
        case float, color, point, bool, int, angle, menu([String])
    }
}

// Example effect with keyframeable parameters
let gaussianBlurParams = [
    EffectParameterDefinition(
        id: "radius", name: "Radius", type: .float,
        defaultValue: .float(10), minValue: .float(0),
        maxValue: .float(100), isKeyframeable: true),
]

let colorCorrectionParams = [
    EffectParameterDefinition(
        id: "exposure", name: "Exposure", type: .float,
        defaultValue: .float(0), minValue: .float(-5),
        maxValue: .float(5), isKeyframeable: true),
    EffectParameterDefinition(
        id: "temperature", name: "Temperature", type: .float,
        defaultValue: .float(6500), minValue: .float(2000),
        maxValue: .float(12000), isKeyframeable: true),
    EffectParameterDefinition(
        id: "tint", name: "Tint", type: .color,
        defaultValue: .color(SIMD4<Float>(1, 1, 1, 1)),
        minValue: nil, maxValue: nil, isKeyframeable: true),
]
```

---

## 7. LUT Support

### .cube File Parsing

```swift
struct CubeLUT {
    let title: String
    let size: Int           // e.g. 17, 33, 65
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
    let data: [SIMD3<Float>]  // size^3 RGB entries

    /// Parse a .cube file from string content
    static func parse(from content: String) throws -> CubeLUT {
        var title = ""
        var size = 0
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var data = [SIMD3<Float>]()

        let lines = content.components(separatedBy: .newlines)
        var parsingData = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE") {
                title = trimmed
                    .replacingOccurrences(of: "TITLE", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                continue
            }
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                    data.reserveCapacity(s * s * s)
                }
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4 {
                    domainMin = SIMD3<Float>(
                        Float(parts[1])!, Float(parts[2])!, Float(parts[3])!)
                }
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4 {
                    domainMax = SIMD3<Float>(
                        Float(parts[1])!, Float(parts[2])!, Float(parts[3])!)
                }
                continue
            }

            // Data lines: three floats per line
            let parts = trimmed.split(separator: " ")
            if parts.count >= 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                data.append(SIMD3<Float>(r, g, b))
            }
        }

        guard size > 0, data.count == size * size * size else {
            throw LUTError.invalidFormat
        }

        return CubeLUT(title: title, size: size,
                        domainMin: domainMin, domainMax: domainMax, data: data)
    }
}

enum LUTError: Error {
    case invalidFormat
    case textureCreationFailed
}
```

### 3D Texture Creation for Metal

```swift
extension CubeLUT {
    /// Create a MTLTexture from the LUT data for GPU sampling
    func createMetalTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw LUTError.textureCreationFailed
        }

        // Convert SIMD3 RGB to RGBA float array
        var rgbaData = [Float](repeating: 0, count: size * size * size * 4)
        for i in 0..<data.count {
            rgbaData[i * 4 + 0] = data[i].x  // R
            rgbaData[i * 4 + 1] = data[i].y  // G
            rgbaData[i * 4 + 2] = data[i].z  // B
            rgbaData[i * 4 + 3] = 1.0         // A
        }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: size, height: size, depth: size))

        texture.replace(
            region: region, mipmapLevel: 0, slice: 0,
            withBytes: rgbaData,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            bytesPerImage: size * size * 4 * MemoryLayout<Float>.size)

        return texture
    }

    /// Alternative: use CIColorCube for Core Image pipeline
    func createCIFilter() -> CIFilter? {
        let filter = CIFilter(name: "CIColorCube")
        var cubeData = [Float]()
        cubeData.reserveCapacity(size * size * size * 4)
        for entry in data {
            cubeData.append(entry.x)
            cubeData.append(entry.y)
            cubeData.append(entry.z)
            cubeData.append(1.0)
        }
        let data = Data(bytes: cubeData,
                         count: cubeData.count * MemoryLayout<Float>.size)
        filter?.setValue(size, forKey: "inputCubeDimension")
        filter?.setValue(data, forKey: "inputCubeData")
        return filter
    }
}
```

### Metal Shader for 3D LUT Lookup

```metal
#include <metal_stdlib>
using namespace metal;

// Trilinear interpolation is handled automatically by the sampler
// when using a 3D texture with linear filtering
kernel void applyLUT(
    texture2d<float, access::read> input      [[texture(0)]],
    texture3d<float, access::sample> lut      [[texture(1)]],
    texture2d<float, access::write> output    [[texture(2)]],
    constant float &intensity                 [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    constexpr sampler lutSampler(
        coord::normalized,
        filter::linear,           // trilinear interpolation
        address::clamp_to_edge
    );

    float4 color = input.read(gid);

    // Use input color as 3D texture coordinates (RGB -> XYZ)
    float3 lutCoord = clamp(color.rgb, 0.0, 1.0);
    float4 lutColor = lut.sample(lutSampler, lutCoord);

    // Mix original and LUT-graded by intensity
    float3 result = mix(color.rgb, lutColor.rgb, intensity);
    output.write(float4(result, color.a), gid);
}

// Manual trilinear interpolation (for when 3D textures unavailable)
kernel void applyLUTManual(
    texture2d<float, access::read> input      [[texture(0)]],
    texture2d<float, access::read> lutFlat    [[texture(1)]],  // flattened 2D
    texture2d<float, access::write> output    [[texture(2)]],
    constant int &lutSize                     [[buffer(0)]],
    constant float &intensity                 [[buffer(1)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 color = input.read(gid);
    float3 rgb = clamp(color.rgb, 0.0, 1.0);

    float s = float(lutSize - 1);
    float3 scaled = rgb * s;

    int3 lo = int3(floor(scaled));
    int3 hi = min(lo + 1, int3(lutSize - 1));
    float3 frac = scaled - float3(lo);

    // Sample 8 corners of the LUT cube cell
    // Flat layout: z-slices arranged left-to-right in the 2D texture
    auto sampleLUT = [&](int r, int g, int b) -> float3 {
        int x = r + b * lutSize;
        int y = g;
        return lutFlat.read(uint2(x, y)).rgb;
    };

    // Trilinear interpolation of 8 samples
    float3 c000 = sampleLUT(lo.x, lo.y, lo.z);
    float3 c100 = sampleLUT(hi.x, lo.y, lo.z);
    float3 c010 = sampleLUT(lo.x, hi.y, lo.z);
    float3 c110 = sampleLUT(hi.x, hi.y, lo.z);
    float3 c001 = sampleLUT(lo.x, lo.y, hi.z);
    float3 c101 = sampleLUT(hi.x, lo.y, hi.z);
    float3 c011 = sampleLUT(lo.x, hi.y, hi.z);
    float3 c111 = sampleLUT(hi.x, hi.y, hi.z);

    float3 c00 = mix(c000, c100, frac.x);
    float3 c10 = mix(c010, c110, frac.x);
    float3 c01 = mix(c001, c101, frac.x);
    float3 c11 = mix(c011, c111, frac.x);

    float3 c0 = mix(c00, c10, frac.y);
    float3 c1 = mix(c01, c11, frac.y);

    float3 lutResult = mix(c0, c1, frac.z);
    float3 result = mix(color.rgb, lutResult, intensity);
    output.write(float4(result, color.a), gid);
}
```

Common LUT sizes: 17x17x17 (4,913 entries, fast), 33x33x33 (35,937 entries, standard), 65x65x65 (274,625 entries, high precision).

---

## 8. Chroma Key (Green/Blue Screen)

### Metal Shader with Spill Suppression

```metal
#include <metal_stdlib>
using namespace metal;

// Convert RGB to chrominance (UV) space
float2 rgbToUV(float3 rgb) {
    return float2(
        rgb.r * -0.169 + rgb.g * -0.331 + rgb.b *  0.5   + 0.5,
        rgb.r *  0.5   + rgb.g * -0.419 + rgb.b * -0.081 + 0.5
    );
}

struct ChromaKeyParams {
    float3 keyColor;     // RGB of the key color (e.g. 0,1,0 for green)
    float similarity;    // threshold for full transparency (0.1-0.5)
    float smoothness;    // edge softness (0.0-0.5)
    float spillRemoval;  // spill suppression strength (0.0-1.0)
    float edgeFeather;   // edge feathering radius
};

kernel void chromaKey(
    texture2d<float, access::read> input      [[texture(0)]],
    texture2d<float, access::read> background [[texture(1)]],
    texture2d<float, access::write> output    [[texture(2)]],
    constant ChromaKeyParams &params          [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 fgColor = input.read(gid);
    float4 bgColor = background.read(gid);

    // Calculate chroma distance in UV space
    float2 fgUV = rgbToUV(fgColor.rgb);
    float2 keyUV = rgbToUV(params.keyColor);
    float chromaDist = distance(fgUV, keyUV);

    // Generate alpha mask
    float baseMask = chromaDist - params.similarity;
    float alphaMask = pow(clamp(baseMask / params.smoothness, 0.0, 1.0), 1.5);

    // Spill suppression: desaturate pixels close to key color
    float spillVal = pow(clamp(baseMask / params.spillRemoval, 0.0, 1.0), 1.5);
    float luma = dot(fgColor.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 desaturated = float3(luma);
    float3 despilled = mix(desaturated, fgColor.rgb, spillVal);

    // Composite foreground over background
    float3 result = despilled * alphaMask + bgColor.rgb * (1.0 - alphaMask);
    float resultAlpha = alphaMask + bgColor.a * (1.0 - alphaMask);

    output.write(float4(result, resultAlpha), gid);
}
```

### Core Image Approach (Apple's Official Method)

```swift
import CoreImage

class ChromaKeyFilter {

    /// Create a chroma key mask using hue range
    func createChromaKeyMask(from image: CIImage,
                              hueAngle: Float = 120,  // green = 120 degrees
                              tolerance: Float = 30) -> CIImage? {
        // Step 1: Create a hue/saturation mask using CIColorCube
        let size = 64
        var cubeData = [Float]()

        let hueMin = (hueAngle - tolerance) / 360.0
        let hueMax = (hueAngle + tolerance) / 360.0

        for z in 0..<size {
            let blue = Float(z) / Float(size - 1)
            for y in 0..<size {
                let green = Float(y) / Float(size - 1)
                for x in 0..<size {
                    let red = Float(x) / Float(size - 1)

                    // Convert RGB to HSV
                    let hsv = rgbToHSV(r: red, g: green, b: blue)
                    let hue = hsv.0

                    // Check if hue falls within key color range
                    let alpha: Float
                    if hsv.1 > 0.1 && hue >= hueMin && hue <= hueMax {
                        alpha = 0.0  // transparent (key color)
                    } else {
                        alpha = 1.0  // opaque (keep)
                    }

                    cubeData.append(red * alpha)
                    cubeData.append(green * alpha)
                    cubeData.append(blue * alpha)
                    cubeData.append(alpha)
                }
            }
        }

        let data = Data(bytes: cubeData,
                         count: cubeData.count * MemoryLayout<Float>.size)

        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    private func rgbToHSV(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC

        var h: Float = 0
        let s: Float = maxC == 0 ? 0 : delta / maxC
        let v = maxC

        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, v)
    }
}
```

---

## 9. Speed Ramping

### Constant Speed Change

```swift
import AVFoundation

func applyConstantSpeed(to asset: AVAsset, speed: Float) -> AVMutableComposition {
    let composition = AVMutableComposition()

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        return composition
    }

    let compVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid)!

    let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
    try! compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

    // Scale time: newDuration = originalDuration / speed
    let scaledDuration = CMTimeMultiplyByFloat64(
        asset.duration, multiplier: Float64(1.0 / speed))

    composition.scaleTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        toDuration: scaledDuration)

    return composition
}
```

### Variable Speed (Speed Ramping) via Segmented Composition

```swift
struct SpeedSegment {
    let sourceRange: CMTimeRange   // range in the original asset
    let speed: Float               // playback speed for this segment
}

func buildSpeedRamp(
    asset: AVAsset,
    segments: [SpeedSegment]
) -> AVMutableComposition {
    let composition = AVMutableComposition()

    guard let videoTrack = asset.tracks(withMediaType: .video).first,
          let audioTrack = asset.tracks(withMediaType: .audio).first else {
        return composition
    }

    let compVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid)!
    let compAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid)!

    var insertTime = CMTime.zero

    for segment in segments {
        // Insert segment at current position
        try! compVideoTrack.insertTimeRange(
            segment.sourceRange, of: videoTrack, at: insertTime)
        try! compAudioTrack.insertTimeRange(
            segment.sourceRange, of: audioTrack, at: insertTime)

        // Calculate the scaled duration for this segment
        let scaledDuration = CMTimeMultiplyByFloat64(
            segment.sourceRange.duration,
            multiplier: Float64(1.0 / segment.speed))

        // Scale just this segment's time range in the composition
        let segmentRange = CMTimeRange(
            start: insertTime, duration: segment.sourceRange.duration)
        composition.scaleTimeRange(segmentRange, toDuration: scaledDuration)

        insertTime = CMTimeAdd(insertTime, scaledDuration)
    }

    return composition
}

// Usage: smooth speed ramp from 1x to 0.25x to 1x
func createSmoothSpeedRamp(asset: AVAsset,
                             slowStart: CMTime,
                             slowEnd: CMTime) -> AVMutableComposition {
    let rampSteps = 10
    let slowSpeed: Float = 0.25

    var segments = [SpeedSegment]()

    // Normal speed before ramp
    if CMTimeGetSeconds(slowStart) > 0 {
        segments.append(SpeedSegment(
            sourceRange: CMTimeRange(start: .zero, duration: slowStart),
            speed: 1.0))
    }

    // Ramp down (1x -> 0.25x)
    let rampInDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let stepDuration = CMTimeMultiplyByFloat64(
        rampInDuration, multiplier: 1.0 / Double(rampSteps))
    var rampTime = slowStart

    for i in 0..<rampSteps {
        let t = Float(i) / Float(rampSteps)
        let speed = 1.0 + (slowSpeed - 1.0) * t  // linear interpolation
        segments.append(SpeedSegment(
            sourceRange: CMTimeRange(start: rampTime, duration: stepDuration),
            speed: speed))
        rampTime = CMTimeAdd(rampTime, stepDuration)
    }

    // Constant slow section
    let slowDuration = CMTimeSubtract(slowEnd, rampTime)
    if CMTimeGetSeconds(slowDuration) > 0 {
        segments.append(SpeedSegment(
            sourceRange: CMTimeRange(start: rampTime, duration: slowDuration),
            speed: slowSpeed))
    }

    // Ramp up (0.25x -> 1x)
    rampTime = slowEnd
    for i in 0..<rampSteps {
        let t = Float(i) / Float(rampSteps)
        let speed = slowSpeed + (1.0 - slowSpeed) * t
        segments.append(SpeedSegment(
            sourceRange: CMTimeRange(start: rampTime, duration: stepDuration),
            speed: speed))
        rampTime = CMTimeAdd(rampTime, stepDuration)
    }

    // Normal speed after ramp
    let remaining = CMTimeSubtract(asset.duration, rampTime)
    if CMTimeGetSeconds(remaining) > 0 {
        segments.append(SpeedSegment(
            sourceRange: CMTimeRange(start: rampTime, duration: remaining),
            speed: 1.0))
    }

    return buildSpeedRamp(asset: asset, segments: segments)
}
```

### Optical Flow Frame Interpolation

Apple provides two approaches:
- **VNGenerateOpticalFlowRequest** (Vision framework): Computes per-pixel motion vectors between frames. Returns dense optical flow field.
- **VTFrameProcessor** (VideoToolbox, iOS 26+/macOS 15.4+): ML-based frame interpolation for smooth slow motion, super resolution, and motion blur. Hardware-accelerated on Apple Silicon.

```swift
import Vision

func computeOpticalFlow(from frameA: CVPixelBuffer,
                         to frameB: CVPixelBuffer) -> VNPixelBufferObservation? {
    let request = VNGenerateOpticalFlowRequest(
        targetedCVPixelBuffer: frameB)
    request.computationAccuracy = .high

    let handler = VNImageRequestHandler(
        cvPixelBuffer: frameA, options: [:])
    try? handler.perform([request])

    return request.results?.first as? VNPixelBufferObservation
}
```

---

## 10. Node-Based Color Grading

### Node Graph Data Model (DaVinci Resolve-Style)

```swift
enum NodeType {
    case serial         // sequential processing
    case parallel       // independent processing, results mixed
    case layerMixer     // blend modes between inputs
    case splitterCombiner  // split into channels, process, recombine
}

enum CompositeMode {
    case normal, multiply, screen, overlay, softLight, hardLight
    case add, colorDodge, colorBurn, luminosity
}

class ColorNode: Identifiable {
    let id: UUID
    var name: String
    var isEnabled: Bool = true
    var nodeType: NodeType = .serial

    // Color correction parameters for this node
    var liftColor: SIMD3<Float> = .zero        // shadow color offset
    var gammaColor: SIMD3<Float> = .one         // midtone color
    var gainColor: SIMD3<Float> = .one          // highlight color
    var offsetColor: SIMD3<Float> = .zero       // overall offset

    var liftMaster: Float = 0.0     // shadow brightness
    var gammaMaster: Float = 1.0    // midtone brightness
    var gainMaster: Float = 1.0     // highlight brightness
    var offsetMaster: Float = 0.0   // overall brightness

    var saturation: Float = 1.0
    var contrast: Float = 1.0
    var pivot: Float = 0.435        // contrast pivot point

    // For parallel/layer nodes
    var compositeMode: CompositeMode = .normal
    var compositeOpacity: Float = 1.0

    // Qualifiers (HSL key for secondary corrections)
    var qualifier: HSLQualifier?

    // LUT (if assigned)
    var lutReference: String?

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

class ColorNodeGraph {
    var nodes: [ColorNode] = []
    var connections: [(from: UUID, to: UUID)] = []

    /// Process a frame through the entire node graph
    func process(input: MTLTexture, context: MetalContext) -> MTLTexture {
        var currentTexture = input

        // Process serial nodes in order
        let serialNodes = getSerialChain()
        for node in serialNodes {
            guard node.isEnabled else { continue }

            if let qualifier = node.qualifier {
                // Secondary correction: apply only to qualified pixels
                let mask = generateQualifierMask(
                    from: currentTexture, qualifier: qualifier, context: context)
                let corrected = applyColorCorrection(
                    to: currentTexture, node: node, context: context)
                currentTexture = compositeMasked(
                    original: currentTexture, corrected: corrected,
                    mask: mask, context: context)
            } else {
                currentTexture = applyColorCorrection(
                    to: currentTexture, node: node, context: context)
            }
        }

        // Process parallel node groups
        let parallelGroups = getParallelGroups()
        for group in parallelGroups {
            var results = [(MTLTexture, Float)]()
            for node in group {
                guard node.isEnabled else { continue }
                let result = applyColorCorrection(
                    to: currentTexture, node: node, context: context)
                results.append((result, node.compositeOpacity))
            }
            currentTexture = mixParallelResults(
                base: currentTexture, results: results, context: context)
        }

        return currentTexture
    }
}
```

### HSL Qualifier

```swift
struct HSLQualifier {
    var hueCenter: Float = 120     // degrees (0-360)
    var hueWidth: Float = 30       // degrees of range
    var hueSoftness: Float = 10    // feather in degrees

    var saturationLow: Float = 0.2
    var saturationHigh: Float = 1.0
    var saturationSoftness: Float = 0.05

    var luminanceLow: Float = 0.0
    var luminanceHigh: Float = 1.0
    var luminanceSoftness: Float = 0.05

    var invertMask: Bool = false
}
```

### HSL Qualifier Metal Shader

```metal
#include <metal_stdlib>
using namespace metal;

struct HSLQualifierParams {
    float hueCenter;       // in degrees 0-360
    float hueWidth;
    float hueSoftness;
    float satLow;
    float satHigh;
    float satSoftness;
    float lumLow;
    float lumHigh;
    float lumSoftness;
    int invertMask;
};

float3 rgbToHSL(float3 rgb) {
    float maxC = max(rgb.r, max(rgb.g, rgb.b));
    float minC = min(rgb.r, min(rgb.g, rgb.b));
    float delta = maxC - minC;

    float l = (maxC + minC) * 0.5;
    float s = 0.0;
    float h = 0.0;

    if (delta > 0.00001) {
        s = (l < 0.5) ? delta / (maxC + minC) : delta / (2.0 - maxC - minC);

        if (maxC == rgb.r) {
            h = (rgb.g - rgb.b) / delta + (rgb.g < rgb.b ? 6.0 : 0.0);
        } else if (maxC == rgb.g) {
            h = (rgb.b - rgb.r) / delta + 2.0;
        } else {
            h = (rgb.r - rgb.g) / delta + 4.0;
        }
        h /= 6.0;
    }
    return float3(h * 360.0, s, l);  // H in degrees, S and L in 0-1
}

float softRange(float value, float low, float high, float softness) {
    float lowEdge = smoothstep(low - softness, low + softness, value);
    float highEdge = 1.0 - smoothstep(high - softness, high + softness, value);
    return lowEdge * highEdge;
}

float hueDistance(float h1, float h2) {
    float d = abs(h1 - h2);
    return min(d, 360.0 - d);
}

kernel void hslQualifier(
    texture2d<float, access::read> input      [[texture(0)]],
    texture2d<float, access::write> mask      [[texture(1)]],
    constant HSLQualifierParams &params       [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 color = input.read(gid);
    float3 hsl = rgbToHSL(color.rgb);

    // Hue qualification
    float hueDist = hueDistance(hsl.x, params.hueCenter);
    float hueMatch = 1.0 - smoothstep(
        params.hueWidth - params.hueSoftness,
        params.hueWidth + params.hueSoftness,
        hueDist);

    // Saturation qualification
    float satMatch = softRange(hsl.y, params.satLow, params.satHigh,
                                params.satSoftness);

    // Luminance qualification
    float lumMatch = softRange(hsl.z, params.lumLow, params.lumHigh,
                                params.lumSoftness);

    float alpha = hueMatch * satMatch * lumMatch;
    if (params.invertMask) alpha = 1.0 - alpha;

    mask.write(float4(alpha, alpha, alpha, 1.0), gid);
}
```

### Lift/Gamma/Gain Metal Shader

```metal
// Core formula: output = lift * (1 - input) + gain * pow(input, 1/gamma)
// Simplified: output = lift + (gain - lift) * pow(input, 1/gamma)

struct LGGParams {
    float3 lift;       // shadow color (typically around 0.0)
    float3 gamma;      // midtone color (typically around 1.0)
    float3 gain;       // highlight color (typically around 1.0)
    float3 offset;     // overall offset
    float saturation;
    float contrast;
    float pivot;       // contrast pivot (default ~0.435)
};

kernel void liftGammaGain(
    texture2d<float, access::read> input      [[texture(0)]],
    texture2d<float, access::write> output    [[texture(1)]],
    constant LGGParams &params               [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 color = input.read(gid);
    float3 rgb = color.rgb;

    // Apply lift/gamma/gain per channel
    // Formula: out = lift * (1 - in) + gain * pow(in, 1/gamma)
    float3 lgg;
    lgg.r = params.lift.r * (1.0 - rgb.r) +
            params.gain.r * pow(max(rgb.r, 0.0001), 1.0 / params.gamma.r);
    lgg.g = params.lift.g * (1.0 - rgb.g) +
            params.gain.g * pow(max(rgb.g, 0.0001), 1.0 / params.gamma.g);
    lgg.b = params.lift.b * (1.0 - rgb.b) +
            params.gain.b * pow(max(rgb.b, 0.0001), 1.0 / params.gamma.b);

    // Apply offset
    lgg += params.offset;

    // Apply contrast around pivot
    lgg = params.pivot + (lgg - params.pivot) * params.contrast;

    // Apply saturation
    float luma = dot(lgg, float3(0.2126, 0.7152, 0.0722));
    lgg = mix(float3(luma), lgg, params.saturation);

    output.write(float4(clamp(lgg, 0.0, 1.0), color.a), gid);
}
```

---

## 11. Color Correction Tools — Metal Shaders

```metal
#include <metal_stdlib>
using namespace metal;

struct ColorCorrectionParams {
    float exposure;      // EV (-5 to +5)
    float contrast;      // 0.0 to 4.0 (1.0 = neutral)
    float saturation;    // 0.0 to 4.0 (1.0 = neutral)
    float vibrance;      // -1.0 to 1.0
    float temperature;   // delta from 6500K (-100 to +100)
    float tint;          // green-magenta (-100 to +100)
    float shadows;       // -1.0 to 1.0
    float highlights;    // -1.0 to 1.0
    float blacks;        // -1.0 to 1.0
    float whites;        // -1.0 to 1.0
};

// Exposure: multiply by 2^EV
float3 applyExposure(float3 color, float ev) {
    return color * pow(2.0, ev);
}

// Contrast: scale around midpoint (0.5 in sRGB, ~0.18 in linear)
float3 applyContrast(float3 color, float contrast) {
    float midpoint = 0.5;
    return midpoint + (color - midpoint) * contrast;
}

// Saturation: mix with luminance
float3 applySaturation(float3 color, float saturation) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    return mix(float3(luma), color, saturation);
}

// Vibrance: smart saturation that protects already-saturated colors
float3 applyVibrance(float3 color, float vibrance) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    float maxChannel = max(color.r, max(color.g, color.b));
    float minChannel = min(color.r, min(color.g, color.b));
    float currentSat = maxChannel - minChannel;

    // Less saturated pixels get more boost
    float weight = 1.0 - currentSat;
    float amount = vibrance * weight;

    return mix(float3(luma), color, 1.0 + amount);
}

// Temperature/Tint: shift color balance
float3 applyTemperatureTint(float3 color, float temp, float tint) {
    // Simplified approximation: warm/cool shift
    // Positive temp = warmer (more red/yellow), negative = cooler (more blue)
    float tempScale = temp / 100.0;
    float tintScale = tint / 100.0;

    color.r += tempScale * 0.1;
    color.b -= tempScale * 0.1;
    color.g += tintScale * 0.1;
    color.r -= tintScale * 0.05;
    color.b -= tintScale * 0.05;

    return color;
}

// Shadows/Highlights recovery
float3 applyShadowsHighlights(float3 color, float shadows, float highlights) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

    // Shadow weight: peaks at dark values
    float shadowWeight = 1.0 - smoothstep(0.0, 0.5, luma);
    // Highlight weight: peaks at bright values
    float highlightWeight = smoothstep(0.5, 1.0, luma);

    color += shadows * shadowWeight * 0.5;
    color += highlights * highlightWeight * 0.5;

    return color;
}

// Blacks/Whites: adjust endpoints
float3 applyBlacksWhites(float3 color, float blacks, float whites) {
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

    float blackWeight = 1.0 - smoothstep(0.0, 0.25, luma);
    float whiteWeight = smoothstep(0.75, 1.0, luma);

    color += blacks * blackWeight * 0.3;
    color += whites * whiteWeight * 0.3;

    return color;
}

// Complete color correction pipeline
kernel void colorCorrection(
    texture2d<float, access::read> input      [[texture(0)]],
    texture2d<float, access::write> output    [[texture(1)]],
    constant ColorCorrectionParams &params    [[buffer(0)]],
    uint2 gid                                 [[thread_position_in_grid]])
{
    float4 color = input.read(gid);
    float3 rgb = color.rgb;

    // Apply corrections in order
    rgb = applyExposure(rgb, params.exposure);
    rgb = applyTemperatureTint(rgb, params.temperature, params.tint);
    rgb = applyShadowsHighlights(rgb, params.shadows, params.highlights);
    rgb = applyBlacksWhites(rgb, params.blacks, params.whites);
    rgb = applyContrast(rgb, params.contrast);
    rgb = applySaturation(rgb, params.saturation);
    rgb = applyVibrance(rgb, params.vibrance);

    output.write(float4(clamp(rgb, 0.0, 1.0), color.a), gid);
}
```

### Color Curves Metal Shader

```metal
// RGB curves with 5-point spline (matching CIToneCurve)
struct CurvePoints {
    float2 points[5];  // (input, output) pairs for the curve
};

// Evaluate a Catmull-Rom spline through the curve points
float evaluateCurve(float input, constant float2 *points) {
    // Find the segment
    int seg = 0;
    for (int i = 0; i < 4; i++) {
        if (input >= points[i].x && input <= points[i + 1].x) {
            seg = i;
            break;
        }
    }

    float t = (input - points[seg].x) /
              (points[seg + 1].x - points[seg].x);

    // Catmull-Rom interpolation
    float2 p0 = (seg > 0) ? points[seg - 1] : points[seg];
    float2 p1 = points[seg];
    float2 p2 = points[seg + 1];
    float2 p3 = (seg < 3) ? points[seg + 2] : points[seg + 1];

    float t2 = t * t;
    float t3 = t2 * t;

    float y = 0.5 * (
        (2.0 * p1.y) +
        (-p0.y + p2.y) * t +
        (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
        (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3
    );
    return clamp(y, 0.0, 1.0);
}

kernel void rgbCurves(
    texture2d<float, access::read> input       [[texture(0)]],
    texture2d<float, access::write> output     [[texture(1)]],
    constant CurvePoints &masterCurve          [[buffer(0)]],
    constant CurvePoints &redCurve             [[buffer(1)]],
    constant CurvePoints &greenCurve           [[buffer(2)]],
    constant CurvePoints &blueCurve            [[buffer(3)]],
    uint2 gid                                  [[thread_position_in_grid]])
{
    float4 color = input.read(gid);

    // Apply per-channel curves then master curve
    float r = evaluateCurve(color.r, redCurve.points);
    float g = evaluateCurve(color.g, greenCurve.points);
    float b = evaluateCurve(color.b, blueCurve.points);

    r = evaluateCurve(r, masterCurve.points);
    g = evaluateCurve(g, masterCurve.points);
    b = evaluateCurve(b, masterCurve.points);

    output.write(float4(r, g, b, color.a), gid);
}
```

---

## 12. Effect Chain Architecture

### Texture Pool for Intermediate Results

```swift
class TexturePool {
    private let device: MTLDevice
    private var available: [String: [MTLTexture]] = [:]
    private let lock = NSLock()

    init(device: MTLDevice) {
        self.device = device
    }

    private func key(for descriptor: MTLTextureDescriptor) -> String {
        return "\(descriptor.width)x\(descriptor.height)_\(descriptor.pixelFormat.rawValue)"
    }

    func acquire(matching descriptor: MTLTextureDescriptor) -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }

        let k = key(for: descriptor)
        if var textures = available[k], !textures.isEmpty {
            return textures.removeLast()
        }

        return device.makeTexture(descriptor: descriptor)!
    }

    func release(_ texture: MTLTexture) {
        lock.lock()
        defer { lock.unlock() }

        let k = "\(texture.width)x\(texture.height)_\(texture.pixelFormat.rawValue)"
        available[k, default: []].append(texture)
    }

    func drain() {
        lock.lock()
        defer { lock.unlock() }
        available.removeAll()
    }
}
```

### Effect Chain Processor

```swift
protocol VideoEffect {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get set }
    var parameters: [String: ParameterValue] { get set }
    var keyframeTracks: [String: KeyframeTrack<Float>] { get set }

    func process(input: MTLTexture, output: MTLTexture,
                 commandBuffer: MTLCommandBuffer,
                 time: CMTime, context: EffectContext)
}

struct EffectContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let texturePool: TexturePool
    let pipelineCache: PipelineStateCache
    let renderSize: CGSize
}

class EffectChain {
    var effects: [VideoEffect] = []
    private let texturePool: TexturePool
    private let context: EffectContext

    init(context: EffectContext) {
        self.context = context
        self.texturePool = context.texturePool
    }

    func process(input: MTLTexture, output: MTLTexture,
                 commandBuffer: MTLCommandBuffer, time: CMTime) {
        let activeEffects = effects.filter { $0.isEnabled }
        guard !activeEffects.isEmpty else {
            // No effects: blit input to output
            blitTexture(from: input, to: output, commandBuffer: commandBuffer)
            return
        }

        if activeEffects.count == 1 {
            // Single effect: input -> output directly
            activeEffects[0].process(
                input: input, output: output,
                commandBuffer: commandBuffer, time: time, context: context)
            return
        }

        // Multiple effects: ping-pong between intermediate textures
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: input.pixelFormat,
            width: input.width, height: input.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]

        var currentInput = input
        var intermediates = [MTLTexture]()

        for (index, effect) in activeEffects.enumerated() {
            let isLast = (index == activeEffects.count - 1)
            let currentOutput: MTLTexture

            if isLast {
                currentOutput = output
            } else {
                currentOutput = texturePool.acquire(matching: descriptor)
                intermediates.append(currentOutput)
            }

            // Evaluate keyframed parameters at current time
            var effectCopy = effect
            for (paramName, track) in effectCopy.keyframeTracks {
                if let value = track.evaluate(at: time) {
                    effectCopy.parameters[paramName] = .float(value)
                }
            }

            effectCopy.process(
                input: currentInput, output: currentOutput,
                commandBuffer: commandBuffer, time: time, context: context)

            currentInput = currentOutput
        }

        // Return intermediate textures to pool after GPU completes
        commandBuffer.addCompletedHandler { [weak self] _ in
            for texture in intermediates {
                self?.texturePool.release(texture)
            }
        }
    }

    private func blitTexture(from: MTLTexture, to: MTLTexture,
                              commandBuffer: MTLCommandBuffer) {
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: from, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: from.width, height: from.height, depth: 1),
                  to: to, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}
```

### Pipeline State Cache

```swift
class PipelineStateCache {
    private let device: MTLDevice
    private let library: MTLLibrary
    private var computePipelines: [String: MTLComputePipelineState] = [:]
    private let lock = NSLock()

    init(device: MTLDevice) {
        self.device = device
        self.library = device.makeDefaultLibrary()!
    }

    func computePipeline(named functionName: String) -> MTLComputePipelineState {
        lock.lock()
        defer { lock.unlock() }

        if let cached = computePipelines[functionName] {
            return cached
        }

        let function = library.makeFunction(name: functionName)!
        let pipeline = try! device.makeComputePipelineState(function: function)
        computePipelines[functionName] = pipeline
        return pipeline
    }
}
```

### Concrete Effect Example: Gaussian Blur

```swift
class GaussianBlurEffect: VideoEffect {
    let id = UUID()
    let name = "Gaussian Blur"
    var isEnabled = true
    var parameters: [String: ParameterValue] = ["radius": .float(10.0)]
    var keyframeTracks: [String: KeyframeTrack<Float>] = [:]

    func process(input: MTLTexture, output: MTLTexture,
                 commandBuffer: MTLCommandBuffer,
                 time: CMTime, context: EffectContext) {
        guard case .float(let radius) = parameters["radius"], radius > 0 else {
            // No blur: just copy
            let blit = commandBuffer.makeBlitCommandEncoder()!
            blit.copy(from: input, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: input.width,
                                          height: input.height, depth: 1),
                      to: output, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            return
        }

        // Use Metal Performance Shaders for optimized Gaussian blur
        let blur = MPSImageGaussianBlur(device: context.device, sigma: radius)
        blur.encode(commandBuffer: commandBuffer,
                    sourceTexture: input, destinationTexture: output)
    }
}
```

### Apple Silicon Optimization Notes

- Use **memoryless render targets** (`.storageMode = .memoryless`) for intermediate textures in tiled rendering on Apple GPUs.
- Leverage **programmable blending** to avoid writing intermediate results to device memory — merge geometry and lighting passes into a single render encoder.
- Use **MTLHeap** for bulk texture allocation to reduce allocation overhead.
- Use **resource heaps** and **indirect command buffers** for GPU-driven pipeline management.
- Pre-create all `MTLComputePipelineState` objects at init time — pipeline creation is expensive.
- For effect chains, minimize the number of intermediate textures by analyzing the render graph to determine reuse opportunities (as MetalPetal does automatically).
- On Apple Silicon, **tile memory** and **imageblocks** provide fast on-chip storage for intermediate results within a single render pass.
