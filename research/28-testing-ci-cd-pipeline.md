# Testing & CI/CD Strategies for a Professional Swift NLE

## Table of Contents
1. [Unit Testing Media Code](#1-unit-testing-media-code)
2. [Snapshot Testing](#2-snapshot-testing)
3. [Integration Testing](#3-integration-testing)
4. [Performance Testing](#4-performance-testing)
5. [UI Testing](#5-ui-testing)
6. [CI/CD Pipeline](#6-cicd-pipeline)
7. [Test Data Management](#7-test-data-management)
8. [Code Quality](#8-code-quality)
9. [Release Automation](#9-release-automation)
10. [Monitoring in Production](#10-monitoring-in-production)

---

## 1. Unit Testing Media Code

### Testing AVFoundation Compositions Without Real Media

AVFoundation classes like `AVComposition` and `AVMutableComposition` are concrete types that cannot be easily mocked. A layered approach provides the best balance of test speed and coverage.

#### Protocol-Based Abstraction

Wrap AVFoundation types behind protocols exposing only the methods you actually use:

```swift
import AVFoundation
import Testing

// Protocol wrapper for composition operations
protocol CompositionProviding {
    var duration: CMTime { get }
    var tracks: [AVCompositionTrack] { get }
    func tracks(withMediaType mediaType: AVMediaType) -> [AVCompositionTrack]
}

// Real implementation wrapping AVComposition
extension AVComposition: CompositionProviding {}

// Mock for unit tests
final class MockComposition: CompositionProviding {
    var duration: CMTime
    var tracks: [AVCompositionTrack] = []

    init(duration: CMTime = CMTime(seconds: 10, preferredTimescale: 600)) {
        self.duration = duration
    }

    func tracks(withMediaType mediaType: AVMediaType) -> [AVCompositionTrack] {
        tracks.filter { $0.mediaType == mediaType }
    }
}
```

#### Function Injection (Mock-Free Testing)

Instead of protocol wrappers, inject closures that encapsulate AVFoundation behavior:

```swift
struct TimelineRenderer {
    var compositionDuration: () -> CMTime
    var videoTracks: () -> [AVCompositionTrack]
    var renderFrame: (CMTime) -> CGImage?

    static func live(composition: AVComposition) -> Self {
        TimelineRenderer(
            compositionDuration: { composition.duration },
            videoTracks: { composition.tracks(withMediaType: .video) },
            renderFrame: { time in
                // Real rendering logic
                nil
            }
        )
    }

    static func mock(
        duration: CMTime = CMTime(seconds: 30, preferredTimescale: 600),
        trackCount: Int = 2
    ) -> Self {
        TimelineRenderer(
            compositionDuration: { duration },
            videoTracks: { [] },
            renderFrame: { _ in nil }
        )
    }
}
```

#### Using Real AVMutableComposition in Tests

`AVMutableComposition` can be instantiated without real media files for many test scenarios:

```swift
import Testing
import AVFoundation

@Suite("Timeline Composition Tests")
struct TimelineCompositionTests {

    @Test("Insert clip at time creates correct duration")
    func insertClipAtTime() throws {
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!

        // Insert empty time range to simulate clip placement
        track.insertEmptyTimeRange(CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        ))

        #expect(composition.duration.seconds == 5.0)
    }
}
```

### Testing Metal Shaders

Metal shaders require a GPU-to-CPU roundtrip approach: write a CPU reference implementation, dispatch the shader on the GPU, read back results, and compare.

#### CPU Reference Implementation Pattern

```swift
import Metal
import Testing

@Suite("Metal Shader Tests")
struct MetalShaderTests {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.noGPU
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.library = try device.makeDefaultLibrary(bundle: .main)
    }

    // CPU reference for a brightness/contrast shader
    func cpuBrightnessContrast(
        pixels: [SIMD4<Float>],
        brightness: Float,
        contrast: Float
    ) -> [SIMD4<Float>] {
        pixels.map { pixel in
            var result = pixel
            result.x = (pixel.x - 0.5) * contrast + 0.5 + brightness
            result.y = (pixel.y - 0.5) * contrast + 0.5 + brightness
            result.z = (pixel.z - 0.5) * contrast + 0.5 + brightness
            result.w = pixel.w // Alpha unchanged
            return simd_clamp(result, .zero, .one)
        }
    }

    @Test("Brightness/contrast shader matches CPU reference")
    func brightnessContrastShader() throws {
        let width = 64
        let height = 64
        let pixelCount = width * height

        // Generate test input
        var inputPixels = [SIMD4<Float>](repeating: .zero, count: pixelCount)
        for i in 0..<pixelCount {
            inputPixels[i] = SIMD4<Float>(
                Float(i % width) / Float(width),
                Float(i / width) / Float(height),
                0.5, 1.0
            )
        }

        let brightness: Float = 0.1
        let contrast: Float = 1.2

        // CPU reference
        let cpuResult = cpuBrightnessContrast(
            pixels: inputPixels,
            brightness: brightness,
            contrast: contrast
        )

        // GPU computation
        let inputBuffer = device.makeBuffer(
            bytes: inputPixels,
            length: MemoryLayout<SIMD4<Float>>.stride * pixelCount
        )!
        let outputBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD4<Float>>.stride * pixelCount
        )!

        let function = library.makeFunction(name: "brightnessContrast")!
        let pipeline = try device.makeComputePipelineState(function: function)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)

        var params = SIMD2<Float>(brightness, contrast)
        encoder.setBytes(&params, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Compare CPU vs GPU results
        let gpuResult = outputBuffer.contents()
            .bindMemory(to: SIMD4<Float>.self, capacity: pixelCount)

        let tolerance: Float = 1e-5
        for i in 0..<pixelCount {
            let cpu = cpuResult[i]
            let gpu = gpuResult[i]
            #expect(abs(cpu.x - gpu.x) < tolerance)
            #expect(abs(cpu.y - gpu.y) < tolerance)
            #expect(abs(cpu.z - gpu.z) < tolerance)
        }
    }
}

enum TestError: Error {
    case noGPU
}
```

#### Metal Shader Validation Layer

Enable the Metal validation layer and shader validation in your test scheme:

```xml
<!-- In your .xcscheme file, add to LaunchAction -->
<EnvironmentVariables>
    <EnvironmentVariable key="MTL_SHADER_VALIDATION" value="1" isEnabled="YES"/>
    <EnvironmentVariable key="MTL_DEBUG_LAYER" value="1" isEnabled="YES"/>
    <EnvironmentVariable key="METAL_DEVICE_WRAPPER_TYPE" value="1" isEnabled="YES"/>
</EnvironmentVariables>
```

### Testing Timeline Operations

```swift
import Testing

@Suite("Timeline Operations")
struct TimelineOperationTests {

    var timeline: Timeline!

    init() {
        timeline = Timeline()
        // Seed with three 10-second clips
        timeline.insertClip(Clip(id: "A", duration: 10.0), at: 0.0)
        timeline.insertClip(Clip(id: "B", duration: 10.0), at: 10.0)
        timeline.insertClip(Clip(id: "C", duration: 10.0), at: 20.0)
    }

    // MARK: - Insert

    @Test("Insert clip pushes subsequent clips forward")
    func insertPushesForward() {
        let newClip = Clip(id: "X", duration: 5.0)
        timeline.insertClip(newClip, at: 10.0, mode: .insert)

        #expect(timeline.totalDuration == 35.0)
        #expect(timeline.clipAt(time: 10.0)?.id == "X")
        #expect(timeline.clipAt(time: 15.0)?.id == "B")
        #expect(timeline.clipAt(time: 25.0)?.id == "C")
    }

    @Test("Insert clip with overwrite replaces content")
    func insertOverwrite() {
        let newClip = Clip(id: "X", duration: 5.0)
        timeline.insertClip(newClip, at: 10.0, mode: .overwrite)

        #expect(timeline.totalDuration == 30.0)
        #expect(timeline.clipAt(time: 10.0)?.id == "X")
        #expect(timeline.clipAt(time: 15.0)?.id == "B") // Remaining portion of B
    }

    // MARK: - Delete

    @Test("Delete clip closes gap with ripple")
    func deleteRipple() {
        timeline.deleteClip(id: "B", mode: .ripple)

        #expect(timeline.totalDuration == 20.0)
        #expect(timeline.clipAt(time: 10.0)?.id == "C")
    }

    @Test("Delete clip leaves gap with lift")
    func deleteLift() {
        timeline.deleteClip(id: "B", mode: .lift)

        #expect(timeline.totalDuration == 30.0)
        #expect(timeline.clipAt(time: 10.0) == nil) // Gap
        #expect(timeline.clipAt(time: 20.0)?.id == "C")
    }

    // MARK: - Trim

    @Test("Trim clip head adjusts in-point")
    func trimHead() {
        timeline.trimClip(id: "B", head: 3.0) // Remove first 3 seconds

        #expect(timeline.clip(id: "B")?.duration == 7.0)
        #expect(timeline.totalDuration == 27.0) // Ripple trim
    }

    @Test("Trim clip tail adjusts out-point")
    func trimTail() {
        timeline.trimClip(id: "B", tail: 4.0) // Remove last 4 seconds

        #expect(timeline.clip(id: "B")?.duration == 6.0)
    }

    // MARK: - Move

    @Test("Move clip reorders timeline")
    func moveClip() {
        timeline.moveClip(id: "C", to: 0.0)

        #expect(timeline.clips.map(\.id) == ["C", "A", "B"])
    }

    // MARK: - Parameterized Tests

    @Test("Trim preserves minimum duration", arguments: [0.1, 0.5, 1.0, 5.0, 9.9])
    func trimPreservesMinimum(trimAmount: Double) {
        timeline.trimClip(id: "B", head: trimAmount)
        #expect(timeline.clip(id: "B")!.duration > 0)
    }
}
```

### Testing Undo/Redo Chains

```swift
@Suite("Undo/Redo Operations")
struct UndoRedoTests {

    @Test("Undo reverts insert operation")
    func undoInsert() {
        let timeline = Timeline()
        let undoManager = UndoManager()
        timeline.undoManager = undoManager

        let clip = Clip(id: "A", duration: 10.0)
        timeline.insertClip(clip, at: 0.0)
        #expect(timeline.clips.count == 1)

        undoManager.undo()
        #expect(timeline.clips.count == 0)

        undoManager.redo()
        #expect(timeline.clips.count == 1)
        #expect(timeline.clips.first?.id == "A")
    }

    @Test("Multiple undo/redo maintains consistency")
    func multipleUndoRedo() {
        let timeline = Timeline()
        let undoManager = UndoManager()
        timeline.undoManager = undoManager

        // Perform a series of operations
        timeline.insertClip(Clip(id: "A", duration: 10.0), at: 0.0)
        timeline.insertClip(Clip(id: "B", duration: 5.0), at: 10.0)
        timeline.deleteClip(id: "A", mode: .ripple)

        #expect(timeline.clips.map(\.id) == ["B"])

        // Undo delete
        undoManager.undo()
        #expect(timeline.clips.map(\.id) == ["A", "B"])

        // Undo second insert
        undoManager.undo()
        #expect(timeline.clips.map(\.id) == ["A"])

        // Redo second insert
        undoManager.redo()
        #expect(timeline.clips.map(\.id) == ["A", "B"])
    }

    @Test("Undo group coalesces related operations")
    func undoGrouping() {
        let timeline = Timeline()
        let undoManager = UndoManager()
        timeline.undoManager = undoManager

        // Group: split a clip into two parts
        undoManager.beginUndoGrouping()
        timeline.splitClip(id: "A", at: 5.0) // Creates A1 and A2
        undoManager.endUndoGrouping()

        #expect(timeline.clips.count == 2)

        // Single undo reverts the entire split
        undoManager.undo()
        #expect(timeline.clips.count == 1)
        #expect(timeline.clips.first?.id == "A")
    }
}
```

---

## 2. Snapshot Testing

### swift-snapshot-testing Library

Point-Free's [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) is the leading snapshot testing library for Swift. Unlike most libraries limited to `UIImage`, it can work with any format of any value on any Swift platform.

#### Setup

```swift
// Package.swift dependency
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),

// Test target
.testTarget(
    name: "EditorTests",
    dependencies: [
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ]
)
```

#### Recording and Comparing Timeline Views

```swift
import XCTest
import SnapshotTesting
@testable import SwiftEditor

final class TimelineViewSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Set to true to record new reference snapshots
        // isRecording = true
    }

    func testTimelineViewEmptyState() {
        let view = TimelineView(timeline: Timeline())

        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 1200, height: 200))
        )
    }

    func testTimelineViewWithMultipleClips() {
        let timeline = Timeline()
        timeline.insertClip(Clip(id: "A", duration: 5.0, color: .blue), at: 0.0)
        timeline.insertClip(Clip(id: "B", duration: 10.0, color: .green), at: 5.0)
        timeline.insertClip(Clip(id: "C", duration: 3.0, color: .red), at: 15.0)

        let view = TimelineView(timeline: timeline)

        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 1200, height: 200))
        )
    }

    func testTimelineViewWithTransitions() {
        let timeline = makeTimelineWithTransitions()
        let view = TimelineView(timeline: timeline)

        assertSnapshot(
            of: view,
            as: .image(size: CGSize(width: 1200, height: 200))
        )
    }

    func testTimelineViewAtZoomLevels() {
        let timeline = makeSampleTimeline()

        for zoom in [0.25, 0.5, 1.0, 2.0, 4.0] {
            let view = TimelineView(timeline: timeline, zoomLevel: zoom)
            assertSnapshot(
                of: view,
                as: .image(size: CGSize(width: 1200, height: 200)),
                named: "zoom-\(zoom)"
            )
        }
    }

    // Snapshot the view hierarchy as text (useful for debugging)
    func testTimelineViewHierarchy() {
        let view = TimelineView(timeline: makeSampleTimeline())
        assertSnapshot(of: view, as: .recursiveDescription)
    }
}
```

#### Viewer Screenshots with Trait Overrides

```swift
final class ViewerSnapshotTests: XCTestCase {

    func testViewerWithVideoFrame() {
        let viewer = ViewerView(
            frame: TestAssets.sampleFrame,
            overlayInfo: ViewerOverlay(timecode: "01:00:05:12", safeAreas: true)
        )

        assertSnapshot(
            of: viewer,
            as: .image(size: CGSize(width: 1920, height: 1080))
        )
    }

    func testViewerDarkMode() {
        let viewer = ViewerView(frame: TestAssets.sampleFrame)

        assertSnapshot(
            of: viewer,
            as: .image(
                size: CGSize(width: 1920, height: 1080),
                traits: NSAppearance(named: .darkAqua)!
            )
        )
    }

    // SwiftUI snapshot testing
    func testInspectorPanelSnapshot() {
        let panel = InspectorPanel(
            selectedClip: Clip(
                id: "test",
                duration: 10.0,
                effects: [.colorCorrection(brightness: 0.1, contrast: 1.2)]
            )
        )

        let hostingView = NSHostingView(rootView: panel)
        hostingView.frame = CGRect(x: 0, y: 0, width: 300, height: 600)

        assertSnapshot(of: hostingView, as: .image)
    }
}
```

#### Useful Extensions for NLE

```swift
import SnapshotTesting

// HEIC format for smaller snapshot files
// Requires: .package(url: "https://github.com/nicklockwood/SnapshotTestingHEIC")
extension Snapshotting where Value: NSView, Format == Data {
    static var heic: Snapshotting {
        .image.pullback { view in
            // Convert to HEIC for smaller file sizes
            view
        }
    }
}

// Custom snapshot strategy for waveform views
extension Snapshotting where Value == AudioWaveformView, Format == NSImage {
    static var waveform: Snapshotting<AudioWaveformView, NSImage> {
        .image(size: CGSize(width: 800, height: 100))
    }
}
```

---

## 3. Integration Testing

### End-to-End Render Tests

Compose a timeline, render it, and verify the output matches expected results.

```swift
import XCTest
import AVFoundation
@testable import SwiftEditor

final class RenderIntegrationTests: XCTestCase {

    let testOutputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("render_test_output.mov")

    override func tearDown() {
        try? FileManager.default.removeItem(at: testOutputURL)
        super.tearDown()
    }

    func testComposeRenderVerify() async throws {
        // 1. Compose
        let timeline = Timeline()
        timeline.insertClip(
            Clip(asset: TestAssets.colorBars5sec, duration: 5.0),
            at: 0.0
        )
        timeline.insertClip(
            Clip(asset: TestAssets.blackSlug2sec, duration: 2.0),
            at: 5.0
        )

        let composition = try timeline.buildAVComposition()

        // 2. Render
        let exporter = try RenderExporter(
            composition: composition,
            outputURL: testOutputURL,
            preset: .hevc1920x1080
        )
        try await exporter.export()

        // 3. Verify output exists and has correct duration
        let outputAsset = AVURLAsset(url: testOutputURL)
        let duration = try await outputAsset.load(.duration)
        XCTAssertEqual(duration.seconds, 7.0, accuracy: 0.1)

        // Verify video track properties
        let videoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)

        let naturalSize = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(naturalSize.width, 1920)
        XCTAssertEqual(naturalSize.height, 1080)
    }
}
```

### Frame-by-Frame Pixel Comparison with AVAssetReader

```swift
final class FrameComparisonTests: XCTestCase {

    /// Extract all frames from a video asset as CVPixelBuffers
    func extractFrames(from url: URL) throws -> [CVPixelBuffer] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)

        let videoTrack = asset.tracks(withMediaType: .video).first!
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: outputSettings
        )
        reader.add(trackOutput)
        reader.startReading()

        var frames: [CVPixelBuffer] = []
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                // Deep copy the pixel buffer since the sample buffer will be reused
                var copy: CVPixelBuffer?
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    CVPixelBufferGetWidth(pixelBuffer),
                    CVPixelBufferGetHeight(pixelBuffer),
                    CVPixelBufferGetPixelFormatType(pixelBuffer),
                    nil,
                    &copy
                )
                if let copy {
                    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                    CVPixelBufferLockBaseAddress(copy, [])
                    memcpy(
                        CVPixelBufferGetBaseAddress(copy),
                        CVPixelBufferGetBaseAddress(pixelBuffer),
                        CVPixelBufferGetDataSize(pixelBuffer)
                    )
                    CVPixelBufferUnlockBaseAddress(copy, [])
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    frames.append(copy)
                }
            }
        }
        return frames
    }
}
```

### PSNR/SSIM for Visual Quality Metrics

Implement PSNR and SSIM in Swift using the Accelerate framework for fast computation:

```swift
import Accelerate

struct VideoQualityMetrics {

    /// Peak Signal-to-Noise Ratio (higher is better, typically 30-50 dB)
    static func psnr(
        reference: CVPixelBuffer,
        distorted: CVPixelBuffer
    ) -> Double {
        CVPixelBufferLockBaseAddress(reference, .readOnly)
        CVPixelBufferLockBaseAddress(distorted, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(reference, .readOnly)
            CVPixelBufferUnlockBaseAddress(distorted, .readOnly)
        }

        let width = CVPixelBufferGetWidth(reference)
        let height = CVPixelBufferGetHeight(reference)
        let refPtr = CVPixelBufferGetBaseAddress(reference)!
            .assumingMemoryBound(to: UInt8.self)
        let distPtr = CVPixelBufferGetBaseAddress(distorted)!
            .assumingMemoryBound(to: UInt8.self)

        let pixelCount = width * height * 4 // BGRA
        var mse: Double = 0

        // Use vDSP for fast computation
        var refFloat = [Float](repeating: 0, count: pixelCount)
        var distFloat = [Float](repeating: 0, count: pixelCount)

        vDSP_vfltu8(refPtr, 1, &refFloat, 1, vDSP_Length(pixelCount))
        vDSP_vfltu8(distPtr, 1, &distFloat, 1, vDSP_Length(pixelCount))

        var diff = [Float](repeating: 0, count: pixelCount)
        vDSP_vsub(distFloat, 1, refFloat, 1, &diff, 1, vDSP_Length(pixelCount))

        var squaredSum: Float = 0
        vDSP_dotpr(diff, 1, diff, 1, &squaredSum, vDSP_Length(pixelCount))

        mse = Double(squaredSum) / Double(pixelCount)

        guard mse > 0 else { return Double.infinity } // Identical frames
        return 10.0 * log10(255.0 * 255.0 / mse)
    }

    /// Structural Similarity Index (0 to 1, higher is better)
    static func ssim(
        reference: CVPixelBuffer,
        distorted: CVPixelBuffer,
        windowSize: Int = 8
    ) -> Double {
        CVPixelBufferLockBaseAddress(reference, .readOnly)
        CVPixelBufferLockBaseAddress(distorted, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(reference, .readOnly)
            CVPixelBufferUnlockBaseAddress(distorted, .readOnly)
        }

        let width = CVPixelBufferGetWidth(reference)
        let height = CVPixelBufferGetHeight(reference)

        // SSIM constants
        let c1: Double = (0.01 * 255) * (0.01 * 255) // (K1 * L)^2
        let c2: Double = (0.03 * 255) * (0.03 * 255) // (K2 * L)^2

        // Compute SSIM over sliding windows (simplified single-channel luminance)
        var ssimSum: Double = 0
        var windowCount: Int = 0

        let refPtr = CVPixelBufferGetBaseAddress(reference)!
            .assumingMemoryBound(to: UInt8.self)
        let distPtr = CVPixelBufferGetBaseAddress(distorted)!
            .assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(reference)

        for y in stride(from: 0, to: height - windowSize, by: windowSize) {
            for x in stride(from: 0, to: width - windowSize, by: windowSize) {
                var muX: Double = 0, muY: Double = 0
                var sigmaX2: Double = 0, sigmaY2: Double = 0, sigmaXY: Double = 0
                let n = Double(windowSize * windowSize)

                for wy in 0..<windowSize {
                    for wx in 0..<windowSize {
                        let offset = (y + wy) * bytesPerRow + (x + wx) * 4
                        // Use green channel as luminance approximation
                        let refVal = Double(refPtr[offset + 1])
                        let distVal = Double(distPtr[offset + 1])
                        muX += refVal
                        muY += distVal
                    }
                }
                muX /= n
                muY /= n

                for wy in 0..<windowSize {
                    for wx in 0..<windowSize {
                        let offset = (y + wy) * bytesPerRow + (x + wx) * 4
                        let refVal = Double(refPtr[offset + 1])
                        let distVal = Double(distPtr[offset + 1])
                        sigmaX2 += (refVal - muX) * (refVal - muX)
                        sigmaY2 += (distVal - muY) * (distVal - muY)
                        sigmaXY += (refVal - muX) * (distVal - muY)
                    }
                }
                sigmaX2 /= (n - 1)
                sigmaY2 /= (n - 1)
                sigmaXY /= (n - 1)

                let numerator = (2 * muX * muY + c1) * (2 * sigmaXY + c2)
                let denominator = (muX * muX + muY * muY + c1) * (sigmaX2 + sigmaY2 + c2)
                ssimSum += numerator / denominator
                windowCount += 1
            }
        }

        return ssimSum / Double(windowCount)
    }
}

// Usage in tests
final class RenderQualityTests: XCTestCase {

    func testRenderQualityMeetsThreshold() throws {
        let referenceFrames = try extractFrames(from: TestAssets.referenceRender)
        let testFrames = try extractFrames(from: testOutputURL)

        XCTAssertEqual(referenceFrames.count, testFrames.count, "Frame count mismatch")

        for (index, (ref, test)) in zip(referenceFrames, testFrames).enumerated() {
            let psnr = VideoQualityMetrics.psnr(reference: ref, distorted: test)
            let ssim = VideoQualityMetrics.ssim(reference: ref, distorted: test)

            XCTAssertGreaterThan(psnr, 35.0, "PSNR below threshold at frame \(index)")
            XCTAssertGreaterThan(ssim, 0.95, "SSIM below threshold at frame \(index)")
        }
    }
}
```

### Audio Comparison Tests

```swift
import AVFoundation
import Accelerate

struct AudioComparisonMetrics {

    /// Extract audio samples as Float32 array
    static func extractSamples(from url: URL) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let audioTrack = asset.tracks(withMediaType: .audio).first!

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(trackOutput)
        reader.startReading()

        var samples: [Float] = []
        while let buffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                            totalLengthOut: &length, dataPointerOut: &dataPointer)
                if let dataPointer {
                    let floatCount = length / MemoryLayout<Float>.size
                    let floatPtr = UnsafeRawPointer(dataPointer)
                        .bindMemory(to: Float.self, capacity: floatCount)
                    samples.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: floatCount))
                }
            }
        }
        return samples
    }

    /// Signal-to-Noise Ratio for audio comparison
    static func snr(reference: [Float], test: [Float]) -> Float {
        let count = min(reference.count, test.count)

        var signalPower: Float = 0
        vDSP_measqv(reference, 1, &signalPower, vDSP_Length(count))

        var diff = [Float](repeating: 0, count: count)
        vDSP_vsub(test, 1, reference, 1, &diff, 1, vDSP_Length(count))

        var noisePower: Float = 0
        vDSP_measqv(diff, 1, &noisePower, vDSP_Length(count))

        guard noisePower > 0 else { return Float.infinity }
        return 10 * log10(signalPower / noisePower)
    }
}
```

---

## 4. Performance Testing

### XCTest Measure Blocks with XCTMetric

XCTest provides five built-in metric types: `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTOSSignpostMetric`, and `XCTStorageMetric`.

```swift
import XCTest
@testable import SwiftEditor

final class PerformanceTests: XCTestCase {

    // MARK: - Combined Metrics

    func testCompositionBuildPerformance() {
        let timeline = makeLargeTimeline(clipCount: 100)

        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: metrics, options: options) {
            _ = try? timeline.buildAVComposition()
        }
    }

    // MARK: - Clock Metric (Elapsed Time)

    func testExportPerformance() {
        let composition = makeTestComposition(duration: 30.0)

        measure(metrics: [XCTClockMetric()]) {
            let expectation = expectation(description: "Export complete")

            Task {
                let exporter = try! RenderExporter(
                    composition: composition,
                    outputURL: tempURL(),
                    preset: .hevc1920x1080
                )
                try! await exporter.export()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 120)
        }
    }

    // MARK: - CPU Metric

    func testEffectProcessingCPU() {
        let frame = TestAssets.sample4KFrame
        let effectChain = EffectChain([
            .colorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.1),
            .sharpen(amount: 0.5),
            .vignette(intensity: 0.3)
        ])

        measure(metrics: [XCTCPUMetric()]) {
            for _ in 0..<100 {
                _ = effectChain.apply(to: frame)
            }
        }
    }

    // MARK: - Memory Metric

    func testTimelineMemoryUsage() {
        measure(metrics: [XCTMemoryMetric()]) {
            let timeline = Timeline()
            for i in 0..<1000 {
                timeline.insertClip(
                    Clip(id: "clip-\(i)", duration: Double.random(in: 1...30)),
                    at: timeline.totalDuration
                )
            }
            // Force processing
            _ = timeline.buildAVComposition()
        }
    }

    // MARK: - Setting Baselines

    func testThumbnailGenerationBaseline() {
        // After first run, set baselines in Xcode:
        // Click the diamond icon next to the test → Set Baseline
        // Xcode will fail the test if performance regresses > 10% by default

        let asset = TestAssets.sampleVideo

        measure {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)

            for i in 0..<30 {
                let time = CMTime(seconds: Double(i), preferredTimescale: 600)
                _ = try? generator.copyCGImage(at: time, actualTime: nil)
            }
        }
    }
}
```

### Custom XCTOSSignpostMetric for Render Timing

Instrument your rendering code with `os_signpost` and measure it in performance tests:

```swift
import os.signpost

// In your app code: instrument the render pipeline
extension RenderEngine {
    static let signpostLog = OSLog(
        subsystem: "com.swifteditor.render",
        category: "RenderPipeline"
    )

    static let signposter = OSSignposter(logHandle: signpostLog)

    func renderFrame(at time: CMTime) -> CVPixelBuffer? {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("RenderFrame", id: signpostID)
        defer { Self.signposter.endInterval("RenderFrame", state) }

        // Actual render logic
        return performRender(at: time)
    }

    func exportTimeline() async throws {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("ExportTimeline", id: signpostID)
        defer { Self.signposter.endInterval("ExportTimeline", state) }

        // Export logic
        try await performExport()
    }
}

// In your tests: measure signposted regions
final class RenderPerformanceTests: XCTestCase {

    func testRenderFramePerformance() {
        let renderMetric = XCTOSSignpostMetric(
            subsystem: "com.swifteditor.render",
            category: "RenderPipeline",
            name: "RenderFrame"
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [renderMetric, XCTClockMetric()], options: options) {
            let engine = RenderEngine(composition: makeTestComposition())
            for i in 0..<60 {
                _ = engine.renderFrame(at: CMTime(value: CMTimeValue(i), timescale: 30))
            }
        }
    }

    func testExportPerformance() {
        let exportMetric = XCTOSSignpostMetric(
            subsystem: "com.swifteditor.render",
            category: "RenderPipeline",
            name: "ExportTimeline"
        )

        measure(metrics: [exportMetric, XCTMemoryMetric()]) {
            let expectation = expectation(description: "Export")
            Task {
                let engine = RenderEngine(composition: makeTestComposition(duration: 10))
                try await engine.exportTimeline()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }
    }
}
```

### MetricKit Signpost Integration

Bridge signpost intervals into MetricKit payloads for production monitoring:

```swift
import MetricKit

// Use mxSignpost for production-grade metrics collection
extension RenderEngine {

    func renderFrameWithMetrics(at time: CMTime) -> CVPixelBuffer? {
        mxSignpost(.begin, log: Self.signpostLog, name: "RenderFrame")
        defer { mxSignpost(.end, log: Self.signpostLog, name: "RenderFrame") }

        return performRender(at: time)
    }
}
```

---

## 5. UI Testing

### XCUITest for NLE Workflows

```swift
import XCTest

final class NLEWorkflowUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Import → Edit → Export Workflow

    func testImportEditExportWorkflow() throws {
        // 1. Import media
        app.menuItems["File"].tap()
        app.menuItems["Import Media..."].tap()

        // Navigate to test media (pre-configured via launch argument)
        let openDialog = app.dialogs.firstMatch
        XCTAssertTrue(openDialog.waitForExistence(timeout: 5))

        // Type the path to test media
        openDialog.typeText(TestPaths.sampleMedia + "\n")

        // Verify media appears in browser
        let mediaBrowser = app.outlines["MediaBrowser"]
        XCTAssertTrue(mediaBrowser.cells.count > 0)

        // 2. Edit: Drag clip to timeline
        let firstClip = mediaBrowser.cells.firstMatch
        let timeline = app.groups["TimelineView"]
        firstClip.press(forDuration: 0.5, thenDragTo: timeline)

        // Verify clip appears in timeline
        let timelineClips = timeline.groups.matching(identifier: "TimelineClip")
        XCTAssertEqual(timelineClips.count, 1)

        // 3. Export
        app.menuItems["File"].tap()
        app.menuItems["Export..."].tap()

        let exportDialog = app.sheets.firstMatch
        XCTAssertTrue(exportDialog.waitForExistence(timeout: 5))

        exportDialog.buttons["Export"].tap()

        // Wait for export to complete
        let progressIndicator = app.progressIndicators.firstMatch
        let exported = NSPredicate(format: "exists == false")
        expectation(for: exported, evaluatedWith: progressIndicator)
        waitForExpectations(timeout: 120)
    }

    // MARK: - Keyboard Shortcuts

    func testKeyboardShortcuts() {
        // Load a project with clips
        loadTestProject()

        // Space: Play/Pause
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.buttons["PauseButton"].waitForExistence(timeout: 2))

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.buttons["PlayButton"].waitForExistence(timeout: 2))

        // J/K/L: Shuttle controls
        app.typeKey("l", modifierFlags: []) // Forward play
        app.typeKey("l", modifierFlags: []) // 2x forward
        app.typeKey("k", modifierFlags: []) // Stop
        app.typeKey("j", modifierFlags: []) // Reverse play
        app.typeKey("k", modifierFlags: []) // Stop

        // I/O: Set in/out points
        app.typeKey("i", modifierFlags: [])
        let inPoint = app.staticTexts["InPointTimecode"].label
        XCTAssertFalse(inPoint.isEmpty)

        app.typeKey("o", modifierFlags: [])
        let outPoint = app.staticTexts["OutPointTimecode"].label
        XCTAssertFalse(outPoint.isEmpty)

        // Cmd+Z: Undo
        app.typeKey("z", modifierFlags: .command)

        // Cmd+Shift+Z: Redo
        app.typeKey("z", modifierFlags: [.command, .shift])

        // Cmd+C / Cmd+V: Copy/Paste
        selectTimelineClip(at: 0)
        app.typeKey("c", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)

        // B: Blade tool
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(app.buttons["BladeTool"].isSelected)

        // A: Select tool (back to default)
        app.typeKey("a", modifierFlags: [])
        XCTAssertTrue(app.buttons["SelectTool"].isSelected)
    }

    // MARK: - Drag and Drop

    func testDragAndDropBetweenTracks() {
        loadTestProject()

        let clip = app.groups["TimelineClip"].firstMatch
        let track2 = app.groups["VideoTrack-2"]

        clip.press(forDuration: 0.5, thenDragTo: track2)

        // Verify clip moved to track 2
        let track2Clips = track2.groups.matching(identifier: "TimelineClip")
        XCTAssertEqual(track2Clips.count, 1)
    }

    func testDragAndDropReorderClips() {
        loadTestProject()

        let firstClip = app.groups["TimelineClip-0"]
        let secondClipPosition = app.groups["TimelineClip-1"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )

        firstClip.press(forDuration: 0.5, thenDragTo: secondClipPosition)
    }

    // MARK: - Accessibility

    func testAccessibilityAudit() throws {
        loadTestProject()

        // Built-in accessibility audit (Xcode 15+)
        try app.performAccessibilityAudit(for: [
            .dynamicType,
            .sufficientElementDescription,
            .contrast
        ]) { issue in
            // Optionally ignore known issues
            var dominated = false
            if issue.auditType == .contrast,
               issue.element?.identifier == "TimelineRuler" {
                dominated = true // Ruler contrast is intentionally subtle
            }
            return dominated
        }
    }

    func testVoiceOverAccessibility() {
        loadTestProject()

        // Verify critical elements have accessibility labels
        let playButton = app.buttons["PlayButton"]
        XCTAssertFalse(playButton.label.isEmpty)

        let timeline = app.groups["TimelineView"]
        XCTAssertFalse(timeline.label.isEmpty)

        // Verify timeline clips are accessible
        let clips = app.groups.matching(identifier: "TimelineClip")
        for i in 0..<clips.count {
            let clip = clips.element(boundBy: i)
            XCTAssertFalse(clip.label.isEmpty, "Clip \(i) missing accessibility label")
        }
    }

    // MARK: - Helpers

    private func loadTestProject() {
        app.menuItems["File"].tap()
        app.menuItems["Open..."].tap()
        // Pre-configured test project path
    }

    private func selectTimelineClip(at index: Int) {
        let clip = app.groups.matching(identifier: "TimelineClip").element(boundBy: index)
        clip.tap()
    }
}
```

---

## 6. CI/CD Pipeline

### GitHub Actions for macOS

#### Main CI Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  DEVELOPER_DIR: /Applications/Xcode_16.2.app/Contents/Developer
  SCHEME: SwiftEditor
  DESTINATION: 'platform=macOS'

jobs:
  build-and-test:
    name: Build & Test
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          lfs: true  # Fetch Git LFS test assets

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      # Cache SPM dependencies
      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: |
            .build
            ~/Library/Caches/org.swift.swiftpm
            ~/Library/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: |
            spm-${{ runner.os }}-

      # Cache Xcode DerivedData with timestamp preservation
      - name: Cache DerivedData
        uses: irgaly/xcode-cache@v1
        with:
          key: deriveddata-${{ runner.os }}-${{ hashFiles('**/*.swift', '**/project.pbxproj') }}
          restore-keys: |
            deriveddata-${{ runner.os }}-

      - name: Resolve packages
        run: |
          xcodebuild -resolvePackageDependencies \
            -scheme "$SCHEME" \
            -clonedSourcePackagesDirPath .spm-cache

      - name: Build
        run: |
          xcodebuild build-for-testing \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -derivedDataPath DerivedData \
            -clonedSourcePackagesDirPath .spm-cache \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify

      - name: Unit Tests
        run: |
          xcodebuild test-without-building \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -derivedDataPath DerivedData \
            -testPlan UnitTests \
            -resultBundlePath TestResults/UnitTests.xcresult \
            | xcbeautify

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: TestResults/*.xcresult
          retention-days: 7

  snapshot-tests:
    name: Snapshot Tests
    runs-on: macos-15
    timeout-minutes: 20

    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: |
            .build
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}

      - name: Run Snapshot Tests
        run: |
          xcodebuild test \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -testPlan SnapshotTests \
            -resultBundlePath TestResults/Snapshots.xcresult \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify

      - name: Upload Failed Snapshots
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failed-snapshots
          path: |
            **/Failures/**
          retention-days: 7

  performance-tests:
    name: Performance Tests
    runs-on: macos-15
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    timeout-minutes: 45

    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - name: Run Performance Tests
        run: |
          xcodebuild test \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -testPlan PerformanceTests \
            -resultBundlePath TestResults/Performance.xcresult \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify

      - name: Extract Performance Metrics
        if: always()
        run: |
          xcrun xcresulttool get --path TestResults/Performance.xcresult \
            --format json > performance-metrics.json

      - name: Upload Performance Metrics
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: performance-metrics
          path: performance-metrics.json

  lint:
    name: Lint & Format
    runs-on: macos-15
    timeout-minutes: 10

    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: brew install swiftlint swiftformat

      - name: SwiftLint
        run: swiftlint lint --strict --reporter github-actions-logging

      - name: SwiftFormat (check only)
        run: swiftformat --lint .
```

#### Code Signing with Certificates in CI

```yaml
# .github/workflows/release.yml (signing portion)
jobs:
  build-signed:
    runs-on: macos-15

    steps:
      - uses: actions/checkout@v4

      # Install the Apple certificate and provisioning profile
      - name: Install code signing certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.DEVELOPER_ID_CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # Create variables
          CERTIFICATE_PATH=$RUNNER_TEMP/certificate.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/build.keychain

          # Decode certificate
          echo -n "$CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH

          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          # Import certificate to keychain
          security import $CERTIFICATE_PATH -P "$CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k $KEYCHAIN_PATH

          # Allow codesign to access the keychain
          security set-key-partition-list -S apple-tool:,apple: \
            -s -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          # Add keychain to search list
          security list-keychains -d user -s $KEYCHAIN_PATH login.keychain

      - name: Build and sign
        run: |
          xcodebuild archive \
            -scheme "SwiftEditor" \
            -destination "generic/platform=macOS" \
            -archivePath $RUNNER_TEMP/SwiftEditor.xcarchive \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="${{ secrets.APPLE_TEAM_ID }}"

      # Notarization
      - name: Notarize app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          # Create zip for notarization
          ditto -c -k --keepParent \
            "$RUNNER_TEMP/SwiftEditor.xcarchive/Products/Applications/SwiftEditor.app" \
            "$RUNNER_TEMP/SwiftEditor.zip"

          # Submit for notarization
          xcrun notarytool submit "$RUNNER_TEMP/SwiftEditor.zip" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

          # Staple the notarization ticket
          xcrun stapler staple \
            "$RUNNER_TEMP/SwiftEditor.xcarchive/Products/Applications/SwiftEditor.app"

      - name: Cleanup keychain
        if: always()
        run: security delete-keychain $RUNNER_TEMP/build.keychain
```

#### Fastlane Match Alternative

```ruby
# Fastfile
default_platform(:mac)

platform :mac do
  lane :ci_build do
    sync_code_signing(
      type: "developer_id",
      readonly: is_ci,
      git_url: "https://github.com/yourorg/certificates.git",
      keychain_name: "build.keychain",
      keychain_password: ENV["KEYCHAIN_PASSWORD"]
    )

    build_mac_app(
      scheme: "SwiftEditor",
      export_method: "developer-id",
      output_directory: "./build"
    )

    notarize(
      package: "./build/SwiftEditor.app",
      bundle_id: "com.yourcompany.swifteditor"
    )
  end
end
```

### Cache Warming Workflow

```yaml
# .github/workflows/cache-warm.yml
name: Cache Warming

on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily

jobs:
  warm-cache:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Resolve and cache SPM
        run: |
          xcodebuild -resolvePackageDependencies \
            -scheme "SwiftEditor" \
            -clonedSourcePackagesDirPath .spm-cache

      - name: Save SPM cache
        uses: actions/cache/save@v4
        with:
          path: |
            .build
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}-warm

      - name: Build to warm DerivedData
        run: |
          xcodebuild build \
            -scheme "SwiftEditor" \
            -destination "platform=macOS" \
            CODE_SIGNING_ALLOWED=NO
```

---

## 7. Test Data Management

### Sample Media Assets for Tests

Organize test assets in a dedicated bundle:

```swift
// TestAssets.swift — test helper
import AVFoundation

enum TestAssets {
    static let bundle = Bundle(for: _TestAssetsMarker.self)

    // Short video clips (1-5 seconds each)
    static var colorBars5sec: AVURLAsset {
        asset(named: "color_bars_5s", ext: "mov")
    }

    static var blackSlug2sec: AVURLAsset {
        asset(named: "black_slug_2s", ext: "mov")
    }

    // Various codecs
    static var h264_1080p: AVURLAsset { asset(named: "h264_1080p", ext: "mp4") }
    static var hevc_4k: AVURLAsset { asset(named: "hevc_4k", ext: "mov") }
    static var prores422: AVURLAsset { asset(named: "prores422", ext: "mov") }
    static var prores4444: AVURLAsset { asset(named: "prores4444", ext: "mov") }

    // Audio
    static var stereo48k: AVURLAsset { asset(named: "stereo_48k", ext: "wav") }
    static var mono44k: AVURLAsset { asset(named: "mono_44k", ext: "aac") }
    static var surround51: AVURLAsset { asset(named: "surround_5.1", ext: "wav") }

    // Still frames
    static var sampleFrame: CGImage {
        let url = bundle.url(forResource: "sample_frame", withExtension: "png")!
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    static var sample4KFrame: CVPixelBuffer {
        // Load from test bundle and convert to CVPixelBuffer
        let image = sampleFrame
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width, image.height,
            kCVPixelFormatType_32BGRA, nil,
            &pixelBuffer
        )
        // ... copy image data
        return pixelBuffer!
    }

    // Reference renders for comparison
    static var referenceRender: URL {
        bundle.url(forResource: "reference_render", withExtension: "mov")!
    }

    private static func asset(named name: String, ext: String) -> AVURLAsset {
        let url = bundle.url(forResource: name, withExtension: ext)!
        return AVURLAsset(url: url)
    }
}

private class _TestAssetsMarker {}
```

### Git LFS for Test Fixtures

Configure Git LFS to track large media test files:

```bash
# .gitattributes
# Track test media with Git LFS
Tests/Fixtures/**/*.mov filter=lfs diff=lfs merge=lfs -text
Tests/Fixtures/**/*.mp4 filter=lfs diff=lfs merge=lfs -text
Tests/Fixtures/**/*.wav filter=lfs diff=lfs merge=lfs -text
Tests/Fixtures/**/*.aac filter=lfs diff=lfs merge=lfs -text
Tests/Fixtures/**/*.png filter=lfs diff=lfs merge=lfs -text

# Reference renders
Tests/ReferenceRenders/**/*.mov filter=lfs diff=lfs merge=lfs -text

# Snapshot references (optional — small PNGs may not need LFS)
# Tests/Snapshots/**/*.png filter=lfs diff=lfs merge=lfs -text
```

Ensure CI fetches LFS objects:

```yaml
# In GitHub Actions
- uses: actions/checkout@v4
  with:
    lfs: true

# Or manually
- name: Fetch LFS
  run: git lfs pull
```

### Synthetic Test Content Generation

Generate deterministic test media programmatically so tests do not depend on external files:

```swift
import AVFoundation
import CoreImage

enum SyntheticMedia {

    /// Generate SMPTE color bars as a CVPixelBuffer
    static func colorBars(width: Int = 1920, height: Int = 1080) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &pixelBuffer
        )
        guard let buffer = pixelBuffer else { fatalError() }

        CVPixelBufferLockBaseAddress(buffer, [])
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
            .assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // SMPTE color bar colors (BGRA)
        let colors: [(UInt8, UInt8, UInt8)] = [
            (191, 191, 191), // White
            (0, 191, 191),   // Yellow
            (191, 191, 0),   // Cyan
            (0, 191, 0),     // Green
            (191, 0, 191),   // Magenta
            (0, 0, 191),     // Red
            (191, 0, 0),     // Blue
        ]

        let barWidth = width / colors.count

        for y in 0..<height {
            for x in 0..<width {
                let colorIndex = min(x / barWidth, colors.count - 1)
                let offset = y * bytesPerRow + x * 4
                let (b, g, r) = colors[colorIndex]
                baseAddress[offset] = b     // Blue
                baseAddress[offset + 1] = g // Green
                baseAddress[offset + 2] = r // Red
                baseAddress[offset + 3] = 255 // Alpha
            }
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Generate a tone (sine wave) as PCM audio data
    static func tone(
        frequency: Double = 1000.0,
        duration: Double = 1.0,
        sampleRate: Double = 48000.0,
        amplitude: Float = 0.5
    ) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        return (0..<sampleCount).map { i in
            let phase = 2.0 * .pi * frequency * Double(i) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }

    /// Write synthetic video to a temporary file
    static func writeTestVideo(
        duration: Double = 5.0,
        fps: Int = 30,
        width: Int = 1920,
        height: Int = 1080,
        includeAudio: Bool = true
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")

        let writer = try AVAssetWriter(url: outputURL, fileType: .mov)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: nil
        )
        writer.add(videoInput)

        // Audio input
        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            writer.add(input)
            audioInput = input
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(duration * Double(fps))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        for i in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            let frame = colorBars(width: width, height: height)
            adaptor.append(frame, withPresentationTime: time)
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        await writer.finishWriting()
        return outputURL
    }
}
```

### Test Project Files

```swift
/// Pre-built timeline project for testing
enum TestProjects {

    /// Simple project with 3 clips on a single track
    static func simpleEdit() throws -> ProjectDocument {
        let project = ProjectDocument()
        project.timeline.insertClip(
            Clip(asset: TestAssets.colorBars5sec, duration: 5.0),
            at: 0.0
        )
        project.timeline.insertClip(
            Clip(asset: TestAssets.h264_1080p, duration: 10.0),
            at: 5.0
        )
        project.timeline.insertClip(
            Clip(asset: TestAssets.blackSlug2sec, duration: 2.0),
            at: 15.0
        )
        return project
    }

    /// Complex project with multiple tracks, effects, transitions
    static func complexEdit() throws -> ProjectDocument {
        let project = ProjectDocument()

        // Video track 1
        project.timeline.insertClip(
            Clip(asset: TestAssets.hevc_4k, duration: 15.0),
            at: 0.0, track: 0
        )

        // Video track 2 (overlay)
        project.timeline.insertClip(
            Clip(asset: TestAssets.prores4444, duration: 8.0,
                 effects: [.opacity(0.7)]),
            at: 5.0, track: 1
        )

        // Transitions
        project.timeline.addTransition(
            .crossDissolve(duration: 1.0),
            between: "clip-0", and: "clip-1"
        )

        // Audio
        project.timeline.insertClip(
            Clip(asset: TestAssets.stereo48k, duration: 15.0),
            at: 0.0, track: .audio(0)
        )

        return project
    }
}
```

---

## 8. Code Quality

### SwiftLint Configuration

```yaml
# .swiftlint.yml
included:
  - Sources
  - Tests

excluded:
  - .build
  - DerivedData
  - Packages

# Rules enabled beyond defaults
opt_in_rules:
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_filter_is_empty
  - contains_over_first_not_nil
  - discouraged_object_literal
  - empty_collection_literal
  - empty_count
  - empty_string
  - enum_case_associated_values_count
  - explicit_init
  - fatal_error_message
  - first_where
  - flatmap_over_map_reduce
  - identical_operands
  - implicit_return
  - joined_default_parameter
  - last_where
  - legacy_multiple
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_arguments
  - multiline_function_chains
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - prefer_self_in_static_references
  - prefer_self_type_over_type_of_self
  - private_action
  - private_outlet
  - prohibited_super_call
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_first_last
  - toggle_bool
  - trailing_closure
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - vertical_parameter_alignment_on_call

# Customized rules
line_length:
  warning: 120
  error: 200
  ignores_urls: true
  ignores_comments: true

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 1000

function_body_length:
  warning: 50
  error: 100

function_parameter_count:
  warning: 6
  error: 8

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 50
  excluded:
    - id
    - x
    - y
    - i
    - j
    - dt
    - dx
    - dy

nesting:
  type_level: 3
  function_level: 3

# Disabled rules
disabled_rules:
  - todo  # Allow TODO comments during development
  - trailing_comma  # Team preference: no trailing commas

# Custom rules for NLE-specific patterns
custom_rules:
  no_force_unwrap_in_production:
    name: "No Force Unwrap in Production Code"
    regex: '(?<!Test)\.swift:.*!(?!\s*$)'
    match_kinds:
      - identifier
    message: "Avoid force unwrapping in production code. Use guard let or if let."
    severity: warning
    included: "Sources/"
    excluded: "Tests/"
```

### SwiftFormat Configuration

```
# .swiftformat

# File options
--exclude .build,DerivedData,Packages

# Format options
--indent 4
--indentcase false
--trimwhitespace always
--voidtype void
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--wrapconditions after-first
--maxwidth 120
--self remove
--importgrouping testable-bottom
--semicolons never
--commas inline
--stripunusedargs closure-only
--header strip

# Rules
--enable blankLinesBetweenScopes
--enable blankLinesBetweenImports
--enable consecutiveSpaces
--enable duplicateImports
--enable isEmpty
--enable markTypes
--enable organizeDeclarations
--enable sortImports
--enable wrapMultilineStatementBraces

--disable redundantReturn  # Allow explicit returns for clarity
--disable wrapSwitchCases  # Keep short cases on one line
```

### Documentation with DocC

DocC is Apple's documentation compiler for Swift frameworks and packages. It produces rich API reference documentation and interactive tutorials.

#### Documenting API with Doc Comments

```swift
/// A timeline track that contains an ordered sequence of clips.
///
/// Use `Track` to organize media clips in a horizontal time-ordered sequence.
/// Each track maintains its own list of clips and handles gap management.
///
/// ## Topics
///
/// ### Creating Tracks
/// - ``init(type:)``
///
/// ### Managing Clips
/// - ``insertClip(_:at:mode:)``
/// - ``deleteClip(id:mode:)``
/// - ``moveClip(id:to:)``
///
/// ### Querying
/// - ``clipAt(time:)``
/// - ``clips``
/// - ``duration``
public struct Track {

    /// The type of media this track contains.
    public enum TrackType {
        /// A track containing video clips.
        case video
        /// A track containing audio clips.
        case audio
    }

    /// Inserts a clip at the specified time position.
    ///
    /// - Parameters:
    ///   - clip: The clip to insert.
    ///   - time: The position in the timeline to insert the clip.
    ///   - mode: The edit mode determining how existing clips are affected.
    ///     Defaults to ``EditMode/insert``.
    ///
    /// - Throws: ``TimelineError/invalidTimeRange`` if the time is outside
    ///   the track's valid range.
    ///
    /// ```swift
    /// let track = Track(type: .video)
    /// try track.insertClip(myClip, at: CMTime.zero, mode: .insert)
    /// ```
    public mutating func insertClip(
        _ clip: Clip,
        at time: CMTime,
        mode: EditMode = .insert
    ) throws {
        // ...
    }
}
```

#### Building Documentation

```bash
# Build documentation in Xcode
# Product > Build Documentation (Ctrl+Shift+Cmd+D)

# Command line
xcodebuild docbuild \
  -scheme SwiftEditor \
  -destination "platform=macOS" \
  -derivedDataPath DerivedData

# Export for hosting
$(xcrun --find docc) process-archive transform-for-static-hosting \
  DerivedData/Build/Products/Debug/SwiftEditor.doccarchive \
  --output-path docs \
  --hosting-base-path swifteditor
```

#### CI Documentation Build

```yaml
  docs:
    name: Build Documentation
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Build DocC
        run: |
          xcodebuild docbuild \
            -scheme "SwiftEditor" \
            -destination "platform=macOS" \
            -derivedDataPath DerivedData \
            CODE_SIGNING_ALLOWED=NO

      - name: Export static site
        run: |
          $(xcrun --find docc) process-archive transform-for-static-hosting \
            DerivedData/Build/Products/Debug/SwiftEditor.doccarchive \
            --output-path docs \
            --hosting-base-path swifteditor

      - name: Deploy to GitHub Pages
        if: github.ref == 'refs/heads/main'
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs
```

---

## 9. Release Automation

### Sparkle Appcast Generation

[Sparkle](https://github.com/sparkle-project/Sparkle) is the standard macOS update framework. Automate appcast generation with `generate_appcast`:

```bash
#!/bin/bash
# scripts/release.sh — Full release pipeline

set -euo pipefail

VERSION=$1
BUILD_NUMBER=$2

echo "=== Building SwiftEditor v${VERSION} (${BUILD_NUMBER}) ==="

# 1. Build and archive
xcodebuild archive \
  -scheme "SwiftEditor" \
  -destination "generic/platform=macOS" \
  -archivePath "build/SwiftEditor.xcarchive" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}"

# 2. Export the app
xcodebuild -exportArchive \
  -archivePath "build/SwiftEditor.xcarchive" \
  -exportOptionsPlist "ExportOptions.plist" \
  -exportPath "build/export"

APP_PATH="build/export/SwiftEditor.app"

# 3. Notarize
ditto -c -k --keepParent "$APP_PATH" "build/SwiftEditor.zip"
xcrun notarytool submit "build/SwiftEditor.zip" \
  --keychain-profile "AC_NOTARIZE" \
  --wait

xcrun stapler staple "$APP_PATH"

# 4. Create DMG
create-dmg \
  --volname "SwiftEditor ${VERSION}" \
  --volicon "Assets/dmg-icon.icns" \
  --background "Assets/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "SwiftEditor.app" 150 200 \
  --app-drop-link 450 200 \
  "build/SwiftEditor-${VERSION}.dmg" \
  "$APP_PATH"

# 5. Sign DMG with Sparkle EdDSA key
./Sparkle/bin/sign_update "build/SwiftEditor-${VERSION}.dmg"

# 6. Generate appcast
mkdir -p updates
cp "build/SwiftEditor-${VERSION}.dmg" updates/
./Sparkle/bin/generate_appcast updates/

echo "=== Release v${VERSION} complete ==="
echo "DMG: build/SwiftEditor-${VERSION}.dmg"
echo "Appcast: updates/appcast.xml"
```

### DMG Creation in CI

```yaml
  create-dmg:
    needs: build-signed
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Download signed app
        uses: actions/download-artifact@v4
        with:
          name: signed-app
          path: build/

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Create DMG
        run: |
          create-dmg \
            --volname "SwiftEditor ${{ github.ref_name }}" \
            --background "Assets/dmg-background.png" \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "SwiftEditor.app" 150 200 \
            --app-drop-link 450 200 \
            "SwiftEditor-${{ github.ref_name }}.dmg" \
            "build/SwiftEditor.app"

      - name: Sign with Sparkle
        env:
          SPARKLE_KEY: ${{ secrets.SPARKLE_EDDSA_KEY }}
        run: |
          echo "$SPARKLE_KEY" > /tmp/sparkle_key
          ./Sparkle/bin/sign_update \
            "SwiftEditor-${{ github.ref_name }}.dmg" \
            --ed-key-file /tmp/sparkle_key

      - name: Upload DMG
        uses: actions/upload-artifact@v4
        with:
          name: dmg
          path: "SwiftEditor-${{ github.ref_name }}.dmg"
```

### TestFlight Upload Automation

```ruby
# Fastfile — TestFlight upload
platform :mac do
  lane :beta do
    increment_build_number(
      build_number: ENV["BUILD_NUMBER"] || latest_testflight_build_number + 1
    )

    build_mac_app(
      scheme: "SwiftEditor",
      export_method: "app-store",
      output_directory: "./build"
    )

    upload_to_testflight(
      skip_waiting_for_build_processing: true,
      changelog: ENV["CHANGELOG"] || "Bug fixes and improvements"
    )
  end
end
```

```yaml
# GitHub Actions — TestFlight
  testflight:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Upload to TestFlight
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY: ${{ secrets.ASC_KEY }}
        run: bundle exec fastlane beta
```

### Semantic Versioning and Changelog Generation

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for changelog

      - name: Generate changelog
        id: changelog
        run: |
          # Get previous tag
          PREV_TAG=$(git tag --sort=-version:refname | sed -n '2p')

          echo "## What's Changed" > CHANGELOG.md
          echo "" >> CHANGELOG.md

          # Features
          FEATURES=$(git log ${PREV_TAG}..HEAD --pretty=format:"- %s" --grep="feat:" --grep="add:" -i)
          if [ -n "$FEATURES" ]; then
            echo "### Features" >> CHANGELOG.md
            echo "$FEATURES" >> CHANGELOG.md
            echo "" >> CHANGELOG.md
          fi

          # Bug fixes
          FIXES=$(git log ${PREV_TAG}..HEAD --pretty=format:"- %s" --grep="fix:" -i)
          if [ -n "$FIXES" ]; then
            echo "### Bug Fixes" >> CHANGELOG.md
            echo "$FIXES" >> CHANGELOG.md
            echo "" >> CHANGELOG.md
          fi

          # Performance
          PERF=$(git log ${PREV_TAG}..HEAD --pretty=format:"- %s" --grep="perf:" -i)
          if [ -n "$PERF" ]; then
            echo "### Performance" >> CHANGELOG.md
            echo "$PERF" >> CHANGELOG.md
          fi

      - name: Build, sign, notarize, create DMG
        run: ./scripts/release.sh "${{ github.ref_name }}" "${{ github.run_number }}"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          body_path: CHANGELOG.md
          files: |
            build/SwiftEditor-*.dmg
          draft: false
          prerelease: ${{ contains(github.ref, 'beta') || contains(github.ref, 'rc') }}
```

---

## 10. Monitoring in Production

### MetricKit for Performance and Crash Data

```swift
import MetricKit

final class AppMetricsSubscriber: NSObject, MXMetricManagerSubscriber {

    static let shared = AppMetricsSubscriber()

    func start() {
        MXMetricManager.shared.add(self)
    }

    // Receives aggregated metrics once every ~24 hours
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            processMetrics(payload)
        }
    }

    // Receives diagnostic payloads (crashes, hangs, disk writes)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            processDiagnostics(payload)
        }
    }

    private func processMetrics(_ payload: MXMetricPayload) {
        // App launch time
        if let launchMetrics = payload.applicationLaunchMetrics {
            let resumeTime = launchMetrics.histogrammedApplicationResumeTime
            let launchTime = launchMetrics.histogrammedTimeToFirstDraw
            Logger.metrics.info("Launch time histogram: \(launchTime.debugDescription)")
            Logger.metrics.info("Resume time histogram: \(resumeTime.debugDescription)")
        }

        // Memory usage
        if let memoryMetrics = payload.memoryMetrics {
            let peakMemory = memoryMetrics.peakMemoryUsage
            Logger.metrics.info("Peak memory: \(peakMemory.description)")
        }

        // CPU metrics
        if let cpuMetrics = payload.cpuMetrics {
            Logger.metrics.info("CPU time: \(cpuMetrics.cumulativeCPUTime.description)")
            Logger.metrics.info(
                "CPU instructions: \(cpuMetrics.cumulativeCPUInstructions.description)"
            )
        }

        // GPU metrics
        if let gpuMetrics = payload.gpuMetrics {
            Logger.metrics.info("GPU time: \(gpuMetrics.cumulativeGPUTime.description)")
        }

        // Animation metrics (hitches)
        if let animationMetrics = payload.animationMetrics {
            Logger.metrics.info(
                "Scroll hitch ratio: \(animationMetrics.scrollHitchTimeRatio.description)"
            )
        }

        // Signpost metrics (custom measurements)
        if let signpostMetrics = payload.signpostMetrics {
            for metric in signpostMetrics {
                Logger.metrics.info(
                    "Signpost '\(metric.signpostName)': " +
                    "count=\(metric.signpostIntervalData.histogrammedSignpostDuration)" +
                    " cpu=\(metric.signpostIntervalData.cumulativeCPUTime)"
                )
            }
        }

        // Send to analytics backend
        sendToAnalytics(payload.jsonRepresentation())
    }

    private func processDiagnostics(_ payload: MXDiagnosticPayload) {
        // Crash diagnostics
        if let crashDiagnostics = payload.crashDiagnostics {
            for crash in crashDiagnostics {
                Logger.metrics.error(
                    "Crash: \(crash.applicationVersion) - " +
                    "\(crash.terminationReason ?? "unknown")"
                )
            }
        }

        // Hang diagnostics (app not responding)
        if let hangDiagnostics = payload.hangDiagnostics {
            for hang in hangDiagnostics {
                Logger.metrics.warning(
                    "Hang detected: \(hang.hangDuration.description)"
                )
            }
        }

        // Disk write diagnostics
        if let diskWriteDiagnostics = payload.diskWriteExceptionDiagnostics {
            for diskWrite in diskWriteDiagnostics {
                Logger.metrics.warning(
                    "Excessive disk writes: \(diskWrite.totalWritesCaused.description)"
                )
            }
        }

        sendDiagnosticsToAnalytics(payload.jsonRepresentation())
    }

    private func sendToAnalytics(_ data: Data) {
        // Send to your analytics backend
    }

    private func sendDiagnosticsToAnalytics(_ data: Data) {
        // Send to your crash reporting backend
    }
}
```

### os_signpost for Render/Export Timing

```swift
import os.signpost

extension Logger {
    static let render = Logger(subsystem: "com.swifteditor", category: "Render")
    static let export = Logger(subsystem: "com.swifteditor", category: "Export")
    static let timeline = Logger(subsystem: "com.swifteditor", category: "Timeline")
    static let metrics = Logger(subsystem: "com.swifteditor", category: "Metrics")
}

/// Signpost-instrumented render pipeline
final class InstrumentedRenderPipeline {

    private let signposter = OSSignposter(
        subsystem: "com.swifteditor",
        category: "RenderPipeline"
    )

    // Also instrument for MetricKit collection
    private let metricsLog = MXMetricManager.makeLogHandle(
        category: "RenderPipeline"
    )

    func renderFrame(at time: CMTime) -> CVPixelBuffer? {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("RenderFrame", id: signpostID,
                                              "\(time.seconds, format: .fixed(precision: 3))s")
        defer { signposter.endInterval("RenderFrame", state) }

        // Also track in MetricKit
        mxSignpost(.begin, log: metricsLog, name: "RenderFrame")
        defer { mxSignpost(.end, log: metricsLog, name: "RenderFrame") }

        // Render sub-stages
        let composited = compositeVideoTracks(at: time)
        let filtered = applyEffects(to: composited, at: time)
        let final_frame = applyColorManagement(to: filtered)

        return final_frame
    }

    private func compositeVideoTracks(at time: CMTime) -> CVPixelBuffer? {
        let state = signposter.beginInterval("CompositeVideoTracks")
        defer { signposter.endInterval("CompositeVideoTracks", state) }

        // Compositing logic
        return nil
    }

    private func applyEffects(to buffer: CVPixelBuffer?, at time: CMTime) -> CVPixelBuffer? {
        let state = signposter.beginInterval("ApplyEffects")
        defer { signposter.endInterval("ApplyEffects", state) }

        // Effect processing
        return buffer
    }

    private func applyColorManagement(to buffer: CVPixelBuffer?) -> CVPixelBuffer? {
        let state = signposter.beginInterval("ColorManagement")
        defer { signposter.endInterval("ColorManagement", state) }

        return buffer
    }

    func exportTimeline(
        composition: AVComposition,
        to url: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Export", id: signpostID)
        defer { signposter.endInterval("Export", state) }

        mxSignpost(.begin, log: metricsLog, name: "Export")
        defer { mxSignpost(.end, log: metricsLog, name: "Export") }

        Logger.export.info("Starting export to \(url.lastPathComponent)")

        // Export logic with progress reporting
        // ...

        Logger.export.info("Export complete: \(url.lastPathComponent)")
    }
}
```

### Structured Logging with OSLog

```swift
import os

// Define loggers for each subsystem
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let app = Logger(subsystem: subsystem, category: "App")
    static let project = Logger(subsystem: subsystem, category: "Project")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let effects = Logger(subsystem: subsystem, category: "Effects")
    static let gpu = Logger(subsystem: subsystem, category: "GPU")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let io = Logger(subsystem: subsystem, category: "IO")
}

// Usage throughout the app
final class ProjectManager {

    func openProject(at url: URL) throws -> ProjectDocument {
        Logger.project.info("Opening project: \(url.lastPathComponent, privacy: .public)")

        let startTime = CFAbsoluteTimeGetCurrent()

        let document = try ProjectDocument(contentsOf: url)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger.project.info(
            "Project opened in \(elapsed, format: .fixed(precision: 3))s - " +
            "\(document.timeline.clips.count) clips, " +
            "\(document.timeline.tracks.count) tracks"
        )

        return document
    }

    func saveProject(_ document: ProjectDocument, to url: URL) throws {
        Logger.project.info("Saving project: \(url.lastPathComponent, privacy: .public)")

        do {
            try document.write(to: url)
            Logger.project.info("Project saved successfully")
        } catch {
            Logger.project.error(
                "Failed to save project: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}

final class MediaImporter {

    func importMedia(from urls: [URL]) async throws -> [MediaAsset] {
        Logger.media.info("Importing \(urls.count) media files")

        var assets: [MediaAsset] = []

        for url in urls {
            Logger.media.debug(
                "Processing: \(url.lastPathComponent, privacy: .public)"
            )

            let asset = try await processMediaFile(at: url)

            Logger.media.info(
                "Imported: \(url.lastPathComponent, privacy: .public) - " +
                "\(asset.codec, privacy: .public), " +
                "\(asset.resolution.width)x\(asset.resolution.height), " +
                "\(asset.duration, format: .fixed(precision: 2))s"
            )

            assets.append(asset)
        }

        Logger.media.info("Import complete: \(assets.count) assets")
        return assets
    }
}

// Reading logs programmatically
final class LogExporter {

    func exportRecentLogs() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(
            date: Date().addingTimeInterval(-3600) // Last hour
        )

        let entries = try store.getEntries(
            at: position,
            matching: NSPredicate(format: "subsystem == %@", Bundle.main.bundleIdentifier!)
        )

        var output = ""
        for entry in entries {
            if let logEntry = entry as? OSLogEntryLog {
                output += "[\(logEntry.date)] [\(logEntry.category)] \(logEntry.composedMessage)\n"
            }
        }
        return output
    }
}
```

### Combining Everything: Production Monitoring Dashboard Data

```swift
/// Collects and reports key metrics for the NLE
final class NLEMonitor {

    static let shared = NLEMonitor()

    private let signposter = OSSignposter(subsystem: "com.swifteditor", category: "Monitor")
    private let metricsLog = MXMetricManager.makeLogHandle(category: "Monitor")

    // Track render performance
    func trackRenderFrame(duration: TimeInterval, droppedFrame: Bool) {
        Logger.render.info(
            "Frame render: \(duration * 1000, format: .fixed(precision: 2))ms" +
            "\(droppedFrame ? " [DROPPED]" : "")"
        )

        if droppedFrame {
            Logger.render.warning("Dropped frame detected")
        }
    }

    // Track export progress
    func trackExport(
        duration: TimeInterval,
        outputSize: Int64,
        codec: String,
        resolution: String
    ) {
        Logger.export.info(
            "Export complete: \(duration, format: .fixed(precision: 1))s, " +
            "\(ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file)), " +
            "\(codec, privacy: .public) \(resolution, privacy: .public)"
        )
    }

    // Track memory pressure during editing
    func trackMemoryPressure() {
        let memoryUsage = ProcessInfo.processInfo.physicalMemory
        Logger.app.info("Physical memory: \(memoryUsage / 1024 / 1024)MB")

        // Report task-level memory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let residentMB = info.resident_size / 1024 / 1024
            Logger.app.info("Resident memory: \(residentMB)MB")
        }
    }
}
```

---

## Summary

| Area | Key Tools/Frameworks | Test Level |
|------|---------------------|------------|
| **Unit Tests** | Swift Testing, Protocol wrappers, AVMutableComposition | Fast, isolated |
| **Metal Shaders** | MTLDevice in tests, CPU reference + GPU compare | GPU roundtrip |
| **Snapshot Tests** | swift-snapshot-testing (Point-Free) | Visual regression |
| **Integration Tests** | AVAssetReader, PSNR/SSIM, Accelerate | End-to-end render |
| **Performance Tests** | XCTMetric, XCTOSSignpostMetric | Regression detection |
| **UI Tests** | XCUITest, performAccessibilityAudit | Workflow validation |
| **CI/CD** | GitHub Actions (macos-15), irgaly/xcode-cache | Automated pipeline |
| **Code Quality** | SwiftLint, SwiftFormat, DocC | Static analysis |
| **Release** | Sparkle, create-dmg, fastlane, notarytool | Distribution |
| **Production** | MetricKit, OSSignposter, OSLog/Logger | Runtime monitoring |

### Test Plan Organization

Create three Xcode test plans to separate concerns:

- **UnitTests.xctestplan** — Fast tests (< 10s total): timeline operations, undo/redo, model logic, Metal shader validation
- **SnapshotTests.xctestplan** — Snapshot comparisons: timeline views, inspector panels, viewer overlays
- **PerformanceTests.xctestplan** — Performance baselines (run on main branch only): composition build, render frame, export timing, memory usage

### Recommended CI Matrix

| Trigger | Jobs Run | Time Budget |
|---------|----------|-------------|
| PR opened/updated | Build + Unit + Lint + Snapshots | ~10 min |
| Push to main | All above + Performance | ~25 min |
| Tag (release) | All above + Sign + Notarize + DMG + Appcast | ~40 min |
| Nightly | Cache warming + Full integration suite | ~60 min |
