# Professional Delivery Formats & Color Management for Swift NLE

## 1. ProRes RAW Workflow

### Overview
ProRes RAW applies compression directly to raw Bayer sensor data, deferring debayering to post-production. This preserves maximum flexibility for ISO, white balance, and exposure adjustments.

### ProRes RAW Decoding on macOS

```swift
import AVFoundation
import VideoToolbox

class ProResRAWDecoder {
    private var decompressionSession: VTDecompressionSession?

    /// Decode ProRes RAW using VideoToolbox
    func setupDecompression(formatDescription: CMFormatDescription) throws {
        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: 3840,
            kCVPixelBufferHeightKey as String: 2160
        ]

        let callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            destinationImageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: UnsafeMutablePointer<VTDecompressionOutputCallbackRecord>(
                mutating: [callback]
            ),
            decompressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw ProResError.decompressionSetupFailed(status)
        }
        self.decompressionSession = session
    }

    /// Read ProRes RAW asset and extract format description
    func readProResRAWAsset(url: URL) async throws -> AVAssetTrack {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProResError.noVideoTrack
        }

        // Check if ProRes RAW
        let descriptions = try await track.load(.formatDescriptions)
        for desc in descriptions {
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            // ProRes RAW codec types
            // kCMVideoCodecType_apco (ProRes RAW)
            // Check for RAW-specific extensions
            if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                print("Format extensions: \(extensions)")
            }
        }
        return track
    }
}
```

### RAW Parameter Adjustments

ProRes RAW supports these adjustable parameters in post:
- **ISO**: Override the capture ISO setting
- **Exposure Bias**: Fine-tune +/- 1 stop from the ISO
- **White Balance**: Color temperature (Kelvin) along blue-amber axis
- **Tint**: Green-magenta fine tuning

```swift
/// RAW parameter adjustment model
struct RAWParameters {
    var iso: Float = 800           // Override ISO
    var exposureBias: Float = 0.0  // -1.0 to +1.0 stops
    var colorTemperature: Float = 5600  // Kelvin
    var tint: Float = 0.0          // Green-magenta

    /// Apply RAW adjustments in a Metal compute shader
    func applyToTexture(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: MTLComputePipelineState
    ) {
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        var params = RAWGPUParams(
            exposureMultiplier: pow(2.0, exposureBias) * (iso / 800.0),
            whiteBalanceGains: colorTemperatureToGains(colorTemperature, tint: tint)
        )
        encoder.setBytes(&params, length: MemoryLayout<RAWGPUParams>.size, index: 0)

        let threadgroups = MTLSize(
            width: (inputTexture.width + 15) / 16,
            height: (inputTexture.height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
    }

    /// Convert color temperature to RGB gains
    private func colorTemperatureToGains(_ kelvin: Float, tint: Float) -> SIMD3<Float> {
        // Planckian locus approximation
        let temp = kelvin / 100.0
        var r: Float, g: Float, b: Float

        if temp <= 66 {
            r = 1.0
            g = 0.3900815787 * log(temp) - 0.6318414437
            b = temp <= 19 ? 0.0 : 0.5432067891 * log(temp - 10) - 1.1962540891
        } else {
            r = 1.2929362 * pow(temp - 60, -0.1332047592)
            g = 1.1298909 * pow(temp - 60, -0.0755148492)
            b = 1.0
        }

        // Normalize and apply tint
        let sum = r + g + b
        r /= sum; g /= sum; b /= sum
        g += tint * 0.01

        return SIMD3<Float>(1.0/r, 1.0/g, 1.0/b)
    }
}

struct RAWGPUParams {
    var exposureMultiplier: Float
    var whiteBalanceGains: SIMD3<Float>
}
```

### Metal Shader for Debayering (RGGB Bayer Pattern)

```metal
#include <metal_stdlib>
using namespace metal;

// Simple bilinear demosaic for RGGB Bayer pattern
kernel void debayer_rggb(
    texture2d<float, access::read>  bayerTexture  [[texture(0)]],
    texture2d<float, access::write> rgbTexture    [[texture(1)]],
    constant RAWParams& params                     [[buffer(0)]],
    uint2 gid                                      [[thread_position_in_grid]]
) {
    if (gid.x >= rgbTexture.get_width() || gid.y >= rgbTexture.get_height()) return;

    uint2 pos = gid;
    int x = pos.x;
    int y = pos.y;

    // Determine Bayer position (RGGB)
    bool isEvenRow = (y % 2) == 0;
    bool isEvenCol = (x % 2) == 0;

    float r, g, b;
    float center = bayerTexture.read(pos).r;

    // Read neighbors
    float top    = bayerTexture.read(uint2(x, max(y-1, 0))).r;
    float bottom = bayerTexture.read(uint2(x, min(y+1, int(bayerTexture.get_height()-1)))).r;
    float left   = bayerTexture.read(uint2(max(x-1, 0), y)).r;
    float right  = bayerTexture.read(uint2(min(x+1, int(bayerTexture.get_width()-1)), y)).r;
    float tl     = bayerTexture.read(uint2(max(x-1,0), max(y-1,0))).r;
    float tr     = bayerTexture.read(uint2(min(x+1,int(bayerTexture.get_width()-1)), max(y-1,0))).r;
    float bl     = bayerTexture.read(uint2(max(x-1,0), min(y+1,int(bayerTexture.get_height()-1)))).r;
    float br     = bayerTexture.read(uint2(min(x+1,int(bayerTexture.get_width()-1)), min(y+1,int(bayerTexture.get_height()-1)))).r;

    if (isEvenRow && isEvenCol) {
        // Red pixel
        r = center;
        g = (top + bottom + left + right) * 0.25;
        b = (tl + tr + bl + br) * 0.25;
    } else if (isEvenRow && !isEvenCol) {
        // Green pixel (red row)
        r = (left + right) * 0.5;
        g = center;
        b = (top + bottom) * 0.5;
    } else if (!isEvenRow && isEvenCol) {
        // Green pixel (blue row)
        r = (top + bottom) * 0.5;
        g = center;
        b = (left + right) * 0.5;
    } else {
        // Blue pixel
        r = (tl + tr + bl + br) * 0.25;
        g = (top + bottom + left + right) * 0.25;
        b = center;
    }

    // Apply RAW adjustments
    float3 rgb = float3(r, g, b);
    rgb *= params.exposureMultiplier;
    rgb *= params.whiteBalanceGains;

    rgbTexture.write(float4(rgb, 1.0), gid);
}
```

---

## 2. ACES Color Management

### ACES Color Spaces

| Space | Primaries | Transfer | Use Case |
|-------|-----------|----------|----------|
| ACES2065-1 | AP0 | Linear | Archival interchange |
| ACEScg | AP1 | Linear | CG rendering, compositing |
| ACEScc | AP1 | Logarithmic | Color grading (pure log) |
| ACEScct | AP1 | Log + toe | Color grading (lifted shadows) |

### AP0 and AP1 Primary Definitions

```swift
/// ACES primary chromaticity coordinates
struct ACESPrimaries {
    // AP0 primaries (ACES2065-1) - encompasses entire visible gamut
    static let AP0_R = SIMD2<Float>(0.7347, 0.2653)
    static let AP0_G = SIMD2<Float>(0.0000, 1.0000)
    static let AP0_B = SIMD2<Float>(0.0001, -0.0770)
    static let AP0_W = SIMD2<Float>(0.32168, 0.33767) // D60

    // AP1 primaries (ACEScg, ACEScc, ACEScct) - practical working gamut
    static let AP1_R = SIMD2<Float>(0.713, 0.293)
    static let AP1_G = SIMD2<Float>(0.165, 0.830)
    static let AP1_B = SIMD2<Float>(0.128, 0.044)
    static let AP1_W = SIMD2<Float>(0.32168, 0.33767) // D60
}
```

### IDT/ODT Transform Matrices

```swift
/// ACES transform matrices for Metal shaders
struct ACESMatrices {
    // AP1 (ACEScg) to AP0 (ACES2065-1)
    static let AP1_to_AP0 = matrix_float3x3(columns: (
        SIMD3<Float>(0.6954522414, 0.0447945634, -0.0055258826),
        SIMD3<Float>(0.1406786965, 0.8596711185,  0.0040252103),
        SIMD3<Float>(0.1638690622, 0.0955343182,  1.0015006723)
    ))

    // AP0 to AP1
    static let AP0_to_AP1 = matrix_float3x3(columns: (
        SIMD3<Float>( 1.4514393161, -0.0765537734,  0.0083161484),
        SIMD3<Float>(-0.2365107469,  1.1762296998, -0.0060324498),
        SIMD3<Float>(-0.2149285693, -0.0996759264,  0.9977163014)
    ))

    // AP1 to CIE XYZ (D65)
    static let AP1_to_XYZ = matrix_float3x3(columns: (
        SIMD3<Float>(0.66245418, 0.27222872, -0.00557465),
        SIMD3<Float>(0.13400421, 0.67408177,  0.00406073),
        SIMD3<Float>(0.15618769, 0.05368952,  1.01033910)
    ))

    // sRGB/Rec.709 to ACEScg (AP1) - common IDT
    static let sRGB_to_ACEScg = matrix_float3x3(columns: (
        SIMD3<Float>(0.6131324224, 0.0701243808, 0.0206155187),
        SIMD3<Float>(0.3395380158, 0.9163538199, 0.1095697680),
        SIMD3<Float>(0.0474166960, 0.0136218193, 0.8697021459)
    ))

    // ACEScg (AP1) to sRGB/Rec.709 - common ODT component
    static let ACEScg_to_sRGB = matrix_float3x3(columns: (
        SIMD3<Float>( 1.7050509926, -0.1302564175, -0.0240033596),
        SIMD3<Float>(-0.6217921206,  1.1408047365, -0.1289689760),
        SIMD3<Float>(-0.0832588720, -0.0105483190,  1.1529723356)
    ))
}
```

