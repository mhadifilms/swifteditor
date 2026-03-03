# Spatial Video, 360/VR, and Emerging Video Formats for Swift NLE

## 1. Apple Vision Pro Spatial Video (MV-HEVC)

### Overview

MV-HEVC (Multiview High Efficiency Video Coding) stores stereoscopic 3D video in a single track with multiple layers. The base layer is standard HEVC (backwards compatible with 2D players), and a delta layer encodes the difference between left and right views. Apple uses this for "Spatial Video" on Vision Pro, iPhone 15 Pro+, and iPhone 16.

**Key specs:**
- iPhone spatial video: 1920x1080 per eye, 30fps, SDR (~130 MB/min)
- Vision Pro capture: up to 1920x1080 per eye, 30fps, with depth
- Professional spatial: up to 4K per eye, HDR (HLG or HDR10)

### Reading Spatial Video

```swift
import AVFoundation

class SpatialVideoReader {
    /// Check if an asset contains MV-HEVC spatial video
    func isSpatialVideo(asset: AVURLAsset) async throws -> Bool {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        for desc in formatDescriptions {
            let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]
            // Check for multiview (MV-HEVC) tags
            if let heroEye = extensions["HasLeftStereoEyeView"] as? Bool, heroEye {
                return true
            }
            // Also check codec type for MV-HEVC
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            // kCMVideoCodecType_HEVCWithAlpha or multiview variant
            if extensions["HasStereoView"] != nil {
                return true
            }
        }

        // Check for tagged buffer support (macOS 14+, iOS 17+)
        let tagCollections = try await videoTrack.load(.tagCollections)
        for collection in tagCollections {
            if collection.contains(where: { $0.value == .stereoView(.leftEye) }) {
                return true
            }
        }

        return false
    }

    /// Read individual left/right eye frames from MV-HEVC
    func readStereoFrames(asset: AVURLAsset) async throws -> AsyncStream<StereoFrame> {
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!

        return AsyncStream { continuation in
            Task {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ])

                // Request multiview output
                output.alwaysCopiesSampleData = false
                reader.add(output)
                reader.startReading()

                while let sampleBuffer = output.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    // Extract tagged buffers for left/right
                    if let taggedBuffers = sampleBuffer.taggedBuffers {
                        var leftBuffer: CVPixelBuffer?
                        var rightBuffer: CVPixelBuffer?

                        for tagged in taggedBuffers {
                            if tagged.tags.contains(where: {
                                $0 == CMTag(.stereoView, value: .stereoView(.leftEye))
                            }) {
                                leftBuffer = tagged.pixelBuffer
                            }
                            if tagged.tags.contains(where: {
                                $0 == CMTag(.stereoView, value: .stereoView(.rightEye))
                            }) {
                                rightBuffer = tagged.pixelBuffer
                            }
                        }

                        if let left = leftBuffer, let right = rightBuffer {
                            continuation.yield(StereoFrame(
                                left: left, right: right,
                                presentationTime: pts
                            ))
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    struct StereoFrame {
        let left: CVPixelBuffer
        let right: CVPixelBuffer
        let presentationTime: CMTime
    }
}
```

### Creating MV-HEVC Spatial Video

```swift
import AVFoundation
import VideoToolbox

class SpatialVideoWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var taggedBufferAdaptor: AVAssetWriterInputTaggedPixelBufferGroupAdaptor?

    struct SpatialMetadata {
        let horizontalFieldOfView: Float  // degrees
        let baselineInMillimeters: Float  // inter-pupillary distance
        let horizontalDisparityAdjustment: Int32  // -10000 to 10000
    }

    /// Setup MV-HEVC writer for spatial video
    func setup(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Float,
        metadata: SpatialMetadata,
        isHDR: Bool = false
    ) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // MV-HEVC compression settings
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: 20_000_000,
            // MV-HEVC specific: define the two views
            kVTCompressionPropertyKey_MVHEVCVideoLayerIDs as String: [0, 1] as [Int],
            kVTCompressionPropertyKey_MVHEVCViewIDs as String: [0, 1] as [Int],
            kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs as String: [0, 1] as [Int],
            kVTCompressionPropertyKey_HasLeftStereoEyeView as String: true,
            kVTCompressionPropertyKey_HasRightStereoEyeView as String: true,
        ]

        // Horizontal field of view (in thousandths of a degree)
        let fovMicroDegrees = Int(metadata.horizontalFieldOfView * 1000)
        compressionProperties[kVTCompressionPropertyKey_HorizontalFieldOfView as String] = fovMicroDegrees

        // Stereo baseline
        let baselineMicrometers = Int(metadata.baselineInMillimeters * 1000)
        compressionProperties["StereoCameraBaseline"] = baselineMicrometers

        // Disparity adjustment
        compressionProperties[kVTCompressionPropertyKey_HorizontalDisparityAdjustment as String] =
            metadata.horizontalDisparityAdjustment

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        if isHDR {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        // Tagged buffer adaptor for stereo frames
        let adaptor = AVAssetWriterInputTaggedPixelBufferGroupAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        writer.add(input)
        self.assetWriter = writer
        self.videoInput = input
        self.taggedBufferAdaptor = adaptor
    }

    /// Write a stereo frame pair
    func writeStereoFrame(
        leftPixelBuffer: CVPixelBuffer,
        rightPixelBuffer: CVPixelBuffer,
        presentationTime: CMTime
    ) throws {
        guard let adaptor = taggedBufferAdaptor,
              adaptor.assetWriterInput.isReadyForMoreMediaData else {
            return
        }

        // Create tagged buffers for left and right eyes
        let leftTagged = CMTaggedBuffer(
            tags: [
                .stereoView(.leftEye),
                .videoLayerID(0)
            ],
            pixelBuffer: leftPixelBuffer
        )

        let rightTagged = CMTaggedBuffer(
            tags: [
                .stereoView(.rightEye),
                .videoLayerID(1)
            ],
            pixelBuffer: rightPixelBuffer
        )

        adaptor.appendTaggedBuffers(
            [leftTagged, rightTagged],
            withPresentationTime: presentationTime
        )
    }

    /// Convert side-by-side 3D to MV-HEVC
    func convertSideBySide(
        inputURL: URL,
        outputURL: URL,
        metadata: SpatialMetadata
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let naturalSize = try await videoTrack.load(.naturalSize)

        // Each eye is half the width for side-by-side
        let eyeWidth = Int(naturalSize.width) / 2
        let eyeHeight = Int(naturalSize.height)

        try setup(outputURL: outputURL, width: eyeWidth, height: eyeHeight,
                  frameRate: 30, metadata: metadata)

        guard let writer = assetWriter else { return }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while let sampleBuffer = output.copyNextSampleBuffer(),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Split side-by-side into left/right
            let (leftBuffer, rightBuffer) = try splitSideBySide(
                imageBuffer, eyeWidth: eyeWidth, eyeHeight: eyeHeight
            )

            try writeStereoFrame(
                leftPixelBuffer: leftBuffer,
                rightPixelBuffer: rightBuffer,
                presentationTime: pts
            )
        }

        videoInput?.markAsFinished()
        await writer.finishWriting()
    }

    /// Split a side-by-side frame into left and right pixel buffers
    private func splitSideBySide(
        _ source: CVPixelBuffer,
        eyeWidth: Int,
        eyeHeight: Int
    ) throws -> (CVPixelBuffer, CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let baseAddress = CVPixelBufferGetBaseAddress(source)!

        // Create left and right buffers
        var leftBuffer: CVPixelBuffer?
        var rightBuffer: CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault, eyeWidth, eyeHeight,
                          kCVPixelFormatType_32BGRA, nil, &leftBuffer)
        CVPixelBufferCreate(kCFAllocatorDefault, eyeWidth, eyeHeight,
                          kCVPixelFormatType_32BGRA, nil, &rightBuffer)

        guard let left = leftBuffer, let right = rightBuffer else {
            throw SpatialVideoError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(left, [])
        CVPixelBufferLockBaseAddress(right, [])

        let leftBase = CVPixelBufferGetBaseAddress(left)!
        let rightBase = CVPixelBufferGetBaseAddress(right)!
        let leftBytesPerRow = CVPixelBufferGetBytesPerRow(left)
        let rightBytesPerRow = CVPixelBufferGetBytesPerRow(right)

        // Copy left half and right half
        for y in 0..<eyeHeight {
            let srcRow = baseAddress + y * bytesPerRow
            memcpy(leftBase + y * leftBytesPerRow, srcRow, eyeWidth * 4)
            memcpy(rightBase + y * rightBytesPerRow, srcRow + eyeWidth * 4, eyeWidth * 4)
        }

        CVPixelBufferUnlockBaseAddress(left, [])
        CVPixelBufferUnlockBaseAddress(right, [])

        return (left, right)
    }
}

enum SpatialVideoError: Error {
    case bufferCreationFailed
    case noVideoTrack
}
```

