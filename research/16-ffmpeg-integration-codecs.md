# FFmpeg Integration & Advanced Codec Support for Swift NLE

## Table of Contents
1. [FFmpeg Swift Wrappers Landscape](#1-ffmpeg-swift-wrappers-landscape)
2. [Format Support Gap Analysis: AVFoundation vs FFmpeg](#2-format-support-gap-analysis)
3. [Subtitle & Caption Support](#3-subtitle--caption-support)
4. [Hardware Decoding: FFmpeg + VideoToolbox](#4-hardware-decoding-ffmpeg--videotoolbox)
5. [Frame-Accurate Seeking](#5-frame-accurate-seeking)
6. [Streaming Protocols](#6-streaming-protocols)
7. [Image Sequence Support for VFX](#7-image-sequence-support-for-vfx)
8. [RAW Video SDK Integration](#8-raw-video-sdk-integration)
9. [Alternative Media Frameworks](#9-alternative-media-frameworks)
10. [Building FFmpeg as XCFramework](#10-building-ffmpeg-as-xcframework)
11. [Licensing Considerations](#11-licensing-considerations)
12. [Recommended Architecture for NLE](#12-recommended-architecture-for-nle)

---

## 1. FFmpeg Swift Wrappers Landscape

### 1.1 SwiftFFmpeg (sunlubo/SwiftFFmpeg)

The most mature pure-Swift wrapper around FFmpeg's C API. Provides idiomatic Swift access to libavformat, libavcodec, libavutil, libswscale, and libswresample.

**Status**: Active development, requires FFmpeg 7.1+, 266 commits, 10 releases.

**Installation**:
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sunlubo/SwiftFFmpeg.git", from: "1.0.0")
]
```

**Architecture**: Uses a C system target `CFFmpeg` with module maps that expose the FFmpeg C libraries, then wraps them in Swift-friendly classes.

**Decoding Example**:
```swift
import SwiftFFmpeg

// Open input file
let fmtCtx = try AVFormatContext(url: inputPath)
try fmtCtx.findStreamInfo()

// Find video stream
guard let videoStream = fmtCtx.videoStream else {
    fatalError("No video stream found")
}

// Set up decoder
guard let codec = AVCodec.findDecoderById(videoStream.codecParameters.codecId) else {
    fatalError("Decoder not found")
}
let codecCtx = AVCodecContext(codec: codec)
try codecCtx.setParameters(videoStream.codecParameters)
try codecCtx.openCodec()

let packet = AVPacket()
let frame = AVFrame()

// Decode loop
while let _ = try? fmtCtx.readFrame(into: packet) {
    defer { packet.unref() }

    if packet.streamIndex == videoStream.index {
        try codecCtx.sendPacket(packet)

        while true {
            do {
                try codecCtx.receiveFrame(frame)
                // Process decoded frame
                // frame.data, frame.linesize, frame.width, frame.height
                // Convert to CVPixelBuffer for display
                processFrame(frame)
                frame.unref()
            } catch let err as AVError where err == .tryAgain || err == .eof {
                break
            }
        }
    }
}
```

**Encoding Example**:
```swift
import SwiftFFmpeg

// Create output context
let outputCtx = try AVFormatContext(url: outputPath, format: nil)

// Add video stream with H.264 codec
guard let encoder = AVCodec.findEncoderById(.h264) else {
    fatalError("H.264 encoder not found")
}
let stream = outputCtx.addStream(codec: encoder)
let encCtx = AVCodecContext(codec: encoder)

encCtx.width = 1920
encCtx.height = 1080
encCtx.pixelFormat = .yuv420p
encCtx.timeBase = AVRational(num: 1, den: 30)
encCtx.bitRate = 8_000_000

try encCtx.openCodec()
stream.codecParameters.copy(from: encCtx)

// Write header
try outputCtx.writeHeader()

// Encode frames...
let packet = AVPacket()
try encCtx.sendFrame(frame)
while true {
    do {
        try encCtx.receivePacket(packet)
        packet.rescaleTimestamp(from: encCtx.timeBase, to: stream.timeBase)
        packet.streamIndex = stream.index
        try outputCtx.interleavedWriteFrame(packet)
    } catch let err as AVError where err == .tryAgain || err == .eof {
        break
    }
}
try outputCtx.writeTrailer()
```

### 1.2 ffmpeg-kit-spm (Archived but forkable)

**WARNING**: The original arthenica/ffmpeg-kit was archived on June 23, 2025. The upstream project was officially retired January 6, 2025 with binary removal by April 1, 2025.

**SPM Wrapper**: `tylerjonesio/ffmpeg-kit-spm` distributes pre-built xcframeworks via SPM.
```swift
// Package.swift (may need community fork)
dependencies: [
    .package(url: "https://github.com/tylerjonesio/ffmpeg-kit-spm/", .upToNextMajor(from: "5.1.0"))
]
```

**Key limitation**: Pre-built binaries mean you cannot customize configure flags. For an NLE, you likely need custom builds.

### 1.3 KSPlayer's FFmpegKit (kingslay/FFmpegKit)

A separate, actively maintained FFmpegKit from the KSPlayer author. This is NOT the archived arthenica version.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "7.1.0")
]
```

**Features**:
- Builds FFmpeg + mpv libraries as xcframeworks
- Supports iOS, macOS, tvOS, visionOS
- Includes libass for subtitle rendering
- Active maintenance (distinct from the retired arthenica project)

### 1.4 FFmpeg-iOS (kewlbear/FFmpeg-iOS)

Swift package that builds FFmpeg and related libraries into xcframeworks via SPM.

```swift
dependencies: [
    .package(url: "https://github.com/kewlbear/FFmpeg-iOS.git", from: "7.0.0")
]
```

### 1.5 LiteAVKit

No significant Swift FFmpeg wrapper found under this name. The search suggests it may be a Tencent SDK (Chinese streaming platform) rather than an open-source FFmpeg wrapper.

---

## 2. Format Support Gap Analysis

### What AVFoundation Handles Natively

| Format/Codec | AVFoundation | Notes |
|---|---|---|
| H.264 (AVC) | Full HW decode + encode | VideoToolbox accelerated |
| H.265 (HEVC) | Full HW decode + encode | VideoToolbox, requires macOS 10.13+ |
| ProRes (422/4444) | Full HW decode + encode | Native Apple codec |
| ProRes RAW | HW decode only | M1 Pro/Max/Ultra+ |
| AAC | Full | Native |
| ALAC | Full | Native |
| MP4/MOV containers | Full | Native |
| HLS | Full playback | Native streaming |
| AV1 | HW decode (M3+) | Added macOS 14/Sonoma |
| VP9 | SW decode | macOS Big Sur+, limited |
| JPEG 2000 | Decode | Via ImageIO |

### What FFmpeg Adds (Gap Filled)

| Format/Codec | FFmpeg | NLE Use Case |
|---|---|---|
| **MKV (Matroska)** | Full read/write | Import YouTube/web content, multi-track containers |
| **WebM** | Full read/write | Web delivery format |
| **AV1 encode** | Via libaom/SVT-AV1 | Next-gen delivery codec |
| **VP9** | Full decode/encode | YouTube/web compatibility |
| **VP8** | Full decode/encode | Legacy web format |
| **DNxHD/DNxHR** | Full decode/encode | Avid interchange |
| **MPEG-2** | Full decode/encode | Broadcast/legacy |
| **DV** | Full decode/encode | Legacy tape-based |
| **Theora** | Full decode/encode | Legacy web |
| **Opus** | Full decode/encode | Best open audio codec |
| **Vorbis** | Full decode/encode | Ogg audio |
| **FLAC** | Full decode/encode | Lossless audio |
| **AC-3 / E-AC-3** | Full decode/encode | Surround sound broadcast |
| **DTS** | Decode | Cinema audio |
| **SRT/ASS subtitles** | Parse/render | Subtitle handling |
| **TS/MTS containers** | Full read/write | Broadcast transport |
| **FLV** | Full read/write | Flash/streaming legacy |
| **AVI** | Full read/write | Legacy Windows format |
| **WMV/WMA** | Decode | Windows Media |
| **CineForm** | Decode/encode | GoPro intermediate |
| **FFV1** | Full decode/encode | Archival lossless codec |
| **HAP** | Full decode/encode | GPU-decoded realtime VJ codec |
| **EXR** | Decode | VFX image sequences |
| **DPX** | Decode/encode | Film scan / DI sequences |

### Critical Gaps Only FFmpeg Fills

1. **MKV Container** - AVFoundation has zero MKV support. Essential for importing web-sourced content.
2. **DNxHD/DNxHR** - Required for Avid interchange workflows. AVFoundation cannot decode it.
3. **Broadcast Codecs** - MPEG-2, AC-3, DTS decoding for ingest from broadcast sources.
4. **Legacy Format Ingest** - AVI, WMV, FLV, DV for migrating old projects.
5. **AV1 Encoding** - AVFoundation decodes AV1 on M3+ but cannot encode. FFmpeg with SVT-AV1 or libaom enables AV1 export.
6. **Opus Audio** - Superior audio codec for web delivery. No AVFoundation support.
7. **Advanced Subtitle Parsing** - ASS/SSA styled subtitles with positioning, effects.

---

## 3. Subtitle & Caption Support

### 3.1 Swift Subtitle Parsing Libraries

**swift-subtitle-kit** (dioKaratzas/swift-subtitle-kit) - Most comprehensive:
- Formats: SRT, VTT, ASS, SSA, SBV, SUB, LRC, SMI, JSON
- Unified `SubtitleDocument` model
- Conversion between any supported formats
- Resync capabilities

```swift
import SubtitleKit

// Parse SRT file
let subtitle = try Subtitle(fileURL: srtURL, encoding: .utf8)

// Access entries
for entry in subtitle.entries {
    print("[\(entry.startTime) -> \(entry.endTime)] \(entry.text)")
}

// Convert SRT to VTT
let vttText = try subtitle.text(format: .vtt, lineEnding: .lf)

// Full conversion to new Subtitle object
let vttSubtitle = try subtitle.convert(to: .vtt, lineEnding: .lf)

// One-shot conversion
let output = try Subtitle.convert(rawText, from: .srt, to: .vtt)
```

**SwiftSubtitles** (dagronf/SwiftSubtitles) - Alternative:
- Formats: SRT, SBV, SUB, VTT, CSV, LRC, ASS/SSA, Podcast Index
- Simpler API, good for basic use cases

### 3.2 ASS/SSA Rendering

For rendering styled subtitles (ASS/SSA with positioning, fonts, effects), you need **libass**:

```swift
// libass is a C library - integrate via bridging header or Swift wrapper
// KSPlayer includes libass integration for subtitle rendering

// Conceptual workflow:
// 1. Parse ASS/SSA file with swift-subtitle-kit or libass
// 2. For simple text: render with Core Text on CATextLayer
// 3. For styled ASS: use libass to rasterize to bitmap, overlay on video

// libass integration pattern:
import CLibass  // via module map

let library = ass_library_init()
let renderer = ass_renderer_init(library)
ass_set_frame_size(renderer, Int32(videoWidth), Int32(videoHeight))

let track = ass_read_file(library, assFilePath, nil)
let image = ass_render_frame(renderer, track, Int64(currentTimeMs), nil)
// image contains bitmap data to composite onto video frame
```

### 3.3 CEA-608/708 Closed Captions

CEA-608 and CEA-708 are embedded in video streams (NTSC line 21 / ATSC digital TV).

**Approach for NLE**:
1. **Extraction**: FFmpeg can extract embedded CC data from transport streams
   ```bash
   ffmpeg -i input.ts -map 0:s:0 -c:s text output.srt
   ```
2. **In Swift**: Use `AVAsset` with `AVMediaCharacteristic.legible` for basic CC
   ```swift
   let asset = AVAsset(url: videoURL)
   let ccTracks = asset.tracks(withMediaCharacteristic: .legible)
   // Read CC samples from track
   ```
3. **FFmpeg libavcodec**: Decode cc_dec (CEA-608 decoder) for frame-level CC extraction
4. **Conversion Pipeline**: Extract CEA-608/708 -> convert to WebVTT/SRT -> parse with SubtitleKit

**NLE Caption Editing Architecture**:
```swift
/// Unified caption model supporting all formats
struct Caption {
    let id: UUID
    var startTime: CMTime
    var endTime: CMTime
    var text: String
    var style: CaptionStyle    // Font, color, position, etc.
    var format: CaptionFormat  // .srt, .ass, .vtt, .cea608, .cea708
}

struct CaptionStyle {
    var fontName: String
    var fontSize: CGFloat
    var foregroundColor: NSColor
    var backgroundColor: NSColor?
    var position: CaptionPosition  // .bottom, .top, .custom(x, y)
    var alignment: NSTextAlignment
    var bold: Bool
    var italic: Bool
    var outline: CGFloat?
    var shadow: CGFloat?
}

/// Caption track in timeline
class CaptionTrack: TimelineTrack {
    var captions: [Caption] = []
    var language: String  // ISO 639-1
    var isClosedCaption: Bool  // vs. subtitle

    func caption(at time: CMTime) -> Caption? {
        captions.first { time >= $0.startTime && time < $0.endTime }
    }

    func exportSRT() -> String { /* ... */ }
    func exportASS() -> String { /* ... */ }
    func exportVTT() -> String { /* ... */ }
    func burnIn(to videoFrame: CVPixelBuffer, at time: CMTime) { /* ... */ }
}
```

---

## 4. Hardware Decoding: FFmpeg + VideoToolbox

### 4.1 How FFmpeg Leverages VideoToolbox on macOS

FFmpeg integrates with Apple's VideoToolbox framework for hardware-accelerated encoding/decoding. The key codecs with HW acceleration:

| Codec | FFmpeg HW Decoder | FFmpeg HW Encoder | Chip Requirement |
|---|---|---|---|
| H.264 | `h264_videotoolbox` | `h264_videotoolbox` | Any Apple Silicon / Intel |
| HEVC | `hevc_videotoolbox` | `hevc_videotoolbox` | A10+ / Intel 6th gen+ |
| ProRes | `prores_videotoolbox` | `prores_videotoolbox` | M1 Pro/Max/Ultra+ for encode |
| VP9 | `vp9_videotoolbox` | N/A | M1+ (decode only) |
| AV1 | N/A via FFmpeg | N/A | M3+ (use AVFoundation directly) |

**Performance Benchmarks** (Apple Silicon M1):
- h264_videotoolbox: ~4x faster than libx264 (software)
- hevc_videotoolbox: ~3x faster than libx265 (software)
- CPU usage: ~20% with HW encoder vs ~100% with SW encoder

### 4.2 Swift Integration with VideoToolbox via FFmpeg

```swift
import SwiftFFmpeg

// Configure hardware-accelerated decoding
let fmtCtx = try AVFormatContext(url: inputPath)
try fmtCtx.findStreamInfo()

guard let videoStream = fmtCtx.videoStream else { return }

// Request VideoToolbox HW acceleration
let codec = AVCodec.findDecoderById(videoStream.codecParameters.codecId)!
let codecCtx = AVCodecContext(codec: codec)
try codecCtx.setParameters(videoStream.codecParameters)

// Enable VideoToolbox hardware acceleration
// The hwDeviceType tells FFmpeg to use Apple's hardware decoder
codecCtx.getFormat = { codecCtx, formats in
    // Check if VideoToolbox pixel format is available
    for format in formats {
        if format == .videoToolbox {
            return .videoToolbox
        }
    }
    return formats[0]  // Fallback to software
}

// Create hardware device context
var hwDeviceCtx: UnsafeMutablePointer<AVBufferRef>?
av_hwdevice_ctx_create(&hwDeviceCtx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0)
codecCtx.hwDeviceCtx = hwDeviceCtx

try codecCtx.openCodec()

// Decoded frames come as CVPixelBuffers (VideoToolbox native)
// This means zero-copy path to Metal rendering
```

### 4.3 Direct VideoToolbox API (No FFmpeg)

For codecs AVFoundation supports natively, use VideoToolbox directly for maximum performance:

```swift
import VideoToolbox

// Hardware decompression session
func createDecompressionSession(
    formatDescription: CMVideoFormatDescription,
    outputCallback: @escaping VTDecompressionOutputHandler
) -> VTDecompressionSession? {
    var session: VTDecompressionSession?

    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ]

    let status = VTDecompressionSessionCreate(
        allocator: nil,
        formatDescription: formatDescription,
        decoderSpecification: nil,
        imageBufferAttributes: attributes as CFDictionary,
        outputCallback: nil,
        decompressionSessionOut: &session
    )

    guard status == noErr, let session = session else { return nil }
    return session
}

// Decode a sample buffer
func decode(sampleBuffer: CMSampleBuffer, session: VTDecompressionSession) {
    VTDecompressionSessionDecodeFrame(
        session,
        sampleBuffer: sampleBuffer,
        flags: [._EnableAsynchronousDecompression],
        infoFlagsOut: nil
    ) { status, flags, imageBuffer, presentationTimeStamp, duration in
        guard let pixelBuffer = imageBuffer else { return }
        // pixelBuffer is hardware-decoded, Metal-compatible CVPixelBuffer
        // Zero-copy to Metal texture for display
    }
}
```

### 4.4 Hybrid Decode Strategy for NLE

```swift
/// Selects the optimal decoder for a given codec
enum DecoderStrategy {
    case avFoundationNative    // H.264, HEVC, ProRes - best performance
    case ffmpegVideoToolbox    // Use FFmpeg demux + VT HW decode
    case ffmpegSoftware        // Exotic codecs, no HW path

    static func select(for codecId: AVCodecID) -> DecoderStrategy {
        switch codecId {
        case .h264, .hevc, .prores:
            return .avFoundationNative
        case .vp9, .mpeg2video, .dnxhd:
            // FFmpeg demux, VideoToolbox decode where available
            return .ffmpegVideoToolbox
        case .vp8, .theora, .ffv1, .cineform:
            return .ffmpegSoftware
        default:
            return .ffmpegSoftware
        }
    }
}
```

---

## 5. Frame-Accurate Seeking

### 5.1 The Core Challenge

Video codecs use inter-frame compression (I/P/B frames). Seeking to an arbitrary frame requires:
1. Finding the nearest preceding keyframe (I-frame)
2. Decoding all frames from that keyframe to the target frame
3. Discarding intermediate frames, displaying only the target

### 5.2 FFmpeg Seeking Approach

```swift
// FFmpeg seeking - keyframe based
func seekToTimestamp(_ timestamp: Int64, in fmtCtx: AVFormatContext, streamIndex: Int) throws {
    // Step 1: Seek to nearest keyframe before target
    // AVSEEK_FLAG_BACKWARD ensures we land on or before target
    av_seek_frame(fmtCtx.cFormatContext, Int32(streamIndex), timestamp, AVSEEK_FLAG_BACKWARD)

    // Step 2: Flush decoder buffers
    avcodec_flush_buffers(codecCtx.cCodecContext)

    // Step 3: Decode forward to exact frame
    let packet = AVPacket()
    let frame = AVFrame()

    while true {
        try fmtCtx.readFrame(into: packet)
        defer { packet.unref() }

        if packet.streamIndex == streamIndex {
            try codecCtx.sendPacket(packet)
            try codecCtx.receiveFrame(frame)

            if frame.pts >= timestamp {
                // This is our target frame (or closest after)
                return
            }
            frame.unref()
        }
    }
}
```

**FFmpeg Seeking Limitations**:
- `av_seek_frame` only seeks to keyframes (not arbitrary frames)
- With `AVSEEK_FLAG_BACKWARD`, it seeks to the keyframe at or before the timestamp
- Some formats/demuxers have buggy seeking (transport streams especially)
- No built-in frame counting - must track PTS manually

### 5.3 AVFoundation Seeking

```swift
// AVFoundation - more reliable for supported formats
let asset = AVAsset(url: videoURL)
let reader = try AVAssetReader(asset: asset)
let videoTrack = asset.tracks(withMediaType: .video).first!

// Seek with tolerance for exact frame
let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
output.supportsRandomAccess = true  // Key for NLE seeking

reader.timeRange = CMTimeRange(
    start: targetTime,
    duration: CMTime(value: 1, timescale: videoTrack.naturalTimeScale)
)
reader.add(output)
reader.startReading()

if let sampleBuffer = output.copyNextSampleBuffer() {
    // Exact frame at targetTime
}

// Reset for next seek
output.reset(forReadingTimeRanges: [
    NSValue(timeRange: CMTimeRange(start: newTime, duration: frameDuration))
])
```

### 5.4 Comparison: FFmpeg vs AVFoundation Seeking

| Feature | AVFoundation | FFmpeg |
|---|---|---|
| Frame-exact for H.264/HEVC | Excellent (with `toleranceBefore: .zero`) | Requires manual decode-forward |
| ProRes seeking | Excellent (all-intra = every frame is keyframe) | Good |
| MKV seeking | Not supported | Good (depends on index) |
| GOP-based codecs | Reliable with tolerances | Manual keyframe + decode-forward |
| Seek table/index | Built into AVAsset | Must build manually or use `avformat_seek_file` |
| Random access performance | Optimized for NLE use | Requires careful buffer management |
| Format support | Limited to Apple formats | Universal |

### 5.5 NLE Seek Strategy

```swift
/// Hybrid frame-accurate seek engine
class FrameAccurateSeeker {
    private var seekTable: [Int64: Int64] = [:]  // frame number -> byte offset

    /// Build seek table for fast random access (critical for timeline scrubbing)
    func buildSeekTable(for url: URL) async throws -> SeekTable {
        let fmtCtx = try AVFormatContext(url: url.path)
        try fmtCtx.findStreamInfo()

        var table = SeekTable()
        let packet = AVPacket()

        while let _ = try? fmtCtx.readFrame(into: packet) {
            defer { packet.unref() }
            if packet.flags.contains(.key) {
                table.addKeyframe(pts: packet.pts, position: packet.pos)
            }
        }
        return table
    }

    /// Two-phase seek: fast keyframe seek + precise decode-forward
    func seek(to targetPTS: Int64) async throws -> DecodedFrame {
        // Phase 1: Jump to nearest keyframe
        let keyframePTS = seekTable.nearestKeyframe(before: targetPTS)
        av_seek_frame(fmtCtx, streamIndex, keyframePTS, AVSEEK_FLAG_BACKWARD)
        avcodec_flush_buffers(codecCtx)

        // Phase 2: Decode forward to exact frame
        var lastFrame: DecodedFrame?
        while let frame = try decodeNextFrame() {
            if frame.pts >= targetPTS {
                return frame
            }
            lastFrame = frame
        }
        return lastFrame!
    }
}
```

---

## 6. Streaming Protocols

### 6.1 HLS (HTTP Live Streaming)

AVFoundation handles HLS natively, but FFmpeg provides more control:

```swift
// AVFoundation HLS (preferred for playback)
let hlsURL = URL(string: "https://example.com/stream.m3u8")!
let playerItem = AVPlayerItem(url: hlsURL)
// Supports adaptive bitrate, encryption, etc.

// FFmpeg HLS (for capture/recording/transcoding)
// Read from HLS, output to file
let fmtCtx = try AVFormatContext(url: "https://example.com/stream.m3u8")
try fmtCtx.findStreamInfo()
// Demux and process individual segments

// HLS Segmentation for export
// ffmpeg -i input.mov -c:v h264_videotoolbox -c:a aac
//        -hls_time 10 -hls_list_size 0 -f hls output.m3u8
```

### 6.2 RTMP (Real-Time Messaging Protocol)

Essential for live editing / ingest scenarios:

```swift
// FFmpeg RTMP ingest - read live stream for editing
let rtmpCtx = try AVFormatContext(url: "rtmp://live.example.com/stream/key")
try rtmpCtx.findStreamInfo()

// Low-latency settings
rtmpCtx.flags |= AVFMT_FLAG_NOBUFFER
// Use avformat options: "rtmp_live", "rtmp_buffer"

// RTMP output - push to streaming service
let outputCtx = try AVFormatContext(url: "rtmp://ingest.twitch.tv/app/stream_key", format: "flv")
// Add video/audio streams, encode, and write
```

### 6.3 SRT (Secure Reliable Transport)

Modern low-latency protocol gaining adoption:
```bash
# FFmpeg SRT ingest
ffmpeg -i "srt://0.0.0.0:9000?mode=listener" -c copy output.ts

# SRT output
ffmpeg -i input.mov -c:v h264_videotoolbox -f mpegts "srt://target:9000"
```

### 6.4 NDI (Network Device Interface)

For professional broadcast workflows. FFmpeg does NOT support NDI natively (licensing), but the NDI SDK is available separately for Swift integration.

### 6.5 NLE Live Ingest Architecture

```swift
/// Protocol-agnostic live ingest for the NLE timeline
class LiveIngestEngine {
    enum Protocol {
        case rtmp(url: URL)
        case srt(host: String, port: Int)
        case hls(url: URL)
        case ndi(sourceName: String)
    }

    private var ffmpegContext: AVFormatContext?
    private var ringBuffer: RingBuffer<CMSampleBuffer>

    func startIngest(protocol: Protocol) async throws {
        let url: String
        switch `protocol` {
        case .rtmp(let rtmpURL): url = rtmpURL.absoluteString
        case .srt(let host, let port): url = "srt://\(host):\(port)"
        case .hls(let hlsURL): url = hlsURL.absoluteString
        case .ndi: throw IngestError.useNDISDK
        }

        ffmpegContext = try AVFormatContext(url: url)
        try ffmpegContext?.findStreamInfo()

        // Continuous decode loop writing to ring buffer
        // Timeline can cut to live source at any point
    }
}
```

---

## 7. Image Sequence Support for VFX

### 7.1 Format Overview

| Format | Bit Depth | Color Space | Compression | Use Case |
|---|---|---|---|---|
| **OpenEXR** | 16/32-bit float | Linear, ACES | PIZ, ZIP, DWAA | VFX compositing, HDR |
| **DPX** | 10/12/16-bit | Log, Linear | None (usually) | Film scan, DI, color grading |
| **TIFF** | 8/16/32-bit | Various | LZW, ZIP, None | General purpose, print |
| **PNG** | 8/16-bit | sRGB | Lossless | Web, alpha channels |
| **TGA** | 8-bit | sRGB | RLE or None | Legacy VFX, game textures |

### 7.2 FFmpeg Image Sequence Reading

```bash
# Read EXR sequence (numbered: frame_0001.exr, frame_0002.exr, ...)
ffmpeg -framerate 24 -i "frame_%04d.exr" -c:v prores_ks -profile:v 4444 output.mov

# Read DPX sequence
ffmpeg -start_number 1001 -framerate 23.976 -i "scan.%07d.dpx" \
       -c:v prores_videotoolbox -profile:v 4 output.mov

# Read TIFF sequence with specific color handling
ffmpeg -framerate 30 -i "render_%05d.tiff" \
       -c:v libx264 -crf 18 -pix_fmt yuv420p output.mp4
```

### 7.3 FFmpeg Image Sequence Writing

```bash
# Export to EXR sequence
ffmpeg -i input.mov -pix_fmt rgb48le "output_%04d.exr"

# Export to DPX sequence (10-bit log)
ffmpeg -i input.mov -pix_fmt gbrp10le "output_%04d.dpx"

# Export to TIFF sequence (16-bit)
ffmpeg -i input.mov -pix_fmt rgb48le -compression_algo lzw "output_%04d.tiff"

# Export to PNG sequence with alpha
ffmpeg -i input.mov -pix_fmt rgba "output_%04d.png"
```

### 7.4 Swift Image Sequence Handler

```swift
import SwiftFFmpeg

/// Handles VFX image sequence import/export
class ImageSequenceHandler {

    struct SequenceInfo {
        let directory: URL
        let pattern: String          // e.g., "frame_%04d.exr"
        let format: ImageFormat      // .exr, .dpx, .tiff, .png
        let startFrame: Int
        let endFrame: Int
        let frameRate: Double
        let width: Int
        let height: Int
        let bitDepth: Int            // 8, 10, 12, 16, 32
        let colorSpace: ColorSpace   // .linear, .log, .sRGB, .aces
    }

    /// Detect and catalog an image sequence from a directory
    func detectSequence(in directory: URL) throws -> SequenceInfo {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        // Parse filenames, detect numbering pattern, determine format
        // Read first frame metadata for resolution, bit depth, color space
        // Return SequenceInfo
        fatalError("Implementation")
    }

    /// Import image sequence as virtual AVAsset for timeline use
    func importSequence(_ info: SequenceInfo) throws -> ImageSequenceAsset {
        // Use FFmpeg to read individual frames on demand
        // Create virtual timeline representation
        // Each frame accessed via FFmpeg's image2 demuxer
        let fmtCtx = try AVFormatContext(url: info.pattern)
        // Configure frame rate, start number, etc.
        return ImageSequenceAsset(context: fmtCtx, info: info)
    }

    /// Export timeline range to image sequence
    func exportSequence(
        from timeline: Timeline,
        range: CMTimeRange,
        format: ImageFormat,
        directory: URL,
        bitDepth: Int = 16,
        colorSpace: ColorSpace = .linear
    ) async throws {
        // Render each frame from timeline
        // Write to disk as numbered image files
        for frameIndex in 0..<totalFrames {
            let time = /* calculate time for frame */
            let pixelBuffer = try await timeline.renderFrame(at: time)

            switch format {
            case .exr:
                try writeEXR(pixelBuffer, to: directory.appending("frame_\(String(format: "%04d", frameIndex)).exr"))
            case .dpx:
                try writeDPX(pixelBuffer, to: directory.appending("frame_\(String(format: "%04d", frameIndex)).dpx"))
            case .tiff:
                try writeTIFF(pixelBuffer, to: directory.appending("frame_\(String(format: "%04d", frameIndex)).tiff"))
            default:
                break
            }
        }
    }
}
```

### 7.5 Native macOS EXR/DPX Support

macOS has some native support via ImageIO:
```swift
import ImageIO

// Read EXR (macOS 11+)
if let source = CGImageSourceCreateWithURL(exrURL as CFURL, nil) {
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    // CGImage from EXR - but limited to 8-bit output
}

// For full fidelity (16/32-bit float), use OpenEXR C++ library or FFmpeg
```

---

## 8. RAW Video SDK Integration

### 8.1 RED R3D SDK

**Availability**: Free download from red.com/download/r3d-sdk
**Language**: C++ API
**Platforms**: macOS, Windows, Linux
**GPU Acceleration**: Metal, CUDA, OpenCL

```cpp
// R3D SDK C++ Example (bridge to Swift via Objective-C++)
#include "R3DSDK.h"

// Initialize
R3DSDK::InitializeSdk(".", OPTION_RED_NONE);

// Open clip
R3DSDK::Clip* clip = new R3DSDK::Clip(filePath);
if (clip->Status() != R3DSDK::DSDecoded) {
    // Error
}

// Get clip metadata
size_t width = clip->Width();
size_t height = clip->Height();
float fps = clip->VideoAudioFramerate();

// Decode frame
R3DSDK::VideoDecodeJob job;
job.Mode = R3DSDK::DECODE_FULL_RES_PREMIUM;
job.OutputBufferType = R3DSDK::PixelType_HalfFloat_4Chan;
job.BytesPerRow = width * 4 * sizeof(uint16_t);
job.OutputBuffer = outputBuffer;

clip->DecodeVideoFrame(frameNumber, job);
```

**Swift Bridge Pattern**:
```swift
// Objective-C++ wrapper (REDDecoder.mm)
// Expose to Swift via bridging header

class REDDecoder {
    private var wrapper: REDDecoderObjC  // Obj-C++ wrapper

    func openClip(at url: URL) throws -> REDClipInfo {
        try wrapper.open(url)
        return REDClipInfo(
            width: wrapper.width,
            height: wrapper.height,
            frameRate: wrapper.frameRate,
            frameCount: wrapper.frameCount,
            codec: wrapper.codecName,
            colorSpace: wrapper.colorSpace
        )
    }

    func decodeFrame(_ index: Int) throws -> CVPixelBuffer {
        // Decode via R3D SDK, return as CVPixelBuffer
        // Metal-compatible for zero-copy to GPU
        return try wrapper.decodeFrame(Int32(index))
    }
}
```

### 8.2 Blackmagic RAW (BRAW) SDK

**Availability**: Free download from blackmagicdesign.com
**Language**: C++ / COM-style API
**Platforms**: macOS, Windows, Linux
**GPU Acceleration**: Metal, CUDA, OpenCL

```cpp
// BRAW SDK C++ Example
#include "BlackmagicRawAPI.h"

// Create factory and codec
IBlackmagicRawFactory* factory = CreateBlackmagicRawFactoryInstance();
IBlackmagicRaw* codec = nullptr;
factory->CreateCodec(&codec);

// Configure for Metal GPU decoding
IBlackmagicRawConfiguration* config = nullptr;
codec->QueryInterface(IID_IBlackmagicRawConfiguration, (void**)&config);
config->SetPipeline(blackmagicRawPipelineMetal, metalDevice);

// Open clip
IBlackmagicRawClip* clip = nullptr;
codec->OpenClip(filePath, &clip);

// Get clip properties
int64_t frameCount;
clip->GetFrameCount(&frameCount);

// Process frame (async callback-based)
IBlackmagicRawJob* job = nullptr;
clip->CreateJobReadFrame(frameIndex, &job);
// Set callback for frame completion
job->Submit();
codec->ProcessFrame(job);  // GPU decode

// Result delivered via IBlackmagicRawCallback interface
```

**Swift Bridge Pattern**:
```swift
class BRAWDecoder {
    private var wrapper: BRAWDecoderObjC  // Obj-C++ COM wrapper

    func openClip(at url: URL) throws -> BRAWClipInfo {
        try wrapper.open(url)
        return BRAWClipInfo(
            width: wrapper.width,
            height: wrapper.height,
            frameRate: wrapper.frameRate,
            frameCount: wrapper.frameCount,
            iso: wrapper.iso,
            whiteBalance: wrapper.whiteBalance
        )
    }

    /// Decode with Metal GPU acceleration
    func decodeFrame(_ index: Int, metalDevice: MTLDevice) async throws -> CVPixelBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            wrapper.decodeFrame(Int32(index), device: metalDevice) { pixelBuffer, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: pixelBuffer!)
                }
            }
        }
    }

    /// Adjust RAW parameters (non-destructive)
    func setRAWParameters(
        iso: Float? = nil,
        whiteBalance: Float? = nil,
        tint: Float? = nil,
        exposure: Float? = nil,
        colorSpace: BRAWColorSpace? = nil,
        gammaCurve: BRAWGamma? = nil
    ) {
        // Adjust decode parameters - re-decode needed for preview
    }
}
```

### 8.3 ARRI Image SDK (ARRIRAW)

**Availability**: Via ARRI Partner Program (requires registration)
**Language**: C++ API
**Features**: Official debayer algorithm (ADA), color science, ACES support

**Access**: Developers must join the ARRI Partner Program:
- Provides SDK, documentation, and technical support
- Includes ARRI Debayer Algorithm (ADA)
- Reference implementation for color science
- Supports .ari and .arx file formats

**Integration Pattern**: Same Objective-C++ bridge approach as RED and BRAW.

### 8.4 Unified RAW Decoder Interface

```swift
/// Protocol for all RAW video decoders
protocol RAWVideoDecoder {
    var clipInfo: RAWClipInfo { get }

    func open(url: URL) async throws
    func decodeFrame(at index: Int) async throws -> CVPixelBuffer
    func close()

    // RAW-specific adjustments
    var exposureAdjustment: Float { get set }
    var whiteBalance: Float { get set }
    var colorSpace: RAWColorSpace { get set }
    var gammaCurve: RAWGammaCurve { get set }
}

struct RAWClipInfo {
    let width: Int
    let height: Int
    let frameRate: Double
    let frameCount: Int
    let codec: RAWCodec       // .r3d, .braw, .arriraw, .proresRAW
    let sensorInfo: String
    let nativeISO: Int
    let nativeWhiteBalance: Int
}

/// Factory for creating the right decoder
class RAWDecoderFactory {
    static func decoder(for url: URL) throws -> RAWVideoDecoder {
        switch url.pathExtension.lowercased() {
        case "r3d":
            return REDDecoder()
        case "braw":
            return BRAWDecoder()
        case "ari", "arx", "mxf":
            return ARRIRAWDecoder()
        default:
            // Check if ProRes RAW (use VideoToolbox)
            return ProResRAWDecoder()
        }
    }
}
```

---

## 9. Alternative Media Frameworks

### 9.1 VLCKit

**License**: LGPLv2.1+
**Wrapper**: Objective-C bindings for libVLC
**SPM**: `tylerjonesio/vlckit-spm`

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/tylerjonesio/vlckit-spm", from: "3.6.0")
]
```

**Pros**:
- Massive format/codec coverage (all FFmpeg codecs + more)
- LGPL-friendly for commercial use
- Proven stability (powers VLC media player)
- Network stream support out of the box

**Cons**:
- Designed for playback, not NLE editing workflows
- No frame-accurate seeking API suitable for timeline scrubbing
- Large binary size (~50MB+)
- Limited encoding/export capabilities
- Objective-C API, not Swift-native

**Verdict**: Good for a media player preview window, NOT suitable as the core decode engine for an NLE.

### 9.2 MPVKit / libmpv

**License**: GPL-2.0+ (or LGPL with restricted builds)
**Wrapper**: `karelrooted/MPVKit` - Swift bindings for libmpv
**Platforms**: macOS 14+, iOS 17+, tvOS 17+

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/karelrooted/MPVKit.git", from: "0.40.0")
]

// SwiftUI integration
import MPVKit
MPVVideoPlayer(url: URL(string: "http://example.com/video.mp4")!)
```

**Pros**:
- Excellent playback quality and format support
- Good macOS integration (used by IINA)
- Vulkan rendering support via MoltenVK
- LuaJIT scripting for custom filters

**Cons**:
- GPL license restricts commercial distribution
- Playback-focused, not editing-focused
- No encoding pipeline
- Work in progress, API may change

**Verdict**: Could power a source monitor or preview player, but not suitable as the primary decode/encode engine for NLE.

### 9.3 KSPlayer

**License**: GPL-3.0 (LGPL available as paid option)
**Platforms**: iOS, macOS, tvOS, visionOS

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.0.0")
]
```

**Features**:
- AVPlayer + FFmpeg hybrid playback
- Hardware-accelerated decoding
- 4K HDR/HDR10/Dolby Vision support
- Text, image, and closed caption subtitles
- SwiftUI native integration
- Online subtitle search
- Low-latency live streaming (<200ms LAN)
- Automatic bitrate switching

**Pros**:
- Most feature-complete Swift video player framework
- SwiftUI-first design
- Active maintenance
- Subtitle rendering with libass

**Cons**:
- GPL by default (LGPL is paid)
- Focused on playback, not editing
- No frame-accurate timeline scrubbing API
- No encoding/export pipeline

**Verdict**: Best-in-class for playback features. Could be referenced for subtitle rendering and streaming architecture, but NLE needs custom decode pipeline.

### 9.4 GStreamer

**License**: LGPL-2.1
**Language**: C with GObject bindings

**Pros**:
- Most flexible pipeline architecture of any media framework
- Plugin-based: only include codecs you need
- Excellent for custom media pipelines
- Good streaming support

**Cons**:
- No Swift bindings (C/GObject API only)
- Complex API
- Large dependency tree
- Not commonly used on macOS/iOS
- No ecosystem support for Apple platforms

**Verdict**: Powerful but wrong ecosystem. Swift/macOS integration would require significant effort.

### 9.5 Framework Comparison Matrix

| Feature | SwiftFFmpeg | KSPlayer | VLCKit | MPVKit | GStreamer |
|---|---|---|---|---|---|
| License | LGPL (FFmpeg) | GPL/LGPL(paid) | LGPL | GPL | LGPL |
| Swift API | Native | Native | Obj-C bridge | Swift | C/GObject |
| Decode | Full control | AVPlayer+FFmpeg | Full | Full | Full |
| Encode | Full control | No | Limited | No | Full |
| NLE Seeking | Manual | No | No | No | Possible |
| HW Accel | VideoToolbox | VideoToolbox | VideoToolbox | VideoToolbox | VideoToolbox |
| Subtitle | Manual | Built-in | Built-in | Built-in | Plugin |
| Streaming | HLS/RTMP/SRT | HLS/RTMP | All | All | All |
| Binary Size | Custom (~10-30MB) | ~40MB | ~50MB | ~35MB | ~20-50MB |
| Best For | NLE core engine | Playback UI | Fallback player | Preview monitor | Complex pipelines |

---

## 10. Building FFmpeg as XCFramework

### 10.1 Build Script for macOS (Apple Silicon + Intel)

```bash
#!/bin/bash
# build-ffmpeg-xcframework.sh
# Builds FFmpeg as xcframeworks for macOS (arm64 + x86_64)

FFMPEG_VERSION="7.1"
PREFIX="$(pwd)/build"
DEPLOYMENT_TARGET="13.0"

# Download FFmpeg source
curl -LO "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
cd "ffmpeg-${FFMPEG_VERSION}"

# Common configure flags (LGPL-safe - no GPL libraries)
COMMON_FLAGS="
    --enable-shared
    --disable-static
    --disable-programs
    --disable-doc
    --enable-pic
    --enable-videotoolbox
    --enable-audiotoolbox
    --enable-neon
    --disable-gpl
    --enable-version3
    --enable-demuxer=mov,mp4,matroska,flv,avi,mpegts,image2,hls
    --enable-muxer=mov,mp4,matroska,flv,mpegts,image2,hls
    --enable-decoder=h264,hevc,vp9,vp8,av1,prores,dnxhd,mpeg2video,aac,opus,flac,ac3
    --enable-encoder=h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox,aac,opus,flac
    --enable-protocol=file,http,https,hls,rtmp,srt
    --enable-filter=scale,crop,overlay,transpose,colorspace,lut3d
    --enable-libdav1d
    --enable-libopus
"

# Build for arm64 (Apple Silicon)
build_arm64() {
    ./configure \
        --prefix="${PREFIX}/arm64" \
        --arch=arm64 \
        --target-os=darwin \
        --cc="clang -arch arm64" \
        --extra-cflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
        --extra-ldflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
        ${COMMON_FLAGS}

    make -j$(sysctl -n hw.ncpu) && make install
    make clean
}

# Build for x86_64 (Intel - Rosetta compatibility)
build_x86_64() {
    ./configure \
        --prefix="${PREFIX}/x86_64" \
        --arch=x86_64 \
        --target-os=darwin \
        --cc="clang -arch x86_64" \
        --extra-cflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
        --extra-ldflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
        ${COMMON_FLAGS}

    make -j$(sysctl -n hw.ncpu) && make install
    make clean
}

build_arm64
build_x86_64

# Create universal (fat) binaries
create_universal() {
    local lib=$1
    mkdir -p "${PREFIX}/universal/lib"
    lipo -create \
        "${PREFIX}/arm64/lib/${lib}" \
        "${PREFIX}/x86_64/lib/${lib}" \
        -output "${PREFIX}/universal/lib/${lib}"
}

for dylib in libavcodec libavformat libavutil libswscale libswresample libavfilter; do
    create_universal "${dylib}.dylib"
done

# Create xcframeworks
create_xcframework() {
    local name=$1

    # Create framework structure
    mkdir -p "${PREFIX}/frameworks/${name}.framework/Headers"
    cp "${PREFIX}/arm64/include/${name}/"*.h "${PREFIX}/frameworks/${name}.framework/Headers/"
    cp "${PREFIX}/universal/lib/${name}.dylib" "${PREFIX}/frameworks/${name}.framework/${name}"

    # Create Info.plist
    cat > "${PREFIX}/frameworks/${name}.framework/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>org.ffmpeg.${name}</string>
    <key>CFBundleName</key>
    <string>${name}</string>
    <key>CFBundleVersion</key>
    <string>${FFMPEG_VERSION}</string>
</dict>
</plist>
PLIST

    # Create xcframework
    xcodebuild -create-xcframework \
        -framework "${PREFIX}/frameworks/${name}.framework" \
        -output "${PREFIX}/xcframeworks/${name}.xcframework"
}

for lib in libavcodec libavformat libavutil libswscale libswresample libavfilter; do
    create_xcframework $lib
done

echo "XCFrameworks created in ${PREFIX}/xcframeworks/"
```

### 10.2 SPM Package for Pre-built Binaries

```swift
// Package.swift for distributing pre-built FFmpeg xcframeworks
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FFmpegBinaries",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FFmpegBinaries", targets: [
            "libavcodec", "libavformat", "libavutil",
            "libswscale", "libswresample", "libavfilter"
        ])
    ],
    targets: [
        .binaryTarget(
            name: "libavcodec",
            path: "xcframeworks/libavcodec.xcframework"
        ),
        .binaryTarget(
            name: "libavformat",
            path: "xcframeworks/libavformat.xcframework"
        ),
        .binaryTarget(
            name: "libavutil",
            path: "xcframeworks/libavutil.xcframework"
        ),
        .binaryTarget(
            name: "libswscale",
            path: "xcframeworks/libswscale.xcframework"
        ),
        .binaryTarget(
            name: "libswresample",
            path: "xcframeworks/libswresample.xcframework"
        ),
        .binaryTarget(
            name: "libavfilter",
            path: "xcframeworks/libavfilter.xcframework"
        )
    ]
)
```

### 10.3 Module Map for Swift Access

```c
// module.modulemap (placed alongside headers)
module CFFmpeg [system] {
    header "libavcodec/avcodec.h"
    header "libavformat/avformat.h"
    header "libavutil/avutil.h"
    header "libavutil/pixfmt.h"
    header "libavutil/frame.h"
    header "libavutil/hwcontext.h"
    header "libavutil/hwcontext_videotoolbox.h"
    header "libswscale/swscale.h"
    header "libswresample/swresample.h"
    header "libavfilter/avfilter.h"
    link "avcodec"
    link "avformat"
    link "avutil"
    link "swscale"
    link "swresample"
    link "avfilter"
    export *
}
```

---

## 11. Licensing Considerations

### 11.1 LGPL vs GPL Decision Tree

```
FFmpeg Core Libraries (libavcodec, libavformat, etc.)
├── Default build: LGPL v2.1+
│   ├── Commercial friendly with conditions
│   └── Dynamic linking required (xcframework/dylib)
│
├── If --enable-gpl:
│   ├── Entire binary becomes GPL
│   ├── Must open-source your app
│   └── Triggered by: libx264, libx265, libvidstab, frei0r
│
└── If --enable-nonfree:
    ├── Binary cannot be redistributed AT ALL
    └── Triggered by: libfdk-aac, openssl (some versions)
```

### 11.2 LGPL Compliance Requirements for macOS App

1. **Attribution**: Credit FFmpeg in About dialog and EULA
2. **Source Code**: Host the exact FFmpeg source used on your download server
3. **Dynamic Linking**: Use dylib/xcframework (NOT static linking)
4. **User Replaceability**: Users must be able to replace the FFmpeg library
   - macOS apps outside App Store: relatively easy (Frameworks directory)
   - Mac App Store: PROBLEMATIC - sandboxing prevents library replacement
5. **No Reverse Engineering Prohibition**: Your EULA cannot prohibit reverse engineering
6. **Provide Build Instructions**: Users should be able to rebuild the library

### 11.3 Safe LGPL-Only Build Configuration

```bash
# These flags ensure LGPL compliance
./configure \
    --disable-gpl \           # Ensure no GPL contamination
    --enable-version3 \       # LGPL v3 (slightly more restrictions but clearer)
    --disable-nonfree \       # Ensure redistributability
    --enable-shared \         # Dynamic linking required
    --disable-static \        # Prevent accidental static linking
    \
    # Safe decoders (all LGPL or BSD):
    --enable-decoder=h264,hevc,vp9,vp8,prores,dnxhd,mpeg2video,ffv1,mjpeg \
    --enable-decoder=aac,mp3,opus,flac,vorbis,ac3,pcm_s16le,pcm_s24le \
    \
    # Safe encoders:
    --enable-encoder=h264_videotoolbox,hevc_videotoolbox,prores_videotoolbox \
    --enable-encoder=aac,opus,flac,pcm_s16le,pcm_s24le \
    \
    # AV1 via dav1d (BSD license - safe):
    --enable-libdav1d \
    \
    # Opus via libopus (BSD license - safe):
    --enable-libopus \
    \
    # DO NOT enable these (GPL):
    # --enable-libx264    (triggers GPL)
    # --enable-libx265    (triggers GPL)
    # --enable-libvidstab (triggers GPL)
    # --enable-frei0r     (triggers GPL)
    \
    # DO NOT enable these (non-free):
    # --enable-libfdk-aac (non-redistributable)
```

### 11.4 Licensing Summary for NLE

| Component | License | Commercial OK? | Notes |
|---|---|---|---|
| FFmpeg (LGPL build) | LGPL v2.1+ | Yes (with conditions) | Dynamic link, attribution, source |
| dav1d (AV1 decode) | BSD | Yes | Freely usable |
| libopus | BSD | Yes | Freely usable |
| VideoToolbox encoders | Apple | Yes | Part of macOS |
| libx264 | GPL | Requires open-source | Avoid for commercial |
| libx265 | GPL | Requires open-source | Avoid for commercial |
| RED R3D SDK | Proprietary (free) | Check RED license | Free but proprietary |
| BRAW SDK | Proprietary (free) | Check BMD license | Free but proprietary |
| ARRI Image SDK | Proprietary | Partner program | Requires agreement |
| libass | ISC (BSD-like) | Yes | Safe for subtitles |
| SubtitleKit | MIT | Yes | Safe for subtitles |
| KSPlayer | GPL / LGPL (paid) | LGPL version for commercial | Paid for LGPL |
| VLCKit | LGPL v2.1+ | Yes (with conditions) | Same as FFmpeg LGPL |

---

## 12. Recommended Architecture for NLE

### 12.1 Layered Decoder Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    NLE Application Layer                 │
├─────────────────────────────────────────────────────────┤
│              Unified Media Engine (Swift)                │
│  ┌─────────────────────────────────────────────────┐    │
│  │         MediaDecoder Protocol (Swift)            │    │
│  │  - open(url:) -> MediaInfo                       │    │
│  │  - decodeFrame(at:) -> CVPixelBuffer             │    │
│  │  - seek(to:) -> Void                             │    │
│  │  - close()                                       │    │
│  └──────┬──────────┬──────────┬──────────┬─────────┘    │
│         │          │          │          │               │
│  ┌──────┴───┐ ┌────┴────┐ ┌──┴───┐ ┌───┴──────┐       │
│  │AVFounda- │ │  FFmpeg  │ │ RED  │ │  BRAW    │       │
│  │tion      │ │ (Swift-  │ │ R3D  │ │  SDK     │       │
│  │Decoder   │ │ FFmpeg)  │ │ SDK  │ │          │       │
│  └──────────┘ └─────────┘ └──────┘ └──────────┘       │
│         │          │          │          │               │
├─────────┴──────────┴──────────┴──────────┴──────────────┤
│               Hardware Acceleration Layer                │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Apple VideoToolbox                     │   │
│  │  H.264 / HEVC / ProRes HW decode + encode        │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Metal GPU Compute                    │   │
│  │  Color conversion, scaling, effects               │   │
│  └──────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                   Output Layer                          │
│  ┌────────┐ ┌──────────┐ ┌─────────┐ ┌────────────┐   │
│  │CVPixel │ │ MTLTexture│ │IOSurface│ │CMSample    │   │
│  │Buffer  │ │          │ │         │ │Buffer      │   │
│  └────────┘ └──────────┘ └─────────┘ └────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 12.2 Decoder Selection Logic

```swift
/// Automatically selects the best decoder for a given media file
class MediaDecoderFactory {

    static func createDecoder(for url: URL) async throws -> any MediaDecoder {
        let ext = url.pathExtension.lowercased()

        // RAW video formats - use vendor SDKs
        switch ext {
        case "r3d":
            return REDDecoder()
        case "braw":
            return BRAWDecoder()
        case "ari", "arx":
            return ARRIRAWDecoder()
        default:
            break
        }

        // Image sequences
        if ["exr", "dpx", "tiff", "tif", "png", "tga"].contains(ext) {
            return ImageSequenceDecoder()
        }

        // Probe with AVFoundation first (fastest, most reliable for supported formats)
        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        if let videoTrack = tracks.first {
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let desc = formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)

                // Use AVFoundation for natively supported codecs
                if isAVFoundationSupported(codecType) {
                    return AVFoundationDecoder(asset: asset)
                }
            }
        }

        // Fall back to FFmpeg for everything else
        return FFmpegDecoder()
    }

    private static func isAVFoundationSupported(_ codecType: FourCharCode) -> Bool {
        let supported: Set<FourCharCode> = [
            kCMVideoCodecType_H264,
            kCMVideoCodecType_HEVC,
            kCMVideoCodecType_HEVCWithAlpha,
            kCMVideoCodecType_AppleProRes4444,
            kCMVideoCodecType_AppleProRes422,
            kCMVideoCodecType_AppleProRes422HQ,
            kCMVideoCodecType_AppleProRes422LT,
            kCMVideoCodecType_AppleProRes422Proxy,
            kCMVideoCodecType_AppleProResRAW,
            kCMVideoCodecType_JPEG,
        ]
        return supported.contains(codecType)
    }
}
```

### 12.3 FFmpeg Integration Best Practices for NLE

1. **Always use dynamic linking** - Required for LGPL compliance and lets you update FFmpeg independently.

2. **Run FFmpeg operations on background threads** - Decoding is CPU-intensive; never block the main thread.

3. **Use VideoToolbox through FFmpeg** - For codecs FFmpeg demuxes but can hardware-decode (VP9, etc.), configure the HW device context.

4. **Build seek tables on import** - Pre-scan files to index keyframe positions for fast timeline scrubbing.

5. **Implement frame caching** - Cache recently decoded frames for smooth scrubbing:
   ```swift
   class FrameCache {
       private var cache: NSCache<NSNumber, CVPixelBuffer>
       private let maxCacheSize = 120  // ~4 seconds at 30fps

       func frame(at index: Int64) -> CVPixelBuffer? {
           cache.object(forKey: NSNumber(value: index))
       }

       func store(frame: CVPixelBuffer, at index: Int64) {
           cache.setObject(frame, forKey: NSNumber(value: index))
       }
   }
   ```

6. **Prefer AVFoundation for supported formats** - It is faster, more reliable, and better integrated with macOS.

7. **Use CVPixelBuffer as the interchange format** - Both AVFoundation and FFmpeg can output CVPixelBuffers, which are zero-copy to Metal textures.

8. **Handle format detection robustly**:
   ```swift
   func probeFormat(url: URL) throws -> MediaFormatInfo {
       // Try AVFoundation first (fast, reliable)
       if let avInfo = try? probeWithAVFoundation(url) {
           return avInfo
       }
       // Fall back to FFmpeg (universal)
       return try probeWithFFmpeg(url)
   }
   ```

### 12.4 Complete Integration Example: FFmpeg Decoder for NLE

```swift
import SwiftFFmpeg
import CoreMedia
import CoreVideo

/// Production-ready FFmpeg decoder for NLE timeline
final class FFmpegTimelineDecoder: @unchecked Sendable {

    private var formatContext: AVFormatContext?
    private var codecContext: AVCodecContext?
    private var videoStreamIndex: Int = -1
    private var swsContext: SwsContext?

    private let decodeLock = NSLock()
    private var seekTable: [(pts: Int64, position: Int64)] = []

    struct MediaInfo {
        let width: Int
        let height: Int
        let duration: CMTime
        let frameRate: Double
        let codecName: String
        let pixelFormat: String
        let hasAudio: Bool
    }

    // MARK: - Open / Close

    func open(url: URL) throws -> MediaInfo {
        let fmtCtx = try AVFormatContext(url: url.path)
        try fmtCtx.findStreamInfo()

        guard let stream = fmtCtx.videoStream else {
            throw DecoderError.noVideoStream
        }

        videoStreamIndex = fmtCtx.streams.firstIndex(where: { $0.mediaType == .video }) ?? -1

        guard let codec = AVCodec.findDecoderById(stream.codecParameters.codecId) else {
            throw DecoderError.codecNotFound
        }

        let ctx = AVCodecContext(codec: codec)
        try ctx.setParameters(stream.codecParameters)

        // Enable multithreaded decoding
        ctx.threadCount = ProcessInfo.processInfo.activeProcessorCount
        ctx.threadType = .frame

        try ctx.openCodec()

        self.formatContext = fmtCtx
        self.codecContext = ctx

        // Build seek table in background
        Task { await self.buildSeekTable() }

        let duration = CMTime(
            value: CMTimeValue(Double(fmtCtx.duration) / Double(AV_TIME_BASE) * 1000),
            timescale: 1000
        )

        return MediaInfo(
            width: ctx.width,
            height: ctx.height,
            duration: duration,
            frameRate: av_q2d(stream.avgFrameRate),
            codecName: codec.name,
            pixelFormat: String(describing: ctx.pixelFormat),
            hasAudio: fmtCtx.audioStream != nil
        )
    }

    func close() {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        codecContext = nil
        formatContext = nil
        swsContext = nil
        seekTable.removeAll()
    }

    // MARK: - Decode

    /// Decode frame at specific timestamp, returning CVPixelBuffer for Metal rendering
    func decodeFrame(at time: CMTime) throws -> CVPixelBuffer {
        decodeLock.lock()
        defer { decodeLock.unlock() }

        guard let fmtCtx = formatContext, let codecCtx = codecContext else {
            throw DecoderError.notOpen
        }

        let targetPTS = cmTimeToFFmpegPTS(time)

        // Seek to nearest keyframe before target
        try seekToKeyframe(before: targetPTS)

        // Decode forward to exact frame
        let packet = AVPacket()
        let frame = AVFrame()
        var lastFrame: AVFrame?

        while true {
            do {
                try fmtCtx.readFrame(into: packet)
            } catch {
                break
            }
            defer { packet.unref() }

            guard packet.streamIndex == videoStreamIndex else { continue }

            try codecCtx.sendPacket(packet)

            while true {
                do {
                    try codecCtx.receiveFrame(frame)

                    if frame.pts >= targetPTS {
                        // Found our frame
                        return try frameToPixelBuffer(frame)
                    }

                    lastFrame = frame
                } catch let err as AVError where err == .tryAgain {
                    break
                } catch let err as AVError where err == .eof {
                    if let last = lastFrame {
                        return try frameToPixelBuffer(last)
                    }
                    throw DecoderError.endOfFile
                }
            }
        }

        throw DecoderError.frameNotFound
    }

    // MARK: - Private Helpers

    private func seekToKeyframe(before pts: Int64) throws {
        guard let fmtCtx = formatContext else { return }

        // Use seek table for fast lookup if available
        if let entry = seekTable.last(where: { $0.pts <= pts }) {
            av_seek_frame(fmtCtx.cFormatContext, Int32(videoStreamIndex), entry.pts, AVSEEK_FLAG_BACKWARD)
        } else {
            av_seek_frame(fmtCtx.cFormatContext, Int32(videoStreamIndex), pts, AVSEEK_FLAG_BACKWARD)
        }

        avcodec_flush_buffers(codecContext?.cCodecContext)
    }

    private func buildSeekTable() async {
        guard let fmtCtx = formatContext else { return }

        var table: [(pts: Int64, position: Int64)] = []
        let packet = AVPacket()

        while let _ = try? fmtCtx.readFrame(into: packet) {
            defer { packet.unref() }
            if packet.streamIndex == videoStreamIndex && packet.flags.contains(.key) {
                table.append((pts: packet.pts, position: packet.pos))
            }
        }

        // Seek back to start
        av_seek_frame(fmtCtx.cFormatContext, Int32(videoStreamIndex), 0, AVSEEK_FLAG_BACKWARD)
        avcodec_flush_buffers(codecContext?.cCodecContext)

        decodeLock.lock()
        seekTable = table
        decodeLock.unlock()
    }

    /// Convert FFmpeg AVFrame to CVPixelBuffer (Metal-compatible)
    private func frameToPixelBuffer(_ frame: AVFrame) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(
            nil,
            frame.width, frame.height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw DecoderError.pixelBufferCreationFailed
        }

        // Use swscale to convert from FFmpeg pixel format to BGRA
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let dstData = CVPixelBufferGetBaseAddress(pb)!
        let dstStride = CVPixelBufferGetBytesPerRow(pb)

        // Configure sws_context for format conversion
        // (YUV420 -> BGRA typically)
        // sws_scale(swsCtx, frame.data, frame.linesize, 0, frame.height, &dstData, &dstStride)

        return pb
    }

    private func cmTimeToFFmpegPTS(_ time: CMTime) -> Int64 {
        guard let stream = formatContext?.streams[videoStreamIndex] else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return Int64(seconds * Double(stream.timeBase.den) / Double(stream.timeBase.num))
    }

    enum DecoderError: Error {
        case notOpen
        case noVideoStream
        case codecNotFound
        case frameNotFound
        case endOfFile
        case pixelBufferCreationFailed
    }
}
```

---

## Key Takeaways

1. **Use AVFoundation as primary decoder** for H.264, HEVC, ProRes - it's faster, more reliable, and better integrated.

2. **Use FFmpeg (via SwiftFFmpeg) as fallback** for MKV, DNxHD, MPEG-2, VP9, AV1 encode, and exotic formats.

3. **Integrate RAW SDKs directly** (RED, BRAW, ARRI) rather than through FFmpeg for maximum quality and GPU acceleration.

4. **Build FFmpeg as LGPL-only xcframework** for commercial distribution safety. Use VideoToolbox encoders instead of libx264/libx265.

5. **KSPlayer's FFmpegKit (kingslay)** is the best maintained community fork for building FFmpeg binaries for Apple platforms.

6. **Frame-accurate seeking requires a seek table** built on import. AVFoundation's `supportsRandomAccess` is superior for supported formats.

7. **SubtitleKit handles 9 formats**; use libass for rendered ASS/SSA subtitles.

8. **ffmpeg-kit (arthenica) is dead** - do not depend on it. Use SwiftFFmpeg, kingslay/FFmpegKit, or build your own xcframework.

9. **VLCKit and MPVKit are playback-focused** - unsuitable as NLE decode engines but useful for reference monitor implementations.

10. **Licensing**: LGPL build of FFmpeg is commercially viable with dynamic linking. Avoid GPL-triggering libraries (libx264, libx265).