### ACEScc/ACEScct Transfer Functions (Metal)

```metal
#include <metal_stdlib>
using namespace metal;

// ACEScc log encoding (pure log, no toe)
float ACEScc_encode(float x) {
    if (x <= 0.0) {
        return -0.3584474886; // (log2(pow(2.0, -16.0)) + 9.72) / 17.52
    } else if (x < pow(2.0, -15.0)) {
        return (log2(pow(2.0, -16.0) + x * 0.5) + 9.72) / 17.52;
    } else {
        return (log2(x) + 9.72) / 17.52;
    }
}

float ACEScc_decode(float x) {
    if (x < -0.3013698630) { // (9.72 - 15) / 17.52
        return (pow(2.0, x * 17.52 - 9.72) - pow(2.0, -16.0)) * 2.0;
    } else {
        return pow(2.0, x * 17.52 - 9.72);
    }
}

// ACEScct log encoding (log with linear toe for better shadow behavior)
float ACEScct_encode(float x) {
    const float CUT = 0.0078125; // 2^-7
    const float A   = 10.5402377416545;
    const float B   = 0.0729055341958355;

    if (x <= CUT) {
        return A * x + B;
    } else {
        return (log2(x) + 9.72) / 17.52;
    }
}

float ACEScct_decode(float x) {
    const float CUT = 0.155251141552511;
    const float A   = 10.5402377416545;
    const float B   = 0.0729055341958355;

    if (x <= CUT) {
        return (x - B) / A;
    } else {
        return pow(2.0, x * 17.52 - 9.72);
    }
}

// Complete ACES pipeline kernel: IDT -> ACEScg working space
kernel void aces_idt_transform(
    texture2d<float, access::read>  input   [[texture(0)]],
    texture2d<float, access::write> output  [[texture(1)]],
    constant float3x3& idt_matrix           [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    float4 color = input.read(gid);

    // Linearize from sRGB gamma
    float3 linear;
    for (int i = 0; i < 3; i++) {
        float c = color[i];
        linear[i] = (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
    }

    // Apply IDT matrix (e.g., sRGB to ACEScg)
    float3 aces = idt_matrix * linear;

    output.write(float4(aces, color.a), gid);
}
```

---

## 3. Color Space Management

### CGColorSpace Constants on macOS

```swift
import CoreGraphics

/// Available CGColorSpace references for video work
struct VideoColorSpaces {
    // SDR color spaces
    static let sRGB        = CGColorSpace(name: CGColorSpace.sRGB)!
    static let displayP3   = CGColorSpace(name: CGColorSpace.displayP3)!
    static let rec709      = CGColorSpace(name: CGColorSpace.itur_709)!
    static let rec2020     = CGColorSpace(name: CGColorSpace.itur_2020)!

    // HDR color spaces with PQ (ST 2084) transfer function
    static let rec2020_PQ  = CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
    static let displayP3_PQ = CGColorSpace(name: CGColorSpace.displayP3_PQ)!

    // HDR color spaces with HLG transfer function
    static let rec2020_HLG  = CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
    static let displayP3_HLG = CGColorSpace(name: CGColorSpace.displayP3_HLG)!

    // Linear color spaces (for compositing)
    static let linearSRGB      = CGColorSpace(name: CGColorSpace.linearSRGB)!
    static let linearDisplayP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
    static let linearRec2020   = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    /// Check if a color space is HLG-based
    static func isHLG(_ space: CGColorSpace) -> Bool {
        return space.name == CGColorSpace.itur_2100_HLG ||
               space.name == CGColorSpace.displayP3_HLG
    }

    /// Check if a color space is PQ-based
    static func isPQ(_ space: CGColorSpace) -> Bool {
        return space.name == CGColorSpace.itur_2100_PQ ||
               space.name == CGColorSpace.displayP3_PQ
    }
}
```

### 3x3 Color Space Conversion Matrices

```swift
/// Color space conversion matrices (linear RGB domain)
/// These operate on linearized values -- apply EOTF first, then matrix, then OETF
struct ColorConversionMatrices {

    // Rec.709 to Rec.2020
    static let rec709_to_rec2020 = matrix_float3x3(columns: (
        SIMD3<Float>(0.6274040, 0.0690970, 0.0163916),
        SIMD3<Float>(0.3292820, 0.9195400, 0.0880132),
        SIMD3<Float>(0.0433136, 0.0113612, 0.8955950)
    ))

    // Rec.2020 to Rec.709
    static let rec2020_to_rec709 = matrix_float3x3(columns: (
        SIMD3<Float>( 1.6604910, -0.1245505, -0.0181508),
        SIMD3<Float>(-0.5876411,  1.1328999, -0.1005789),
        SIMD3<Float>(-0.0728499, -0.0083494,  1.1187297)
    ))

    // Rec.709 to DCI-P3
    static let rec709_to_p3 = matrix_float3x3(columns: (
        SIMD3<Float>(0.8224622, 0.0331942, 0.0170826),
        SIMD3<Float>(0.1775378, 0.9668058, 0.0723974),
        SIMD3<Float>(0.0000000, 0.0000000, 0.9105200)
    ))

    // DCI-P3 to Rec.709
    static let p3_to_rec709 = matrix_float3x3(columns: (
        SIMD3<Float>( 1.2249402, -0.0420570, -0.0196376),
        SIMD3<Float>(-0.2249402,  1.0420570, -0.0786507),
        SIMD3<Float>( 0.0000000,  0.0000000,  1.0982883)
    ))

    // DCI-P3 to Rec.2020
    static let p3_to_rec2020 = matrix_float3x3(columns: (
        SIMD3<Float>(0.7535827, 0.0457456, 0.0008393),
        SIMD3<Float>(0.1985830, 0.9419180, 0.0763325),
        SIMD3<Float>(0.0478344, 0.0123364, 0.9228283)
    ))
}
```

### Metal Shader for Color Space Conversion

```metal
// Transfer functions (EOTF/OETF)

// sRGB / Rec.709 EOTF (electrical to linear)
float3 srgb_eotf(float3 v) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        result[i] = (v[i] <= 0.04045)
            ? v[i] / 12.92
            : pow((v[i] + 0.055) / 1.055, 2.4);
    }
    return result;
}

// sRGB / Rec.709 OETF (linear to electrical)
float3 srgb_oetf(float3 v) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        result[i] = (v[i] <= 0.0031308)
            ? v[i] * 12.92
            : 1.055 * pow(v[i], 1.0/2.4) - 0.055;
    }
    return result;
}

// PQ (SMPTE ST 2084) EOTF
float3 pq_eotf(float3 N) {
    const float m1 = 0.1593017578125;    // 2610/16384
    const float m2 = 78.84375;           // 2523/32 * 128
    const float c1 = 0.8359375;          // 3424/4096
    const float c2 = 18.8515625;         // 2413/128
    const float c3 = 18.6875;            // 2392/128

    float3 result;
    for (int i = 0; i < 3; i++) {
        float Np = pow(max(N[i], 0.0), 1.0/m2);
        float num = max(Np - c1, 0.0);
        float den = c2 - c3 * Np;
        result[i] = 10000.0 * pow(num / den, 1.0/m1); // cd/m^2
    }
    return result;
}

// PQ (SMPTE ST 2084) inverse EOTF (linear to PQ)
float3 pq_oetf(float3 L) {
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;

    float3 result;
    for (int i = 0; i < 3; i++) {
        float Y = L[i] / 10000.0;
        float Ym1 = pow(max(Y, 0.0), m1);
        result[i] = pow((c1 + c2 * Ym1) / (1.0 + c3 * Ym1), m2);
    }
    return result;
}

// HLG OETF (scene linear to HLG)
float3 hlg_oetf(float3 E) {
    const float a = 0.17883277;
    const float b = 0.28466892; // 1 - 4*a
    const float c = 0.55991073; // 0.5 - a*ln(4*a)

    float3 result;
    for (int i = 0; i < 3; i++) {
        result[i] = (E[i] <= 1.0/12.0)
            ? sqrt(3.0 * E[i])
            : a * log(12.0 * E[i] - b) + c;
    }
    return result;
}

// Complete color space conversion kernel
kernel void convert_color_space(
    texture2d<float, access::read>  input      [[texture(0)]],
    texture2d<float, access::write> output     [[texture(1)]],
    constant float3x3& conversionMatrix        [[buffer(0)]],
    constant int& sourceTransfer               [[buffer(1)]],  // 0=sRGB, 1=PQ, 2=HLG
    constant int& destTransfer                 [[buffer(2)]],
    uint2 gid                                  [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    float4 color = input.read(gid);
    float3 rgb = color.rgb;

    // Step 1: Apply source EOTF (to linear)
    if (sourceTransfer == 0) rgb = srgb_eotf(rgb);
    else if (sourceTransfer == 1) rgb = pq_eotf(rgb) / 10000.0; // normalize
    // HLG needs OOTF application too

    // Step 2: Apply 3x3 gamut conversion matrix
    rgb = conversionMatrix * rgb;

    // Step 3: Apply destination OETF
    if (destTransfer == 0) rgb = srgb_oetf(rgb);
    else if (destTransfer == 1) rgb = pq_oetf(rgb * 10000.0);
    else if (destTransfer == 2) rgb = hlg_oetf(rgb);

    output.write(float4(rgb, color.a), gid);
}
```