### NLE Timeline Support for Spatial Video

```swift
/// Spatial video clip representation in timeline
struct SpatialVideoClip {
    let assetURL: URL
    let isSpatial: Bool
    let stereoLayout: StereoLayout
    let horizontalFOV: Float        // degrees
    let baseline: Float             // mm
    let convergenceDistance: Float   // meters

    enum StereoLayout {
        case mvHevc           // Native MV-HEVC (Apple Spatial)
        case sideBySide       // Left-right side by side
        case overUnder        // Top-bottom
        case frameSequential  // Alternating frames
    }

    /// Preview modes for spatial content in 2D editor
    enum PreviewMode {
        case leftEyeOnly     // Show left view
        case rightEyeOnly    // Show right view
        case anaglyph        // Red-cyan anaglyph
        case sideBySide      // Show both side by side
        case checkerboard    // Interlaced checkerboard
    }
}
```

---

## 2. 360/VR Video Editing

### Projection Types

| Projection | Description | File Storage |
|-----------|-------------|--------------|
| Equirectangular | Full sphere mapped to 2:1 rectangle | Standard, most common |
| Cubemap | Six faces of a cube | Compact, less distortion |
| Equi-Angular Cubemap (EAC) | YouTube's optimized cubemap | Better quality distribution |
| Rectilinear | Standard flat perspective | Used for "tiny planet" / reframing |

### Equirectangular Projection Math

```swift
import simd

/// 360 video projection utilities
struct SphericalProjection {
    /// Convert equirectangular UV to 3D direction vector
    /// u: 0..1 (longitude, 0=left, 1=right)
    /// v: 0..1 (latitude, 0=top, 1=bottom)
    static func equirectangularToDirection(u: Float, v: Float) -> SIMD3<Float> {
        let theta = u * 2.0 * .pi       // longitude: 0..2pi
        let phi = v * .pi               // latitude: 0..pi (top to bottom)

        return SIMD3<Float>(
            sin(phi) * sin(theta),       // x
            cos(phi),                     // y (up)
            sin(phi) * cos(theta)        // z
        )
    }

    /// Convert 3D direction to equirectangular UV
    static func directionToEquirectangular(_ dir: SIMD3<Float>) -> SIMD2<Float> {
        let d = normalize(dir)
        let u = atan2(d.x, d.z) / (2.0 * .pi) + 0.5
        let v = acos(clamp(d.y, min: -1.0, max: 1.0)) / .pi
        return SIMD2<Float>(u, v)
    }

    /// Convert cubemap face + UV to 3D direction
    static func cubemapToDirection(face: CubeFace, u: Float, v: Float) -> SIMD3<Float> {
        // Map 0..1 UV to -1..1
        let s = u * 2.0 - 1.0
        let t = v * 2.0 - 1.0

        switch face {
        case .positiveX: return normalize(SIMD3<Float>( 1,  t, -s))
        case .negativeX: return normalize(SIMD3<Float>(-1,  t,  s))
        case .positiveY: return normalize(SIMD3<Float>( s,  1, -t))
        case .negativeY: return normalize(SIMD3<Float>( s, -1,  t))
        case .positiveZ: return normalize(SIMD3<Float>( s,  t,  1))
        case .negativeZ: return normalize(SIMD3<Float>(-s,  t, -1))
        }
    }

    enum CubeFace: Int, CaseIterable {
        case positiveX = 0, negativeX, positiveY, negativeY, positiveZ, negativeZ
    }

    /// Extract a rectilinear (flat) viewport from equirectangular
    struct RectilinearViewport {
        var yaw: Float = 0      // horizontal rotation (radians)
        var pitch: Float = 0    // vertical rotation (radians)
        var roll: Float = 0     // roll (radians)
        var fov: Float = 90     // field of view (degrees)
        var outputWidth: Int = 1920
        var outputHeight: Int = 1080
    }
}
```

### Metal Shader: Equirectangular to Rectilinear Reframing

