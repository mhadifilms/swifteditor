# 06 - Rendering, Export & Codec Support

## Table of Contents
1. [AVAssetExportSession vs AVAssetWriter](#1-avassetexportsession-vs-avassetwriter)
2. [AVAssetWriter Complete Setup & Usage](#2-avassetwriter-complete-setup--usage)
3. [AVAssetReader + AVAssetWriter Pipeline](#3-avassetreader--avassetwriter-pipeline)
4. [VideoToolbox: Hardware-Accelerated Encoding](#4-videotoolbox-hardware-accelerated-encoding)
5. [VideoToolbox: Hardware-Accelerated Decoding](#5-videotoolbox-hardware-accelerated-decoding)
6. [Codec Support & Configuration](#6-codec-support--configuration)
7. [Container Formats](#7-container-formats)
8. [Resolution Handling (Up to 8K)](#8-resolution-handling-up-to-8k)
9. [Frame Rate Handling](#9-frame-rate-handling)
10. [HDR & Wide Color Gamut Export](#10-hdr--wide-color-gamut-export)
11. [Render Queue Management](#11-render-queue-management)
12. [Background Rendering](#12-background-rendering)
13. [Progress Reporting](#13-progress-reporting)
14. [Proxy Workflow](#14-proxy-workflow)
15. [Smart Rendering](#15-smart-rendering)
16. [Batch Export](#16-batch-export)
17. [Custom Video Compositor](#17-custom-video-compositor)
18. [Open-Source Libraries](#18-open-source-libraries)
19. [WWDC Sessions Reference](#19-wwdc-sessions-reference)
20. [Architecture Recommendations for NLE Export System](#20-architecture-recommendations-for-nle-export-system)

---

## 1. AVAssetExportSession vs AVAssetWriter

### When to Use AVAssetExportSession

- **Simple operations**: format conversion, trimming, basic composition
- **Preset-based**: limited to predefined quality presets
- **Quick implementation**: minimal code for basic export
- **Built-in progress**: has a `progress` property (0.0 - 1.0)
- **Limited control**: cannot customize codec settings, bitrate, or frame-by-frame processing

```swift
import AVFoundation

func exportWithSession(asset: AVAsset, outputURL: URL) async throws {
    // Check preset compatibility
    let compatible = await AVAssetExportSession.compatibility(
        ofExportPreset: AVAssetExportPresetHEVCHighestQuality,
        with: asset,
        outputFileType: .mov
    )
    guard compatible else { throw ExportError.presetNotCompatible }

    guard let session = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetHEVCHighestQuality
    ) else { throw ExportError.sessionCreationFailed }

    session.outputURL = outputURL
    session.outputFileType = .mov
    session.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    // Optional: set video composition for effects
    // session.videoComposition = myVideoComposition

    // Export with modern async API (iOS 18+ / macOS 15+)
    await session.export()

    guard session.status == .completed else {
        throw session.error ?? ExportError.unknown
    }
}
```

**Available Export Presets:**
```swift
// Standard quality presets
AVAssetExportPresetLowQuality
AVAssetExportPresetMediumQuality
AVAssetExportPresetHighestQuality

// Resolution-specific presets
AVAssetExportPreset640x480
AVAssetExportPreset960x540
AVAssetExportPreset1280x720
AVAssetExportPreset1920x1080
AVAssetExportPreset3840x2160

// HEVC presets
AVAssetExportPresetHEVCHighestQuality
AVAssetExportPresetHEVC1920x1080
AVAssetExportPresetHEVC3840x2160
AVAssetExportPresetHEVCHighestQualityWithAlpha

// ProRes presets (macOS)
AVAssetExportPresetAppleProRes422LPCM
AVAssetExportPresetAppleProRes4444LPCM

// Passthrough (no re-encoding)
AVAssetExportPresetPassthrough
```

### When to Use AVAssetWriter

- **Full control**: specify exact codec, bitrate, resolution, color space
- **Frame-by-frame processing**: process each frame with Metal/Core Image
- **Multiple tracks**: write video, audio, metadata tracks independently
- **Real-time recording**: capture from camera with custom encoding
- **Custom compositions**: combine sources with precise timing
- **ProRes encoding**: full control over ProRes variants
- **HDR export**: explicit control over color space and transfer function

### Decision Matrix

| Feature | AVAssetExportSession | AVAssetWriter |
|---------|---------------------|---------------|
| Setup complexity | Low | High |
| Codec control | Presets only | Full control |
| Bitrate control | No | Yes |
| Frame processing | No | Yes |
| Multiple inputs | No | Yes |
| Progress tracking | Built-in | Manual |
| Performance | Fast (optimized) | 3-6x slower* |
| HDR support | Via presets | Full control |
| ProRes variants | Limited | All variants |
| Alpha channel | HEVC w/ Alpha preset | Full control |

*Note: AVAssetExportSession uses internal optimizations that may bypass full decode/encode cycles.

---

## 2. AVAssetWriter Complete Setup & Usage

### Basic Video-Only Export

```swift
import AVFoundation
import CoreVideo

class VideoExporter {

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// Set up AVAssetWriter for H.264 video export
    func setupWriter(outputURL: URL, width: Int, height: Int) throws {
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Create writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Video output settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30
            ] as [String: Any]
        ]

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        videoInput?.expectsMediaDataInRealTime = false // false for offline rendering

        // Pixel buffer adaptor for efficient buffer management
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] // Enable IOSurface for Metal
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if assetWriter!.canAdd(videoInput!) {
            assetWriter!.add(videoInput!)
        }
    }

    /// Start the writing session
    func startWriting() throws {
        guard let writer = assetWriter else { throw ExportError.writerNotSetUp }

        guard writer.startWriting() else {
            throw writer.error ?? ExportError.unknown
        }
        writer.startSession(atSourceTime: .zero)
    }

    /// Append a pixel buffer at a given time
    func appendFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        guard let adaptor = pixelBufferAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else {
            return false
        }
        return adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    /// Create a pixel buffer from the adaptor's pool (more efficient than manual creation)
    func createPixelBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferAdaptor?.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    /// Finish writing and finalize the file
    func finishWriting() async throws {
        videoInput?.markAsFinished()

        guard let writer = assetWriter else { throw ExportError.writerNotSetUp }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? ExportError.unknown
        }
    }
}
```

### Complete Export with Audio

```swift
class VideoAudioExporter {

    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!

    func setup(
        outputURL: URL,
        fileType: AVFileType = .mov,
        width: Int,
        height: Int,
        frameRate: Double = 30.0,
        videoBitRate: Int = 10_000_000,
        audioSampleRate: Double = 48000.0,
        audioChannels: Int = 2,
        audioBitRate: Int = 256_000
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        // -- Video Settings --
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2), // keyframe every 2 seconds
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoAllowFrameReorderingKey: true
            ] as [String: Any]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        // -- Audio Settings --
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: audioChannels,
            AVEncoderBitRateKey: audioBitRate,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false

        // Add inputs
        if assetWriter.canAdd(videoInput) { assetWriter.add(videoInput) }
        if assetWriter.canAdd(audioInput) { assetWriter.add(audioInput) }
    }

    /// Lossless audio settings (for ProRes workflows)
    static func losslessAudioSettings(sampleRate: Double = 48000, channels: Int = 2) -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
```

### Frame-by-Frame Export Loop (Rendering from Timeline)

```swift
extension VideoAudioExporter {

    /// Export a timeline by rendering each frame
    func exportTimeline(
        duration: CMTime,
        frameRate: Double,
        renderFrame: @escaping (CMTime) -> CVPixelBuffer?,
        progressHandler: @escaping (Double) -> Void
    ) async throws {

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? ExportError.unknown
        }
        assetWriter.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1000, timescale: CMTimeScale(frameRate * 1000))
        let totalFrames = Int(CMTimeGetSeconds(duration) * frameRate)

        // Write video frames on a dedicated queue
        let videoQueue = DispatchQueue(label: "com.editor.export.video")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var frameIndex = 0

            videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                guard let self = self else { return }

                while self.videoInput.isReadyForMoreMediaData {
                    if frameIndex >= totalFrames {
                        self.videoInput.markAsFinished()
                        continuation.resume()
                        return
                    }

                    let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))

                    if let pixelBuffer = renderFrame(presentationTime) {
                        if !self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                            continuation.resume(throwing: self.assetWriter.error ?? ExportError.appendFailed)
                            return
                        }
                    }

                    frameIndex += 1

                    // Report progress
                    let progress = Double(frameIndex) / Double(totalFrames)
                    DispatchQueue.main.async {
                        progressHandler(progress)
                    }
                }
            }
        }

        // Finish writing
        await assetWriter.finishWriting()

        guard assetWriter.status == .completed else {
            throw assetWriter.error ?? ExportError.unknown
        }
    }
}
```

---

## 3. AVAssetReader + AVAssetWriter Pipeline

This is the standard pattern for transcoding, re-encoding, or processing existing video files.

### Complete Transcode Pipeline

```swift
import AVFoundation

actor TranscodePipeline {

    enum TranscodeError: Error {
        case readerCreationFailed
        case writerCreationFailed
        case noVideoTrack
        case readingFailed(Error?)
        case writingFailed(Error?)
    }

    /// Transcode a video file with full codec control
    func transcode(
        sourceURL: URL,
        outputURL: URL,
        outputFileType: AVFileType = .mov,
        videoOutputSettings: [String: Any],
        audioOutputSettings: [String: Any]?,
        videoComposition: AVVideoComposition? = nil,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {

        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: sourceURL)

        // -- Create Reader --
        let reader = try AVAssetReader(asset: asset)

        // Video reader output - decompress to pixel buffers
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.noVideoTrack
        }

        let videoReaderSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] // for Metal access
        ]

        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: videoReaderSettings
        )
        videoReaderOutput.alwaysCopiesSampleData = false // performance optimization

        if reader.canAdd(videoReaderOutput) {
            reader.add(videoReaderOutput)
        }

        // Audio reader output - decompress to PCM
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioDecompressSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: audioDecompressSettings
            )
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioReaderOutput = output
            }
        }

        // -- Create Writer --
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)

        // Video writer input
        let videoFormatHint = try await videoTrack.load(.formatDescriptions).first
        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings,
            sourceFormatHint: videoFormatHint
        )
        videoWriterInput.expectsMediaDataInRealTime = false

        // Apply transform from source
        let transform = try await videoTrack.load(.preferredTransform)
        videoWriterInput.transform = transform

        if writer.canAdd(videoWriterInput) {
            writer.add(videoWriterInput)
        }

        // Audio writer input
        var audioWriterInput: AVAssetWriterInput?
        if let audioOutput = audioReaderOutput {
            let audioFormatHint = try await asset.loadTracks(withMediaType: .audio).first?
                .load(.formatDescriptions).first
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioOutputSettings,
                sourceFormatHint: audioFormatHint
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input
            }
        }

        // -- Start --
        guard reader.startReading() else {
            throw TranscodeError.readingFailed(reader.error)
        }
        guard writer.startWriting() else {
            throw TranscodeError.writingFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        // -- Transfer Samples --
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Video transfer
            group.addTask {
                await self.transferSamples(
                    from: videoReaderOutput,
                    to: videoWriterInput,
                    totalDuration: totalSeconds,
                    progressHandler: progressHandler
                )
            }

            // Audio transfer
            if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
                group.addTask {
                    await self.transferSamples(
                        from: audioOutput,
                        to: audioInput,
                        totalDuration: totalSeconds,
                        progressHandler: nil
                    )
                }
            }

            try await group.waitForAll()
        }

        // -- Finish --
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw TranscodeError.writingFailed(writer.error)
        }
    }

    /// Transfer samples from reader output to writer input
    private func transferSamples(
        from readerOutput: AVAssetReaderTrackOutput,
        to writerInput: AVAssetWriterInput,
        totalDuration: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.editor.transcode.\(writerInput.mediaType.rawValue)")

            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }

                    // Report progress based on presentation time
                    if let handler = progressHandler {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let progress = CMTimeGetSeconds(pts) / totalDuration
                        handler(min(progress, 1.0))
                    }

                    writerInput.append(sampleBuffer)
                }
            }
        }
    }
}
```

### Using with AVVideoComposition (for effects during export)

```swift
extension TranscodePipeline {

    /// Transcode with a video composition for applying effects
    func transcodeWithComposition(
        sourceURL: URL,
        outputURL: URL,
        videoComposition: AVVideoComposition
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)

        let reader = try AVAssetReader(asset: asset)

        // Use AVAssetReaderVideoCompositionOutput for composed output
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let compositionOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        compositionOutput.videoComposition = videoComposition

        if reader.canAdd(compositionOutput) {
            reader.add(compositionOutput)
        }

        // ... rest of pipeline similar to above
    }
}
```

---

## 4. VideoToolbox: Hardware-Accelerated Encoding

### VTCompressionSession - Complete Setup

```swift
import VideoToolbox
import CoreMedia
import CoreVideo

class HardwareEncoder {

    private var compressionSession: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private let codecType: CMVideoCodecType
    private let outputQueue = DispatchQueue(label: "com.editor.encoder.output")

    /// Callback for compressed output
    var onCompressedFrame: ((CMSampleBuffer) -> Void)?
    var onError: ((OSStatus) -> Void)?

    init(width: Int32, height: Int32, codec: CMVideoCodecType = kCMVideoCodecType_HEVC) {
        self.width = width
        self.height = height
        self.codecType = codec
    }

    /// Create and configure the compression session
    func prepare(
        requireHardware: Bool = false,
        preferHardware: Bool = true,
        realTime: Bool = false,
        bitRate: Int? = nil,
        frameRate: Double = 30.0,
        keyFrameInterval: Int = 60,
        profileLevel: CFString? = nil
    ) throws {

        // Encoder specification
        var encoderSpec: [CFString: Any] = [:]
        if requireHardware {
            encoderSpec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
        } else if preferHardware {
            encoderSpec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
        }

        // Create session with callback
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codecType,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let session = compressionSession else {
            throw VideoToolboxError.sessionCreationFailed(status)
        }

        // -- Configure Properties --

        // Profile Level
        if let profile = profileLevel {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
        } else {
            // Auto-select based on codec
            switch codecType {
            case kCMVideoCodecType_H264:
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                                     value: kVTProfileLevel_H264_High_AutoLevel)
            case kCMVideoCodecType_HEVC:
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                                     value: kVTProfileLevel_HEVC_Main_AutoLevel)
            default:
                break
            }
        }

        // Real-time encoding (for capture/streaming)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,
                             value: realTime as CFBoolean)

        // Bitrate
        if let bitRate = bitRate {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                                 value: bitRate as CFNumber)
            // Data rate limits: [bytes per second, duration in seconds]
            let limits = [bitRate / 8 * 2, 1] as CFArray // 2x burst allowed
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                                 value: limits)
        }

        // Key frame interval
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: keyFrameInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: (Double(keyFrameInterval) / frameRate) as CFNumber)

        // Frame rate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: frameRate as CFNumber)

        // Allow frame reordering (B-frames) for better compression
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: true as CFBoolean)

        // Entropy coding (H.264 only)
        if codecType == kCMVideoCodecType_H264 {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode,
                                 value: kVTH264EntropyMode_CABAC)
        }

        // Quality vs speed tradeoff (0.0 = faster, 1.0 = better quality)
        // Only used by software encoders
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality,
                             value: 0.8 as CFNumber)

        // Prepare the session
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    /// Encode a single frame
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, duration: CMTime) throws {
        guard let session = compressionSession else {
            throw VideoToolboxError.noSession
        }

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        guard status == noErr else {
            throw VideoToolboxError.encodingFailed(status)
        }
    }

    /// Force a keyframe on the next encode call
    func encodeKeyframe(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, duration: CMTime) throws {
        guard let session = compressionSession else {
            throw VideoToolboxError.noSession
        }

        let frameProperties: [CFString: Any] = [
            kVTEncodeFrameOptionKey_ForceKeyFrame: true
        ]

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: frameProperties as CFDictionary,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        guard status == noErr else {
            throw VideoToolboxError.encodingFailed(status)
        }
    }

    /// Flush all pending frames and complete encoding
    func finish() throws {
        guard let session = compressionSession else { return }

        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else {
            throw VideoToolboxError.flushFailed(status)
        }
    }

    /// Invalidate and tear down the session
    func invalidate() {
        guard let session = compressionSession else { return }
        VTCompressionSessionInvalidate(session)
        compressionSession = nil
    }

    deinit {
        invalidate()
    }

    // -- Output Callback (C function) --

    private static let compressionOutputCallback: VTCompressionOutputCallback = {
        outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in

        guard let refCon = outputCallbackRefCon else { return }
        let encoder: HardwareEncoder = Unmanaged.fromOpaque(refCon).takeUnretainedValue()

        guard status == noErr else {
            encoder.onError?(status)
            return
        }

        guard let sampleBuffer = sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        // Check if frame was dropped
        if infoFlags.contains(.frameDropped) {
            return
        }

        encoder.onCompressedFrame?(sampleBuffer)
    }
}

enum VideoToolboxError: Error {
    case sessionCreationFailed(OSStatus)
    case noSession
    case encodingFailed(OSStatus)
    case decodingFailed(OSStatus)
    case flushFailed(OSStatus)
}
```

### VTCompressionSession Property Reference

```swift
// -- Key VTCompressionSession Properties --

// Bitrate Control
kVTCompressionPropertyKey_AverageBitRate          // Average bitrate (bps)
kVTCompressionPropertyKey_DataRateLimits           // Hard limit [bytes/sec, period in sec]
kVTCompressionPropertyKey_Quality                  // 0.0-1.0, software encoder quality

// Frame Structure
kVTCompressionPropertyKey_MaxKeyFrameInterval      // Max frames between keyframes
kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration // Max seconds between keyframes
kVTCompressionPropertyKey_AllowFrameReordering     // Enable B-frames

// Rate Control
kVTCompressionPropertyKey_ExpectedFrameRate        // Expected input frame rate
kVTCompressionPropertyKey_RealTime                 // Optimize for real-time encoding

// Profile / Level
kVTCompressionPropertyKey_ProfileLevel             // Codec profile and level
kVTCompressionPropertyKey_H264EntropyMode          // CAVLC or CABAC (H.264)

// Hardware
kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder

// Color
kVTCompressionPropertyKey_ColorPrimaries
kVTCompressionPropertyKey_TransferFunction
kVTCompressionPropertyKey_YCbCrMatrix

// Advanced
kVTCompressionPropertyKey_MaxFrameDelayCount       // Max frames in encoder pipeline
kVTCompressionPropertyKey_AllowTemporalCompression // Enable inter-frame compression
kVTCompressionPropertyKey_PixelTransferProperties  // Pixel format conversion
```

### Hierarchical Encoding for High Frame Rate

```swift
/// Configure hierarchical encoding for 120fps content
/// Allows dropping to 60fps or 30fps by discarding temporal layers
func configureHierarchicalEncoding(session: VTCompressionSession, totalFPS: Double, baseFPS: Double) {
    VTSessionSetProperty(session,
                         key: kVTCompressionPropertyKey_BaseLayerFrameRate,
                         value: baseFPS as CFNumber)
    VTSessionSetProperty(session,
                         key: kVTCompressionPropertyKey_ExpectedFrameRate,
                         value: totalFPS as CFNumber)
}
// Usage: configureHierarchicalEncoding(session: s, totalFPS: 120, baseFPS: 30)
// Temporal layers: 30fps base -> 60fps -> 120fps
```

---

## 5. VideoToolbox: Hardware-Accelerated Decoding

### VTDecompressionSession Setup

```swift
import VideoToolbox

class HardwareDecoder {

    private var decompressionSession: VTDecompressionSession?
    private let outputQueue = DispatchQueue(label: "com.editor.decoder.output")

    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// Create a decompression session from a format description
    func prepare(formatDescription: CMFormatDescription) throws {

        // Decoder specification - prefer hardware
        let decoderSpec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]

        // Destination pixel buffer attributes
        let destinationAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:], // Enable IOSurface for Metal
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        // Callback record
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &decompressionSession
        )

        guard status == noErr, decompressionSession != nil else {
            throw VideoToolboxError.sessionCreationFailed(status)
        }
    }

    /// Decode a single compressed sample buffer
    func decode(sampleBuffer: CMSampleBuffer) throws {
        guard let session = decompressionSession else {
            throw VideoToolboxError.noSession
        }

        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        guard status == noErr else {
            throw VideoToolboxError.decodingFailed(status)
        }
    }

    /// Wait for all pending frames to complete
    func flush() {
        guard let session = decompressionSession else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    func invalidate() {
        guard let session = decompressionSession else { return }
        VTDecompressionSessionInvalidate(session)
        decompressionSession = nil
    }

    // -- Decompression Callback --

    private static let decompressionOutputCallback: VTDecompressionOutputCallback = {
        decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in

        guard status == noErr,
              let imageBuffer = imageBuffer,
              let refCon = decompressionOutputRefCon else {
            return
        }

        let decoder: HardwareDecoder = Unmanaged.fromOpaque(refCon).takeUnretainedValue()
        decoder.onDecodedFrame?(imageBuffer, presentationTimeStamp)
    }
}
```

### Using VTDecompressionSession with AVAssetReader

```swift
/// Decode video frames using hardware decoder via AVAssetReader
func decodeAsset(url: URL) async throws {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)

    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }

    // Read compressed samples (nil settings = no decompression)
    let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    if reader.canAdd(output) { reader.add(output) }

    guard reader.startReading() else { return }

    let decoder = HardwareDecoder()

    while let sampleBuffer = output.copyNextSampleBuffer() {
        // Get format description from first sample
        if decoder.decompressionSession == nil,
           let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            try decoder.prepare(formatDescription: formatDesc)
        }

        try decoder.decode(sampleBuffer: sampleBuffer)
    }

    decoder.flush()
}
```

---

## 6. Codec Support & Configuration

### H.264 (AVC)

```swift
// AVAssetWriter settings for H.264
let h264Settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 1920,
    AVVideoHeightKey: 1080,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 10_000_000,       // 10 Mbps
        AVVideoMaxKeyFrameIntervalKey: 60,            // keyframe every 2s at 30fps
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
        AVVideoExpectedSourceFrameRateKey: 30,
        AVVideoAllowFrameReorderingKey: true          // B-frames
    ] as [String: Any]
]

// VTCompressionSession codec type
let h264Codec = kCMVideoCodecType_H264
// Profiles: Baseline, Main, High
// kVTProfileLevel_H264_Baseline_AutoLevel
// kVTProfileLevel_H264_Main_AutoLevel
// kVTProfileLevel_H264_High_AutoLevel

// Quality/Size Tradeoffs (1080p @ 30fps):
// Low:    2-4 Mbps  (streaming, mobile)
// Medium: 5-10 Mbps (web, general use)
// High:   15-25 Mbps (broadcast quality)
// Max:    50+ Mbps (near-lossless)
```

### H.265 / HEVC

```swift
// AVAssetWriter settings for HEVC
let hevcSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: 3840,
    AVVideoHeightKey: 2160,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 20_000_000,        // 20 Mbps (comparable to H.264 @ 40 Mbps)
        AVVideoMaxKeyFrameIntervalKey: 120,
        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
        AVVideoExpectedSourceFrameRateKey: 30,
        AVVideoAllowFrameReorderingKey: true
    ] as [String: Any]
]

// HEVC 10-bit (for HDR)
let hevc10BitSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: 3840,
    AVVideoHeightKey: 2160,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 30_000_000,
        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
    ] as [String: Any]
]

// HEVC with Alpha channel
let hevcAlphaSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: 1920,
    AVVideoHeightKey: 1080,
    AVVideoCompressionPropertiesKey: [
        AVVideoQualityKey: 0.8
    ] as [String: Any]
]

// VTCompressionSession codec types
let hevcCodec = kCMVideoCodecType_HEVC
let hevcAlphaCodec = kCMVideoCodecType_HEVCWithAlpha

// Profiles:
// kVTProfileLevel_HEVC_Main_AutoLevel      (8-bit)
// kVTProfileLevel_HEVC_Main10_AutoLevel    (10-bit, HDR)

// Quality/Size Tradeoffs (4K @ 30fps):
// Low:    8-12 Mbps  (streaming)
// Medium: 15-25 Mbps (general distribution)
// High:   30-50 Mbps (high quality)
// Max:    80+ Mbps   (near master quality)

// Hardware encoding support:
// - iPhone 7+ (A10): 8-bit hardware encode
// - Mac 2017+ (6th gen Intel / Apple Silicon): 8-bit hardware encode
// - macOS software encoder: 10-bit encode (non-realtime)
// - Apple Silicon M1+: both 8-bit and 10-bit hardware encode
```

### Apple ProRes Family

```swift
// ProRes codec types
let proRes422Proxy  = kCMVideoCodecType_AppleProRes422Proxy    // 'ap4l' - ~45 Mbps @ 1080p/29.97
let proRes422LT     = kCMVideoCodecType_AppleProRes422LT       // 'ap4h' - ~102 Mbps @ 1080p/29.97
let proRes422       = kCMVideoCodecType_AppleProRes422          // 'apcn' - ~147 Mbps @ 1080p/29.97
let proRes422HQ     = kCMVideoCodecType_AppleProRes422HQ        // 'apch' - ~220 Mbps @ 1080p/29.97
let proRes4444      = kCMVideoCodecType_AppleProRes4444         // 'ap4h' - ~330 Mbps @ 1080p/29.97
let proRes4444XQ    = kCMVideoCodecType_AppleProRes4444XQ       // 'ap4x' - ~500 Mbps @ 1080p/29.97
let proResRAW       = kCMVideoCodecType_AppleProResRAW          // 'aprn'
let proResRAWHQ     = kCMVideoCodecType_AppleProResRAWHQ        // 'aprh'

// AVVideoCodecType equivalents (Swift-friendly)
// AVVideoCodecType.proRes422Proxy
// AVVideoCodecType.proRes422LT
// AVVideoCodecType.proRes422
// AVVideoCodecType.proRes422HQ
// AVVideoCodecType.proRes4444
// (check availability for newer variants)

// ProRes 422 export (standard professional intermediate)
let proRes422Settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes422,
    AVVideoWidthKey: 1920,
    AVVideoHeightKey: 1080
    // Note: ProRes does NOT use bitrate settings - quality is fixed per variant
    // The codec internally manages quality/data rate
]

// ProRes 4444 with alpha (VFX/compositing)
let proRes4444Settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes4444,
    AVVideoWidthKey: 3840,
    AVVideoHeightKey: 2160
]

// ProRes 422 HQ (mastering quality)
let proRes422HQSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes422HQ,
    AVVideoWidthKey: 7680,
    AVVideoHeightKey: 4320 // 8K
]

// ProRes Data Rate Reference Table (per variant @ 29.97fps):
//
// Variant          | 1080p    | 2K       | 4K       | 8K (est.)
// -----------------|----------|----------|----------|----------
// 422 Proxy        | 45 Mbps  | 50 Mbps  | 150 Mbps | ~600 Mbps
// 422 LT           | 102 Mbps | 113 Mbps | 340 Mbps | ~1.4 Gbps
// 422              | 147 Mbps | 162 Mbps | 471 Mbps | ~1.9 Gbps
// 422 HQ           | 220 Mbps | 243 Mbps | 707 Mbps | ~2.8 Gbps
// 4444             | 330 Mbps | 365 Mbps | 1.06 Gbps| ~4.2 Gbps
// 4444 XQ          | 500 Mbps | 553 Mbps | 1.6 Gbps | ~6.4 Gbps
//
// Key characteristics:
// - ProRes 422 variants: 4:2:2 chroma, 10-bit, no alpha
// - ProRes 4444/XQ: 4:4:4 chroma, up to 12-bit + 16-bit alpha
// - ProRes RAW: applied to raw sensor data, variable rate
// - All variants support all frame sizes and frame rates
// - Hardware encoding available on Apple Silicon (M1 Pro/Max and later)

// IMPORTANT: Pixel format considerations on Apple Silicon
// On M1 Pro/Max: use kCVPixelFormatType_64RGBALE for 16-bit
// AVOID kCVPixelFormatType_64ARGB on M1 Pro/Max (known crash bug)
// Safe universal format: kCVPixelFormatType_32BGRA for 8-bit workflows
```

### AV1

```swift
// AV1 Status on Apple platforms (as of 2025):
//
// DECODING:
// - Hardware decode: M3 chip and later, iPhone 15 Pro and later
// - Software decode: Available on older hardware via VTDecompressionSession
// - No special entitlement required
//
// ENCODING:
// - NO hardware AV1 encoding via VideoToolbox (as of macOS 15)
// - Software encoding possible via third-party libraries (libaom, SVT-AV1, rav1e)
// - May require bundling FFmpeg or similar for AV1 encoding
//
// For AV1 decode via VideoToolbox:
let av1Codec = kCMVideoCodecType_AV1  // Available on supported hardware

// For AV1 encoding, consider:
// 1. libsvtav1 (Intel SVT-AV1) - best speed/quality tradeoff
// 2. libaom (reference encoder) - best quality, slowest
// 3. rav1e (Rust-based) - good balance
// These would need to be integrated as external libraries

// Container support: AV1 works in MP4 (ISOBMFF) and MKV containers
```

### Codec Comparison Summary

```
Codec     | Compression | Quality  | HW Encode | HW Decode | Alpha | HDR  | Use Case
----------|-------------|----------|-----------|-----------|-------|------|------------------
H.264     | Good        | Good     | Yes       | Yes       | No    | No   | Universal delivery
HEVC      | Excellent   | Better   | Yes       | Yes       | Yes*  | Yes  | Modern delivery/HDR
ProRes422 | Low         | Excellent| Yes**     | Yes       | No    | Yes  | Professional editing
ProRes4444| Very Low    | Pristine | Yes**     | Yes       | Yes   | Yes  | VFX/Compositing
AV1       | Best        | Best     | No***     | Yes****   | Yes   | Yes  | Web/streaming

*  HEVC with Alpha variant
** Apple Silicon M1 Pro/Max and later
*** No hardware encoding on Apple platforms yet
**** M3+ hardware decode, software on older
```

---

## 7. Container Formats

### MOV (QuickTime Movie)

```swift
// MOV container - Apple's native format
let movWriter = try AVAssetWriter(outputURL: url, fileType: .mov) // AVFileType.mov

// Advantages:
// - Full ProRes support (all variants)
// - Full timecode track support
// - Alpha channel support (ProRes 4444, HEVC with Alpha)
// - Multiple audio tracks
// - Rich metadata (including chapter markers)
// - Edit lists for non-destructive trimming
// - Best choice for professional workflows on macOS

// Supported codecs in MOV:
// H.264, HEVC, HEVC with Alpha, ProRes (all), Motion JPEG, Apple Animation
```

### MP4 (MPEG-4 Part 14)

```swift
// MP4 container - universal format
let mp4Writer = try AVAssetWriter(outputURL: url, fileType: .mp4) // AVFileType.mp4

// Advantages:
// - Universal compatibility (all platforms, browsers, devices)
// - Streaming-optimized (faststart/moov atom at front)
// - Smaller overhead than MOV
// - Best choice for delivery/distribution

// Supported codecs in MP4:
// H.264, HEVC, AV1, AAC, AC-3, E-AC-3
// Note: ProRes in MP4 is technically possible but NOT recommended
```

### M4V (iTunes Video)

```swift
// M4V - Apple's variant of MP4
let m4vWriter = try AVAssetWriter(outputURL: url, fileType: .m4v) // AVFileType.m4v
// Essentially MP4 with Apple DRM support
```

### AVFileType Constants

```swift
// All available file types for AVAssetWriter
AVFileType.mov              // .mov - QuickTime Movie
AVFileType.mp4              // .mp4 - MPEG-4
AVFileType.m4v              // .m4v - iTunes Video
AVFileType.m4a              // .m4a - MPEG-4 Audio
AVFileType.caf              // .caf - Core Audio Format
AVFileType.wav              // .wav - WAVE Audio
AVFileType.aiff             // .aiff - AIFF Audio
AVFileType.aifc             // .aifc - AIFF-C Audio
AVFileType.amr              // .amr - Adaptive Multi-Rate
AVFileType.avci             // .avci - AVC Intra
AVFileType.heic             // .heic - HEIF Image
AVFileType.heif             // .heif - HEIF Image

// MKV (Matroska): NOT natively supported by AVAssetWriter
// For MKV output, you would need FFmpeg or a similar library
```

---

## 8. Resolution Handling (Up to 8K)

### Standard Resolutions

```swift
enum VideoResolution {
    case sd480p       // 720 x 480 (NTSC) or 720 x 576 (PAL)
    case hd720p       // 1280 x 720
    case fullHD1080p  // 1920 x 1080
    case dci2K        // 2048 x 1080
    case qhd1440p     // 2560 x 1440
    case uhd4K        // 3840 x 2160
    case dci4K        // 4096 x 2160
    case uhd8K        // 7680 x 4320
    case dci8K        // 8192 x 4320

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .sd480p:       return (720, 480)
        case .hd720p:       return (1280, 720)
        case .fullHD1080p:  return (1920, 1080)
        case .dci2K:        return (2048, 1080)
        case .qhd1440p:     return (2560, 1440)
        case .uhd4K:        return (3840, 2160)
        case .dci4K:        return (4096, 2160)
        case .uhd8K:        return (7680, 4320)
        case .dci8K:        return (8192, 4320)
        }
    }

    /// Suggested bitrate ranges for H.264 (in bps)
    var h264BitRateRange: ClosedRange<Int> {
        switch self {
        case .sd480p:       return 1_500_000...5_000_000
        case .hd720p:       return 3_000_000...8_000_000
        case .fullHD1080p:  return 5_000_000...20_000_000
        case .dci2K:        return 8_000_000...25_000_000
        case .qhd1440p:     return 10_000_000...30_000_000
        case .uhd4K:        return 20_000_000...80_000_000
        case .dci4K:        return 25_000_000...100_000_000
        case .uhd8K:        return 80_000_000...300_000_000
        case .dci8K:        return 100_000_000...400_000_000
        }
    }

    /// Suggested bitrate for HEVC (roughly 50-60% of H.264 for same quality)
    var hevcBitRateRange: ClosedRange<Int> {
        let h264 = h264BitRateRange
        return (h264.lowerBound * 50 / 100)...(h264.upperBound * 60 / 100)
    }
}
```

### 8K Considerations

```swift
// 8K export considerations:
//
// 1. MEMORY: A single 8K BGRA frame = 7680 * 4320 * 4 bytes = ~127 MB
//    - Use pixel buffer pools to reduce allocation overhead
//    - Process frames sequentially, not buffered
//    - Consider using YUV (4:2:0) to reduce to ~47 MB per frame
//
// 2. CODEC SUPPORT:
//    - H.264: Technically supports 8K but not practical (Level 6.2)
//    - HEVC: Native 8K support (Level 6.1/6.2), recommended
//    - ProRes: Supports 8K on Apple Silicon
//    - AV1: Supports 8K but no HW encode on Apple
//
// 3. HARDWARE:
//    - Apple Silicon M1 Pro+ recommended for 8K encode
//    - Hardware HEVC encoder may have resolution limits
//    - ProRes hardware encode on M1 Pro/Max supports 8K
//    - Ensure sufficient unified memory (32GB+ recommended)
//
// 4. STORAGE:
//    - 8K ProRes 422 HQ @ 30fps = ~2.8 Gbps = ~21 GB/minute
//    - 8K HEVC @ 30fps high quality = ~150 Mbps = ~1.1 GB/minute
//    - Use NVMe SSD for write speeds (>2 GB/s)

// Check hardware encoder limits
func queryEncoderCapabilities(codec: CMVideoCodecType) {
    let encoderList = VTCopyVideoEncoderList(nil, nil)
    // Enumerate to find max supported resolution per encoder
}
```

---

## 9. Frame Rate Handling

### CMTime Representations for Standard Frame Rates

```swift
import CoreMedia

enum StandardFrameRate: Double, CaseIterable {
    case fps23_976 = 23.976  // Film (NTSC pulldown)
    case fps24     = 24.0    // Cinema
    case fps25     = 25.0    // PAL broadcast
    case fps29_97  = 29.97   // NTSC broadcast
    case fps30     = 30.0    // Web/digital
    case fps48     = 48.0    // HFR cinema
    case fps50     = 50.0    // PAL interlaced as progressive
    case fps59_94  = 59.94   // NTSC progressive
    case fps60     = 60.0    // High frame rate
    case fps120    = 120.0   // Ultra HFR

    /// Precise CMTime frame duration (avoids floating-point errors)
    var frameDuration: CMTime {
        switch self {
        case .fps23_976: return CMTime(value: 1001, timescale: 24000)
        case .fps24:     return CMTime(value: 1, timescale: 24)
        case .fps25:     return CMTime(value: 1, timescale: 25)
        case .fps29_97:  return CMTime(value: 1001, timescale: 30000)
        case .fps30:     return CMTime(value: 1, timescale: 30)
        case .fps48:     return CMTime(value: 1, timescale: 48)
        case .fps50:     return CMTime(value: 1, timescale: 50)
        case .fps59_94:  return CMTime(value: 1001, timescale: 60000)
        case .fps60:     return CMTime(value: 1, timescale: 60)
        case .fps120:    return CMTime(value: 1, timescale: 120)
        }
    }

    /// Timescale that allows exact representation of this frame rate
    /// CRITICAL: Use high timescales for NTSC rates to avoid drift
    var optimalTimescale: CMTimeScale {
        switch self {
        case .fps23_976: return 24000  // 1001/24000 per frame
        case .fps29_97:  return 30000  // 1001/30000 per frame
        case .fps59_94:  return 60000  // 1001/60000 per frame
        default:         return CMTimeScale(rawValue * 1000)
        }
    }

    /// Whether this is a "drop frame" rate (NTSC-derived)
    var isDropFrame: Bool {
        switch self {
        case .fps23_976, .fps29_97, .fps59_94: return true
        default: return false
        }
    }

    /// Presentation time for frame N
    func presentationTime(forFrame frame: Int64) -> CMTime {
        return CMTime(
            value: frame * frameDuration.value,
            timescale: frameDuration.timescale
        )
    }
}

// CRITICAL: The 1001/30000 representation for 29.97fps
// Using value: 1, timescale: 30 would SILENTLY give you 30fps, not 29.97!
// Always use the 1001-based timescale for NTSC rates.

// Example: Generate presentation times for 29.97fps
let fps = StandardFrameRate.fps29_97
for frame in 0..<100 {
    let pts = fps.presentationTime(forFrame: Int64(frame))
    // pts.value = frame * 1001, pts.timescale = 30000
}
```

### Frame Rate Conversion

```swift
/// Timecode conversion utilities
struct TimecodeUtils {

    /// Convert seconds to SMPTE timecode string
    static func timecodeString(seconds: Double, frameRate: StandardFrameRate) -> String {
        let totalFrames = Int(seconds * frameRate.rawValue)
        let fps = Int(frameRate.rawValue.rounded(.up))

        let hours = totalFrames / (fps * 3600)
        let minutes = (totalFrames / (fps * 60)) % 60
        let secs = (totalFrames / fps) % 60
        let frames = totalFrames % fps

        let separator = frameRate.isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, secs, separator, frames)
    }
}
```

---

## 10. HDR & Wide Color Gamut Export

### HEVC HDR Export Configuration

```swift
/// Configure AVAssetWriter for HDR (HLG or HDR10) output
func configureHDRExport(
    outputURL: URL,
    width: Int,
    height: Int,
    hdrType: HDRType = .hlg
) throws -> AVAssetWriter {

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

    // Color properties depend on HDR format
    var colorProperties: [String: Any]

    switch hdrType {
    case .hlg:
        colorProperties = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
        ]
    case .hdr10:
        colorProperties = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
        ]
    case .sdr:
        colorProperties = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]
    }

    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: colorProperties,
        AVVideoCompressionPropertiesKey: [
            // MUST use Main10 profile for HDR
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
            AVVideoAverageBitRateKey: 40_000_000 // Higher bitrate for HDR
        ] as [String: Any]
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)

    // Use 10-bit pixel format for HDR
    let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: pixelBufferAttributes
    )

    if writer.canAdd(input) { writer.add(input) }

    return writer
}

enum HDRType {
    case sdr
    case hlg    // Hybrid Log-Gamma (backward compatible)
    case hdr10  // PQ transfer function
}

// Pixel formats for HDR:
// kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange  (10-bit YUV 4:2:0)
// kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange  (10-bit YUV 4:2:2)
// kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange  (10-bit YUV 4:4:4)
// kCVPixelFormatType_ARGB2101010LEPacked             (10-bit ARGB packed)
```

---

## 11. Render Queue Management

### Architecture for a Professional Render Queue

```swift
import Foundation
import Combine

/// Represents a single render job
struct RenderJob: Identifiable, Sendable {
    let id: UUID
    let name: String
    let sourceTimeline: TimelineReference  // Reference to timeline to render
    let outputURL: URL
    let outputSettings: ExportSettings
    let priority: RenderPriority
    let createdAt: Date

    enum RenderPriority: Int, Comparable, Sendable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

struct TimelineReference: Sendable {
    let id: UUID
}

/// Status of a render job
enum RenderJobStatus: Sendable {
    case queued
    case preparing
    case rendering(progress: Double)
    case paused(progress: Double)
    case completed(outputURL: URL, duration: TimeInterval)
    case failed(Error)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .rendering: return true
        default: return false
        }
    }
}

/// Manages a queue of render jobs
@MainActor
class RenderQueueManager: ObservableObject {

    @Published private(set) var jobs: [RenderJob] = []
    @Published private(set) var jobStatuses: [UUID: RenderJobStatus] = [:]
    @Published private(set) var isProcessing = false

    private var activeTask: Task<Void, Never>?
    private let maxConcurrentJobs: Int
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(maxConcurrentJobs: Int = 1) {
        self.maxConcurrentJobs = maxConcurrentJobs
    }

    /// Add a job to the render queue
    func enqueue(_ job: RenderJob) {
        jobs.append(job)
        jobStatuses[job.id] = .queued
        processQueueIfNeeded()
    }

    /// Remove a queued job
    func remove(_ jobID: UUID) {
        if case .queued = jobStatuses[jobID] {
            jobs.removeAll { $0.id == jobID }
            jobStatuses.removeValue(forKey: jobID)
        }
    }

    /// Cancel an active or queued job
    func cancel(_ jobID: UUID) {
        activeTasks[jobID]?.cancel()
        activeTasks.removeValue(forKey: jobID)
        jobStatuses[jobID] = .cancelled
    }

    /// Reorder job in queue
    func moveJob(from source: IndexSet, to destination: Int) {
        jobs.move(fromOffsets: source, toOffset: destination)
    }

    /// Process the next jobs in the queue
    private func processQueueIfNeeded() {
        let activeCount = activeTasks.count
        guard activeCount < maxConcurrentJobs else { return }

        let slotsAvailable = maxConcurrentJobs - activeCount
        let queuedJobs = jobs.filter { jobStatuses[$0.id] == .queued }
            .sorted { $0.priority > $1.priority }
            .prefix(slotsAvailable)

        for job in queuedJobs {
            let task = Task {
                await processJob(job)
                activeTasks.removeValue(forKey: job.id)
                processQueueIfNeeded()
            }
            activeTasks[job.id] = task
        }

        isProcessing = !activeTasks.isEmpty
    }

    /// Process a single render job
    private func processJob(_ job: RenderJob) async {
        jobStatuses[job.id] = .preparing

        let startTime = Date()

        do {
            // Set up the export pipeline
            let exporter = try await createExporter(for: job)

            jobStatuses[job.id] = .rendering(progress: 0)

            // Run the export with progress
            try await exporter.export { [weak self] progress in
                Task { @MainActor in
                    self?.jobStatuses[job.id] = .rendering(progress: progress)
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            jobStatuses[job.id] = .completed(outputURL: job.outputURL, duration: duration)

        } catch is CancellationError {
            jobStatuses[job.id] = .cancelled
        } catch {
            jobStatuses[job.id] = .failed(error)
        }
    }

    private func createExporter(for job: RenderJob) async throws -> TimelineExporter {
        // Create appropriate exporter based on job settings
        return try TimelineExporter(job: job)
    }
}

// Placeholder for the actual exporter
struct TimelineExporter {
    init(job: RenderJob) throws {}
    func export(progressHandler: @escaping (Double) -> Void) async throws {}
}

struct ExportSettings: Sendable {
    let codec: ExportCodec
    let resolution: VideoResolution
    let frameRate: StandardFrameRate
    let bitRate: Int?
    let fileType: AVFileType
    let audioCodec: AudioCodec
    let audioBitRate: Int

    enum ExportCodec: Sendable {
        case h264
        case hevc
        case hevc10Bit
        case proRes422
        case proRes422HQ
        case proRes4444
    }

    enum AudioCodec: Sendable {
        case aac
        case lpcm
        case alac
    }
}
```

---

## 12. Background Rendering

### Running Export in Background Thread

```swift
import Foundation

/// Background render manager that doesn't block the main thread
actor BackgroundRenderEngine {

    private var activeRenders: [UUID: Task<URL, Error>] = [:]

    /// Start a background render, returns immediately
    func startRender(
        job: RenderJob,
        renderFrame: @escaping @Sendable (CMTime) -> CVPixelBuffer?
    ) -> Task<URL, Error> {

        let task = Task.detached(priority: .userInitiated) { [job] in
            try Task.checkCancellation()

            let exporter = VideoAudioExporter()
            let settings = job.outputSettings
            let dims = settings.resolution.dimensions

            try exporter.setup(
                outputURL: job.outputURL,
                fileType: settings.fileType,
                width: dims.width,
                height: dims.height,
                frameRate: settings.frameRate.rawValue
            )

            try await exporter.exportTimeline(
                duration: CMTime(seconds: 60, preferredTimescale: 600), // from timeline
                frameRate: settings.frameRate.rawValue,
                renderFrame: renderFrame,
                progressHandler: { progress in
                    // Update UI on main thread
                    NotificationCenter.default.post(
                        name: .renderProgressUpdated,
                        object: nil,
                        userInfo: ["jobID": job.id, "progress": progress]
                    )
                }
            )

            return job.outputURL
        }

        activeRenders[job.id] = task
        return task
    }

    func cancelRender(jobID: UUID) {
        activeRenders[jobID]?.cancel()
        activeRenders.removeValue(forKey: jobID)
    }
}

extension Notification.Name {
    static let renderProgressUpdated = Notification.Name("renderProgressUpdated")
}
```

### Process Priority Management

```swift
import Foundation

/// Manages system resource allocation for background renders
class RenderResourceManager {

    /// Set process priority for render tasks
    static func configureForBackgroundRender() {
        // Use QoS to manage priority
        // .userInitiated for foreground renders
        // .utility for background renders (allows system to throttle)
        // .background for overnight batch renders
    }

    /// Check available system resources before starting render
    static func canStartRender(estimatedMemoryMB: Int) -> Bool {
        let info = ProcessInfo.processInfo
        let availableMemory = info.physicalMemory
        let estimatedBytes = UInt64(estimatedMemoryMB) * 1024 * 1024

        // Leave at least 4GB for system + app
        let reservedBytes: UInt64 = 4 * 1024 * 1024 * 1024
        return estimatedBytes < (availableMemory - reservedBytes)
    }

    /// Estimate memory needed for a render
    static func estimateMemoryMB(width: Int, height: Int, bufferCount: Int = 3) -> Int {
        let bytesPerFrame = width * height * 4 // BGRA
        let totalBytes = bytesPerFrame * bufferCount
        return totalBytes / (1024 * 1024)
    }
}
```

---

## 13. Progress Reporting

### Modern Async Progress Reporting

```swift
import Foundation

/// Progress reporting using AsyncStream
struct ExportProgress: Sendable {
    let framesCompleted: Int
    let totalFrames: Int
    let currentTime: CMTime
    let estimatedTimeRemaining: TimeInterval?

    var fraction: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(framesCompleted) / Double(totalFrames)
    }

    var percentString: String {
        String(format: "%.1f%%", fraction * 100)
    }
}

/// Export with AsyncStream-based progress
func exportWithProgress(
    outputURL: URL,
    settings: ExportSettings
) -> (task: Task<URL, Error>, progress: AsyncStream<ExportProgress>) {

    let (stream, continuation) = AsyncStream.makeStream(of: ExportProgress.self)

    let task = Task<URL, Error> {
        defer { continuation.finish() }

        // ... setup writer, reader ...

        let totalFrames = 1000 // calculated from duration * frameRate
        var startTime = Date()

        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()

            // Render and write frame...

            // Calculate ETA
            let elapsed = Date().timeIntervalSince(startTime)
            let framesPerSecond = Double(frameIndex + 1) / elapsed
            let remainingFrames = totalFrames - frameIndex - 1
            let eta = framesPerSecond > 0 ? Double(remainingFrames) / framesPerSecond : nil

            let progress = ExportProgress(
                framesCompleted: frameIndex + 1,
                totalFrames: totalFrames,
                currentTime: CMTime(value: Int64(frameIndex), timescale: 30),
                estimatedTimeRemaining: eta
            )

            // Only report at meaningful intervals (every 1%)
            if frameIndex % max(1, totalFrames / 100) == 0 {
                continuation.yield(progress)
            }
        }

        return outputURL
    }

    return (task, stream)
}

// Usage:
// let (exportTask, progressStream) = exportWithProgress(...)
// for await progress in progressStream {
//     updateUI(progress: progress.fraction)
//     updateETA(progress.estimatedTimeRemaining)
// }
// let outputURL = try await exportTask.value
```

### AVAssetExportSession Progress Monitoring

```swift
/// Monitor AVAssetExportSession progress with a timer
func monitorExportProgress(session: AVAssetExportSession) -> AsyncStream<Float> {
    AsyncStream { continuation in
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            continuation.yield(session.progress)

            switch session.status {
            case .completed, .failed, .cancelled:
                continuation.finish()
            default:
                break
            }
        }

        continuation.onTermination = { _ in
            timer.invalidate()
        }
    }
}
```

---

## 14. Proxy Workflow

### Proxy Generation and Management

```swift
import AVFoundation

/// Manages proxy media generation and conforming
class ProxyManager {

    /// Proxy resolution options
    enum ProxyQuality {
        case quarter    // 1/4 resolution
        case half       // 1/2 resolution
        case custom(width: Int, height: Int)

        func dimensions(from original: CGSize) -> (width: Int, height: Int) {
            switch self {
            case .quarter:
                return (Int(original.width) / 4, Int(original.height) / 4)
            case .half:
                return (Int(original.width) / 2, Int(original.height) / 2)
            case .custom(let w, let h):
                return (w, h)
            }
        }
    }

    /// Generate a proxy file from a full-resolution source
    func generateProxy(
        sourceURL: URL,
        proxyURL: URL,
        quality: ProxyQuality = .half,
        progressHandler: @escaping (Double) -> Void
    ) async throws {

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProxyError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let dims = quality.dimensions(from: naturalSize)

        // Use low bitrate H.264 for proxy (small files, fast decode)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dims.width,
            AVVideoHeightKey: dims.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000, // 2 Mbps - lightweight
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 15 // frequent keyframes for scrubbing
            ] as [String: Any]
        ]

        // AAC audio at reduced bitrate
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]

        let pipeline = TranscodePipeline()
        try await pipeline.transcode(
            sourceURL: sourceURL,
            outputURL: proxyURL,
            outputFileType: .mp4,
            videoOutputSettings: videoSettings,
            audioOutputSettings: audioSettings,
            progressHandler: progressHandler
        )
    }

    /// Generate proxies for all clips in a project
    func generateProxies(
        for clips: [MediaClip],
        proxyDirectory: URL,
        quality: ProxyQuality = .half
    ) async throws -> [UUID: URL] {

        var proxyMap: [UUID: URL] = [:]

        // Process in parallel with limited concurrency
        try await withThrowingTaskGroup(of: (UUID, URL).self) { group in
            // Limit concurrent proxy generation to avoid memory pressure
            let maxConcurrent = min(ProcessInfo.processInfo.activeProcessorCount, 4)
            var pending = clips.makeIterator()
            var inFlight = 0

            // Seed the group
            for _ in 0..<maxConcurrent {
                guard let clip = pending.next() else { break }
                inFlight += 1
                group.addTask {
                    let proxyURL = proxyDirectory.appendingPathComponent("\(clip.id)_proxy.mp4")
                    try await self.generateProxy(
                        sourceURL: clip.sourceURL,
                        proxyURL: proxyURL,
                        quality: quality,
                        progressHandler: { _ in }
                    )
                    return (clip.id, proxyURL)
                }
            }

            // Process results and add more tasks
            for try await (clipID, proxyURL) in group {
                proxyMap[clipID] = proxyURL
                inFlight -= 1

                if let clip = pending.next() {
                    inFlight += 1
                    group.addTask {
                        let url = proxyDirectory.appendingPathComponent("\(clip.id)_proxy.mp4")
                        try await self.generateProxy(
                            sourceURL: clip.sourceURL,
                            proxyURL: url,
                            quality: quality,
                            progressHandler: { _ in }
                        )
                        return (clip.id, url)
                    }
                }
            }
        }

        return proxyMap
    }
}

struct MediaClip: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
}

enum ProxyError: Error {
    case noVideoTrack
    case generationFailed
}

/// Media resolver that switches between proxy and full-res
class MediaResolver {

    enum MediaMode {
        case proxy      // Use proxy files for editing
        case fullRes    // Use original files for export
        case optimized  // Use optimized media (intermediate codec)
    }

    var currentMode: MediaMode = .proxy
    private var proxyMap: [UUID: URL] = [:]
    private var originalMap: [UUID: URL] = [:]

    /// Resolve the appropriate media URL for a clip
    func resolveURL(for clipID: UUID) -> URL? {
        switch currentMode {
        case .proxy:
            return proxyMap[clipID] ?? originalMap[clipID]
        case .fullRes, .optimized:
            return originalMap[clipID]
        }
    }

    /// Switch mode (e.g., proxy for editing, fullRes for export)
    func setMode(_ mode: MediaMode) {
        currentMode = mode
    }
}
```

---

## 15. Smart Rendering

### Partial Re-encode Strategy

```swift
import AVFoundation

/// Smart rendering: only re-encode segments that have been modified
class SmartRenderer {

    /// Segment of a timeline that may or may not need re-encoding
    struct TimelineSegment {
        let timeRange: CMTimeRange
        let needsReencoding: Bool   // true if effects/transitions applied
        let sourceAsset: AVAsset?   // original asset for passthrough
        let sourceTimeRange: CMTimeRange? // range within source for passthrough
    }

    /// Analyze timeline to determine which segments need re-encoding
    func analyzeTimeline(clips: [TimelineClip]) -> [TimelineSegment] {
        var segments: [TimelineSegment] = []

        for clip in clips {
            if clip.hasEffects || clip.hasColorCorrection || clip.hasSpeedChange {
                // This segment needs full re-encoding
                segments.append(TimelineSegment(
                    timeRange: clip.timelineRange,
                    needsReencoding: true,
                    sourceAsset: nil,
                    sourceTimeRange: nil
                ))
            } else if clip.isTransitionBoundary {
                // Transition frames need re-encoding
                segments.append(TimelineSegment(
                    timeRange: clip.transitionRange,
                    needsReencoding: true,
                    sourceAsset: nil,
                    sourceTimeRange: nil
                ))
                // Non-transition portion can be passthrough
                segments.append(TimelineSegment(
                    timeRange: clip.nonTransitionRange,
                    needsReencoding: false,
                    sourceAsset: clip.sourceAsset,
                    sourceTimeRange: clip.sourceRange
                ))
            } else {
                // Untouched clip - passthrough (no re-encoding!)
                segments.append(TimelineSegment(
                    timeRange: clip.timelineRange,
                    needsReencoding: false,
                    sourceAsset: clip.sourceAsset,
                    sourceTimeRange: clip.sourceRange
                ))
            }
        }

        return segments
    }

    /// Export using smart rendering
    /// Passthrough segments are copied without re-encoding
    /// Modified segments are fully rendered
    func smartExport(
        segments: [TimelineSegment],
        outputURL: URL,
        renderFrame: @escaping (CMTime) -> CVPixelBuffer?
    ) async throws {

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // For passthrough segments, use nil outputSettings
        // For re-encode segments, use configured settings

        // Strategy 1: Use AVMutableComposition for passthrough,
        // then stitch with re-encoded segments

        // Strategy 2: Use AVAssetWriter with two inputs:
        // - Passthrough input (nil settings) for unmodified segments
        // - Encoded input (with settings) for modified segments

        // NOTE: In practice, smart rendering requires:
        // 1. Codec compatibility (source codec must match output)
        // 2. GOP boundary alignment (must cut at keyframes)
        // 3. Careful timestamp management at stitch points

        // The simplest approach is AVMutableComposition:
        let composition = AVMutableComposition()

        for segment in segments where !segment.needsReencoding {
            if let asset = segment.sourceAsset,
               let sourceRange = segment.sourceTimeRange {
                // Add passthrough segment to composition
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let compTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    try compTrack?.insertTimeRange(sourceRange, of: track, at: segment.timeRange.start)
                }
            }
        }

        // Then export the composition with passthrough for unmodified
        // and custom rendering for modified segments
    }
}

struct TimelineClip {
    let timelineRange: CMTimeRange
    let sourceAsset: AVAsset
    let sourceRange: CMTimeRange
    let hasEffects: Bool
    let hasColorCorrection: Bool
    let hasSpeedChange: Bool
    let isTransitionBoundary: Bool
    var transitionRange: CMTimeRange { .zero } // simplified
    var nonTransitionRange: CMTimeRange { timelineRange } // simplified
}
```

---

## 16. Batch Export

### Multiple Format Export

```swift
import AVFoundation

/// Export preset for batch processing
struct ExportPreset: Identifiable, Sendable {
    let id: UUID
    let name: String
    let codec: AVVideoCodecType
    let fileType: AVFileType
    let width: Int
    let height: Int
    let bitRate: Int
    let frameRate: Double
    let audioSettings: [String: Any]

    // Common presets
    static let youtube4K = ExportPreset(
        id: UUID(), name: "YouTube 4K",
        codec: .hevc, fileType: .mp4,
        width: 3840, height: 2160,
        bitRate: 40_000_000, frameRate: 30,
        audioSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000
        ]
    )

    static let youtube1080p = ExportPreset(
        id: UUID(), name: "YouTube 1080p",
        codec: .h264, fileType: .mp4,
        width: 1920, height: 1080,
        bitRate: 12_000_000, frameRate: 30,
        audioSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
    )

    static let proResArchive = ExportPreset(
        id: UUID(), name: "ProRes 422 HQ Archive",
        codec: .proRes422HQ, fileType: .mov,
        width: 3840, height: 2160,
        bitRate: 0, frameRate: 24, // ProRes ignores bitrate
        audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    )

    static let socialMediaVertical = ExportPreset(
        id: UUID(), name: "Social Media (9:16)",
        codec: .h264, fileType: .mp4,
        width: 1080, height: 1920,
        bitRate: 8_000_000, frameRate: 30,
        audioSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
    )
}

/// Batch export manager
actor BatchExporter {

    struct BatchResult: Sendable {
        let presetName: String
        let outputURL: URL
        let success: Bool
        let error: Error?
        let duration: TimeInterval
        let fileSize: UInt64
    }

    /// Export to multiple formats from a single source
    func batchExport(
        sourceURL: URL,
        presets: [ExportPreset],
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (String, Double) -> Void
    ) async throws -> [BatchResult] {

        var results: [BatchResult] = []

        // Process sequentially to avoid memory pressure
        // (each export uses significant memory)
        for preset in presets {
            let startTime = Date()
            let fileName = "\(preset.name).\(preset.fileType == .mov ? "mov" : "mp4")"
            let outputURL = outputDirectory.appendingPathComponent(fileName)

            do {
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: preset.codec,
                    AVVideoWidthKey: preset.width,
                    AVVideoHeightKey: preset.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: preset.bitRate
                    ] as [String: Any]
                ]

                let pipeline = TranscodePipeline()
                try await pipeline.transcode(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    outputFileType: preset.fileType,
                    videoOutputSettings: videoSettings,
                    audioOutputSettings: preset.audioSettings,
                    progressHandler: { progress in
                        progressHandler(preset.name, progress)
                    }
                )

                let fileSize = try FileManager.default.attributesOfItem(
                    atPath: outputURL.path
                )[.size] as? UInt64 ?? 0

                results.append(BatchResult(
                    presetName: preset.name,
                    outputURL: outputURL,
                    success: true,
                    error: nil,
                    duration: Date().timeIntervalSince(startTime),
                    fileSize: fileSize
                ))

            } catch {
                results.append(BatchResult(
                    presetName: preset.name,
                    outputURL: outputURL,
                    success: false,
                    error: error,
                    duration: Date().timeIntervalSince(startTime),
                    fileSize: 0
                ))
            }
        }

        return results
    }
}
```

---

## 17. Custom Video Compositor

### AVVideoCompositing Protocol Implementation

```swift
import AVFoundation
import CoreImage

/// Custom compositor for applying effects during export
class NLEVideoCompositor: NSObject, AVVideoCompositing {

    // Required pixel format(s)
    var sourcePixelBufferAttributes: [String: Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
    }

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Get the instruction (custom subclass)
        guard let instruction = request.videoCompositionInstruction as? NLECompositionInstruction else {
            request.finish(with: NSError(domain: "NLECompositor", code: -1))
            return
        }

        // Create output pixel buffer
        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(with: NSError(domain: "NLECompositor", code: -2))
            return
        }

        // Get source frames
        var sourceImages: [CIImage] = []
        for trackID in request.sourceTrackIDs {
            if let sourceBuffer = request.sourceFrame(byTrackID: trackID.int32Value) {
                let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
                sourceImages.append(ciImage)
            }
        }

        // Apply effects from instruction
        guard var composited = sourceImages.first else {
            request.finish(with: outputBuffer)
            return
        }

        // Apply filters
        for effect in instruction.effects {
            composited = effect.apply(to: composited, at: request.compositionTime)
        }

        // Render to output buffer
        ciContext.render(composited, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Handle cancellation
    }
}

/// Custom instruction carrying effect information
class NLECompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = true
    var containsTweening: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let effects: [VideoEffect]

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], effects: [VideoEffect]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.effects = effects
    }
}

protocol VideoEffect {
    func apply(to image: CIImage, at time: CMTime) -> CIImage
}
```

---

## 18. Open-Source Libraries

### NextLevelSessionExporter
- **URL**: https://github.com/NextLevel/NextLevelSessionExporter
- **Purpose**: Drop-in replacement for AVAssetExportSession with full codec control
- **Features**: Swift 6 concurrency, HDR support, async/await API, progress reporting
- **Use case**: When you need AVAssetExportSession convenience with AVAssetWriter control

### VideoToolboxH265Encoder
- **URL**: https://github.com/zf3/VideoToolboxH265Encoder
- **Purpose**: Example of VTCompressionSession for H.264/HEVC encoding
- **Features**: Camera capture, NAL unit parsing, VPS/SPS/PPS extraction
- **Use case**: Reference for VideoToolbox compression session setup

### Transcoding (finnvoor)
- **URL**: https://github.com/finnvoor/Transcoding
- **Purpose**: Simple video transcoding library wrapping VideoToolbox
- **Features**: VideoEncoder class for CMSampleBuffer encoding

### TimecodeKit
- **URL**: https://github.com/orchetect/TimecodeKit
- **Purpose**: SMPTE timecode library for Swift
- **Features**: Frame rate handling, drop-frame timecode, timecode arithmetic
- **Use case**: Professional timecode management in NLE

### OpenTimelineIO-AVFoundation
- **URL**: https://github.com/Synopsis/OpenTimelineIO-AVFoundation
- **Purpose**: Bridge between OpenTimelineIO and AVFoundation/CoreMedia
- **Use case**: Timeline interchange format support

---

## 19. WWDC Sessions Reference

| Year | Session | Title | Key Topics |
|------|---------|-------|------------|
| 2014 | 513 | Direct Access to Video Encoding and Decoding | VTCompressionSession, VTDecompressionSession basics |
| 2017 | 511 | Working with HEIF and HEVC | HEVC encoding/decoding, hardware support, presets |
| 2019 | 506 | HEVC Video with Alpha | Alpha channel in HEVC, compositing workflows |
| 2020 | 10010 | Export HDR Media with AVFoundation | HDR export, color properties, 10-bit HEVC |
| 2020 | 10090 | Decode ProRes with AVFoundation and VideoToolbox | ProRes decode pipeline, optimal graphics pipeline |
| 2021 | 10146 | What's New in AVFoundation | Async APIs, modern AVFoundation patterns |
| 2021 | 10158 | Explore Low-Latency Video Encoding | Low-latency VideoToolbox encoding, real-time |

---

## 20. Architecture Recommendations for NLE Export System

### Recommended Export Pipeline Architecture

```
Timeline Model
     |
     v
+------------------+
| Render Scheduler |  <-- Manages render queue, priorities
+------------------+
     |
     v
+------------------+
| Frame Renderer   |  <-- Metal-based compositor
| (per-frame)      |     Applies effects, transitions, color
+------------------+
     |
     v
+------------------+
| Pixel Buffer     |  <-- CVPixelBufferPool for efficiency
| Management       |     IOSurface-backed for Metal compat
+------------------+
     |
     +-----> [AVAssetWriter Path]         -- For file-based export
     |       - AVAssetWriterInput
     |       - AVAssetWriterInputPixelBufferAdaptor
     |
     +-----> [VTCompressionSession Path]  -- For streaming/custom encoding
              - Hardware-accelerated encode
              - NAL unit output for network streaming
```

### Key Design Principles

1. **Separate render and encode**: The frame rendering (Metal compositor) should be completely separate from the encoding step. This allows swapping encoders without changing the render pipeline.

2. **Use pixel buffer pools**: Always use `CVPixelBufferPool` (from the adaptor or manual) to avoid per-frame allocation overhead. For 4K+, allocation time matters.

3. **IOSurface-backed buffers**: Set `kCVPixelBufferIOSurfacePropertiesKey` so Metal can render directly to the buffer without copies.

4. **Prefer AVAssetWriter for NLE export**: VideoToolbox `VTCompressionSession` is for streaming or when you need raw NAL units. For file-based export, AVAssetWriter internally uses VideoToolbox anyway and handles container writing.

5. **Smart rendering as optimization**: Implement passthrough for unmodified segments. This can reduce export time by 80%+ for minor edits.

6. **Proxy-first workflow**: Always generate proxies on import. Edit with proxies, export with originals. This makes the editing experience smooth regardless of source resolution.

7. **Background processing**: Use `Task.detached(priority: .userInitiated)` for exports. Never block the main thread. Use `AsyncStream` for progress reporting.

8. **Cancellation support**: Check `Task.checkCancellation()` in render loops. Call `AVAssetWriter.cancelWriting()` on cancel.

### Export Settings Builder Pattern

```swift
/// Fluent builder for export settings
class ExportSettingsBuilder {
    private var codec: AVVideoCodecType = .hevc
    private var width: Int = 1920
    private var height: Int = 1080
    private var bitRate: Int?
    private var frameRate: Double = 30
    private var fileType: AVFileType = .mov
    private var colorProperties: [String: Any]?
    private var profileLevel: String?

    func codec(_ codec: AVVideoCodecType) -> Self { self.codec = codec; return self }
    func resolution(_ w: Int, _ h: Int) -> Self { width = w; height = h; return self }
    func bitRate(_ bps: Int) -> Self { bitRate = bps; return self }
    func frameRate(_ fps: Double) -> Self { frameRate = fps; return self }
    func fileType(_ type: AVFileType) -> Self { fileType = type; return self }
    func hdr(_ type: HDRType) -> Self {
        switch type {
        case .hlg:
            colorProperties = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
            profileLevel = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        case .hdr10:
            colorProperties = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
            profileLevel = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        case .sdr:
            colorProperties = nil
            profileLevel = nil
        }
        return self
    }

    func build() -> [String: Any] {
        var compressionProperties: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoAllowFrameReorderingKey: true
        ]
        if let bitRate = bitRate {
            compressionProperties[AVVideoAverageBitRateKey] = bitRate
        }
        if let profile = profileLevel {
            compressionProperties[AVVideoProfileLevelKey] = profile
        }

        var settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        if let colorProps = colorProperties {
            settings[AVVideoColorPropertiesKey] = colorProps
        }

        return settings
    }
}

// Usage:
// let settings = ExportSettingsBuilder()
//     .codec(.hevc)
//     .resolution(3840, 2160)
//     .bitRate(40_000_000)
//     .frameRate(24)
//     .hdr(.hlg)
//     .build()
```

### Error Handling

```swift
enum ExportError: LocalizedError {
    case writerNotSetUp
    case readerNotSetUp
    case presetNotCompatible
    case sessionCreationFailed
    case appendFailed
    case codecNotSupported(String)
    case resolutionNotSupported(Int, Int)
    case insufficientMemory
    case diskSpaceExhausted
    case unknown

    var errorDescription: String? {
        switch self {
        case .writerNotSetUp: return "AVAssetWriter not configured"
        case .readerNotSetUp: return "AVAssetReader not configured"
        case .presetNotCompatible: return "Export preset not compatible with source"
        case .sessionCreationFailed: return "Failed to create export session"
        case .appendFailed: return "Failed to append sample buffer"
        case .codecNotSupported(let codec): return "Codec \(codec) not supported on this hardware"
        case .resolutionNotSupported(let w, let h): return "Resolution \(w)x\(h) not supported"
        case .insufficientMemory: return "Not enough memory for this export"
        case .diskSpaceExhausted: return "Insufficient disk space"
        case .unknown: return "Unknown export error"
        }
    }
}
```

---

## Summary of Key Recommendations

1. **Primary export path**: `AVAssetReader` -> frame processing (Metal) -> `AVAssetWriter`
2. **Use `AVAssetExportSession`** only for simple passthrough or preset-based exports
3. **Always use hardware encoding** when available (Apple Silicon has excellent H.264/HEVC/ProRes encoders)
4. **ProRes 422 HQ** for archival/mastering, **HEVC** for delivery, **H.264** for maximum compatibility
5. **CMTime precision matters**: use 1001/30000 for 29.97fps, never floating point
6. **Implement proxy workflow** from day one -- essential for 4K+ editing performance
7. **Smart rendering** is a major optimization for timeline-based NLE export
8. **Use `AsyncStream`** for progress reporting in modern Swift concurrency
9. **CVPixelBufferPool** + IOSurface-backed buffers for Metal-compatible rendering pipeline
10. **Container choice**: MOV for professional/ProRes, MP4 for delivery/web