---

## 4. Professional Delivery Formats

### IMF (Interoperable Master Format)

IMF (SMPTE ST 2067) is a component-based container where each essence type (video, audio, subtitles) is stored in individual MXF Track Files, with a Composition Playlist (CPL) synchronizing them.

**Key components:**
- **Output Profile List (OPL)**: Describes output versions
- **Composition Playlist (CPL)**: XML describing timeline assembly
- **Track Files**: MXF-wrapped JPEG 2000 video, PCM audio
- **Packing List**: Manifest of all files
- **Asset Map**: Maps UUIDs to filenames

```swift
/// IMF package structure model
struct IMFPackage {
    let assetMap: IMFAssetMap
    let packingList: IMFPackingList
    let compositionPlaylist: IMFCompositionPlaylist
    let trackFiles: [IMFTrackFile]

    struct IMFCompositionPlaylist {
        let id: UUID
        let editRate: CMTime  // e.g., 24/1
        let segments: [IMFSegment]
    }

    struct IMFSegment {
        let id: UUID
        let sequences: [IMFSequence]  // video, audio, subtitle sequences
    }

    struct IMFSequence {
        let trackID: String
        let resources: [IMFResource]
    }

    struct IMFResource {
        let trackFileID: UUID
        let entryPoint: Int64  // edit units
        let sourceDuration: Int64
        let repeatCount: Int
    }

    struct IMFTrackFile {
        let id: UUID
        let mxfFilePath: URL
        let essenceType: EssenceType

        enum EssenceType {
            case jpeg2000Video
            case pcmAudio
            case timedText
        }
    }
}
```

### DCP (Digital Cinema Package)

DCP uses JPEG 2000 compressed video at 12-bit 4:4:4 XYZ color space, 24-bit linear PCM audio, DCI resolution (2048x1080 or 4096x2160).

```swift
/// DCP export configuration
struct DCPConfiguration {
    enum Resolution {
        case scope2K   // 2048 x 858
        case flat2K    // 1998 x 1080
        case full2K    // 2048 x 1080
        case scope4K   // 4096 x 1716
        case flat4K    // 3996 x 2160
        case full4K    // 4096 x 2160
    }

    let resolution: Resolution
    let frameRate: Double        // 24, 25, 30, 48, 60
    let is3D: Bool = false
    let contentKind: String      // "feature", "trailer", "short"
    let colorSpace: String = "XYZ"  // DCI XYZ always
    let bitDepth: Int = 12
    let jpeg2000Bitrate: Int = 250_000_000  // bits/sec, max 250 Mbit/s
    let audioSampleRate: Int = 48000
    let audioBitDepth: Int = 24
    let audioChannels: Int = 6   // 5.1 minimum

    // XYZ conversion from Rec.709
    static let rec709_to_xyz = matrix_float3x3(columns: (
        SIMD3<Float>(0.4124564, 0.2126729, 0.0193339),
        SIMD3<Float>(0.3575761, 0.7151522, 0.1191920),
        SIMD3<Float>(0.1804375, 0.0721750, 0.9503041)
    ))
}
```

---

## 5. Loudness Standards

### ITU-R BS.1770 / EBU R128 / ATSC A/85

| Standard | Target | Max True Peak | Use |
|----------|--------|---------------|-----|
| EBU R128 | -23 LUFS | -1 dBTP | European broadcast |
| ATSC A/85 | -24 LKFS | -2 dBTP | US broadcast |
| iTunes/Apple | -16 LUFS | -1 dBTP | Streaming |
| YouTube | -14 LUFS | -1 dBTP | Streaming |
| Netflix | -27 LKFS (dialog) | -2 dBTP | Streaming |
| Spotify | -14 LUFS | -1 dBTP | Music streaming |

### K-Weighting Filter Implementation

```swift
import Accelerate
import AVFoundation

/// ITU-R BS.1770-4 compliant loudness measurement
class LoudnessMeter {
    private let sampleRate: Double

    // K-weighting filter coefficients (48 kHz)
    // Stage 1: High-shelf filter (+4dB at 1681 Hz)
    private let shelf_b: [Double] = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    private let shelf_a: [Double] = [1.0, -1.69065929318241, 0.73248077421585]

    // Stage 2: High-pass filter (38 Hz, RLB weighting)
    private let hp_b: [Double] = [1.0, -2.0, 1.0]
    private let hp_a: [Double] = [1.0, -1.99004745483398, 0.99007225036621]

    // Filter state
    private var shelfState: [[Double]]  // per-channel
    private var hpState: [[Double]]     // per-channel

    // Channel weights for 5.1 surround (BS.1770-4)
    // L=1.0, R=1.0, C=1.0, LFE=0.0, Ls=1.41, Rs=1.41
    static let channelWeights: [Double] = [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]

    init(sampleRate: Double = 48000, channelCount: Int = 2) {
        self.sampleRate = sampleRate
        self.shelfState = Array(repeating: [0.0, 0.0], count: channelCount)
        self.hpState = Array(repeating: [0.0, 0.0], count: channelCount)
    }

    /// Measure integrated loudness (LUFS) of an audio buffer
    func measureIntegratedLoudness(buffer: AVAudioPCMBuffer) -> Double {
        guard let floatData = buffer.floatChannelData else { return -Double.infinity }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let blockSize = Int(0.4 * sampleRate) // 400ms blocks
        let stepSize = Int(0.1 * sampleRate)  // 75% overlap

        var blockLoudnesses: [Double] = []

        for blockStart in stride(from: 0, to: frameCount - blockSize, by: stepSize) {
            var blockPower = 0.0

            for ch in 0..<min(channelCount, 6) {
                let channelPtr = floatData[ch]
                var filtered = [Float](repeating: 0, count: blockSize)

                // Apply K-weighting filter
                for i in 0..<blockSize {
                    let sample = Double(channelPtr[blockStart + i])
                    let kWeighted = applyKWeighting(sample: sample, channel: ch)
                    filtered[i] = Float(kWeighted)
                }

                // Mean square
                var meanSquare: Float = 0
                vDSP_measqv(filtered, 1, &meanSquare, vDSP_Length(blockSize))

                let weight = ch < LoudnessMeter.channelWeights.count
                    ? LoudnessMeter.channelWeights[ch] : 1.0
                blockPower += Double(meanSquare) * weight
            }

            let blockLoudness = -0.691 + 10.0 * log10(max(blockPower, 1e-10))
            blockLoudnesses.append(blockLoudness)
        }

        // Gating: absolute threshold at -70 LUFS
        let absoluteGated = blockLoudnesses.filter { $0 > -70.0 }
        guard !absoluteGated.isEmpty else { return -Double.infinity }

        let absoluteMean = absoluteGated.reduce(0, +) / Double(absoluteGated.count)
        let relativeThreshold = absoluteMean - 10.0

        // Relative gating
        let relativeGated = absoluteGated.filter { $0 > relativeThreshold }
        guard !relativeGated.isEmpty else { return -Double.infinity }

        return relativeGated.reduce(0, +) / Double(relativeGated.count)
    }

    /// Apply K-weighting (shelf + highpass) to single sample
    private func applyKWeighting(sample: Double, channel: Int) -> Double {
        // Stage 1: High shelf
        let shelfOut = shelf_b[0] * sample
            + shelf_b[1] * shelfState[channel][0]
            + shelf_b[2] * shelfState[channel][1]
            - shelf_a[1] * shelfState[channel][0]
            - shelf_a[2] * shelfState[channel][1]

        shelfState[channel][1] = shelfState[channel][0]
        shelfState[channel][0] = shelfOut

        // Stage 2: High pass (RLB)
        let hpOut = hp_b[0] * shelfOut
            + hp_b[1] * hpState[channel][0]
            + hp_b[2] * hpState[channel][1]
            - hp_a[1] * hpState[channel][0]
            - hp_a[2] * hpState[channel][1]

        hpState[channel][1] = hpState[channel][0]
        hpState[channel][0] = hpOut

        return hpOut
    }

    /// Measure true peak using 4x oversampling (BS.1770-4)
    func measureTruePeak(buffer: AVAudioPCMBuffer) -> Double {
        guard let floatData = buffer.floatChannelData else { return -Double.infinity }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var maxPeak: Float = 0

        for ch in 0..<channelCount {
            let channelPtr = floatData[ch]
            // 4x upsample using vDSP
            let upsampledCount = frameCount * 4
            var upsampled = [Float](repeating: 0, count: upsampledCount)

            // Insert zeros between samples, then lowpass filter
            for i in 0..<frameCount {
                upsampled[i * 4] = channelPtr[i]
            }

            // Find absolute max of upsampled signal
            var chMax: Float = 0
            vDSP_maxmgv(upsampled, 1, &chMax, vDSP_Length(upsampledCount))
            maxPeak = max(maxPeak, chMax * 4.0) // compensate for zero-insertion
        }

        return 20.0 * log10(Double(max(maxPeak, 1e-10)))
    }

    /// Normalize audio to target loudness
    func normalize(buffer: AVAudioPCMBuffer, targetLUFS: Double) -> Float {
        let currentLUFS = measureIntegratedLoudness(buffer: buffer)
        let gainDB = targetLUFS - currentLUFS
        return Float(pow(10.0, gainDB / 20.0))
    }
}
```