```metal
#include <metal_stdlib>
using namespace metal;

struct VRViewParams {
    float4x4 rotationMatrix; // yaw/pitch/roll camera rotation
    float fovRadians;        // vertical field of view
    float aspectRatio;       // width/height
};

/// Sample equirectangular texture from a flat (rectilinear) viewport
kernel void equirect_to_rectilinear(
    texture2d<float, access::sample> equirect  [[texture(0)]],
    texture2d<float, access::write>  output    [[texture(1)]],
    constant VRViewParams& params              [[buffer(0)]],
    uint2 gid                                  [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    constexpr sampler bilinear(filter::linear, address::repeat);

    float outW = float(output.get_width());
    float outH = float(output.get_height());

    // Normalized device coordinates (-1..1)
    float ndcX = (float(gid.x) + 0.5) / outW * 2.0 - 1.0;
    float ndcY = 1.0 - (float(gid.y) + 0.5) / outH * 2.0;

    // Ray direction in camera space
    float halfFov = tan(params.fovRadians * 0.5);
    float3 rayDir = normalize(float3(
        ndcX * halfFov * params.aspectRatio,
        ndcY * halfFov,
        1.0
    ));

    // Rotate ray to world space
    float3 worldDir = (params.rotationMatrix * float4(rayDir, 0.0)).xyz;
    worldDir = normalize(worldDir);

    // Convert direction to equirectangular UV
    float u = atan2(worldDir.x, worldDir.z) / (2.0 * M_PI_F) + 0.5;
    float v = acos(clamp(worldDir.y, -1.0f, 1.0f)) / M_PI_F;

    float4 color = equirect.sample(bilinear, float2(u, v));
    output.write(color, gid);
}

/// Convert equirectangular to cubemap face
kernel void equirect_to_cubemap(
    texture2d<float, access::sample>  equirect  [[texture(0)]],
    texture2d<float, access::write>   cubeFace  [[texture(1)]],
    constant int& faceIndex                     [[buffer(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= cubeFace.get_width() || gid.y >= cubeFace.get_height()) return;

    constexpr sampler bilinear(filter::linear, address::repeat);

    float faceSize = float(cubeFace.get_width());
    float s = (float(gid.x) + 0.5) / faceSize * 2.0 - 1.0;
    float t = 1.0 - (float(gid.y) + 0.5) / faceSize * 2.0;

    float3 dir;
    switch (faceIndex) {
        case 0: dir = normalize(float3( 1,  t, -s)); break; // +X
        case 1: dir = normalize(float3(-1,  t,  s)); break; // -X
        case 2: dir = normalize(float3( s,  1, -t)); break; // +Y
        case 3: dir = normalize(float3( s, -1,  t)); break; // -Y
        case 4: dir = normalize(float3( s,  t,  1)); break; // +Z
        case 5: dir = normalize(float3(-s,  t, -1)); break; // -Z
        default: dir = float3(0, 0, 1); break;
    }

    float u = atan2(dir.x, dir.z) / (2.0 * M_PI_F) + 0.5;
    float v = acos(clamp(dir.y, -1.0f, 1.0f)) / M_PI_F;

    float4 color = equirect.sample(bilinear, float2(u, v));
    cubeFace.write(color, gid);
}
```

### 360 Video Metadata

```swift
/// 360 video spherical metadata (per Google/YouTube specification)
struct SphericalMetadata {
    let isSpherical: Bool
    let stitchingSoftware: String?
    let projectionType: ProjectionType
    let stereoMode: StereoMode
    let sourceCount: Int?

    // Cropping (for partial 360)
    let croppedAreaLeft: Int?
    let croppedAreaTop: Int?
    let croppedAreaWidth: Int?
    let croppedAreaHeight: Int?
    let fullPanoWidth: Int?
    let fullPanoHeight: Int?

    // Initial viewing direction
    let initialViewHeading: Float?   // degrees
    let initialViewPitch: Float?
    let initialViewRoll: Float?

    enum ProjectionType: String {
        case equirectangular
        case cubemap
        case equiAngularCubemap = "equi-angular-cubemap"
        case mesh  // custom mesh projection
    }

    enum StereoMode: String {
        case mono
        case leftRight = "left-right"
        case topBottom = "top-bottom"
    }

    /// Extract spherical metadata from QuickTime/MP4 asset
    static func extract(from asset: AVURLAsset) async throws -> SphericalMetadata? {
        let metadata = try await asset.load(.metadata)
        var isSpherical = false
        var projection = ProjectionType.equirectangular

        for item in metadata {
            let key = try? await item.load(.key) as? String
            let identifier = item.identifier

            // Check for spherical video V2 (sv3d box)
            if identifier == AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.spherical-video") {
                isSpherical = true
            }

            // Google spherical metadata (XMP)
            if key == "SphericalVideo" || key == "GSpherical:Spherical" {
                isSpherical = true
            }

            if key == "GSpherical:ProjectionType" {
                if let value = try? await item.load(.stringValue) {
                    projection = ProjectionType(rawValue: value) ?? .equirectangular
                }
            }
        }

        guard isSpherical else { return nil }
        return SphericalMetadata(
            isSpherical: true, stitchingSoftware: nil,
            projectionType: projection, stereoMode: .mono,
            sourceCount: nil, croppedAreaLeft: nil, croppedAreaTop: nil,
            croppedAreaWidth: nil, croppedAreaHeight: nil,
            fullPanoWidth: nil, fullPanoHeight: nil,
            initialViewHeading: nil, initialViewPitch: nil, initialViewRoll: nil
        )
    }
}
```

---

## 3. Vertical/Social Video Auto-Reframing

### Architecture Overview

Auto-reframing uses a pipeline: **Detect subjects -> Track across frames -> Determine crop strategy -> Smooth camera motion -> Render output**.

### Subject Detection with Vision Framework

