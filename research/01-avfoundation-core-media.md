# AVFoundation & Core Media Architecture for NLE

## Table of Contents

1. [Core Media Time System](#1-core-media-time-system)
2. [AVAsset & Track Model](#2-avasset--track-model)
3. [AVMutableComposition — The Editable Timeline](#3-avmutablecomposition--the-editable-timeline)
4. [AVVideoComposition — Frame-Level Rendering Control](#4-avvideocomposition--frame-level-rendering-control)
5. [Custom Video Compositing (AVVideoCompositing Protocol)](#5-custom-video-compositing-avvideocompositing-protocol)
6. [AVAudioMix — Audio Mixing Pipeline](#6-avaudiomix--audio-mixing-pipeline)
7. [Playback Pipeline (AVPlayer / AVPlayerItem)](#7-playback-pipeline-avplayer--avplayeritem)
8. [Export Pipeline (AVAssetExportSession / AVAssetReader+Writer)](#8-export-pipeline)
9. [Thumbnail Generation (AVAssetImageGenerator)](#9-thumbnail-generation-avassetimagegenerator)
10. [Multi-Track Transition Architecture](#10-multi-track-transition-architecture)
11. [Metal Integration for Custom Compositing](#11-metal-integration-for-custom-compositing)
12. [CVPixelBuffer & Memory Management](#12-cvpixelbuffer--memory-management)
13. [Modern Swift Concurrency with AVFoundation](#13-modern-swift-concurrency-with-avfoundation)
14. [Time Remapping & Speed Changes](#14-time-remapping--speed-changes)
15. [Performance Tips & Gotchas](#15-performance-tips--gotchas)
16. [Debugging Compositions](#16-debugging-compositions)
17. [Architecture Patterns from Open-Source Frameworks](#17-architecture-patterns-from-open-source-frameworks)
18. [Complete NLE Composition Builder Example](#18-complete-nle-composition-builder-example)

---

## 1. Core Media Time System

### CMTime — Rational Number Time Representation

CMTime is the foundational time type in Core Media. It represents time as a **rational number** (fraction) rather than floating-point, eliminating accumulation of rounding errors that plague float-based time systems.

```swift
// CMTime structure (C struct bridged to Swift)
public struct CMTime {
    public var value: CMTimeValue     // Int64 — numerator
    public var timescale: CMTimeScale // Int32 — denominator (subdivisions per second)
    public var flags: CMTimeFlags     // Special states (valid, infinite, indefinite, rounded)
    public var epoch: CMTimeEpoch     // Int64 — additional temporal grouping
}

// Actual time in seconds = value / timescale
```

#### Why Timescale 600?

Apple recommends a timescale of **600** for video because it is the **least common multiple** of standard frame rates:

| Frame Rate | Frames in 600 ticks/sec |
|-----------|------------------------|
| 24 fps (film) | 25 ticks per frame |
| 25 fps (PAL) | 24 ticks per frame |
| 30 fps (NTSC) | 20 ticks per frame |
| 60 fps | 10 ticks per frame |

This means you can represent **any number of whole frames** in these systems without rounding.

#### Creating CMTime Values

```swift
// From value and timescale
let oneSecond = CMTime(value: 600, timescale: 600)
let oneFrame24fps = CMTime(value: 25, timescale: 600)
let oneFrame30fps = CMTime(value: 20, timescale: 600)

// From seconds (convenience — internally converts to rational)
let halfSecond = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
// Result: value=300, timescale=600

// CAUTION: This loses precision!
let badTime = CMTimeMakeWithSeconds(0.5, preferredTimescale: 1)
// Cannot represent 0.5 with timescale 1 — gets rounded

// From frame count
func timeForFrame(_ frame: Int, fps: Int, timescale: Int32 = 600) -> CMTime {
    let ticksPerFrame = Int64(timescale) / Int64(fps)
    return CMTime(value: Int64(frame) * ticksPerFrame, timescale: timescale)
}
```

#### Special CMTime Values

```swift
let zero = CMTime.zero                    // 0/1
let invalid = CMTime.invalid              // Not a valid time
let positiveInfinity = CMTime.positiveInfinity
let negativeInfinity = CMTime.negativeInfinity
let indefinite = CMTime.indefinite        // e.g., duration of a live stream

// Checking special values
CMTimeCompare(time, .zero)  // -1, 0, or 1
time.isValid
time.isNumeric      // Valid AND not infinite/indefinite
time.isPositiveInfinity
time.isNegativeInfinity
time.isIndefinite
```

#### CMTime Arithmetic

**Always use the dedicated functions** — they handle overflow, rounding, and special values correctly:

```swift
let a = CMTime(value: 100, timescale: 600)
let b = CMTime(value: 200, timescale: 600)

// Addition & Subtraction
let sum = CMTimeAdd(a, b)          // or a + b in Swift (operator overload available)
let diff = CMTimeSubtract(b, a)    // or b - a

// Comparison
let cmp = CMTimeCompare(a, b)      // -1 (a < b), 0 (equal), 1 (a > b)
let max = CMTimeMaximum(a, b)
let min = CMTimeMinimum(a, b)

// Conversion to seconds (Float64)
let seconds = CMTimeGetSeconds(sum) // Returns Float64

// Multiplication (by scalar)
let doubled = CMTimeMultiplyByRatio(a, multiplier: 2, divisor: 1)

// Halving a duration (trick: double the timescale)
var halfDuration = duration
halfDuration.timescale *= 2  // Equivalent to dividing by 2
```

### CMTimeRange — A Span of Time

```swift
// Creation
let range = CMTimeRange(start: CMTime.zero, duration: CMTime(value: 300, timescale: 600))
let rangeFromTo = CMTimeRange(start: startTime, end: endTime) // end = start + duration

// Convenience
let fullRange = CMTimeRangeMake(start: .zero, duration: asset.duration)

// Properties
range.start      // CMTime
range.duration   // CMTime
range.end        // Computed: start + duration

// Operations
let intersection = CMTimeRangeGetIntersection(rangeA, otherRange: rangeB)
let union = CMTimeRangeGetUnion(rangeA, otherRange: rangeB)
let contains = CMTimeRangeContainsTime(range, time: someTime)
let containsRange = CMTimeRangeContainsTimeRange(outerRange, otherRange: innerRange)
let isEmpty = range.isEmpty

// Special ranges
let zero = CMTimeRange.zero
let invalid = CMTimeRange.invalid
```

### CMTimeMapping — Source-to-Target Time Mapping

Used for time remapping (speed changes, slow motion):

```swift
// Maps a source time range to a target time range
let mapping = CMTimeMapping(
    source: CMTimeRange(start: .zero, duration: CMTime(value: 600, timescale: 600)), // 1 second of source
    target: CMTimeRange(start: .zero, duration: CMTime(value: 1200, timescale: 600))  // stretched to 2 seconds
)
// This represents 0.5x speed (slow motion)

// Utility functions
let mappedTime = CMTimeMapTimeFromRangeToRange(sourceTime, fromRange: source, toRange: target)
let mappedDuration = CMTimeMapDurationFromRangeToRange(sourceDuration, fromRange: source, toRange: target)
```

---

## 2. AVAsset & Track Model

### AVAsset — Immutable Media Container

AVAsset is a **timed collection of media data** — an immutable model representing a media file or remote stream.

```swift
// Loading an asset from a file URL
let url = URL(fileURLWithPath: "/path/to/video.mov")
let asset = AVURLAsset(url: url)

// Modern async loading (iOS 15+ / macOS 12+)
let duration = try await asset.load(.duration)
let tracks = try await asset.loadTracks(withMediaType: .video)
let isPlayable = try await asset.load(.isPlayable)
let isExportable = try await asset.load(.isExportable)

// Legacy synchronous (deprecated but still common)
let legacyDuration = asset.duration
let legacyTracks = asset.tracks(withMediaType: .video)
```

### AVAssetTrack — Single Media Stream

Each track represents one stream of media (video, audio, subtitle, timecode, etc.):

```swift
let videoTrack = try await asset.loadTracks(withMediaType: .video).first!

// Key properties (modern async)
let naturalSize = try await videoTrack.load(.naturalSize)       // CGSize — pixel dimensions
let preferredTransform = try await videoTrack.load(.preferredTransform) // CGAffineTransform — orientation
let timeRange = try await videoTrack.load(.timeRange)           // CMTimeRange
let nominalFrameRate = try await videoTrack.load(.nominalFrameRate) // Float — e.g., 29.97
let estimatedDataRate = try await videoTrack.load(.estimatedDataRate) // Float — bits/sec
let formatDescriptions = try await videoTrack.load(.formatDescriptions) // Codec details

// Track media types
AVMediaType.video
AVMediaType.audio
AVMediaType.subtitle
AVMediaType.timecode
AVMediaType.text
AVMediaType.metadata
```

#### Handling Video Orientation (Critical for iPhone Video)

iPhones record video in landscape sensor orientation and apply a **preferredTransform** to indicate the correct display orientation:

```swift
func isPortraitVideo(_ track: AVAssetTrack) async throws -> Bool {
    let transform = try await track.load(.preferredTransform)
    // Portrait: rotation by +/-90 degrees means a==0 and d==0
    return transform.a == 0 && transform.d == 0
}

func correctedSize(for track: AVAssetTrack) async throws -> CGSize {
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let isPortrait = transform.a == 0 && transform.d == 0
    return isPortrait
        ? CGSize(width: size.height, height: size.width)
        : size
}
```

---

## 3. AVMutableComposition — The Editable Timeline

AVMutableComposition is the **heart of non-destructive editing** in AVFoundation. It assembles media from multiple source assets into a virtual timeline **without copying media data**.

```
AVMutableComposition (conforms to AVAsset)
  +-- AVMutableCompositionTrack[0] (Video A)
  |     [segment: source asset 1, 0s-5s] [segment: source asset 2, 0s-3s]
  +-- AVMutableCompositionTrack[1] (Video B)
  |     [segment: source asset 3, 2s-4s overlapping with track 0]
  +-- AVMutableCompositionTrack[2] (Audio A)
  |     [segment: audio from asset 1, 0s-5s]
  +-- AVMutableCompositionTrack[3] (Audio B)
        [segment: audio from asset 3, 2s-4s]
```

### Creating a Composition

```swift
let composition = AVMutableComposition()

// Set natural size (for player sizing)
composition.naturalSize = CGSize(width: 1920, height: 1080)

// Add tracks
guard let videoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid // Auto-assign ID
) else { return }

guard let audioTrack = composition.addMutableTrack(
    withMediaType: .audio,
    preferredTrackID: kCMPersistentTrackID_Invalid
) else { return }
```

### Inserting Media (Core Editing Operations)

```swift
// Insert a portion of a source track into the composition track
// Parameters:
//   timeRange: which portion of the SOURCE to copy
//   of: the source AVAssetTrack
//   at: where in the COMPOSITION timeline to place it
try videoTrack.insertTimeRange(
    CMTimeRange(start: .zero, duration: sourceAssetTrack.timeRange.duration),
    of: sourceAssetTrack,
    at: .zero  // Position in composition
)

// Insert at a later time (append)
try videoTrack.insertTimeRange(
    CMTimeRange(start: .zero, duration: secondClipTrack.timeRange.duration),
    of: secondClipTrack,
    at: firstClipDuration  // After the first clip
)

// Insert a sub-range (trim)
let inPoint = CMTime(value: 300, timescale: 600)  // 0.5s
let outPoint = CMTime(value: 1800, timescale: 600) // 3.0s
try videoTrack.insertTimeRange(
    CMTimeRange(start: inPoint, duration: CMTimeSubtract(outPoint, inPoint)),
    of: sourceTrack,
    at: insertionPoint
)
```

### Composition-Level Editing Operations

```swift
// Insert empty time (push everything after by duration)
composition.insertEmptyTimeRange(
    CMTimeRange(start: splitPoint, duration: gapDuration)
)

// Remove time range from ALL tracks (ripple delete)
composition.removeTimeRange(
    CMTimeRange(start: cutStart, duration: cutDuration)
)

// Scale time range on ALL tracks (speed change)
composition.scaleTimeRange(
    CMTimeRange(start: .zero, duration: originalDuration),
    toDuration: newDuration  // Shorter = speed up, longer = slow down
)
```

### Track-Level Editing Operations

```swift
// Insert empty time on a single track
videoTrack.insertEmptyTimeRange(
    CMTimeRange(start: gapStart, duration: gapDuration)
)

// Remove from single track
videoTrack.removeTimeRange(
    CMTimeRange(start: cutStart, duration: cutDuration)
)

// Scale on single track
videoTrack.scaleTimeRange(originalRange, toDuration: newDuration)
```

### Finding Compatible Tracks

```swift
// Reuse existing track if compatible (avoids creating too many tracks)
if let existingTrack = composition.mutableTrack(compatibleWith: sourceTrack) {
    try existingTrack.insertTimeRange(range, of: sourceTrack, at: time)
} else {
    let newTrack = composition.addMutableTrack(
        withMediaType: sourceTrack.mediaType,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )
    try newTrack?.insertTimeRange(range, of: sourceTrack, at: time)
}
```

### Track Segments

Each composition track internally consists of **segments** — references back to source media:

```swift
// Read segments (for debugging / visualization)
for segment in videoTrack.segments {
    let sourceURL = segment.sourceURL
    let sourceTimeRange = segment.timeMapping.source  // Time in source file
    let targetTimeRange = segment.timeMapping.target  // Time in composition
    let isEmpty = segment.isEmpty  // true for gaps
}
```

---

## 4. AVVideoComposition — Frame-Level Rendering Control

AVVideoComposition describes **how to composite video frames** at each point in time. Without it, the player uses a default passthrough renderer. With it, you control transforms, opacity, blending, and custom rendering.

### Quick Setup (Auto-Configuration)

```swift
// Automatically configures based on the composition's tracks
let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
// Sets: renderSize, frameDuration, instructions (passthrough for each track)
```

### Manual Configuration

```swift
let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = CGSize(width: 1920, height: 1080)
videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
videoComposition.renderScale = 1.0 // default
videoComposition.instructions = instructions // Array of AVVideoCompositionInstruction
```

### Built-In Instructions

```swift
// Passthrough instruction — display one track unmodified
let passthrough = AVMutableVideoCompositionInstruction()
passthrough.timeRange = CMTimeRange(start: .zero, duration: clipDuration)
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrackA)
passthrough.layerInstructions = [layerInstruction]

// Apply a static transform
layerInstruction.setTransform(rotationTransform, at: .zero)

// Apply a transform ramp (animate over time)
layerInstruction.setTransformRamp(
    fromStart: identityTransform,
    toEnd: slideOutTransform,
    timeRange: transitionRange
)

// Apply opacity
layerInstruction.setOpacity(1.0, at: .zero)

// Apply opacity ramp (fade out)
layerInstruction.setOpacityRamp(
    fromStartOpacity: 1.0,
    toEndOpacity: 0.0,
    timeRange: fadeOutRange
)

// Crop rect
layerInstruction.setCropRectangle(CGRect(x: 0, y: 0, width: 960, height: 1080), at: .zero)
layerInstruction.setCropRectangleRamp(
    fromStartCropRectangle: fullFrame,
    toEndCropRectangle: croppedFrame,
    timeRange: cropAnimationRange
)
```

### CIFilter-Based Composition (Single Track)

For applying CIFilters during playback or export on a single video:

```swift
let videoComposition = AVMutableVideoComposition(asset: asset) { request in
    // request: AVAsynchronousCIImageFilteringRequest
    let sourceImage = request.sourceImage

    // Apply a CIFilter
    let filter = CIFilter(name: "CIGaussianBlur")!
    filter.setValue(sourceImage, forKey: kCIInputImageKey)
    filter.setValue(5.0, forKey: kCIInputRadiusKey)

    // Animate based on composition time
    let time = request.compositionTime
    let progress = CMTimeGetSeconds(time) / CMTimeGetSeconds(asset.duration)
    filter.setValue(progress * 20.0, forKey: kCIInputRadiusKey)

    request.finish(with: filter.outputImage!, context: nil)
}
videoComposition.renderSize = CGSize(width: 1920, height: 1080)
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
```

**Limitation**: The CIFilter approach only works for single-video workflows. For multi-track compositing with transitions, you need a custom compositor.

### Core Animation Tool (Overlays/Watermarks)

```swift
let videoLayer = CALayer()
videoLayer.frame = CGRect(origin: .zero, size: renderSize)

let overlayLayer = CALayer()
overlayLayer.frame = CGRect(origin: .zero, size: renderSize)

// Add watermark
let watermark = CALayer()
watermark.contents = NSImage(named: "logo")
watermark.frame = CGRect(x: 20, y: 20, width: 100, height: 50)
overlayLayer.addSublayer(watermark)

// Add text
let textLayer = CATextLayer()
textLayer.string = "My Video"
textLayer.font = NSFont.systemFont(ofSize: 24)
textLayer.frame = CGRect(x: 0, y: 0, width: 400, height: 50)
overlayLayer.addSublayer(textLayer)

let parentLayer = CALayer()
parentLayer.frame = CGRect(origin: .zero, size: renderSize)
parentLayer.addSublayer(videoLayer)
parentLayer.addSublayer(overlayLayer)

videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: parentLayer
)
```

---

## 5. Custom Video Compositing (AVVideoCompositing Protocol)

For NLE-level control, implement `AVVideoCompositing` to get **per-frame access to all source track pixels** and render custom output using Metal, Core Image, or CPU.

### Protocol Requirements

```swift
class CustomVideoCompositor: NSObject, AVVideoCompositing {

    // REQUIRED: Pixel format for source frames delivered to you
    var sourcePixelBufferAttributes: [String: Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    // REQUIRED: Pixel format for output frames you produce
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    // REQUIRED: Called when the render context changes (size, pixel aspect ratio, etc.)
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Store render context; allocate new pixel buffers from it
        self.renderContext = newRenderContext
    }

    // REQUIRED: Called for each frame that needs compositing
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Get the custom instruction
        guard let instruction = request.videoCompositionInstruction
            as? CustomCompositionInstruction else {
            request.finish(with: NSError(domain: "compositor", code: -1))
            return
        }

        // Get source frames by track ID
        if let foregroundBuffer = request.sourceFrame(byTrackID: instruction.foregroundTrackID),
           let backgroundBuffer = request.sourceFrame(byTrackID: instruction.backgroundTrackID) {

            // Render using Metal/CIContext/CPU
            let outputBuffer = renderContext.newPixelBuffer()!
            renderTransition(
                foreground: foregroundBuffer,
                background: backgroundBuffer,
                output: outputBuffer,
                tween: instruction.tweenFactor(for: request.compositionTime)
            )

            request.finish(withComposedVideoFrame: outputBuffer)
        } else if let passthroughID = instruction.passthroughTrackID,
                  let buffer = request.sourceFrame(byTrackID: passthroughID) {
            // Passthrough — no compositing needed
            request.finish(withComposedVideoFrame: buffer)
        }
    }

    // OPTIONAL: Cancel pending requests
    func cancelAllPendingVideoCompositionRequests() {
        shouldCancelAllRequests = true
        renderingQueue.async(flags: .barrier) { [weak self] in
            self?.shouldCancelAllRequests = false
        }
    }
}
```

### Custom Instruction Protocol

```swift
class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    // REQUIRED protocol properties
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = true
    var containsTweening: Bool = true

    // For passthrough optimization
    var passthroughTrackID: CMPersistentTrackID? = nil

    // Which tracks this instruction needs
    var requiredSourceTrackIDs: [NSValue]?

    // Custom NLE properties
    var foregroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var backgroundTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var transitionType: TransitionType = .crossDissolve

    // Calculate tween factor (0.0 to 1.0) for animation
    func tweenFactor(for time: CMTime) -> Float {
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(time, timeRange.start))
        let duration = CMTimeGetSeconds(timeRange.duration)
        return Float(elapsed / duration)
    }

    // Passthrough initializer
    init(passthroughTrackID: CMPersistentTrackID, timeRange: CMTimeRange) {
        self.timeRange = timeRange
        self.passthroughTrackID = passthroughTrackID
        self.containsTweening = false
        self.requiredSourceTrackIDs = nil  // nil signals passthrough
        super.init()
    }

    // Transition initializer
    init(sourceTrackIDs: [CMPersistentTrackID], timeRange: CMTimeRange) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = sourceTrackIDs.map { NSNumber(value: $0) as NSValue }
        super.init()
    }
}
```

### Performance Optimization Flags (Critical)

From WWDC 2013 Session 612:

- **`passthroughTrackID`**: When set (not `kCMPersistentTrackID_Invalid`), the compositor is **completely bypassed** and the source frame is passed directly to output. Use this for non-transition segments.
- **`requiredSourceTrackIDs`**: Only the listed tracks will be decoded. Unlisted tracks skip decoding entirely. Set to `nil` for passthrough.
- **`containsTweening`**: When `false`, the compositor can **reuse the last rendered frame** instead of re-rendering every frame. Set to `false` for static segments.

### Assigning Custom Compositor

```swift
let videoComposition = AVMutableVideoComposition()
videoComposition.customVideoCompositorClass = CustomVideoCompositor.self
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.renderSize = CGSize(width: 1920, height: 1080)
videoComposition.instructions = instructions
```

---

## 6. AVAudioMix — Audio Mixing Pipeline

### Basic Volume Control

```swift
let audioMix = AVMutableAudioMix()

let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
parameters.trackID = audioTrack.trackID

// Set static volume
parameters.setVolume(0.8, at: .zero)

// Volume ramp (fade in)
parameters.setVolumeRamp(
    fromStartVolume: 0.0,
    toEndVolume: 1.0,
    timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 30)) // 2 seconds
)

// Volume ramp (fade out at end)
let fadeOutStart = CMTimeSubtract(composition.duration, CMTime(value: 60, timescale: 30))
parameters.setVolumeRamp(
    fromStartVolume: 1.0,
    toEndVolume: 0.0,
    timeRange: CMTimeRange(start: fadeOutStart, duration: CMTime(value: 60, timescale: 30))
)

audioMix.inputParameters = [parameters]
```

### Audio Processing Tap (Advanced)

For real-time audio processing (EQ, compression, effects):

```swift
var callbacks = MTAudioProcessingTapCallbacks(
    version: kMTAudioProcessingTapCallbacksVersion_0,
    clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
    init: tapInit,
    finalize: tapFinalize,
    prepare: tapPrepare,
    unprepare: tapUnprepare,
    process: tapProcess
)

var tap: Unmanaged<MTAudioProcessingTap>?
let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)

let inputParameters = AVMutableAudioMixInputParameters()
inputParameters.audioTapProcessor = tap?.takeRetainedValue()
inputParameters.trackID = audioTrack.trackID
```

---

## 7. Playback Pipeline (AVPlayer / AVPlayerItem)

### Basic Composition Playback

```swift
// Create player item from composition
let playerItem = AVPlayerItem(asset: composition)
playerItem.videoComposition = videoComposition
playerItem.audioMix = audioMix

// Create player
let player = AVPlayer(playerItem: playerItem)

// macOS: Attach to AVPlayerView
let playerView = AVPlayerView()
playerView.player = player

// Start playback
player.play()
```

### Smooth Scrubbing (Chase Seek Pattern)

This is the **Apple-recommended pattern** (TN QA1820) for smooth scrubbing in an NLE:

```swift
class TimelineScrubber {
    private let player: AVPlayer
    private var isSeekInProgress = false
    private var chaseTime: CMTime = .zero

    init(player: AVPlayer) {
        self.player = player
    }

    /// Called when the user drags the scrubber / playhead
    func scrubTo(time: CMTime) {
        player.pause()

        if CMTimeCompare(time, chaseTime) != 0 {
            chaseTime = time
            if !isSeekInProgress {
                trySeekToChaseTime()
            }
        }
    }

    private func trySeekToChaseTime() {
        guard player.currentItem?.status == .readyToPlay else { return }
        actuallySeekToTime()
    }

    private func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTarget = chaseTime

        player.seek(
            to: seekTarget,
            toleranceBefore: .zero,   // Frame-accurate seek
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard let self = self else { return }

            if CMTimeCompare(seekTarget, self.chaseTime) == 0 {
                // No new seek requested while we were seeking
                self.isSeekInProgress = false
            } else {
                // User moved scrubber again — chase the new position
                self.trySeekToChaseTime()
            }
        }
    }
}
```

**Key points:**
- Use `toleranceBefore: .zero, toleranceAfter: .zero` for frame-accurate seeking (required for NLE)
- The chase pattern ensures rapid scrubber movement doesn't queue hundreds of seeks
- Each new seek target replaces the previous, and only the latest target is executed

### Periodic Time Observer (Playhead Tracking)

```swift
let interval = CMTime(value: 1, timescale: 30) // Every frame at 30fps
let observer = player.addPeriodicTimeObserver(
    forInterval: interval,
    queue: .main
) { [weak self] time in
    self?.updatePlayheadPosition(time)
    self?.updateTimecodeDisplay(time)
}

// Remove when done
player.removeTimeObserver(observer)
```

### Boundary Time Observer

```swift
// Notify at specific times (e.g., marker positions)
let times = [
    NSValue(time: CMTime(value: 300, timescale: 600)),
    NSValue(time: CMTime(value: 600, timescale: 600))
]
let observer = player.addBoundaryTimeObserver(
    forTimes: times,
    queue: .main
) {
    print("Reached a marker!")
}
```

### AVPlayerItemVideoOutput (Frame Tapping for Metal Preview)

For getting pixel buffers during playback to apply Metal effects:

```swift
let outputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferMetalCompatibilityKey as String: true
]
let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
playerItem.add(videoOutput)

// In your display link callback (CADisplayLink / CVDisplayLink):
func displayLinkFired(_ displayLink: CVDisplayLink) {
    let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())

    if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
        if let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: nil
        ) {
            // Convert to Metal texture and render
            renderWithMetal(pixelBuffer)
        }
    }
}
```

---

## 8. Export Pipeline

### AVAssetExportSession (Simple Export)

Best for straightforward exports with standard presets:

```swift
guard let exportSession = AVAssetExportSession(
    asset: composition,
    presetName: AVAssetExportPresetHighestQuality
) else { return }

exportSession.outputURL = outputURL
exportSession.outputFileType = .mov
exportSession.videoComposition = videoComposition
exportSession.audioMix = audioMix
exportSession.shouldOptimizeForNetworkUse = true

// Optional: Trim
exportSession.timeRange = CMTimeRange(start: inPoint, duration: duration)

// Export
await exportSession.export()

switch exportSession.status {
case .completed:
    print("Export succeeded: \(outputURL)")
case .failed:
    print("Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
case .cancelled:
    print("Export cancelled")
default:
    break
}

// Progress monitoring
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
    let progress = exportSession.progress // 0.0 to 1.0
    updateProgressBar(progress)
    if exportSession.status != .exporting {
        timer.invalidate()
    }
}
```

#### Export Presets

```swift
AVAssetExportPresetHighestQuality     // Best available quality
AVAssetExportPresetMediumQuality      // Balanced
AVAssetExportPresetLowQuality         // Small file
AVAssetExportPreset1920x1080          // Specific resolution
AVAssetExportPreset3840x2160          // 4K
AVAssetExportPresetHEVCHighestQuality // H.265
AVAssetExportPresetAppleProRes422LPCM // ProRes 422 with PCM audio
AVAssetExportPresetAppleProRes4444LPCM // ProRes 4444 with PCM audio
AVAssetExportPresetPassthrough        // No re-encoding
```

### AVAssetReader + AVAssetWriter (Full Control Export)

For professional-grade export with full control over codec settings:

```swift
// READER setup
let reader = try AVAssetReader(asset: composition)

let videoReaderOutput = AVAssetReaderVideoCompositionOutput(
    videoTracks: composition.tracks(withMediaType: .video),
    videoSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
)
videoReaderOutput.videoComposition = videoComposition
reader.add(videoReaderOutput)

let audioReaderOutput = AVAssetReaderAudioMixOutput(
    audioTracks: composition.tracks(withMediaType: .audio),
    audioSettings: nil // Native format
)
audioReaderOutput.audioMix = audioMix
reader.add(audioReaderOutput)

// WRITER setup
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

let videoWriterInput = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: 1920,
        AVVideoHeightKey: 1080,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 20_000_000,        // 20 Mbps
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
            AVVideoAllowFrameReorderingKey: true,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]
    ]
)
videoWriterInput.expectsMediaDataInRealTime = false
writer.add(videoWriterInput)

let audioWriterInput = AVAssetWriterInput(
    mediaType: .audio,
    outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
)
writer.add(audioWriterInput)

// START
reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// PROCESS video
let videoQueue = DispatchQueue(label: "video.writer")
videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
    while videoWriterInput.isReadyForMoreMediaData {
        if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
            videoWriterInput.append(sampleBuffer)
        } else {
            videoWriterInput.markAsFinished()
            break
        }
    }
}

// PROCESS audio (similar pattern on separate queue)
let audioQueue = DispatchQueue(label: "audio.writer")
audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
    while audioWriterInput.isReadyForMoreMediaData {
        if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
            audioWriterInput.append(sampleBuffer)
        } else {
            audioWriterInput.markAsFinished()
            break
        }
    }
}

// FINISH (after both inputs marked as finished)
await writer.finishWriting()
```

**Important**: AVAssetReader/Writer are **NOT for real-time processing**. They are offline batch processing tools. Use AVPlayer + AVVideoCompositing for real-time preview.

### ProRes Export Settings

```swift
// ProRes 422
let proRes422Settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes422,
    AVVideoWidthKey: 1920,
    AVVideoHeightKey: 1080
]

// ProRes 4444 (with alpha)
let proRes4444Settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes4444,
    AVVideoWidthKey: 1920,
    AVVideoHeightKey: 1080
]

// ProRes 422 HQ
let proResHQSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.proRes422HQ,
    AVVideoWidthKey: 3840,
    AVVideoHeightKey: 2160
]
```

---

## 9. Thumbnail Generation (AVAssetImageGenerator)

### Single Thumbnail

```swift
let generator = AVAssetImageGenerator(asset: composition)
generator.appliesPreferredTrackTransform = true  // Correct orientation
generator.maximumSize = CGSize(width: 320, height: 180) // Reduce size for speed
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

// Modern async (iOS 16+ / macOS 13+)
let (image, actualTime) = try await generator.image(at: requestedTime)

// Legacy
generator.generateCGImagesAsynchronously(
    forTimes: [NSValue(time: requestedTime)]
) { requestedTime, image, actualTime, result, error in
    if let image = image {
        DispatchQueue.main.async {
            self.thumbnailView.image = NSImage(cgImage: image, size: .zero)
        }
    }
}
```

### Batch Thumbnails for Timeline Strip

```swift
func generateTimelineThumbnails(
    asset: AVAsset,
    count: Int,
    size: CGSize
) async throws -> [(CMTime, CGImage)] {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = size
    // Allow tolerance for speed (don't require exact frames)
    generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
    generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)

    let duration = try await asset.load(.duration)
    let increment = CMTimeGetSeconds(duration) / Double(count)

    var times: [NSValue] = []
    for i in 0..<count {
        let time = CMTimeMakeWithSeconds(Double(i) * increment, preferredTimescale: 600)
        times.append(NSValue(time: time))
    }

    var results: [(CMTime, CGImage)] = []

    generator.generateCGImagesAsynchronously(forTimes: times) { requested, image, actual, result, error in
        if result == .succeeded, let image = image {
            results.append((actual, image))
        }
    }

    return results
}
```

**Performance tip**: Setting non-zero tolerance (e.g., `CMTime(value: 1, timescale: 2)`) allows the generator to return the nearest keyframe, which is **much faster** than seeking to exact frames.

---

## 10. Multi-Track Transition Architecture

### The Two-Track Alternating Pattern

This is the **standard AVFoundation pattern for transitions**. You need two video tracks, alternating clips between them, with overlapping time ranges during transitions:

```
Timeline:  |---Clip A---|====|---Clip B---|====|---Clip C---|
Track 0:   [  Clip A         ][             Clip C          ]
Track 1:   [             Clip B              ]
                        ^^^^^           ^^^^^
                      Transition      Transition
                      (overlap)       (overlap)
```

#### Complete Implementation

```swift
class TransitionCompositionBuilder {

    struct ClipInfo {
        let asset: AVAsset
        let timeRange: CMTimeRange  // Portion of source to use
    }

    let clips: [ClipInfo]
    let transitionDuration: CMTime
    let renderSize: CGSize
    let frameDuration: CMTime

    func buildComposition() throws -> (
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition
    ) {
        let composition = AVMutableComposition()
        composition.naturalSize = renderSize

        // Create TWO video tracks and TWO audio tracks (for alternating)
        guard let videoTrackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackCreationFailed }

        let videoTracks = [videoTrackA, videoTrackB]
        let audioTracks = [audioTrackA, audioTrackB]

        // Ensure transition is not longer than half the shortest clip
        var actualTransitionDuration = transitionDuration
        for clip in clips {
            var halfDuration = clip.timeRange.duration
            halfDuration.timescale *= 2  // Halve by doubling timescale
            actualTransitionDuration = CMTimeMinimum(actualTransitionDuration, halfDuration)
        }

        var passThroughRanges: [CMTimeRange] = []
        var transitionRanges: [CMTimeRange] = []
        var nextClipStartTime: CMTime = .zero

        for (i, clip) in clips.enumerated() {
            let alternatingIndex = i % 2

            // Get source tracks
            let sourceVideoTrack = try await clip.asset.loadTracks(withMediaType: .video).first!
            let sourceAudioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first

            // Insert video
            try videoTracks[alternatingIndex].insertTimeRange(
                clip.timeRange,
                of: sourceVideoTrack,
                at: nextClipStartTime
            )

            // Insert audio (if available)
            if let audioSource = sourceAudioTrack {
                try audioTracks[alternatingIndex].insertTimeRange(
                    clip.timeRange,
                    of: audioSource,
                    at: nextClipStartTime
                )
            }

            // Calculate pass-through range (excluding transition overlap)
            var passRange = CMTimeRange(start: nextClipStartTime, duration: clip.timeRange.duration)
            if i > 0 {
                // Not the first clip: trim start for incoming transition
                passRange.start = CMTimeAdd(passRange.start, actualTransitionDuration)
                passRange.duration = CMTimeSubtract(passRange.duration, actualTransitionDuration)
            }
            if i < clips.count - 1 {
                // Not the last clip: trim end for outgoing transition
                passRange.duration = CMTimeSubtract(passRange.duration, actualTransitionDuration)
            }
            passThroughRanges.append(passRange)

            // Advance insert point (overlapping by transition duration)
            nextClipStartTime = CMTimeAdd(nextClipStartTime, clip.timeRange.duration)
            nextClipStartTime = CMTimeSubtract(nextClipStartTime, actualTransitionDuration)

            // Record transition range
            if i < clips.count - 1 {
                transitionRanges.append(CMTimeRange(
                    start: nextClipStartTime,
                    duration: actualTransitionDuration
                ))
            }
        }

        // Build video composition instructions
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for (i, _) in clips.enumerated() {
            let altIdx = i % 2

            // Passthrough instruction
            let passInstruction = AVMutableVideoCompositionInstruction()
            passInstruction.timeRange = passThroughRanges[i]
            let passLayer = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTracks[altIdx]
            )
            passInstruction.layerInstructions = [passLayer]
            instructions.append(passInstruction)

            // Transition instruction (if not last clip)
            if i < clips.count - 1 {
                let transInstruction = AVMutableVideoCompositionInstruction()
                transInstruction.timeRange = transitionRanges[i]

                let fromLayer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[altIdx]
                )
                let toLayer = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTracks[1 - altIdx]
                )

                // Cross-dissolve: fade out the outgoing clip
                fromLayer.setOpacityRamp(
                    fromStartOpacity: 1.0,
                    toEndOpacity: 0.0,
                    timeRange: transitionRanges[i]
                )

                transInstruction.layerInstructions = [fromLayer, toLayer]
                instructions.append(transInstruction)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions

        return (composition, videoComposition)
    }
}
```

---

## 11. Metal Integration for Custom Compositing

### CVPixelBuffer to Metal Texture

```swift
class MetalCompositorRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var textureCache: CVMetalTextureCache?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &cache
        ) == kCVReturnSuccess else { return nil }
        self.textureCache = cache
    }

    func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,         // Plane index
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTex = cvTexture else { return nil }

        return CVMetalTextureGetTexture(cvTex)
    }

    func renderTransition(
        foreground: CVPixelBuffer,
        background: CVPixelBuffer,
        output: CVPixelBuffer,
        tween: Float
    ) {
        guard let fgTexture = texture(from: foreground),
              let bgTexture = texture(from: background),
              let outTexture = texture(from: output) else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!

        // Set up compute or render pass to blend textures
        // using tween factor...
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = outTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        // Configure pipeline, set textures, draw quad...
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
```

### IOSurface Lifecycle with CVPixelBufferPool

When Metal is processing a CVPixelBuffer obtained from a pool, you must prevent the pool from recycling the backing IOSurface:

```swift
// Before Metal starts processing
IOSurfaceIncrementUseCount(CVPixelBufferGetIOSurface(pixelBuffer)!.takeUnretainedValue())

// In Metal command buffer completion handler
commandBuffer.addCompletedHandler { _ in
    IOSurfaceDecrementUseCount(surface)
}
```

---

## 12. CVPixelBuffer & Memory Management

### Creating CVPixelBuffers

```swift
// From a pool (preferred for repeated allocation)
var pool: CVPixelBufferPool?
let poolAttributes: [String: Any] = [
    kCVPixelBufferPoolMinimumBufferCountKey as String: 3
]
let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: 1920,
    kCVPixelBufferHeightKey as String: 1080,
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]  // Enable IOSurface backing
]

CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary,
                         pixelBufferAttributes as CFDictionary, &pool)

// Allocate from pool
var pixelBuffer: CVPixelBuffer?
CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &pixelBuffer)
```

### Memory Tips

- **Use `autoreleasepool`** in tight render loops to prevent CVPixelBuffer accumulation
- **Pool recycling**: When a CVPixelBuffer allocated from a pool is released, its backing IOSurface returns to the pool for reuse
- **Minimize format conversions**: Request source buffers in the same format as your render pipeline (e.g., BGRA for Metal)
- **Use `renderContext.newPixelBuffer()`** in custom compositors — this allocates from a managed pool

---

## 13. Modern Swift Concurrency with AVFoundation

### Async Property Loading (iOS 15+ / macOS 12+)

```swift
// Modern approach — type-safe, non-blocking
let duration = try await asset.load(.duration)
let tracks = try await asset.loadTracks(withMediaType: .video)
let isPlayable = try await asset.load(.isPlayable)
let naturalSize = try await tracks.first?.load(.naturalSize)

// Load multiple properties at once
let (dur, playable) = try await asset.load(.duration, .isPlayable)
```

### Legacy Approach (Still Common)

```swift
// Pre-iOS 15 — string-based, callback-based
asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
    var error: NSError?
    let status = asset.statusOfValue(forKey: "duration", error: &error)
    if status == .loaded {
        let duration = asset.duration
        // Safe to use
    }
}
```

### Swift 6 Sendability Considerations

AVFoundation types are generally not `Sendable`. When working with strict concurrency:

```swift
// Use @preconcurrency import to suppress warnings temporarily
@preconcurrency import AVFoundation

// Or isolate AVFoundation work to a specific actor
@MainActor
class CompositionManager {
    let composition = AVMutableComposition()

    func addClip(_ asset: AVAsset) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        // All composition manipulation on MainActor
    }
}
```

---

## 14. Time Remapping & Speed Changes

### Composition-Level Speed Change

```swift
// Slow motion (2x slower)
composition.scaleTimeRange(
    CMTimeRange(start: .zero, duration: originalDuration),
    toDuration: CMTimeMultiplyByRatio(originalDuration, multiplier: 2, divisor: 1)
)

// Speed up (2x faster)
composition.scaleTimeRange(
    CMTimeRange(start: .zero, duration: originalDuration),
    toDuration: CMTimeMultiplyByRatio(originalDuration, multiplier: 1, divisor: 2)
)
```

### Track-Level Speed Change

```swift
// Speed up just one segment on a track
let segmentRange = CMTimeRange(start: segmentStart, duration: segmentDuration)
let newDuration = CMTimeMultiplyByRatio(segmentDuration, multiplier: 1, divisor: 3) // 3x speed
videoTrack.scaleTimeRange(segmentRange, toDuration: newDuration)
```

### Understanding CMTimeMapping in Segments

```swift
// After scaleTimeRange, the track segment will have a CMTimeMapping where
// source.duration != target.duration
for segment in track.segments {
    let mapping = segment.timeMapping
    let sourceDuration = CMTimeGetSeconds(mapping.source.duration)
    let targetDuration = CMTimeGetSeconds(mapping.target.duration)
    let speedFactor = sourceDuration / targetDuration
    // speedFactor > 1 = sped up, < 1 = slowed down
}
```

### Variable Speed with Multiple Segments

```swift
// Build a composition with different speeds for different segments
let composition = AVMutableComposition()
let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!

// Normal speed segment (0-5s)
try track.insertTimeRange(
    CMTimeRange(start: .zero, duration: CMTime(value: 3000, timescale: 600)),
    of: sourceTrack,
    at: .zero
)

// Slow-mo segment (5-10s of source, stretched to 10 seconds)
let slowMoSource = CMTimeRange(
    start: CMTime(value: 3000, timescale: 600),
    duration: CMTime(value: 3000, timescale: 600)
)
try track.insertTimeRange(slowMoSource, of: sourceTrack, at: CMTime(value: 3000, timescale: 600))

// Scale the slow-mo segment
track.scaleTimeRange(
    CMTimeRange(start: CMTime(value: 3000, timescale: 600), duration: CMTime(value: 3000, timescale: 600)),
    toDuration: CMTime(value: 6000, timescale: 600) // 2x slower
)
```

---

## 15. Performance Tips & Gotchas

### Track Count Management

- **Use only 2 video tracks** for alternating clip placement with transitions
- Creating a new track for each clip wastes decoder resources
- Each active video track requires a dedicated hardware decoder instance
- Reuse tracks with `mutableTrack(compatibleWith:)` when clips don't overlap

### Seek Performance

- Default `seek(to:)` has tolerance — trades precision for speed
- `seek(to:toleranceBefore:.zero, toleranceAfter:.zero)` requires decoding from the nearest keyframe — can be slow for long-GOP codecs (H.264/H.265)
- ProRes is all-intra — every frame is a keyframe — best for NLE scrubbing performance
- Always use the **chase seek pattern** (Section 7) for scrubbing

### Video Composition Gotchas

1. **frameDuration** must be set correctly — setting it to the asset duration produces only one frame
2. **Gaps between instructions** produce black frames
3. **Layer instruction order matters** — first in array is topmost
4. **setTransformRamp broke in iOS 13.0** (fixed in 13.1) — test thoroughly
5. **Multiple segments on same track** cause frame drops at segment boundaries on some devices

### Memory Management

- Use `autoreleasepool` in render loops
- Release CVPixelBuffers promptly — they back significant GPU memory
- Use IOSurfaceIncrementUseCount/DecrementUseCount when sharing with Metal
- Monitor with Instruments: Allocations, Leaks, Metal System Trace

### Export Performance

- `AVAssetExportSession` is simpler but limited to presets
- `AVAssetReader/Writer` gives full control but is 3-6x slower for simple operations
- `AVAssetExportSession` with a custom `AVVideoCompositing` compositor is nearly as fast as raw `AVAssetWriter`
- Apple Silicon hardware-accelerates ProRes encode/decode (M1+), HEVC encode/decode, and H.264

### Backgrounding (iOS)

- OpenGL/Metal compositors **cannot render when the app is backgrounded** on iOS
- You must provide a **CPU fallback** compositor
- macOS does not have this limitation

---

## 16. Debugging Compositions

### Visual Debugging

Apple provides **AVCompositionDebugViewer** sample code for both macOS and iOS that draws:
- Green bars for video track segments
- Blue bars for audio track segments
- Orange for video composition instructions
- Red for gaps or errors

### Validation API

```swift
// Implement AVVideoCompositionValidationHandling
extension CompositionBuilder: AVVideoCompositionValidationHandling {
    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingInvalidValueForKey key: String
    ) -> Bool {
        print("Invalid value for key: \(key)")
        return true // Continue validating to find all errors
    }

    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingEmptyTimeRange timeRange: CMTimeRange
    ) -> Bool {
        print("Empty time range: \(timeRange)")
        return true
    }

    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingInvalidTimeRangeIn instruction: AVVideoCompositionInstructionProtocol
    ) -> Bool {
        print("Invalid time range in instruction: \(instruction.timeRange)")
        return true
    }

    func videoComposition(
        _ videoComposition: AVVideoComposition,
        shouldContinueValidatingAfterFindingInvalidTrackIDIn instruction: AVVideoCompositionInstructionProtocol,
        layerInstruction: AVVideoCompositionLayerInstruction,
        asset: AVAsset
    ) -> Bool {
        print("Invalid track ID in layer instruction")
        return true
    }
}

// Run validation
let isValid = videoComposition.isValid(
    for: composition,
    timeRange: CMTimeRange(start: .zero, duration: composition.duration),
    validationDelegate: self
)
```

### Common Debugging Checks

```swift
func debugComposition(_ composition: AVMutableComposition) {
    print("=== Composition Debug ===")
    print("Duration: \(CMTimeGetSeconds(composition.duration))s")
    print("Natural size: \(composition.naturalSize)")

    for track in composition.tracks {
        print("\nTrack \(track.trackID) [\(track.mediaType)]:")
        for (i, segment) in track.segments.enumerated() {
            let source = segment.timeMapping.source
            let target = segment.timeMapping.target
            print("  Segment \(i): source=[\(CMTimeGetSeconds(source.start))-\(CMTimeGetSeconds(source.end))] "
                + "target=[\(CMTimeGetSeconds(target.start))-\(CMTimeGetSeconds(target.end))] "
                + "empty=\(segment.isEmpty)")
        }
    }
}
```

---

## 17. Architecture Patterns from Open-Source Frameworks

### VideoLab Architecture (After Effects-like)

VideoLab abstracts AVFoundation into a layer-based composition system:

```
RenderComposition (top-level container)
  ├── renderSize: CGSize
  ├── frameDuration: CMTime
  ├── backgroundColor: CIColor
  └── layers: [RenderLayer]
        ├── source: Source (video, image, audio)
        ├── timeRange: CMTimeRange
        ├── transform: Transform
        ├── audioConfiguration: AudioConfiguration
        ├── operations: [RenderLayerOperation] (effects chain)
        └── layerLevel: Int (z-order)

RenderLayerGroup : RenderLayer (pre-composition)
  └── layers: [RenderLayer]  // nested composition
```

**Key design decisions:**
- Video track reuse when layers don't overlap temporally
- One audio track per audio layer (required for per-layer pitch control)
- Custom `AVVideoCompositing` implementation renders layers bottom-up by z-order
- `VideoCompositionInstruction` carries all layer/blending info per time segment

### Cabbage Architecture (Timeline-based)

```
Timeline
  ├── videoChannel: [VideoProvider]
  ├── audioChannel: [AudioProvider]
  └── overlays: [VideoProvider]

VideoProvider protocol
  ├── resource: Resource
  ├── videoConfiguration: VideoConfiguration
  ├── audioConfiguration: AudioConfiguration
  └── startTime: CMTime

TransitionableVideoProvider : VideoProvider
  └── transition: VideoTransition?
```

**Key design decisions:**
- Uses CIContext for rendering (simpler than Metal, but less control)
- Source pixel buffer format: YCbCr 420 (native H.264 decode output)
- Output pixel buffer format: BGRA (required for Core Image rendering)
- Custom `AVVideoCompositing` with `autoreleasepool` in render loop

### Recommended NLE Architecture Pattern

For a DaVinci Resolve-style NLE, combine patterns:

```
Project
  └── Timeline
        ├── videoTracks: [Track]  // Visual hierarchy
        │     └── clips: [Clip]
        │           ├── asset: AVAsset
        │           ├── sourceTimeRange: CMTimeRange
        │           ├── timelineOffset: CMTime
        │           ├── speed: Double
        │           └── effects: [Effect]
        ├── audioTracks: [Track]
        └── transitions: [Transition]
              ├── timeRange: CMTimeRange
              ├── type: TransitionType
              └── tracks: (from: Track, to: Track)

CompositionBuilder  // Converts Timeline → AVFoundation objects
  ├── buildAVMutableComposition()
  ├── buildAVVideoComposition()
  ├── buildAVAudioMix()
  └── buildPlayerItem() / buildExportSession()
```

**Separation of concerns**: The Timeline model is your app's domain model (serializable, undoable). The `CompositionBuilder` translates it into AVFoundation objects for playback/export. This separation enables:
- Undo/redo by operating on the Timeline model and rebuilding the composition
- Serialization/deserialization of project files
- UI binding to the Timeline model
- Decoupling from AVFoundation internals

---

## 18. Complete NLE Composition Builder Example

This brings together all concepts into a production-ready composition builder:

```swift
import AVFoundation
import CoreMedia

/// Represents a clip on the timeline
struct TimelineClip {
    let id: UUID
    let asset: AVAsset
    let sourceIn: CMTime        // In-point within source
    let sourceOut: CMTime       // Out-point within source
    let timelinePosition: CMTime // Position on timeline
    let speed: Double           // 1.0 = normal, 0.5 = half speed, 2.0 = double

    var sourceDuration: CMTime {
        CMTimeSubtract(sourceOut, sourceIn)
    }

    var timelineDuration: CMTime {
        CMTimeMultiplyByFloat64(sourceDuration, multiplier: 1.0 / speed)
    }

    var sourceRange: CMTimeRange {
        CMTimeRange(start: sourceIn, duration: sourceDuration)
    }
}

/// Represents a transition between two clips
struct TimelineTransition {
    let duration: CMTime
    let type: TransitionType

    enum TransitionType {
        case crossDissolve
        case diagonalWipe
        case push(direction: PushDirection)
    }

    enum PushDirection {
        case left, right, up, down
    }
}

/// Builds AVFoundation composition objects from timeline model
class NLECompositionBuilder {

    let renderSize: CGSize
    let frameRate: Int32

    init(renderSize: CGSize = CGSize(width: 1920, height: 1080), frameRate: Int32 = 30) {
        self.renderSize = renderSize
        self.frameRate = frameRate
    }

    func build(
        clips: [TimelineClip],
        transitions: [TimelineTransition?]  // nil = no transition between clips[i] and clips[i+1]
    ) async throws -> (
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix
    ) {
        let composition = AVMutableComposition()
        composition.naturalSize = renderSize

        // Two alternating tracks for transitions
        guard let videoTrackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackCreationFailed }

        let videoTracks = [videoTrackA, videoTrackB]
        let audioTracks = [audioTrackA, audioTrackB]

        var insertTime: CMTime = .zero
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []

        for (i, clip) in clips.enumerated() {
            let trackIndex = i % 2

            // Load source tracks
            let sourceTracks = try await clip.asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = sourceTracks.first else { continue }

            // Insert video
            try videoTracks[trackIndex].insertTimeRange(
                clip.sourceRange,
                of: sourceVideoTrack,
                at: insertTime
            )

            // Insert audio (if available)
            if let sourceAudioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
                try audioTracks[trackIndex].insertTimeRange(
                    clip.sourceRange,
                    of: sourceAudioTrack,
                    at: insertTime
                )
            }

            // Apply speed change if needed
            if clip.speed != 1.0 {
                let insertedRange = CMTimeRange(start: insertTime, duration: clip.sourceDuration)
                videoTracks[trackIndex].scaleTimeRange(insertedRange, toDuration: clip.timelineDuration)
                audioTracks[trackIndex].scaleTimeRange(insertedRange, toDuration: clip.timelineDuration)
            }

            // Calculate transition overlap
            let transitionBefore = (i > 0) ? transitions[i - 1] : nil
            let transitionAfter = (i < clips.count - 1) ? transitions[i] : nil

            // Build passthrough range
            var passStart = insertTime
            var passDuration = clip.timelineDuration

            if let tb = transitionBefore {
                passStart = CMTimeAdd(passStart, tb.duration)
                passDuration = CMTimeSubtract(passDuration, tb.duration)
            }
            if let ta = transitionAfter {
                passDuration = CMTimeSubtract(passDuration, ta.duration)
            }

            // Passthrough instruction
            let passInstruction = AVMutableVideoCompositionInstruction()
            passInstruction.timeRange = CMTimeRange(start: passStart, duration: passDuration)
            let passLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[trackIndex])
            passInstruction.layerInstructions = [passLayer]
            instructions.append(passInstruction)

            // Transition instruction (outgoing)
            if let ta = transitionAfter, i < clips.count - 1 {
                let transStart = CMTimeAdd(insertTime, CMTimeSubtract(clip.timelineDuration, ta.duration))
                let transRange = CMTimeRange(start: transStart, duration: ta.duration)

                let transInstruction = AVMutableVideoCompositionInstruction()
                transInstruction.timeRange = transRange

                let fromLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[trackIndex])
                let toLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[1 - trackIndex])

                // Apply transition effect
                switch ta.type {
                case .crossDissolve:
                    fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: transRange)
                case .push(let direction):
                    let dx: CGFloat = direction == .left ? -renderSize.width : (direction == .right ? renderSize.width : 0)
                    let dy: CGFloat = direction == .up ? -renderSize.height : (direction == .down ? renderSize.height : 0)
                    fromLayer.setTransformRamp(
                        fromStart: .identity,
                        toEnd: CGAffineTransform(translationX: dx, y: dy),
                        timeRange: transRange
                    )
                    toLayer.setTransformRamp(
                        fromStart: CGAffineTransform(translationX: -dx, y: -dy),
                        toEnd: .identity,
                        timeRange: transRange
                    )
                default:
                    fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: transRange)
                }

                transInstruction.layerInstructions = [fromLayer, toLayer]
                instructions.append(transInstruction)
            }

            // Advance timeline position
            insertTime = CMTimeAdd(insertTime, clip.timelineDuration)
            if let ta = transitionAfter {
                insertTime = CMTimeSubtract(insertTime, ta.duration)
            }
        }

        // Sort instructions by start time
        instructions.sort { CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0 }

        // Build video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)
        videoComposition.instructions = instructions

        // Build audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters

        return (composition, videoComposition, audioMix)
    }

    /// Create an AVPlayerItem for real-time preview
    func playerItem(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix
    ) -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }

    /// Create an export session
    func exportSession(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix,
        outputURL: URL,
        preset: String = AVAssetExportPresetHighestQuality
    ) -> AVAssetExportSession? {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { return nil }
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        return session
    }
}

enum CompositionError: Error {
    case trackCreationFailed
    case sourceTrackNotFound
    case invalidTimeRange
}
```

---

## Key Takeaways for NLE Development

1. **CMTime is your foundation** — Always use rational time arithmetic with timescale 600. Never use Float/Double for time calculations.

2. **Separate domain model from AVFoundation** — Build your timeline model independently, then use a builder to create AVFoundation objects. This enables undo/redo, serialization, and UI binding.

3. **Two-track alternating pattern** is essential for transitions. You cannot crossfade between clips on the same track.

4. **Custom compositing (AVVideoCompositing)** unlocks NLE-quality rendering. Use Metal for performance, CIContext for convenience.

5. **Passthrough optimization** via `passthroughTrackID`, `requiredSourceTrackIDs`, and `containsTweening` is critical for smooth playback — avoid rendering frames that don't need compositing.

6. **Chase seek pattern** is mandatory for smooth scrubbing. Never fire rapid sequential seeks.

7. **AVAssetExportSession for simple exports**, AVAssetReader/Writer for full codec control. ProRes for professional workflows.

8. **Validate compositions** using AVVideoCompositionValidationHandling and visual debugging tools.

9. **Memory management**: Use autoreleasepool in render loops, respect IOSurface lifecycle when sharing with Metal, and allocate from pools.

10. **Test with varied content**: Different codecs (H.264, HEVC, ProRes), frame rates (24, 25, 30, 60), orientations (landscape, portrait), and resolutions (HD, 4K) will all exercise different code paths.

---

## References

- [Apple AVFoundation Editing Guide](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html)
- [Apple TN2447: Debugging Compositions](https://developer.apple.com/library/archive/technotes/tn2447/_index.html)
- [Apple TN QA1820: Smooth Scrubbing](https://developer.apple.com/library/archive/qa/qa1820/_index.html)
- [WWDC 2013 Session 612: Advanced Editing with AV Foundation](https://asciiwwdc.com/2013/sessions/612)
- [WWDC 2020: Decode ProRes with AVFoundation](https://developer.apple.com/videos/play/wwdc2020/10090/)
- [WWDC 2022: Create a More Responsive Media App](https://developer.apple.com/videos/play/wwdc2022/110379/)
- [WWDC 2022: Display HDR Video in EDR](https://developer.apple.com/videos/play/wwdc2022/110565/)
- [Warren Moore: Understanding CMTime](https://warrenmoore.net/understanding-cmtime)
- [Apple AVCustomEdit Sample Code](https://developer.apple.com/library/archive/samplecode/AVCustomEdit/Introduction/Intro.html)
- [VideoLab Framework](https://github.com/ruanjx/VideoLab)
- [Cabbage Framework](https://github.com/VideoFlint/Cabbage)
- [Scott Logic: Video Stitching](https://blog.scottlogic.com/2014/11/10/Video-Stitching-With-AVFoundation.html)
- [Apple: Loading Media Data Asynchronously](https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously)