---

## 6. SMPTE Timecode

### Drop-Frame vs Non-Drop-Frame

- **Non-Drop-Frame (NDF)**: Frames counted sequentially. At 29.97fps, timecode drifts ~3.6 seconds per hour vs real time. Separator: colon (HH:MM:SS:FF)
- **Drop-Frame (DF)**: Drops frame numbers 00 and 01 at the start of each minute, except every 10th minute. Keeps timecode synchronized with wall clock. Separator: semicolon (HH:MM:SS;FF)

### Timecode Implementation

```swift
import CoreMedia

/// SMPTE timecode representation and arithmetic
struct SMPTETimecode: Equatable, Comparable, CustomStringConvertible {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let frameRate: FrameRate
    let isDropFrame: Bool

    enum FrameRate: Double, CaseIterable {
        case fps23_976 = 23.976
        case fps24     = 24.0
        case fps25     = 25.0
        case fps29_97  = 29.97
        case fps30     = 30.0
        case fps48     = 48.0
        case fps50     = 50.0
        case fps59_94  = 59.94
        case fps60     = 60.0

        var nominalFrames: Int {
            switch self {
            case .fps23_976: return 24
            case .fps24:     return 24
            case .fps25:     return 25
            case .fps29_97:  return 30
            case .fps30:     return 30
            case .fps48:     return 48
            case .fps50:     return 50
            case .fps59_94:  return 60
            case .fps60:     return 60
            }
        }

        var supportsDropFrame: Bool {
            self == .fps29_97 || self == .fps59_94
        }

        /// Frames dropped per minute (except every 10th)
        var droppedFramesPerMinute: Int {
            switch self {
            case .fps29_97: return 2
            case .fps59_94: return 4
            default: return 0
            }
        }
    }

    var description: String {
        let separator = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }

    // MARK: - Frame Number Conversion

    /// Convert timecode to total frame count
    func toFrameNumber() -> Int {
        let fps = frameRate.nominalFrames

        if !isDropFrame {
            // Non-drop-frame: simple calculation
            return hours * 3600 * fps
                 + minutes * 60 * fps
                 + seconds * fps
                 + frames
        }

        // Drop-frame calculation
        let dropPerMin = frameRate.droppedFramesPerMinute
        let totalMinutes = hours * 60 + minutes
        let tenMinuteIntervals = totalMinutes / 10
        let remainingMinutes = totalMinutes % 10

        // Total frames = time-based frames - dropped frames
        let timeFrames = hours * 3600 * fps
                       + minutes * 60 * fps
                       + seconds * fps
                       + frames

        let droppedFrames = dropPerMin * (totalMinutes - tenMinuteIntervals)

        return timeFrames - droppedFrames
    }

    /// Create timecode from total frame count
    static func fromFrameNumber(_ totalFrames: Int, frameRate: FrameRate, dropFrame: Bool) -> SMPTETimecode {
        let fps = frameRate.nominalFrames

        if !dropFrame {
            let f = totalFrames % fps
            let s = (totalFrames / fps) % 60
            let m = (totalFrames / (fps * 60)) % 60
            let h = totalFrames / (fps * 3600)
            return SMPTETimecode(hours: h, minutes: m, seconds: s, frames: f,
                               frameRate: frameRate, isDropFrame: false)
        }

        // Drop-frame reverse calculation
        let drop = frameRate.droppedFramesPerMinute
        let framesPerMin = fps * 60 - drop
        let framesPer10Min = framesPerMin * 10 + drop

        let tenMinBlocks = totalFrames / framesPer10Min
        var remainder = totalFrames % framesPer10Min

        var minutes = tenMinBlocks * 10

        if remainder >= fps * 60 {
            remainder -= fps * 60
            minutes += 1

            let additionalMinutes = remainder / framesPerMin
            remainder = remainder % framesPerMin
            minutes += additionalMinutes

            // Add back dropped frames for display
            remainder += drop
        }

        let h = minutes / 60
        let m = minutes % 60
        let s = remainder / fps
        let f = remainder % fps

        return SMPTETimecode(hours: h, minutes: m, seconds: s, frames: f,
                           frameRate: frameRate, isDropFrame: true)
    }

    /// Convert to CMTime
    func toCMTime() -> CMTime {
        let frameNumber = toFrameNumber()
        let timescale: Int32
        let value: Int64

        switch frameRate {
        case .fps23_976:
            timescale = 24000
            value = Int64(frameNumber) * 1001
        case .fps29_97:
            timescale = 30000
            value = Int64(frameNumber) * 1001
        case .fps59_94:
            timescale = 60000
            value = Int64(frameNumber) * 1001
        default:
            timescale = Int32(frameRate.rawValue * 1000)
            value = Int64(frameNumber) * 1000
        }

        return CMTime(value: value, timescale: timescale)
    }

    /// Parse from string "HH:MM:SS:FF" or "HH:MM:SS;FF"
    static func parse(_ string: String, frameRate: FrameRate) -> SMPTETimecode? {
        let isDrop = string.contains(";")
        let components = string.split(separator: isDrop ? ";" : ":").compactMap { Int($0) }

        // Handle "HH:MM:SS;FF" format (3 colons then semicolon)
        let parts: [Int]
        if isDrop {
            let colonParts = string.split(separator: ";")
            guard colonParts.count == 2, let ff = Int(colonParts[1]) else { return nil }
            let hmsParts = colonParts[0].split(separator: ":").compactMap { Int($0) }
            guard hmsParts.count == 3 else { return nil }
            parts = hmsParts + [ff]
        } else {
            parts = components
        }

        guard parts.count == 4 else { return nil }

        return SMPTETimecode(
            hours: parts[0], minutes: parts[1],
            seconds: parts[2], frames: parts[3],
            frameRate: frameRate, isDropFrame: isDrop
        )
    }

    // MARK: - Arithmetic

    static func + (lhs: SMPTETimecode, rhs: SMPTETimecode) -> SMPTETimecode {
        let totalFrames = lhs.toFrameNumber() + rhs.toFrameNumber()
        return fromFrameNumber(totalFrames, frameRate: lhs.frameRate, dropFrame: lhs.isDropFrame)
    }

    static func - (lhs: SMPTETimecode, rhs: SMPTETimecode) -> SMPTETimecode {
        let totalFrames = max(0, lhs.toFrameNumber() - rhs.toFrameNumber())
        return fromFrameNumber(totalFrames, frameRate: lhs.frameRate, dropFrame: lhs.isDropFrame)
    }

    static func < (lhs: SMPTETimecode, rhs: SMPTETimecode) -> Bool {
        lhs.toFrameNumber() < rhs.toFrameNumber()
    }
}

/// Timecode burn-in overlay renderer
class TimecodeBurnIn {
    let font: CTFont
    let backgroundColor: CGColor
    let textColor: CGColor

    init(fontSize: CGFloat = 24) {
        self.font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        self.backgroundColor = CGColor(gray: 0, alpha: 0.7)
        self.textColor = CGColor(gray: 1, alpha: 1)
    }

    /// Render timecode string into a Metal texture
    func renderTimecode(_ timecode: SMPTETimecode, into texture: MTLTexture, device: MTLDevice) {
        let text = timecode.description
        let width = texture.width
        let height = texture.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Draw background box
        let boxRect = CGRect(x: 20, y: 20, width: 300, height: 40)
        context.setFillColor(backgroundColor)
        context.fill(boxRect)

        // Draw timecode text
        let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(attrString, CFRangeMake(0, 0), text as CFString)
        CFAttributedStringSetAttribute(attrString, CFRangeMake(0, text.count),
                                       kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(attrString, CFRangeMake(0, text.count),
                                       kCTForegroundColorAttributeName, textColor)

        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 30, y: 28)
        CTLineDraw(line, context)

        // Copy to texture
        if let data = context.data {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: data,
                bytesPerRow: width * 4
            )
        }
    }
}

/// Extract timecode from source media
func extractTimecode(from asset: AVURLAsset) async throws -> SMPTETimecode? {
    let metadataItems = try await asset.load(.metadata)

    for item in metadataItems {
        guard let key = item.commonKey?.rawValue ?? (try? await item.load(.key) as? String)
        else { continue }

        if key.contains("timecode") || key == "com.apple.quicktime.timecode" {
            if let stringValue = try? await item.load(.stringValue) {
                return SMPTETimecode.parse(stringValue, frameRate: .fps29_97)
            }
        }
    }

    // Try reading from timecode track
    let tracks = try await asset.loadTracks(withMediaType: .timecode)
    if let tcTrack = tracks.first {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tcTrack, outputSettings: nil)
        reader.add(output)
        reader.startReading()

        if let sampleBuffer = output.copyNextSampleBuffer() {
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
            // Parse timecode from format description
            if let desc = formatDesc {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                // kCMTimeCodeFormatType_TimeCode32 or TimeCode64
                print("Timecode format: \(mediaSubType)")
            }
        }
    }

    return nil
}
```