```swift
import Vision

/// AI-powered auto-reframing engine using Apple Vision framework
class AutoReframer {
    /// Target aspect ratio presets
    enum TargetAspect: String, CaseIterable {
        case portrait9x16 = "9:16"    // TikTok, Reels, Shorts
        case square1x1 = "1:1"        // Instagram feed
        case portrait4x5 = "4:5"      // Instagram portrait
        case landscape16x9 = "16:9"   // Standard widescreen
        case cinema21x9 = "21:9"      // Cinemascope

        var ratio: Float {
            switch self {
            case .portrait9x16: return 9.0 / 16.0
            case .square1x1:    return 1.0
            case .portrait4x5:  return 4.0 / 5.0
            case .landscape16x9: return 16.0 / 9.0
            case .cinema21x9:   return 21.0 / 9.0
            }
        }
    }

    /// Reframing strategy
    enum ReframingStrategy {
        case stationary     // Fixed crop position (no movement in scene)
        case tracking       // Follow moving subject
        case panning        // Smooth pan between interest points
    }

    struct DetectedSubject {
        let boundingBox: CGRect     // normalized 0..1
        let confidence: Float
        let type: SubjectType

        enum SubjectType {
            case face
            case person
            case salientObject
        }
    }

    struct ReframeKeyframe {
        let time: CMTime
        let cropRect: CGRect         // normalized crop in source
        let strategy: ReframingStrategy
    }

    /// Analyze video and generate reframing keyframes
    func analyze(
        asset: AVURLAsset,
        targetAspect: TargetAspect,
        sampleInterval: CMTime = CMTime(value: 1, timescale: 10)  // every 100ms
    ) async throws -> [ReframeKeyframe] {
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        reader.startReading()

        var allDetections: [(time: CMTime, subjects: [DetectedSubject])] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let subjects = try await detectSubjects(in: pixelBuffer)
            allDetections.append((time: pts, subjects: subjects))
        }

        // Generate keyframes from detections
        return generateKeyframes(
            detections: allDetections,
            sourceSize: naturalSize,
            targetAspect: targetAspect.ratio
        )
    }

    /// Detect subjects in a single frame using Vision
    private func detectSubjects(in pixelBuffer: CVPixelBuffer) async throws -> [DetectedSubject] {
        var subjects: [DetectedSubject] = []

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // 1. Face detection
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3

        // 2. Person detection (full body)
        let personRequest = VNDetectHumanRectanglesRequest()
        personRequest.upperBodyOnly = false

        // 3. Person segmentation for precise bounds
        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .fast

        // 4. Saliency (attention) detection for non-person content
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        try requestHandler.perform([faceRequest, personRequest, saliencyRequest])

        // Collect face detections
        if let faceResults = faceRequest.results {
            for face in faceResults {
                subjects.append(DetectedSubject(
                    boundingBox: face.boundingBox,
                    confidence: face.confidence,
                    type: .face
                ))
            }
        }

        // Collect person detections
        if let personResults = personRequest.results {
            for person in personResults {
                subjects.append(DetectedSubject(
                    boundingBox: person.boundingBox,
                    confidence: person.confidence,
                    type: .person
                ))
            }
        }

        // Collect saliency regions
        if let saliencyResults = saliencyRequest.results?.first {
            if let salientObjects = saliencyResults.salientObjects {
                for obj in salientObjects {
                    subjects.append(DetectedSubject(
                        boundingBox: obj.boundingBox,
                        confidence: obj.confidence,
                        type: .salientObject
                    ))
                }
            }
        }

        return subjects
    }

    /// Generate smoothed keyframes from detections
    private func generateKeyframes(
        detections: [(time: CMTime, subjects: [DetectedSubject])],
        sourceSize: CGSize,
        targetAspect: Float
    ) -> [ReframeKeyframe] {
        var keyframes: [ReframeKeyframe] = []

        let sourceAspect = Float(sourceSize.width / sourceSize.height)

        // Calculate crop dimensions
        let cropWidth: Float
        let cropHeight: Float
        if targetAspect < sourceAspect {
            // Target is taller (e.g., 9:16 from 16:9)
            cropHeight = 1.0
            cropWidth = targetAspect / sourceAspect
        } else {
            // Target is wider
            cropWidth = 1.0
            cropHeight = sourceAspect / targetAspect
        }

        for (time, subjects) in detections {
            // Priority: faces > persons > salient objects
            let prioritized = subjects.sorted { a, b in
                let priorityA = a.type == .face ? 3 : (a.type == .person ? 2 : 1)
                let priorityB = b.type == .face ? 3 : (b.type == .person ? 2 : 1)
                return priorityA > priorityB
            }

            // Center crop on primary subject
            var centerX: Float = 0.5
            var centerY: Float = 0.5

            if let primary = prioritized.first {
                centerX = Float(primary.boundingBox.midX)
                centerY = Float(primary.boundingBox.midY)
            }

            // Clamp so crop stays within frame
            let halfW = cropWidth / 2.0
            let halfH = cropHeight / 2.0
            centerX = max(halfW, min(1.0 - halfW, centerX))
            centerY = max(halfH, min(1.0 - halfH, centerY))

            let cropRect = CGRect(
                x: CGFloat(centerX - halfW),
                y: CGFloat(centerY - halfH),
                width: CGFloat(cropWidth),
                height: CGFloat(cropHeight)
            )

            let strategy: ReframingStrategy = subjects.isEmpty ? .stationary : .tracking
            keyframes.append(ReframeKeyframe(time: time, cropRect: cropRect, strategy: strategy))
        }

        // Smooth keyframes to avoid jitter
        return smoothKeyframes(keyframes)
    }

    /// Apply temporal smoothing to keyframes
    private func smoothKeyframes(_ keyframes: [ReframeKeyframe]) -> [ReframeKeyframe] {
        guard keyframes.count > 2 else { return keyframes }

        var smoothed = keyframes
        let windowSize = 5  // frames to average

        for i in 0..<keyframes.count {
            let start = max(0, i - windowSize / 2)
            let end = min(keyframes.count - 1, i + windowSize / 2)

            var avgX: CGFloat = 0
            var avgY: CGFloat = 0
            let count = CGFloat(end - start + 1)

            for j in start...end {
                avgX += keyframes[j].cropRect.origin.x
                avgY += keyframes[j].cropRect.origin.y
            }

            smoothed[i] = ReframeKeyframe(
                time: keyframes[i].time,
                cropRect: CGRect(
                    x: avgX / count,
                    y: avgY / count,
                    width: keyframes[i].cropRect.width,
                    height: keyframes[i].cropRect.height
                ),
                strategy: keyframes[i].strategy
            )
        }

        return smoothed
    }
}
```

---

## 4. High Frame Rate (120/240fps) and VFR Handling

### HFR Capture and Playback