---

## 7. EDL/XML/AAF Interchange

### CMX 3600 EDL Format

```swift
/// CMX 3600 EDL parser and generator
struct EDLEvent {
    let eventNumber: Int          // 001-999
    let reelName: String          // Max 8 chars, A-Z 0-9
    let trackType: TrackType
    let editType: EditType
    let sourceIn: SMPTETimecode
    let sourceOut: SMPTETimecode
    let recordIn: SMPTETimecode
    let recordOut: SMPTETimecode
    var comment: String?
    var fromClipName: String?

    enum TrackType: String {
        case video = "V"
        case audioMono = "A"
        case audio1 = "A1"
        case audio2 = "A2"
        case both = "B"
        case audioAll = "AA"
        case audioAllVideo = "AA/V"
    }

    enum EditType: String {
        case cut = "C"
        case dissolve = "D"
        case wipePattern = "W"
    }
}

class EDLParser {
    /// Parse CMX 3600 EDL file
    func parse(fileContent: String, frameRate: SMPTETimecode.FrameRate) -> [EDLEvent] {
        var events: [EDLEvent] = []
        let lines = fileContent.components(separatedBy: .newlines)
        var currentEvent: EDLEvent?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip TITLE and FCM lines
            if trimmed.hasPrefix("TITLE:") || trimmed.hasPrefix("FCM:") { continue }

            // Event line: "001  REEL01   V     C        01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00"
            if let event = parseEventLine(trimmed, frameRate: frameRate) {
                if let prev = currentEvent { events.append(prev) }
                currentEvent = event
            }

            // Comment lines
            if trimmed.hasPrefix("* FROM CLIP NAME:") {
                currentEvent?.fromClipName = String(trimmed.dropFirst(18)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("*") {
                currentEvent?.comment = String(trimmed.dropFirst(2))
            }
        }

        if let last = currentEvent { events.append(last) }
        return events
    }

    private func parseEventLine(_ line: String, frameRate: SMPTETimecode.FrameRate) -> EDLEvent? {
        // Pattern: EventNum  Reel  Track  EditType  SrcIn  SrcOut  RecIn  RecOut
        let components = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard components.count >= 8,
              let eventNum = Int(components[0]),
              eventNum >= 1 && eventNum <= 999
        else { return nil }

        let reel = components[1]
        let track = EDLEvent.TrackType(rawValue: components[2]) ?? .video
        let edit = EDLEvent.EditType(rawValue: components[3]) ?? .cut

        guard let srcIn = SMPTETimecode.parse(components[4], frameRate: frameRate),
              let srcOut = SMPTETimecode.parse(components[5], frameRate: frameRate),
              let recIn = SMPTETimecode.parse(components[6], frameRate: frameRate),
              let recOut = SMPTETimecode.parse(components[7], frameRate: frameRate)
        else { return nil }

        return EDLEvent(
            eventNumber: eventNum, reelName: reel,
            trackType: track, editType: edit,
            sourceIn: srcIn, sourceOut: srcOut,
            recordIn: recIn, recordOut: recOut
        )
    }

    /// Generate CMX 3600 EDL string
    func generate(title: String, events: [EDLEvent], dropFrame: Bool) -> String {
        var output = "TITLE: \(title)\n"
        output += "FCM: \(dropFrame ? "DROP FRAME" : "NON-DROP FRAME")\n\n"

        for event in events {
            output += String(format: "%03d  %-8s %-5s %-4s %s %s %s %s\n",
                           event.eventNumber,
                           (event.reelName as NSString).utf8String!,
                           (event.trackType.rawValue as NSString).utf8String!,
                           (event.editType.rawValue as NSString).utf8String!,
                           event.sourceIn.description,
                           event.sourceOut.description,
                           event.recordIn.description,
                           event.recordOut.description)

            if let clipName = event.fromClipName {
                output += "* FROM CLIP NAME: \(clipName)\n"
            }
            if let comment = event.comment {
                output += "* \(comment)\n"
            }
        }

        return output
    }
}
```

### FCPXML Export/Import

```swift
import Foundation

/// FCPXML generator for Final Cut Pro interchange
class FCPXMLGenerator {
    let version = "1.11"  // Latest FCPXML version

    struct ProjectSettings {
        let name: String
        let duration: CMTime
        let frameRate: Double
        let width: Int
        let height: Int
        let audioRate: Int = 48000
        let audioChannels: Int = 2
    }

    struct ClipReference {
        let id: String
        let name: String
        let sourceURL: URL
        let duration: CMTime
        let start: CMTime           // position on timeline
        let sourceStart: CMTime     // in-point in source
        let audioRole: String?
        let videoRole: String?
    }

    /// Generate FCPXML document
    func generate(settings: ProjectSettings, clips: [ClipReference]) -> String {
        let formatID = "r1"
        let fps = rationalFrameRate(settings.frameRate)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="\(version)">
            <resources>
                <format id="\(formatID)" name="FFVideoFormat\(settings.width)x\(settings.height)p\(fps.display)" \
        frameDuration="\(fps.duration)s" width="\(settings.width)" height="\(settings.height)" \
        colorSpace="1-1-1 (Rec. 709)"/>
        """

        // Add asset resources
        for clip in clips {
            xml += """

                    <asset id="\(clip.id)" name="\(escapeXML(clip.name))" \
            src="\(clip.sourceURL.absoluteString)" \
            start="0s" duration="\(cmTimeToFCPString(clip.duration))" \
            format="\(formatID)" hasVideo="1" hasAudio="1"/>
            """
        }

        xml += """

            </resources>
            <library>
                <event name="\(escapeXML(settings.name))">
                    <project name="\(escapeXML(settings.name))">
                        <sequence format="\(formatID)" \
        duration="\(cmTimeToFCPString(settings.duration))" \
        tcStart="0s" tcFormat="\(settings.frameRate == 29.97 ? "DF" : "NDF")">
                            <spine>
        """

        // Add clips to spine
        for clip in clips {
            xml += """

                                <asset-clip ref="\(clip.id)" \
            name="\(escapeXML(clip.name))" \
            offset="\(cmTimeToFCPString(clip.start))" \
            duration="\(cmTimeToFCPString(clip.duration))" \
            start="\(cmTimeToFCPString(clip.sourceStart))"/>
            """
        }

        xml += """

                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """

        return xml
    }

    /// Parse FCPXML and extract clip references
    func parse(xmlData: Data) throws -> (settings: ProjectSettings, clips: [ClipReference]) {
        let parser = FCPXMLXMLParser(data: xmlData)
        return try parser.parse()
    }

    // Helper: convert CMTime to FCPXML rational time string
    private func cmTimeToFCPString(_ time: CMTime) -> String {
        return "\(time.value)/\(time.timescale)s"
    }

    // Helper: get rational frame duration
    private func rationalFrameRate(_ fps: Double) -> (duration: String, display: String) {
        switch fps {
        case 23.976: return ("1001/24000", "2398")
        case 24:     return ("100/2400", "24")
        case 25:     return ("100/2500", "25")
        case 29.97:  return ("1001/30000", "2997")
        case 30:     return ("100/3000", "30")
        case 50:     return ("100/5000", "50")
        case 59.94:  return ("1001/60000", "5994")
        case 60:     return ("100/6000", "60")
        default:     return ("100/\(Int(fps * 100))", "\(Int(fps))")
        }
    }

    private func escapeXML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Basic FCPXML parser using XMLParser
class FCPXMLXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var assets: [String: (name: String, src: String, duration: String)] = [:]
    private var clips: [FCPXMLGenerator.ClipReference] = []
    private var currentElement = ""

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> (settings: FCPXMLGenerator.ProjectSettings, clips: [FCPXMLGenerator.ClipReference]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        let settings = FCPXMLGenerator.ProjectSettings(
            name: "Imported", duration: CMTime.zero,
            frameRate: 24, width: 1920, height: 1080
        )
        return (settings, clips)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "asset" {
            if let id = attributeDict["id"],
               let name = attributeDict["name"],
               let src = attributeDict["src"] {
                assets[id] = (name: name, src: src, duration: attributeDict["duration"] ?? "0s")
            }
        }

        if elementName == "asset-clip" {
            if let ref = attributeDict["ref"], let asset = assets[ref] {
                let clip = FCPXMLGenerator.ClipReference(
                    id: ref,
                    name: attributeDict["name"] ?? asset.name,
                    sourceURL: URL(string: asset.src) ?? URL(fileURLWithPath: ""),
                    duration: parseFCPTime(attributeDict["duration"] ?? "0s"),
                    start: parseFCPTime(attributeDict["offset"] ?? "0s"),
                    sourceStart: parseFCPTime(attributeDict["start"] ?? "0s"),
                    audioRole: nil, videoRole: nil
                )
                clips.append(clip)
            }
        }
    }

    private func parseFCPTime(_ string: String) -> CMTime {
        let cleaned = string.replacingOccurrences(of: "s", with: "")
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/")
            if parts.count == 2, let num = Int64(parts[0]), let den = Int32(parts[1]) {
                return CMTime(value: num, timescale: den)
            }
        }
        if let seconds = Double(cleaned) {
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
        return .zero
    }
}
```

### Premiere Pro XML (XMEML) Structure

Premiere Pro uses Apple's legacy FCP 7 XML format (XMEML) with Adobe-specific extensions.

```swift
/// Premiere Pro XML (XMEML) generator
class PremiereXMLGenerator {

    struct Sequence {
        let name: String
        let duration: Int  // frames
        let timebase: Int  // fps
        let ntsc: Bool     // true for 29.97, 23.976
        let width: Int
        let height: Int
    }

    struct ClipItem {
        let id: String
        let name: String
        let filePath: URL
        let inPoint: Int   // frames
        let outPoint: Int  // frames
        let startOnTimeline: Int  // frames
    }

    func generate(sequence: Sequence, clips: [ClipItem]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="5">
            <sequence>
                <name>\(sequence.name)</name>
                <duration>\(sequence.duration)</duration>
                <rate>
                    <timebase>\(sequence.timebase)</timebase>
                    <ntsc>\(sequence.ntsc ? "TRUE" : "FALSE")</ntsc>
                </rate>
                <media>
                    <video>
                        <format>
                            <samplecharacteristics>
                                <width>\(sequence.width)</width>
                                <height>\(sequence.height)</height>
                            </samplecharacteristics>
                        </format>
                        <track>
        """

        for clip in clips {
            xml += """

                            <clipitem id="\(clip.id)">
                                <name>\(clip.name)</name>
                                <duration>\(clip.outPoint - clip.inPoint)</duration>
                                <rate>
                                    <timebase>\(sequence.timebase)</timebase>
                                    <ntsc>\(sequence.ntsc ? "TRUE" : "FALSE")</ntsc>
                                </rate>
                                <start>\(clip.startOnTimeline)</start>
                                <end>\(clip.startOnTimeline + clip.outPoint - clip.inPoint)</end>
                                <in>\(clip.inPoint)</in>
                                <out>\(clip.outPoint)</out>
                                <file id="file-\(clip.id)">
                                    <name>\(clip.name)</name>
                                    <pathurl>\(clip.filePath.absoluteString)</pathurl>
                                </file>
                            </clipitem>
            """
        }

        xml += """

                        </track>
                    </video>
                </media>
            </sequence>
        </xmeml>
        """

        return xml
    }
}
```

### OpenTimelineIO Integration

```swift
/// OpenTimelineIO-compatible timeline model (pure Swift, no C++ dependency)
/// Can serialize to OTIO JSON format
struct OTIOTimeline: Codable {
    var name: String
    var tracks: OTIOStack

    struct OTIOStack: Codable {
        var name: String = "tracks"
        var children: [OTIOTrack]
    }

    struct OTIOTrack: Codable {
        var name: String
        var kind: String  // "Video" or "Audio"
        var children: [OTIOClip]
    }

    struct OTIOClip: Codable {
        var name: String
        var mediaReference: OTIOMediaReference
        var sourceRange: OTIOTimeRange
    }

    struct OTIOMediaReference: Codable {
        var targetURL: String
    }

    struct OTIOTimeRange: Codable {
        var startTime: OTIORationalTime
        var duration: OTIORationalTime
    }

    struct OTIORationalTime: Codable {
        var value: Double
        var rate: Double
    }

    /// Export as OTIO JSON
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(self)
    }
}
```

---

## 8. Closed Captions

### CEA-608 / CEA-708

- **CEA-608**: Legacy SD standard, 2 bytes per field, 32 chars/row, embedded on line 21 (analog) or in MPEG user data
- **CEA-708**: HD standard, superset of 608 with enhanced styling, up to 8 services, Unicode support

### SCC File Parser

```swift
/// SCC (Scenarist Closed Captions) parser - CEA-608 format
class SCCParser {
    struct CaptionEvent {
        let timecode: SMPTETimecode
        let data: [UInt16]  // Two-byte words (with parity stripped)
        var text: String = ""
    }

    /// Parse SCC file
    func parse(fileContent: String, frameRate: SMPTETimecode.FrameRate = .fps29_97) -> [CaptionEvent] {
        var events: [CaptionEvent] = []
        let lines = fileContent.components(separatedBy: .newlines)

        // Verify header
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "Scenarist_SCC V1.0" else {
            return []
        }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Format: "HH:MM:SS:FF\tXXXX XXXX XXXX..."
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let isDropFrame = parts[0].contains(";")
            guard let tc = SMPTETimecode.parse(String(parts[0]), frameRate: frameRate) else { continue }

            let hexWords = parts[1].split(separator: " ").compactMap { word -> UInt16? in
                guard let value = UInt16(word, radix: 16) else { return nil }
                // Strip parity bits (bit 7 of each byte)
                let byte1 = UInt8((value >> 8) & 0x7F)
                let byte2 = UInt8(value & 0x7F)
                return UInt16(byte1) << 8 | UInt16(byte2)
            }

            var event = CaptionEvent(timecode: tc, data: hexWords)
            event.text = decodeCEA608(hexWords)
            events.append(event)
        }

        return events
    }

    /// Basic CEA-608 character decoding
    private func decodeCEA608(_ words: [UInt16]) -> String {
        var text = ""

        for word in words {
            let byte1 = UInt8((word >> 8) & 0x7F)
            let byte2 = UInt8(word & 0x7F)

            // Control codes: byte1 has bit patterns 0x10-0x1F
            if byte1 >= 0x10 && byte1 <= 0x1F {
                // Skip control codes for basic parsing
                continue
            }

            // Printable characters (0x20-0x7F range after parity stripping)
            if byte1 >= 0x20 && byte1 <= 0x7F {
                text.append(Character(UnicodeScalar(byte1)))
            }
            if byte2 >= 0x20 && byte2 <= 0x7F {
                text.append(Character(UnicodeScalar(byte2)))
            }
        }

        return text
    }

    /// Generate SCC file from caption events
    func generate(events: [CaptionEvent]) -> String {
        var output = "Scenarist_SCC V1.0\n\n"

        for event in events {
            let hexString = event.data.map { String(format: "%04x", $0) }.joined(separator: " ")
            output += "\(event.timecode.description)\t\(hexString)\n\n"
        }

        return output
    }
}

/// MCC (MacCaption Closed Captions) parser for CEA-708
class MCCParser {
    struct MCCCaptionEvent {
        let timecode: SMPTETimecode
        let data: Data  // CEA-708 caption data
    }

    func parse(fileContent: String) -> [MCCCaptionEvent] {
        var events: [MCCCaptionEvent] = []
        let lines = fileContent.components(separatedBy: .newlines)

        // MCC files start with "File Format=MacCaption_MCC V2.0"
        // or similar header
        var inData = false

        for line in lines {
            if line.hasPrefix("//") || line.isEmpty { continue }
            if line.hasPrefix("File Format=") { continue }
            if line.hasPrefix("UUID=") || line.hasPrefix("Creation") { continue }
            if line.hasPrefix("Time Code Rate=") { continue }

            // Data lines: "HH:MM:SS:FF\tdata..."
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }

            if let tc = SMPTETimecode.parse(String(parts[0]), frameRate: .fps29_97) {
                // MCC uses run-length encoded hex data
                let decoded = decodeMCCData(String(parts[1]))
                events.append(MCCCaptionEvent(timecode: tc, data: decoded))
            }
        }

        return events
    }

    private func decodeMCCData(_ encoded: String) -> Data {
        // MCC uses special compression: G=repeated bytes, etc.
        var data = Data()
        var chars = Array(encoded)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Expansion characters
            switch c {
            case "G": // FA 00 00
                data.append(contentsOf: [0xFA, 0x00, 0x00])
                i += 1
            case "H": // FA 00 00 FA 00 00
                data.append(contentsOf: [0xFA, 0x00, 0x00, 0xFA, 0x00, 0x00])
                i += 1
            case "I": // FA 00 00 FA 00 00 FA 00 00
                data.append(contentsOf: [0xFA, 0x00, 0x00, 0xFA, 0x00, 0x00, 0xFA, 0x00, 0x00])
                i += 1
            default:
                // Regular hex pair
                if i + 1 < chars.count {
                    let hex = String(chars[i...i+1])
                    if let byte = UInt8(hex, radix: 16) {
                        data.append(byte)
                    }
                    i += 2
                } else {
                    i += 1
                }
            }
        }

        return data
    }
}

/// Embed captions into MOV/MP4 using AVAssetWriter
class CaptionEmbedder {
    /// Add CEA-608 caption track to video export
    func embedCaptions(
        sourceAsset: AVAsset,
        captions: [SCCParser.CaptionEvent],
        outputURL: URL
    ) async throws {
        let reader = try AVAssetReader(asset: sourceAsset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Setup video and audio pass-through
        let videoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first!
        let audioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        writer.add(videoInput)

        if let audioTrack = audioTrack {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(audioOutput)

            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            writer.add(audioInput)
        }

        // Add closed caption input
        // Note: AVAssetWriterInput with .closedCaption media type
        // requires specific format for CEA-608 embedding
        let ccInput = AVAssetWriterInput(mediaType: .closedCaption, outputSettings: nil)
        writer.add(ccInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Copy video samples
        while let sample = videoOutput.copyNextSampleBuffer() {
            videoInput.append(sample)
        }

        videoInput.markAsFinished()
        ccInput.markAsFinished()
        await writer.finishWriting()
    }
}
```