```swift
import AVFoundation

/// High frame rate video handling
class HFRVideoHandler {

    /// Detect the actual frame rate of a video track
    func detectFrameRate(track: AVAssetTrack) async throws -> FrameRateInfo {
        let nominalRate = try await track.load(.nominalFrameRate)
        let minDuration = try await track.load(.minFrameDuration)
        let timeRange = try await track.load(.timeRange)

        // Check for variable frame rate by reading sample times
        let isVFR = try await detectVFR(track: track)

        let maxFPS: Float
        if minDuration.seconds > 0 {
            maxFPS = Float(1.0 / minDuration.seconds)
        } else {
            maxFPS = nominalRate
        }

        return FrameRateInfo(
            nominalFPS: nominalRate,
            maxFPS: maxFPS,
            isVariableFrameRate: isVFR,
            duration: timeRange.duration
        )
    }

    struct FrameRateInfo {
        let nominalFPS: Float
        let maxFPS: Float
        let isVariableFrameRate: Bool
        let duration: CMTime

        var isHighFrameRate: Bool { maxFPS > 60 }
        var isSlowMotion: Bool { maxFPS >= 120 }
    }

    /// Detect variable frame rate by analyzing sample timing
    private func detectVFR(track: AVAssetTrack) async throws -> Bool {
        let asset = track.asset!
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var lastPTS: CMTime?
        var durations: Set<Int64> = []
        var sampleCount = 0
        let maxSamples = 300  // Sample first 300 frames

        while let sample = output.copyNextSampleBuffer(), sampleCount < maxSamples {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if let last = lastPTS {
                let delta = CMTimeSubtract(pts, last)
                durations.insert(delta.value)
            }
            lastPTS = pts
            sampleCount += 1
        }

        reader.cancelReading()

        // VFR if more than 2 distinct frame durations exist
        return durations.count > 2
    }

    /// Conform VFR to constant frame rate
    func conformToConstantFrameRate(
        asset: AVURLAsset,
        targetFPS: Double,
        outputURL: URL
    ) async throws {
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let naturalSize = try await videoTrack.load(.naturalSize)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: nil
        )
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        var currentOutputTime = CMTime.zero
        var lastInputSample: CVPixelBuffer?
        var lastInputPTS = CMTime.zero

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            let inputPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            // Write frames at constant intervals
            while currentOutputTime <= inputPTS {
                if writerInput.isReadyForMoreMediaData {
                    // Use the closest available frame
                    let bufferToWrite = (abs(CMTimeGetSeconds(CMTimeSubtract(inputPTS, currentOutputTime)))
                        < abs(CMTimeGetSeconds(CMTimeSubtract(lastInputPTS, currentOutputTime))))
                        ? pixelBuffer : (lastInputSample ?? pixelBuffer)

                    adaptor.append(bufferToWrite, withPresentationTime: currentOutputTime)
                    currentOutputTime = CMTimeAdd(currentOutputTime, frameDuration)
                }
            }

            lastInputSample = pixelBuffer
            lastInputPTS = inputPTS
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
    }
}

/// Slow motion segment definition
struct SlowMotionSegment {
    let sourceTimeRange: CMTimeRange  // range in source at native fps
    let playbackRate: Float           // 0.25 = quarter speed, 1.0 = normal
    let targetFPS: Float              // output frame rate

    /// Calculate how to retime 240fps footage to 24fps at various speeds
    static func calculateRetime(sourceFPS: Float, targetFPS: Float) -> Float {
        return targetFPS / sourceFPS  // e.g., 24/240 = 0.1x = 10x slower
    }
}
```

### Timescale Handling for Different Frame Rates

```swift
/// Preferred timescales for different frame rates (avoiding floating-point drift)
struct FrameRateTimescales {
    static func preferredTimescale(for fps: Double) -> CMTimeScale {
        switch fps {
        case 23.976:  return 24000   // 1001/24000 per frame
        case 24.0:    return 24000
        case 25.0:    return 25000
        case 29.97:   return 30000   // 1001/30000 per frame
        case 30.0:    return 30000
        case 47.952:  return 48000
        case 48.0:    return 48000
        case 50.0:    return 50000
        case 59.94:   return 60000   // 1001/60000 per frame
        case 60.0:    return 60000
        case 119.88:  return 120000  // 1001/120000 per frame
        case 120.0:   return 120000
        case 239.76:  return 240000
        case 240.0:   return 240000
        default:      return 600     // General purpose
        }
    }

    /// Frame duration for NTSC rates (multiply by 1001 for actual duration)
    static func frameDuration(for fps: Double) -> CMTime {
        let timescale = preferredTimescale(for: fps)
        let isNTSC = [23.976, 29.97, 59.94, 119.88, 239.76].contains(fps)

        if isNTSC {
            return CMTime(value: 1001, timescale: timescale)
        } else {
            return CMTime(value: CMTimeValue(Double(timescale) / fps), timescale: timescale)
        }
    }
}
```

---

## 5. Volumetric Video (NeRF / Gaussian Splatting)

### Gaussian Splatting Overview

3D Gaussian Splatting represents scenes as collections of 3D Gaussian primitives, each with:
- Position (xyz)
- Covariance matrix (rotation + scale) defining shape
- Opacity (alpha)
- Color (spherical harmonics coefficients)

Real-time rendering at 60+ fps is possible by splatting Gaussians as 2D ellipses in screen space.

### PLY File Loading for Gaussian Splats