---

## 9. HDR Mastering

### Dolby Vision on macOS

Apple supports Dolby Vision Profile 8.4 (HLG-compatible, cross-compatible with HDR10). AVFoundation automatically handles Dolby Vision playback and export.

```swift
import AVFoundation

/// HDR metadata configuration for export
struct HDRMetadata {
    // Mastering Display Color Volume (MDCV) - SMPTE ST 2086
    struct MasteringDisplay {
        let redPrimary: SIMD2<Float>    // CIE xy
        let greenPrimary: SIMD2<Float>
        let bluePrimary: SIMD2<Float>
        let whitePoint: SIMD2<Float>
        let maxLuminance: Float         // cd/m^2
        let minLuminance: Float         // cd/m^2

        /// Standard mastering display for DCI-P3 D65 at 1000 nits
        static let p3_1000nits = MasteringDisplay(
            redPrimary:   SIMD2<Float>(0.680, 0.320),
            greenPrimary: SIMD2<Float>(0.265, 0.690),
            bluePrimary:  SIMD2<Float>(0.150, 0.060),
            whitePoint:   SIMD2<Float>(0.3127, 0.3290),
            maxLuminance: 1000,
            minLuminance: 0.0001
        )

        /// Standard mastering display for Rec.2020 at 4000 nits
        static let rec2020_4000nits = MasteringDisplay(
            redPrimary:   SIMD2<Float>(0.708, 0.292),
            greenPrimary: SIMD2<Float>(0.170, 0.797),
            bluePrimary:  SIMD2<Float>(0.131, 0.046),
            whitePoint:   SIMD2<Float>(0.3127, 0.3290),
            maxLuminance: 4000,
            minLuminance: 0.0001
        )
    }

    // Content Light Level Info (CLLI)
    struct ContentLightLevel {
        let maxCLL: UInt16   // Maximum Content Light Level (cd/m^2)
        let maxFALL: UInt16  // Maximum Frame-Average Light Level (cd/m^2)
    }

    let masteringDisplay: MasteringDisplay
    let contentLightLevel: ContentLightLevel
}

/// HDR video exporter with metadata
class HDRExporter {

    enum HDRFormat {
        case hdr10        // Static metadata, PQ transfer
        case dolbyVision  // Dynamic metadata, Profile 8.4
        case hlg           // HLG transfer, no metadata required
    }

    /// Export HDR video with proper metadata
    func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition?,
        hdrFormat: HDRFormat,
        metadata: HDRMetadata?,
        outputURL: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Video settings for HDR
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 3840,
            AVVideoHeightKey: 2160,
        ]

        // Compression properties
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: 50_000_000,  // 50 Mbps
            AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel",
        ]

        switch hdrFormat {
        case .hdr10:
            // HDR10: PQ transfer, Rec.2020 gamut, 10-bit
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]

        case .dolbyVision:
            // Dolby Vision Profile 8.4 with HLG cross-compatibility
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]

        case .hlg:
            // HLG: backwards compatible with SDR displays
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
        }

        videoSettings[AVVideoCompressionPropertiesKey] = compressionProps

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )

        // Add HDR metadata extensions
        if let metadata = metadata {
            addHDRMetadata(to: writer, metadata: metadata)
        }

        writer.add(videoInput)

        // Audio: PCM or AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writer.add(audioInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write frames from composition...
        // (reader/writer loop omitted for brevity)

        await writer.finishWriting()
    }

    /// Add HDR10 static metadata to asset writer
    private func addHDRMetadata(to writer: AVAssetWriter, metadata: HDRMetadata) {
        var metadataItems: [AVMutableMetadataItem] = []

        // Mastering Display Color Volume (mdcv)
        let mdcv = AVMutableMetadataItem()
        mdcv.key = "mdcv" as NSString
        mdcv.keySpace = .quickTimeMetadata

        // Encode MDCV as per SMPTE ST 2086
        var mdcvData = Data()
        let display = metadata.masteringDisplay
        // Primaries in 0.00002 units, luminance in 0.0001 cd/m^2 units
        let primaries: [(Float, Float)] = [
            (display.greenPrimary.x, display.greenPrimary.y),
            (display.bluePrimary.x, display.bluePrimary.y),
            (display.redPrimary.x, display.redPrimary.y),
            (display.whitePoint.x, display.whitePoint.y)
        ]
        for (x, y) in primaries {
            var xVal = UInt16(x * 50000).bigEndian
            var yVal = UInt16(y * 50000).bigEndian
            mdcvData.append(Data(bytes: &xVal, count: 2))
            mdcvData.append(Data(bytes: &yVal, count: 2))
        }
        var maxLum = UInt32(display.maxLuminance * 10000).bigEndian
        var minLum = UInt32(display.minLuminance * 10000).bigEndian
        mdcvData.append(Data(bytes: &maxLum, count: 4))
        mdcvData.append(Data(bytes: &minLum, count: 4))

        mdcv.value = mdcvData as NSData
        metadataItems.append(mdcv)

        // Content Light Level (clli)
        let clli = AVMutableMetadataItem()
        clli.key = "clli" as NSString
        clli.keySpace = .quickTimeMetadata

        var clliData = Data()
        var maxCLL = metadata.contentLightLevel.maxCLL.bigEndian
        var maxFALL = metadata.contentLightLevel.maxFALL.bigEndian
        clliData.append(Data(bytes: &maxCLL, count: 2))
        clliData.append(Data(bytes: &maxFALL, count: 2))

        clli.value = clliData as NSData
        metadataItems.append(clli)

        writer.metadata = metadataItems
    }

    /// Analyze content for MaxCLL and MaxFALL
    func analyzeContentLightLevels(asset: AVAsset) async throws -> HDRMetadata.ContentLightLevel {
        let reader = try AVAssetReader(asset: asset)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var maxPixelLuminance: Float = 0
        var sumFrameAverages: Float = 0
        var frameCount: Int = 0

        while let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Analyze luminance from pixel data
            // (simplified - real implementation would use Metal compute)
            var frameMax: Float = 0
            var frameSum: Float = 0

            // ... pixel analysis loop ...

            maxPixelLuminance = max(maxPixelLuminance, frameMax)
            sumFrameAverages += frameSum / Float(width * height)
            frameCount += 1
        }

        let maxFALL = frameCount > 0 ? sumFrameAverages / Float(frameCount) : 0

        return HDRMetadata.ContentLightLevel(
            maxCLL: UInt16(min(maxPixelLuminance, 10000)),
            maxFALL: UInt16(min(maxFALL, 10000))
        )
    }
}
```

---

## 10. Platform Delivery Specifications

### Netflix

```swift
/// Netflix delivery configuration
struct NetflixDeliverySpec {
    // IMF is the required final delivery format
    static let format = "IMF Application #2E"
    static let standards = ["SMPTE ST 2067-21:2016", "SMPTE ST 2067-21:2020", "SMPTE ST 2067-21:2023"]

    // Video
    static let videoCodec = "JPEG 2000"  // within MXF
    static let containerFormat = "MXF"
    static let minBitDepth = 10
    static let hdrBitDepth = 12
    static let colorSpace_SDR = "Rec. 709"
    static let colorSpace_HDR = "Rec. 2020 / PQ (ST 2084)"

    // Servicing turnover (pre-IMF)
    struct ServicingTurnover {
        static let sdrCodec = "ProRes 422 HQ"  // or DNxHR HQX
        static let hdrCodec = "ProRes 4444 XQ"  // 12-bit minimum
        static let resolution = (width: 3840, height: 2160)  // UHD preferred
    }

    // Audio
    static let audioSampleRate = 48000
    static let audioBitDepth = 24
    static let dialogLoudness = -27.0  // LKFS
    static let dialogTolerance = 2.0   // +/- LKFS
    static let truePeakMax = -2.0      // dBTP
    static let atmosMinBeds = "7.1.4"

    // Captions
    static let captionFormat = "TTML"  // Netflix Timed Text
    static let captionFPS = 24.0
}
```

### YouTube

```swift
/// YouTube recommended upload specs
struct YouTubeDeliverySpec {
    static let containerFormat = "MP4"
    static let videoCodec = "H.264"  // or VP9, AV1
    static let audioCodec = "AAC-LC"

    // Recommended bitrates (Mbps)
    static func recommendedBitrate(resolution: Int, hdr: Bool, frameRate: Int) -> Int {
        let high = frameRate > 30
        switch (resolution, hdr, high) {
        case (2160, true, true):  return 66  // 4K HDR HFR
        case (2160, true, false): return 44
        case (2160, false, true): return 53
        case (2160, false, false): return 35
        case (1440, true, true):  return 30
        case (1440, true, false): return 20
        case (1440, false, true): return 24
        case (1440, false, false): return 16
        case (1080, _, true):     return 12
        case (1080, _, false):    return 8
        case (720, _, true):      return 7
        case (720, _, false):     return 5
        default:                  return 5
        }
    }

    // Audio bitrate recommendations
    static let stereoBitrate = 384    // kbps
    static let surround51Bitrate = 512 // kbps

    // Color space
    static let sdrColorSpace = "Rec. 709"
    static let hdrTransfer = "PQ (ST 2084) or HLG"
    static let hdrGamut = "Rec. 2020"
}
```

### Apple TV+

```swift
/// Apple TV+ delivery specification
struct AppleTVDeliverySpec {
    // Video
    static let videoCodec = "ProRes 4444 or ProRes 4444 XQ"
    static let bitDepth = 12
    static let resolutions = ["3840x2160", "4096x2160"]  // UHD or DCI 4K

    // HDR
    static let hdrFormat = "Dolby Vision"
    static let dvProfile = "Profile 8.4"
    static let dvMetadataVersions = ["CM v2.9", "CM v4.0"]
    static let colorSpace = "Rec. 2020"

    // SDR
    static let sdrColorSpace = "Rec. 709"

    // Audio
    static let audioFormat = "PCM"
    static let sampleRate = 48000
    static let bitDepthAudio = 24

    // Requirements
    static let mustStartWithBlackFrame = true
    static let mustEndWithBlackFrame = true
    static let audioMustBePresent = true

    // Dolby Vision metadata must cover all frames with no gaps
    static let dvMetadataGapsAllowed = false
}
```

### Unified Export Preset System

```swift
/// Export preset system covering all major delivery targets
enum DeliveryPreset: String, CaseIterable {
    case netflix_imf = "Netflix IMF"
    case netflix_turnover_sdr = "Netflix Turnover (SDR)"
    case netflix_turnover_hdr = "Netflix Turnover (HDR)"
    case appleTVPlus_hdr = "Apple TV+ (HDR)"
    case appleTVPlus_sdr = "Apple TV+ (SDR)"
    case youtube_4k = "YouTube 4K"
    case youtube_1080p = "YouTube 1080p"
    case broadcast_hd = "Broadcast HD (Rec.709)"
    case broadcast_uhd_hdr = "Broadcast UHD HDR"
    case dcp_2k = "DCP 2K"
    case dcp_4k = "DCP 4K"
    case archive_prores = "Archive (ProRes 4444)"
    case web_h264 = "Web (H.264)"
    case web_hevc = "Web (HEVC)"

    var configuration: ExportConfiguration {
        switch self {
        case .netflix_imf:
            return ExportConfiguration(
                videoCodec: .jpeg2000, container: .mxf,
                width: 3840, height: 2160, bitDepth: 10,
                colorSpace: .rec709, transferFunction: .bt1886,
                audioBitDepth: 24, audioSampleRate: 48000,
                loudnessTarget: -27.0, truePeakMax: -2.0
            )
        case .youtube_4k:
            return ExportConfiguration(
                videoCodec: .h264, container: .mp4,
                width: 3840, height: 2160, bitDepth: 8,
                colorSpace: .rec709, transferFunction: .srgb,
                videoBitrate: 35_000_000,
                audioBitDepth: 16, audioSampleRate: 48000,
                audioCodec: .aac, audioBitrate: 384_000,
                loudnessTarget: -14.0, truePeakMax: -1.0
            )
        case .appleTVPlus_hdr:
            return ExportConfiguration(
                videoCodec: .prores4444XQ, container: .mov,
                width: 3840, height: 2160, bitDepth: 12,
                colorSpace: .rec2020, transferFunction: .hlg,
                hdrFormat: .dolbyVision,
                audioBitDepth: 24, audioSampleRate: 48000,
                loudnessTarget: -24.0, truePeakMax: -2.0
            )
        case .dcp_2k:
            return ExportConfiguration(
                videoCodec: .jpeg2000, container: .mxf,
                width: 2048, height: 1080, bitDepth: 12,
                colorSpace: .xyz, transferFunction: .gamma26,
                videoBitrate: 250_000_000,
                audioBitDepth: 24, audioSampleRate: 48000,
                audioChannels: 6,
                loudnessTarget: -20.0, truePeakMax: -3.0
            )
        case .broadcast_hd:
            return ExportConfiguration(
                videoCodec: .proresHQ, container: .mxf,
                width: 1920, height: 1080, bitDepth: 10,
                colorSpace: .rec709, transferFunction: .bt1886,
                audioBitDepth: 24, audioSampleRate: 48000,
                loudnessTarget: -23.0, truePeakMax: -1.0
            )
        default:
            return ExportConfiguration.defaultConfig()
        }
    }
}

struct ExportConfiguration {
    var videoCodec: VideoCodec
    var container: ContainerFormat
    var width: Int
    var height: Int
    var bitDepth: Int
    var colorSpace: ColorSpaceID
    var transferFunction: TransferFunction
    var hdrFormat: HDRFormatType?
    var videoBitrate: Int?
    var audioBitDepth: Int
    var audioSampleRate: Int
    var audioCodec: AudioCodec = .pcm
    var audioBitrate: Int?
    var audioChannels: Int = 2
    var loudnessTarget: Double  // LUFS
    var truePeakMax: Double     // dBTP

    enum VideoCodec { case h264, hevc, proresHQ, prores4444, prores4444XQ, jpeg2000, proResRAW }
    enum ContainerFormat { case mov, mp4, mxf }
    enum ColorSpaceID { case srgb, rec709, displayP3, rec2020, xyz, acesCG }
    enum TransferFunction { case srgb, bt1886, pq, hlg, gamma26, linear }
    enum HDRFormatType { case hdr10, hdr10Plus, dolbyVision, hlg }
    enum AudioCodec { case pcm, aac, ac3, eac3 }

    static func defaultConfig() -> ExportConfiguration {
        ExportConfiguration(
            videoCodec: .h264, container: .mp4,
            width: 1920, height: 1080, bitDepth: 8,
            colorSpace: .rec709, transferFunction: .srgb,
            audioBitDepth: 16, audioSampleRate: 48000,
            loudnessTarget: -14.0, truePeakMax: -1.0
        )
    }
}
```

---

## Key References

- Apple ProRes RAW White Paper (May 2023)
- WWDC20: Decode ProRes with AVFoundation and VideoToolbox
- WWDC20: Export HDR media in your app with AVFoundation
- Apple High Dynamic Range Metadata for Apple Devices v0.9
- SMPTE ST 2084:2014 (PQ EOTF)
- SMPTE ST 2086:2018 (Mastering Display Color Volume)
- SMPTE ST 2067-21 (IMF Application #2E)
- ITU-R BT.2100 (HDR TV)
- ITU-R BS.1770-5 (Loudness measurement)
- EBU R128 (Loudness normalization)
- ACES Documentation (acescentral.com)
- OpenTimelineIO (github.com/AcademySoftwareFoundation/OpenTimelineIO)
- Netflix Partner Help Center delivery specs
- Apple Video and Audio Asset Guide
- CMX3600 specification (SMPTE 258M-2004)