```swift
/// Load Gaussian Splat data from PLY file
struct GaussianSplat {
    var position: SIMD3<Float>     // xyz
    var scale: SIMD3<Float>        // sx, sy, sz (log scale)
    var rotation: simd_quatf       // quaternion
    var opacity: Float             // sigmoid-encoded
    var shCoefficients: [Float]    // spherical harmonics (DC + higher order)
}

class PLYSplatLoader {
    /// Parse a binary PLY file containing Gaussian splat data
    func load(url: URL) throws -> [GaussianSplat] {
        let data = try Data(contentsOf: url)
        var offset = 0

        // Parse ASCII header
        guard let headerEnd = findHeaderEnd(in: data) else {
            throw SplatError.invalidHeader
        }

        let headerString = String(data: data[0..<headerEnd], encoding: .ascii) ?? ""
        let header = parsePLYHeader(headerString)

        offset = headerEnd + "end_header\n".utf8.count

        var splats: [GaussianSplat] = []
        splats.reserveCapacity(header.vertexCount)

        for _ in 0..<header.vertexCount {
            // Read position (3 floats)
            let x = data.readFloat(at: offset); offset += 4
            let y = data.readFloat(at: offset); offset += 4
            let z = data.readFloat(at: offset); offset += 4

            // Read normals (skip 3 floats)
            offset += 12

            // Read spherical harmonics DC term (3 floats for RGB)
            let sh0 = data.readFloat(at: offset); offset += 4
            let sh1 = data.readFloat(at: offset); offset += 4
            let sh2 = data.readFloat(at: offset); offset += 4

            // Skip higher-order SH coefficients
            let shCount = (header.shDegree + 1) * (header.shDegree + 1) - 1
            let higherSH: [Float] = (0..<shCount * 3).map { _ in
                let v = data.readFloat(at: offset); offset += 4; return v
            }

            // Read opacity (1 float, sigmoid-encoded)
            let rawOpacity = data.readFloat(at: offset); offset += 4

            // Read scale (3 floats, log-encoded)
            let sx = data.readFloat(at: offset); offset += 4
            let sy = data.readFloat(at: offset); offset += 4
            let sz = data.readFloat(at: offset); offset += 4

            // Read rotation quaternion (4 floats: w, x, y, z)
            let rw = data.readFloat(at: offset); offset += 4
            let rx = data.readFloat(at: offset); offset += 4
            let ry = data.readFloat(at: offset); offset += 4
            let rz = data.readFloat(at: offset); offset += 4

            let splat = GaussianSplat(
                position: SIMD3<Float>(x, y, z),
                scale: SIMD3<Float>(sx, sy, sz),
                rotation: simd_quatf(ix: rx, iy: ry, iz: rz, r: rw),
                opacity: rawOpacity,
                shCoefficients: [sh0, sh1, sh2] + higherSH
            )
            splats.append(splat)
        }

        return splats
    }

    struct PLYHeader {
        var vertexCount: Int = 0
        var shDegree: Int = 0
    }

    private func parsePLYHeader(_ header: String) -> PLYHeader {
        var result = PLYHeader()
        for line in header.components(separatedBy: "\n") {
            if line.hasPrefix("element vertex") {
                result.vertexCount = Int(line.split(separator: " ").last ?? "0") ?? 0
            }
            // Count SH properties to determine degree
            if line.contains("f_rest_") {
                result.shDegree = max(result.shDegree, 3)  // typical SH degree 3
            }
        }
        return result
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let marker = "end_header\n".data(using: .ascii)!
        return data.range(of: marker)?.lowerBound
    }
}

extension Data {
    func readFloat(at offset: Int) -> Float {
        return self.withUnsafeBytes { raw in
            raw.load(fromByteOffset: offset, as: Float.self)
        }
    }
}

enum SplatError: Error {
    case invalidHeader
    case invalidData
}
```

### Metal Renderer for Gaussian Splatting

```metal
#include <metal_stdlib>
using namespace metal;

struct SplatVertex {
    packed_float3 position;
    packed_float3 scale;     // log scale
    packed_float4 rotation;  // quaternion wxyz
    float opacity;           // sigmoid raw
    packed_float3 shDC;      // spherical harmonics DC
};

struct SplatFragment {
    float4 position [[position]];
    float2 pointCoord;
    float4 color;
    float opacity;
};

/// Compute covariance in screen space for a single Gaussian
float3x3 computeCovariance3D(float3 scale, float4 quat) {
    // Build rotation matrix from quaternion
    float r = quat.x, x = quat.y, y = quat.z, z = quat.w;
    float3x3 R = float3x3(
        float3(1.0 - 2.0*(y*y + z*z), 2.0*(x*y - r*z), 2.0*(x*z + r*y)),
        float3(2.0*(x*y + r*z), 1.0 - 2.0*(x*x + z*z), 2.0*(y*z - r*x)),
        float3(2.0*(x*z - r*y), 2.0*(y*z + r*x), 1.0 - 2.0*(x*x + y*y))
    );

    // Scale matrix (exp of log-encoded scale)
    float3 s = exp(scale);
    float3x3 S = float3x3(float3(s.x,0,0), float3(0,s.y,0), float3(0,0,s.z));

    // Covariance = R * S * S^T * R^T
    float3x3 M = R * S;
    return M * transpose(M);
}

/// Project 3D covariance to 2D screen space
float2x2 projectCovariance(float3x3 cov3D, float4x4 viewMatrix, float3 position,
                           float focalX, float focalY) {
    float3 viewPos = (viewMatrix * float4(position, 1.0)).xyz;
    float z2 = viewPos.z * viewPos.z;

    // Jacobian of perspective projection
    float3x3 J = float3x3(
        float3(focalX / viewPos.z, 0, -focalX * viewPos.x / z2),
        float3(0, focalY / viewPos.z, -focalY * viewPos.y / z2),
        float3(0, 0, 0)
    );

    float3x3 viewRot = float3x3(viewMatrix[0].xyz, viewMatrix[1].xyz, viewMatrix[2].xyz);
    float3x3 T = J * viewRot;
    float3x3 projected = T * cov3D * transpose(T);

    return float2x2(
        float2(projected[0][0], projected[0][1]),
        float2(projected[1][0], projected[1][1])
    );
}

/// Evaluate 2D Gaussian at a point
float evaluateGaussian2D(float2 diff, float2x2 covariance) {
    float det = covariance[0][0] * covariance[1][1] - covariance[0][1] * covariance[1][0];
    if (det < 1e-6) return 0;

    float2x2 inv = float2x2(
        float2(covariance[1][1], -covariance[0][1]),
        float2(-covariance[1][0], covariance[0][0])
    ) / det;

    float mahal = dot(diff, inv * diff);
    return exp(-0.5 * mahal);
}

/// Color from spherical harmonics DC term
float3 sh2rgb(float3 shDC) {
    // SH DC coefficient to color: C = SH * 0.2820947917 + 0.5
    return shDC * 0.28209479177387814 + 0.5;
}

/// Sigmoid activation for opacity
float sigmoid(float x) {
    return 1.0 / (1.0 + exp(-x));
}
```

### Integration with NLE Timeline

```swift
/// Volumetric video clip in NLE timeline
struct VolumetricClip {
    let splatsURL: URL            // .ply or .splat file
    let format: VolumetricFormat
    let frameCount: Int?          // for dynamic sequences (4DGS)
    let fps: Float?

    enum VolumetricFormat {
        case gaussianSplat_PLY    // Static .ply from 3DGS
        case gaussianSplat_SPZ    // Compressed .spz (Khronos/OGC)
        case gaussianSplat_SPLAT  // .splat format
        case gaussianSplat_4D     // 4D Gaussian Splatting (dynamic)
        case nerf                 // NeRF (requires inference)
        case pointCloud           // LiDAR point cloud
    }

    /// Camera path for rendering volumetric content
    struct CameraPath {
        var keyframes: [CameraKeyframe]

        struct CameraKeyframe {
            let time: CMTime
            let position: SIMD3<Float>
            let lookAt: SIMD3<Float>
            let up: SIMD3<Float>
            let fov: Float
        }
    }

    /// Render a frame at given camera position
    func render(
        camera: CameraPath.CameraKeyframe,
        outputSize: (width: Int, height: Int),
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        // Gaussian splatting render pipeline would go here
        // Uses sort-by-depth -> tile-based rasterization -> alpha compositing
        return nil
    }
}
```

---

## 6. Screen Recording APIs

### ScreenCaptureKit (macOS 13+)

```swift
import ScreenCaptureKit
import AVFoundation

/// Screen recording engine using ScreenCaptureKit
class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false

    struct RecordingConfig {
        var captureType: CaptureType = .display
        var displayID: CGDirectDisplayID?
        var windowID: CGWindowID?
        var bundleID: String?     // for app capture
        var width: Int = 1920
        var height: Int = 1080
        var frameRate: Int = 60
        var showsCursor: Bool = true
        var capturesAudio: Bool = true
        var isHDR: Bool = false
        var pixelFormat: OSType = kCVPixelFormatType_32BGRA
        var presenterOverlay: Bool = false
        var excludeCurrentProcess: Bool = true

        enum CaptureType {
            case display
            case window
            case application
        }
    }

    /// Start recording with configuration
    func startRecording(config: RecordingConfig, outputURL: URL) async throws {
        // 1. Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        // 2. Create content filter
        let filter: SCContentFilter
        switch config.captureType {
        case .display:
            guard let display = availableContent.displays.first(where: {
                config.displayID == nil || $0.displayID == config.displayID!
            }) else { throw RecordingError.noDisplay }

            // Optionally exclude own app
            let excludedApps = config.excludeCurrentProcess
                ? availableContent.applications.filter {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                : []

            filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )

        case .window:
            guard let windowID = config.windowID,
                  let window = availableContent.windows.first(where: { $0.windowID == windowID })
            else { throw RecordingError.noWindow }
            filter = SCContentFilter(desktopIndependentWindow: window)

        case .application:
            guard let bundleID = config.bundleID,
                  let app = availableContent.applications.first(where: {
                      $0.bundleIdentifier == bundleID
                  }),
                  let display = availableContent.displays.first
            else { throw RecordingError.noApplication }
            filter = SCContentFilter(
                display: display,
                including: [app],
                exceptingWindows: []
            )
        }

        // 3. Configure stream
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.showsCursor = config.showsCursor
        streamConfig.capturesAudio = config.capturesAudio
        streamConfig.pixelFormat = config.pixelFormat

        // HDR capture (macOS 15+)
        if config.isHDR {
            streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            if #available(macOS 15.0, *) {
                streamConfig.captureDynamicRange = .hdrLocalDisplay
            }
        }

        // Presenter overlay (macOS 14+)
        if config.presenterOverlay {
            if #available(macOS 14.0, *) {
                streamConfig.presenterOverlayPrivacyAlertSetting = .always
            }
        }

        // Audio configuration
        if config.capturesAudio {
            streamConfig.sampleRate = 48000
            streamConfig.channelCount = 2
        }

        // 4. Setup AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.isHDR ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.width * config.height * config.frameRate / 4,
                AVVideoExpectedSourceFrameRateKey: config.frameRate
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        self.videoInput = vInput

        if config.capturesAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            self.audioInput = aInput
        }

        self.assetWriter = writer

        // 5. Create and start stream
        let captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        if config.capturesAudio {
            try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        }

        writer.startWriting()
        writer.startSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))

        try await captureStream.startCapture()
        self.stream = captureStream
        self.isRecording = true
    }

    /// Stop recording
    func stopRecording() async throws {
        guard isRecording else { return }
        isRecording = false

        try await stream?.stopCapture()
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard isRecording else { return }

        switch type {
        case .screen:
            guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }

            // Check for valid content (not idle/blank frames)
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete
            else { return }

            videoInput.append(sampleBuffer)

        case .audio:
            guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)

        case .microphone:
            break  // Handle microphone separately if needed

        @unknown default:
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRecording = false
    }
}

enum RecordingError: Error {
    case noDisplay
    case noWindow
    case noApplication
}
```

---

## 7. Live Streaming Output (RTMP/SRT)

### Protocol Comparison

| Feature | RTMP | SRT |
|---------|------|-----|
| Transport | TCP | UDP with ARQ |
| Latency | ~2-5s | <1s possible |
| Encryption | RTMPS (TLS) | AES-128/256 built-in |
| Codec | H.264 (H.265 limited) | Codec agnostic |
| NAT traversal | Poor | Rendezvous mode |
| Error recovery | TCP retransmit | Selective ARQ |
| Industry | YouTube/Twitch/Facebook | Broadcast, enterprise |

### RTMP Streaming Implementation

```swift
import AVFoundation
import VideoToolbox

/// Live streaming output manager
class LiveStreamOutput {
    enum StreamProtocol {
        case rtmp(url: String, streamKey: String)
        case srt(host: String, port: Int, streamID: String?, passphrase: String?, latency: Int)
    }

    struct StreamSettings {
        var videoWidth: Int = 1920
        var videoHeight: Int = 1080
        var videoBitrate: Int = 6_000_000   // 6 Mbps
        var videoFPS: Int = 30
        var videoCodec: VideoCodec = .h264
        var keyframeInterval: Int = 2       // seconds

        var audioSampleRate: Int = 48000
        var audioChannels: Int = 2
        var audioBitrate: Int = 192_000     // 192 kbps
        var audioCodec: AudioCodec = .aac

        enum VideoCodec { case h264, hevc }
        enum AudioCodec { case aac, opus }
    }

    private var videoEncoder: VideoEncoder?
    private var audioEncoder: AudioEncoder?

    /// Setup video encoding using VideoToolbox
    func setupVideoEncoder(settings: StreamSettings) throws {
        videoEncoder = try VideoEncoder(settings: settings)
    }

    /// Encode and send a video frame
    func sendVideoFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        videoEncoder?.encode(pixelBuffer: pixelBuffer, pts: presentationTime) { [weak self] data, isKeyframe in
            // Send encoded NAL units over RTMP/SRT
            self?.transmitVideoData(data, isKeyframe: isKeyframe, pts: presentationTime)
        }
    }

    private func transmitVideoData(_ data: Data, isKeyframe: Bool, pts: CMTime) {
        // Implementation depends on protocol (RTMP FLV wrapping or SRT raw)
    }
}

/// Hardware video encoder using VideoToolbox
class VideoEncoder {
    private var session: VTCompressionSession?
    private let outputCallback: (Data, Bool) -> Void = { _, _ in }
    private let settings: LiveStreamOutput.StreamSettings

    init(settings: LiveStreamOutput.StreamSettings) throws {
        self.settings = settings
        try createSession()
    }

    private func createSession() throws {
        let codecType: CMVideoCodecType = settings.videoCodec == .h264
            ? kCMVideoCodecType_H264
            : kCMVideoCodecType_HEVC

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(settings.videoWidth),
            height: Int32(settings.videoHeight),
            codecType: codecType,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
            ] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw EncoderError.sessionCreationFailed
        }

        // Configure encoder for live streaming
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                           value: settings.videoBitrate as CFNumber)

        // Data rate limits: [bytes per second, interval in seconds]
        let limits = [settings.videoBitrate * 5 / 4, 1] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                           value: settings.keyframeInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                           value: settings.videoFPS as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                           value: kCFBooleanFalse)  // No B-frames for low latency

        if settings.videoCodec == .h264 {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                               value: kVTProfileLevel_H264_Main_AutoLevel)
        }

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
    }

    func encode(
        pixelBuffer: CVPixelBuffer,
        pts: CMTime,
        completion: @escaping (Data, Bool) -> Void
    ) {
        guard let session = session else { return }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: CMTimeScale(settings.videoFPS)),
            frameProperties: nil,
            infoFlagsOut: nil
        ) { status, flags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else { return }

            let isKeyframe = !sampleBuffer.isNotSync
            guard let dataBuffer = sampleBuffer.dataBuffer else { return }

            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

            if let dataPointer = dataPointer {
                let data = Data(bytes: dataPointer, count: totalLength)
                completion(data, isKeyframe)
            }
        }
    }

    deinit {
        if let session = session {
            VTCompressionSessionInvalidate(session)
        }
    }
}

enum EncoderError: Error {
    case sessionCreationFailed
}

extension CMSampleBuffer {
    var isNotSync: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false)
                as? [[CFString: Any]],
              let first = attachments.first
        else { return false }
        return first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
    }
}
```

### HaishinKit Integration (Recommended Library)

```swift
/// Integration with HaishinKit for RTMP/SRT streaming
/// Package: https://github.com/HaishinKit/HaishinKit.swift
///
/// Example usage pattern:
///
/// import HaishinKit
///
/// // RTMP streaming
/// let rtmpConnection = RTMPConnection()
/// let rtmpStream = RTMPStream(connection: rtmpConnection)
///
/// // Configure video
/// rtmpStream.videoSettings.videoSize = .init(width: 1920, height: 1080)
/// rtmpStream.videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String
/// rtmpStream.videoSettings.bitRate = 6_000_000
/// rtmpStream.videoSettings.maxKeyFrameIntervalDuration = 2
/// rtmpStream.videoSettings.bitRateMode = .average
/// rtmpStream.videoSettings.isHardwareEncoderEnabled = true
///
/// // Configure audio
/// rtmpStream.audioSettings.bitRate = 192_000
///
/// // Connect and publish
/// rtmpConnection.connect("rtmp://live.twitch.tv/app")
/// rtmpStream.publish("your_stream_key")
///
/// // Feed frames from NLE timeline
/// rtmpStream.append(sampleBuffer)  // CMSampleBuffer from render output
///
/// // SRT streaming
/// let srtConnection = SRTConnection()
/// let srtStream = SRTStream(connection: srtConnection)
///
/// srtConnection.connect(URL(string: "srt://server:port?streamid=key")!)
/// srtStream.publish()
///
/// // ScreenCaptureKit integration (macOS)
/// // HaishinKit supports SCStream as input source for screen streaming

/// Stream output configuration for NLE export-to-stream
struct StreamOutputConfig {
    let `protocol`: LiveStreamOutput.StreamProtocol
    let settings: LiveStreamOutput.StreamSettings

    /// Presets for common streaming platforms
    static let twitch1080p = StreamOutputConfig(
        protocol: .rtmp(url: "rtmp://live.twitch.tv/app", streamKey: ""),
        settings: .init(
            videoWidth: 1920, videoHeight: 1080,
            videoBitrate: 6_000_000, videoFPS: 30,
            audioBitrate: 160_000
        )
    )

    static let youtube4K = StreamOutputConfig(
        protocol: .rtmp(url: "rtmp://a.rtmp.youtube.com/live2", streamKey: ""),
        settings: .init(
            videoWidth: 3840, videoHeight: 2160,
            videoBitrate: 20_000_000, videoFPS: 30,
            audioBitrate: 256_000
        )
    )

    static let srtBroadcast = StreamOutputConfig(
        protocol: .srt(host: "ingest.example.com", port: 9000,
                       streamID: nil, passphrase: nil, latency: 120),
        settings: .init(
            videoWidth: 1920, videoHeight: 1080,
            videoBitrate: 8_000_000, videoFPS: 30,
            videoCodec: .hevc,
            audioBitrate: 256_000
        )
    )
}
```

---

## Key References

- Apple Developer: Converting side-by-side 3D video to multiview HEVC and spatial video
- WWDC23: Deliver video content for spatial experiences
- WWDC22: Meet ScreenCaptureKit
- WWDC24: Capture HDR content with ScreenCaptureKit
- MetalSplatter: github.com/scier/MetalSplatter (Gaussian splatting on Metal)
- HaishinKit: github.com/HaishinKit/HaishinKit.swift (RTMP/SRT streaming)
- SpatialMediaKit: github.com/sturmen/SpatialMediaKit (MV-HEVC tools)
- Google AutoFlip: open-source auto-reframing via MediaPipe
- Finn Voorhees: Reading and Writing Spatial Video with AVFoundation
- Mike Swanson: Encoding Spatial Video blog series
- 3D Gaussian Splatting paper (Kerbl et al., SIGGRAPH 2023)
- Haivision SRT: github.com/Haivision/srt
- Bitmovin: How MV-HEVC makes spatial and multiview video more efficient
