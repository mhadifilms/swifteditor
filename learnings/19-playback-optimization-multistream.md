# Playback Optimization & Multi-Stream Handling for Professional NLE

## Table of Contents

1. [Multi-Stream Simultaneous Playback](#1-multi-stream-simultaneous-playback)
2. [AVSampleBufferDisplayLayer — Direct Sample Buffer Rendering](#2-avsamplebufferdisplaylayer--direct-sample-buffer-rendering)
3. [AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer](#3-avsamplebufferaudiorenderer--avsamplebufferrendersynchronizer)
4. [Scrubbing Optimization — Frame-Accurate Seeking](#4-scrubbing-optimization--frame-accurate-seeking)
5. [AVPlayerItemVideoOutput + Display Link — Metal Frame Tapping](#5-avplayeritemvideooutput--display-link--metal-frame-tapping)
6. [Multi-Cam Editing — Sync, Switch, and Composite](#6-multi-cam-editing--sync-switch-and-composite)
7. [Composition Performance — Handling 20+ Tracks](#7-composition-performance--handling-20-tracks)
8. [Live Effect Preview During Playback](#8-live-effect-preview-during-playback)
9. [Audio Monitoring — Real-Time Peak/RMS Metering](#9-audio-monitoring--real-time-peakrms-metering)
10. [Reverse Playback and Variable Speed](#10-reverse-playback-and-variable-speed)
11. [Preroll and Buffer Management for Gapless Playback](#11-preroll-and-buffer-management-for-gapless-playback)

---

## 1. Multi-Stream Simultaneous Playback

### The Synchronization Problem

In a professional NLE multi-cam view, you need 2-16 video streams playing in exact frame-level sync. AVPlayer alone was never designed for this — each player has its own internal clock and buffering strategy. The challenge is to lock them all to a single master clock so that frames from different angles appear at exactly the same wall-clock time.

### Approach A: Master Clock + setRate(time:atHostTime:)

The classic (pre-WWDC25) approach uses `CMClockGetHostTimeClock()` as a shared timebase, then issues a synchronized start across all players:

```swift
import AVFoundation
import CoreMedia

/// Manages synchronized playback of multiple AVPlayers locked to a shared master clock.
final class SynchronizedMultiPlayerController {
    private var players: [AVPlayer] = []
    private let masterClock = CMClockGetHostTimeClock()

    func addPlayer(for url: URL) -> AVPlayer {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        // Lock each player's master clock to the host clock
        player.masterClock = masterClock

        // Disable automatic waiting so we control start precisely
        player.automaticallyWaitsToMinimizeStalling = false

        players.append(player)
        return player
    }

    /// Preroll all players, then start them at the exact same host-time instant.
    func synchronizedPlay(at rate: Float = 1.0) {
        let group = DispatchGroup()

        // Step 1: Preroll every player
        for player in players {
            group.enter()
            player.preroll(atRate: rate) { finished in
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }

            // Step 2: Pick a start time slightly in the future (50ms)
            // to give all players time to react
            let now = CMClockGetTime(self.masterClock)
            let startHostTime = CMTimeAdd(now, CMTime(value: 50, timescale: 1000))

            // Step 3: Issue synchronized start on ALL players
            for player in self.players {
                let itemTime = player.currentTime()
                player.setRate(
                    rate,
                    time: itemTime,
                    atHostTime: startHostTime
                )
            }
        }
    }

    /// Pause all players simultaneously
    func synchronizedPause() {
        let hostTime = CMClockGetTime(masterClock)
        for player in players {
            player.setRate(0, time: .invalid, atHostTime: hostTime)
        }
    }

    /// Seek all players to the same timeline position
    func synchronizedSeek(to time: CMTime) async {
        // Cancel any in-progress playback
        for player in players {
            player.rate = 0
        }

        // Seek all players concurrently
        await withTaskGroup(of: Void.self) { group in
            for player in players {
                group.addTask {
                    await player.seek(
                        to: time,
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
            }
        }
    }
}
```

**Key points:**
- `player.masterClock = masterClock` locks each player's timebase to the same reference
- `setRate(_:time:atHostTime:)` specifies "at this host-clock instant, the item should be at this time, playing at this rate"
- Scheduling 50ms in the future gives the system time to prepare all decoders
- `preroll(atRate:)` primes the decode pipeline so first frames are ready

### Approach B: AVPlaybackCoordinationMedium (macOS 26 / iOS 19+, WWDC25)

Apple introduced `AVPlaybackCoordinationMedium` at WWDC25 specifically to solve multi-player synchronization without manual clock management:

```swift
import AVFoundation

/// Modern approach using AVPlaybackCoordinationMedium (WWDC25).
/// Automatically handles rate changes, time jumps, stalling, interruptions.
final class CoordinatedMultiPlayerController {
    private let coordinationMedium = AVPlaybackCoordinationMedium()
    private var players: [AVPlayer] = []

    func addPlayer(for url: URL) -> AVPlayer {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        // Connect this player's coordinator to the shared medium
        // Once connected, play/pause/seek on ANY player propagates to ALL
        player.playbackCoordinator.coordinateWith(coordinationMedium)

        players.append(player)
        return player
    }

    /// Play — call on any one player and all synchronized players follow
    func play() {
        players.first?.play()
        // All other connected players automatically start in sync
    }

    /// Seek — call on any one player
    func seek(to time: CMTime) async {
        await players.first?.seek(to: time)
        // Coordination medium propagates the seek to all players
    }

    /// Disconnect a specific player (e.g., when removing an angle)
    func removePlayer(_ player: AVPlayer) {
        player.playbackCoordinator.stopCoordinating()
        players.removeAll { $0 === player }
    }
}
```

**What AVPlaybackCoordinationMedium handles automatically:**
- Rate changes propagated to all players
- Time jumps (seeks) synchronized across all
- Stalling — if one player stalls, others pause until it recovers
- Interruptions (audio session interrupts, route changes)
- Startup synchronization — all players begin playback together

### Approach C: CMSync for Ultra-Tight Clock Control

For the most control (e.g., syncing video playback to external hardware timecode), use Core Media's clock synchronization primitives directly:

```swift
import CoreMedia

/// Low-level clock synchronization using CMSync.
final class CMSyncClockManager {
    private var timebase: CMTimebase?

    init() throws {
        // Create a timebase driven by the host clock
        let hostClock = CMClockGetHostTimeClock()
        var tb: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: hostClock,
            timebaseOut: &tb
        )
        guard status == noErr, let timebase = tb else {
            throw NSError(domain: "CMSync", code: Int(status))
        }
        self.timebase = timebase
    }

    /// Set the timebase time (anchor point)
    func setTime(_ time: CMTime) {
        guard let timebase else { return }
        CMTimebaseSetTime(timebase, time: time)
    }

    /// Set the playback rate
    func setRate(_ rate: Float64) {
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: rate)
    }

    /// Get the current time according to our timebase
    func currentTime() -> CMTime {
        guard let timebase else { return .invalid }
        return CMTimebaseGetTime(timebase)
    }

    /// Add a timer that fires at specific media times
    func addTimerCallback(at time: CMTime, queue: DispatchQueue, handler: @escaping () -> Void) {
        guard let timebase else { return }
        CMTimebaseAddTimerDispatchSource(
            timebase,
            timerSource: DispatchSource.makeTimerSource(queue: queue) as! DispatchSource,
            fireTime: time
        )
    }

    /// Compare two clocks for drift
    static func measureDrift(
        between clockA: CMClock,
        and clockB: CMClock
    ) -> CMTime {
        let timeA = CMClockGetTime(clockA)
        let timeB = CMClockGetTime(clockB)
        return CMTimeSubtract(timeA, timeB)
    }
}
```

### Performance Considerations for Multi-Stream

| Streams | Recommended Approach | Notes |
|---------|---------------------|-------|
| 2-4     | AVPlayer + masterClock | Straightforward, good performance |
| 4-9     | AVPlaybackCoordinationMedium | Handles stall coordination |
| 9-16    | AVSampleBufferDisplayLayer | Decode to sample buffers, single sync |
| 16+     | Thumbnail proxies + 1 full-res | Only decode full quality for selected angle |

---

## 2. AVSampleBufferDisplayLayer — Direct Sample Buffer Rendering

### Why Bypass AVPlayer?

AVPlayer adds convenience (buffering, error recovery, AirPlay) but also latency. For an NLE where you control the decode pipeline (e.g., reading from AVAssetReader or decoding with VideoToolbox), `AVSampleBufferDisplayLayer` lets you push decoded frames directly to the display with minimal overhead.

### Architecture

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────────────────┐
│ AVAssetReader│───▶│ CMSampleBuffer   │───▶│ AVSampleBufferDisplayLayer│
│  (decoder)   │    │ (decoded frame)  │    │      (CALayer subclass)   │
└─────────────┘    └──────────────────┘    └──────────────────────────┘
       │                                              │
       │           ┌──────────────────┐               │
       └──────────▶│ VideoToolbox     │───────────────┘
                   │ VTDecompression  │  (compressed → display)
                   └──────────────────┘
```

### Basic Implementation

```swift
import AVFoundation
import CoreMedia
import QuartzCore

/// Custom video renderer using AVSampleBufferDisplayLayer for low-latency frame display.
final class SampleBufferVideoRenderer {
    let displayLayer = AVSampleBufferDisplayLayer()
    private let serialQueue = DispatchQueue(label: "com.nle.samplebuffer.display")

    init() {
        displayLayer.videoGravity = .resizeAspect

        // Observe errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLayerError),
            name: .AVSampleBufferDisplayLayerFailedToDecode,
            object: displayLayer
        )
    }

    // MARK: — Constrained Mode (push frames as they arrive)

    /// Enqueue a single decoded frame for immediate display.
    /// The sample buffer must have a valid presentation time stamp.
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        serialQueue.async { [weak self] in
            guard let self, self.displayLayer.status != .failed else { return }
            self.displayLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: — Unconstrained Mode (layer pulls frames when ready)

    /// Start pull-based rendering — layer requests buffers when it needs them.
    /// Use this for smoother playback as the layer manages its own timing.
    func startPullBasedRendering(
        bufferProvider: @escaping () -> CMSampleBuffer?
    ) {
        displayLayer.requestMediaDataWhenReady(on: serialQueue) { [weak self] in
            guard let self else { return }

            while self.displayLayer.isReadyForMoreMediaData {
                guard let buffer = bufferProvider() else {
                    self.displayLayer.stopRequestingMediaData()
                    return
                }
                self.displayLayer.enqueue(buffer)
            }
        }
    }

    /// Stop the pull-based rendering loop.
    func stopPullBasedRendering() {
        displayLayer.stopRequestingMediaData()
    }

    /// Flush all pending buffers (e.g., on seek or source switch).
    func flush() {
        displayLayer.flush()
    }

    /// Flush and remove displayed image (show blank).
    func flushAndRemoveImage() {
        displayLayer.flushAndRemoveImage()
    }

    @objc private func handleLayerError(_ notification: Notification) {
        if let error = displayLayer.error {
            print("Display layer error: \(error)")
        }
        // Attempt recovery
        displayLayer.flush()
    }
}
```

### Creating Sample Buffers from CVPixelBuffer

When you already have decoded pixel buffers (from Metal processing, Core Image, etc.):

```swift
import CoreMedia
import CoreVideo

/// Creates a CMSampleBuffer wrapping a CVPixelBuffer with a specific presentation time.
func makeSampleBuffer(
    from pixelBuffer: CVPixelBuffer,
    presentationTime: CMTime,
    duration: CMTime
) -> CMSampleBuffer? {
    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    guard let format = formatDescription else { return nil }

    var timing = CMSampleTimingInfo(
        duration: duration,
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: format,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )

    return sampleBuffer
}
```

### When to Use AVSampleBufferDisplayLayer vs AVPlayer

| Feature | AVSampleBufferDisplayLayer | AVPlayerLayer |
|---------|---------------------------|---------------|
| Latency | Very low (~1-2 frames) | Higher (buffering adds 100-500ms) |
| Error recovery | Manual | Automatic |
| AirPlay | Not supported | Built-in |
| Audio sync | Must pair with synchronizer | Built-in |
| Custom decode | Full control | AVPlayer controls decode |
| HDR/EDR | Supported | Supported |
| Scrubbing | Excellent (push individual frames) | Seek-based |
| Complexity | High | Low |

---

## 3. AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer

### The Complete Custom Playback Pipeline

When you bypass AVPlayer entirely, you need:
1. **Video display**: AVSampleBufferDisplayLayer
2. **Audio playback**: AVSampleBufferAudioRenderer
3. **A/V sync**: AVSampleBufferRenderSynchronizer

The synchronizer maintains a shared timebase that drives both renderers, ensuring lip-sync.

```swift
import AVFoundation
import CoreMedia

/// A complete custom playback engine bypassing AVPlayer entirely.
/// Uses AVSampleBufferRenderSynchronizer for A/V sync.
final class CustomPlaybackEngine {
    // Renderers
    let videoLayer = AVSampleBufferDisplayLayer()
    let audioRenderer = AVSampleBufferAudioRenderer()

    // Synchronizer — the master clock
    let synchronizer = AVSampleBufferRenderSynchronizer()

    // Decode queues
    private let videoQueue = DispatchQueue(label: "com.nle.decode.video")
    private let audioQueue = DispatchQueue(label: "com.nle.decode.audio")

    // Source
    private var assetReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var audioOutput: AVAssetReaderTrackOutput?

    init() {
        // Register both renderers with the synchronizer
        synchronizer.addRenderer(videoLayer)
        synchronizer.addRenderer(audioRenderer)

        // Configure audio renderer
        audioRenderer.audioTimePitchAlgorithm = .spectral

        // Observe the synchronizer's timebase for position tracking
        synchronizer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            self?.handleTimeUpdate(time)
        }
    }

    // MARK: — Loading

    func load(asset: AVAsset) async throws {
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        let reader = try AVAssetReader(asset: asset)

        // Configure video output — request pixel buffer format optimal for Metal
        if let videoTrack {
            let videoSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            let vOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: videoSettings
            )
            vOutput.alwaysCopiesSampleData = false  // Zero-copy for performance
            reader.add(vOutput)
            self.videoOutput = vOutput
        }

        // Configure audio output — request LPCM for direct rendering
        if let audioTrack {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]
            let aOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: audioSettings
            )
            aOutput.alwaysCopiesSampleData = false
            reader.add(aOutput)
            self.audioOutput = aOutput
        }

        self.assetReader = reader
    }

    // MARK: — Playback Control

    func play() {
        guard let reader = assetReader else { return }

        // Start reading
        reader.startReading()

        // Begin pull-based feeding on both renderers
        startVideoFeed()
        startAudioFeed()

        // Start the synchronizer — this starts the shared clock
        synchronizer.setRate(1.0, time: .zero)
    }

    func pause() {
        synchronizer.setRate(0, time: synchronizer.currentTime())
    }

    func seek(to time: CMTime) async {
        // 1. Pause
        synchronizer.setRate(0, time: time)

        // 2. Flush both renderers
        videoLayer.flush()
        audioRenderer.flush()

        // 3. Restart reader at new position
        assetReader?.cancelReading()
        // Re-create reader with time range starting at 'time'
        // (omitted for brevity — same as load() but with timeRange set)

        // 4. Resume feeding and playing
        startVideoFeed()
        startAudioFeed()
        synchronizer.setRate(1.0, time: time)
    }

    // MARK: — Buffer Feeding

    private func startVideoFeed() {
        videoLayer.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self, let output = self.videoOutput else { return }

            while self.videoLayer.isReadyForMoreMediaData {
                guard self.assetReader?.status == .reading,
                      let buffer = output.copyNextSampleBuffer() else {
                    self.videoLayer.stopRequestingMediaData()
                    return
                }
                self.videoLayer.enqueue(buffer)
            }
        }
    }

    private func startAudioFeed() {
        audioRenderer.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            guard let self, let output = self.audioOutput else { return }

            while self.audioRenderer.isReadyForMoreMediaData {
                guard self.assetReader?.status == .reading,
                      let buffer = output.copyNextSampleBuffer() else {
                    self.audioRenderer.stopRequestingMediaData()
                    return
                }
                self.audioRenderer.enqueue(buffer)
            }
        }
    }

    private func handleTimeUpdate(_ time: CMTime) {
        // Update transport UI, timeline cursor, etc.
    }
}
```

### Multiple Audio Renderers (Multi-Track Audio)

The synchronizer can manage multiple audio renderers, each representing a different audio track:

```swift
/// Add separate audio renderers for each audio track in the timeline.
func addAudioTrack() -> AVSampleBufferAudioRenderer {
    let renderer = AVSampleBufferAudioRenderer()
    renderer.audioTimePitchAlgorithm = .spectral
    synchronizer.addRenderer(renderer)
    return renderer
}

/// Control individual track volume
func setVolume(_ volume: Float, for renderer: AVSampleBufferAudioRenderer) {
    renderer.volume = volume
}

/// Mute a specific track
func mute(_ renderer: AVSampleBufferAudioRenderer) {
    renderer.isMuted = true
}
```

### Synchronizer Timebase Access

```swift
// Get the synchronizer's timebase for advanced clock operations
let timebase = synchronizer.timebase

// Query current time without observer overhead
let currentTime = CMTimebaseGetTime(timebase)

// Check if playing
let rate = CMTimebaseGetRate(timebase)
let isPlaying = rate != 0
```

---

## 4. Scrubbing Optimization — Frame-Accurate Seeking

### The Scrubbing Challenge

Professional NLEs need three levels of scrubbing performance:
1. **Thumbnail scrub** (timeline drag): Low-res thumbnails, 15-60fps update
2. **Frame-accurate scrub** (frame step / mouse-wheel): Exact frame, may stutter
3. **JKL shuttle**: Variable-speed playback at 2x-32x forward/reverse

### Strategy 1: Coalesced Seeking with AVPlayer

The critical mistake is calling `seek()` rapidly without waiting for completion. Each seek cancels the previous one, wasting decode work:

```swift
import AVFoundation
import CoreMedia

/// Manages efficient scrubbing with seek coalescing and completion tracking.
final class ScrubbingController {
    private let player: AVPlayer
    private var isSeekInProgress = false
    private var pendingSeekTime: CMTime?

    init(player: AVPlayer) {
        self.player = player
    }

    /// Call this rapidly from a slider/gesture — seeks are coalesced automatically.
    func scrub(to time: CMTime, frameAccurate: Bool = false) {
        if isSeekInProgress {
            // Store the latest requested time — only the most recent one matters
            pendingSeekTime = time
            return
        }

        isSeekInProgress = true
        let tolerance: CMTime = frameAccurate ? .zero : CMTime(value: 1, timescale: 2)

        player.seek(
            to: time,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] finished in
            guard let self else { return }
            self.isSeekInProgress = false

            // If a newer seek was requested during this seek, perform it now
            if let pending = self.pendingSeekTime {
                self.pendingSeekTime = nil
                self.scrub(to: pending, frameAccurate: frameAccurate)
            }
        }
    }
}
```

### Strategy 2: Dual-Layer Scrubbing (Thumbnail + Full Frame)

Use AVAssetImageGenerator for fast thumbnail previews while AVPlayer catches up with full-quality frames:

```swift
import AVFoundation
import CoreMedia
import CoreGraphics

/// Dual-layer scrubbing: fast thumbnails overlaid while full-quality frame loads.
final class DualLayerScrubController {
    private let player: AVPlayer
    private let thumbnailGenerator: AVAssetImageGenerator
    private var thumbnailCache = NSCache<NSNumber, CGImage>()

    // Callbacks
    var onThumbnailReady: ((CGImage, CMTime) -> Void)?
    var onFullFrameReady: (() -> Void)?

    init(player: AVPlayer, asset: AVAsset) {
        self.player = player
        self.thumbnailGenerator = AVAssetImageGenerator(asset: asset)

        // Configure for fast thumbnail generation
        thumbnailGenerator.maximumSize = CGSize(width: 320, height: 180) // Small
        thumbnailGenerator.appliesPreferredTrackTransform = true
        thumbnailGenerator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        thumbnailGenerator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
    }

    /// Scrub with thumbnail preview followed by full-quality frame.
    func scrub(to time: CMTime) {
        let frameNumber = NSNumber(value: CMTimeGetSeconds(time))

        // 1. Check thumbnail cache first
        if let cached = thumbnailCache.object(forKey: frameNumber) {
            onThumbnailReady?(cached, time)
        } else {
            // 2. Generate thumbnail asynchronously (fast, low-res)
            thumbnailGenerator.cancelAllCGImageGeneration()

            let timeValue = NSValue(time: time)
            thumbnailGenerator.generateCGImagesAsynchronously(
                forTimes: [timeValue]
            ) { [weak self] _, image, _, result, _ in
                guard result == .succeeded, let image else { return }
                self?.thumbnailCache.setObject(image, forKey: frameNumber)
                DispatchQueue.main.async {
                    self?.onThumbnailReady?(image, time)
                }
            }
        }

        // 3. Simultaneously seek player for full-quality frame
        player.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onFullFrameReady?()
            }
        }
    }
}
```

### Strategy 3: Pre-Generated Filmstrip for Timeline

Generate a filmstrip of evenly-spaced thumbnails for the timeline waveform display:

```swift
import AVFoundation

/// Pre-generates an array of thumbnails for timeline filmstrip display.
final class FilmstripGenerator {

    /// Generate filmstrip thumbnails at regular intervals.
    /// Uses the modern async sequence API (macOS 13+ / iOS 16+).
    func generateFilmstrip(
        for asset: AVAsset,
        thumbnailWidth: CGFloat = 96,
        intervalSeconds: Double = 1.0
    ) async throws -> [(time: CMTime, image: CGImage)] {
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        let count = Int(totalSeconds / intervalSeconds) + 1

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(
            width: thumbnailWidth,
            height: thumbnailWidth * 9.0 / 16.0
        )
        generator.appliesPreferredTrackTransform = true
        // Allow tolerance for speed — we don't need exact frames here
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // Build time array
        let times: [CMTime] = (0..<count).map { i in
            CMTimeMakeWithSeconds(Double(i) * intervalSeconds, preferredTimescale: 600)
        }

        var results: [(time: CMTime, image: CGImage)] = []
        results.reserveCapacity(count)

        // Modern async API (Swift 5.9+)
        for await result in generator.images(for: times) {
            let (requestedTime, image, _) = result
            results.append((time: requestedTime, image: image))
        }

        return results
    }
}
```

### Strategy 4: Frame-Step (Arrow Key / Mouse Wheel)

For single-frame stepping, use AVPlayerItem's `step(byCount:)`:

```swift
extension AVPlayer {
    /// Step forward or backward by a specific number of frames.
    /// Positive count = forward, negative = backward.
    func stepByFrames(_ count: Int) {
        guard let item = currentItem else { return }

        // Pause before stepping
        if rate != 0 { pause() }

        item.step(byCount: count)
    }

    /// Step to a specific frame number at a given frame rate.
    func seekToFrame(_ frameNumber: Int, fps: Double) async {
        let time = CMTime(
            value: CMTimeValue(frameNumber),
            timescale: CMTimeScale(fps * 100) // High precision
        )
        // Recompute for standard timescale
        let preciseTime = CMTimeMakeWithSeconds(
            Double(frameNumber) / fps,
            preferredTimescale: Int32(fps * 600)
        )
        await seek(to: preciseTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
```

### Strategy 5: JKL Shuttle Control

Professional shuttle control (J = reverse, K = pause, L = forward) with speed ramping:

```swift
/// JKL shuttle controller for professional-grade variable-speed playback.
final class ShuttleController {
    private let player: AVPlayer

    // Speed ladder: each L press increases speed, each J press reverses
    private let speedLadder: [Float] = [1, 2, 4, 8, 16, 32]
    private var currentSpeedIndex = 0
    private var direction: Float = 1 // +1 forward, -1 reverse

    init(player: AVPlayer) {
        self.player = player
    }

    /// L key: play forward, or increase speed if already playing forward
    func shuttleForward() {
        if player.rate <= 0 {
            // Was stopped or reversing — start forward at 1x
            direction = 1
            currentSpeedIndex = 0
        } else if direction > 0 {
            // Already going forward — increase speed
            currentSpeedIndex = min(currentSpeedIndex + 1, speedLadder.count - 1)
        } else {
            // Was reversing — decrease reverse speed
            if currentSpeedIndex > 0 {
                currentSpeedIndex -= 1
            } else {
                direction = 1
                currentSpeedIndex = 0
            }
        }
        applyRate()
    }

    /// J key: play reverse, or increase reverse speed
    func shuttleReverse() {
        if player.rate >= 0 {
            direction = -1
            currentSpeedIndex = 0
        } else if direction < 0 {
            currentSpeedIndex = min(currentSpeedIndex + 1, speedLadder.count - 1)
        } else {
            if currentSpeedIndex > 0 {
                currentSpeedIndex -= 1
            } else {
                direction = -1
                currentSpeedIndex = 0
            }
        }
        applyRate()
    }

    /// K key: pause (or slow-mo if held with J/L)
    func shuttlePause() {
        player.rate = 0
        currentSpeedIndex = 0
    }

    /// K+L held together: slow forward (0.5x typically)
    func slowForward() {
        player.rate = 0.5
        // Use timeDomain pitch algorithm for voice clarity at slow speed
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
    }

    /// K+J held together: slow reverse
    func slowReverse() {
        player.rate = -0.5
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
    }

    private func applyRate() {
        let speed = speedLadder[currentSpeedIndex] * direction

        // Choose pitch algorithm based on speed
        if abs(speed) <= 2.0 {
            player.currentItem?.audioTimePitchAlgorithm = .spectral
        } else {
            // At high speeds, audio is typically muted or uses low-quality
            player.currentItem?.audioTimePitchAlgorithm = .lowQualityZeroLatency
        }

        player.rate = speed
    }
}
```

---

## 5. AVPlayerItemVideoOutput + Display Link — Metal Frame Tapping

### Concept

`AVPlayerItemVideoOutput` is a "tap" that lets you extract each decoded video frame as a `CVPixelBuffer` during playback. Combined with a display-link callback (CADisplayLink on iOS, CAMetalDisplayLink on macOS 14+), you can intercept frames, process them in Metal, and render to your own view — all while AVPlayer handles decode and A/V sync.

### Architecture

```
AVPlayer ──▶ AVPlayerItem ──▶ AVPlayerItemVideoOutput
                                        │
                                        ▼
                              copyPixelBuffer(forItemTime:)
                                        │
                                        ▼
                              CVPixelBuffer ──▶ Metal Texture
                                                    │
                                                    ▼
                                              Metal Pipeline
                                              (effects, scopes, LUTs)
                                                    │
                                                    ▼
                                              MTKView / CAMetalLayer
```

### Full Implementation (macOS with CAMetalDisplayLink)

```swift
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import QuartzCore

/// Taps video frames from AVPlayer and renders them through a Metal pipeline.
/// Uses CAMetalDisplayLink (macOS 14+) for vsync-aligned rendering.
final class MetalVideoFrameTap: NSObject {
    // AVFoundation
    private let player: AVPlayer
    private let videoOutput: AVPlayerItemVideoOutput

    // Metal
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let metalView: MTKView

    // Display Link (macOS 14+)
    private var displayLink: CAMetalDisplayLink?

    // Pipeline
    private var renderPipeline: MTLRenderPipelineState?

    init(player: AVPlayer, metalView: MTKView) throws {
        self.player = player
        self.metalView = metalView

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw NSError(domain: "Metal", code: -1)
        }
        self.device = device
        self.commandQueue = commandQueue

        // Create texture cache for zero-copy CVPixelBuffer → MTLTexture conversion
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard let textureCache = cache else {
            throw NSError(domain: "TextureCache", code: -1)
        }
        self.textureCache = textureCache

        // Create video output with Metal-friendly pixel format
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        self.videoOutput = AVPlayerItemVideoOutput(
            pixelBufferAttributes: pixelBufferAttributes
        )

        super.init()

        // Configure Metal view
        metalView.device = device
        metalView.isPaused = true // We drive rendering from display link
        metalView.enableSetNeedsDisplay = false
        metalView.colorPixelFormat = .bgra8Unorm

        setupRenderPipeline()
    }

    /// Attach to the current player item and start rendering.
    func start() {
        guard let item = player.currentItem else { return }
        item.add(videoOutput)

        #if os(macOS)
        startCAMetalDisplayLink()
        #else
        startCADisplayLink()
        #endif
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        player.currentItem?.remove(videoOutput)
    }

    // MARK: — macOS: CAMetalDisplayLink (macOS 14+)

    #if os(macOS)
    private func startCAMetalDisplayLink() {
        guard let metalLayer = metalView.layer as? CAMetalLayer else { return }
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        link.add(to: .current, forMode: .common)
        self.displayLink = link
    }
    #endif

    // MARK: — iOS: CADisplayLink

    #if os(iOS)
    private var iosDisplayLink: CADisplayLink?

    private func startCADisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .current, forMode: .common)
        self.iosDisplayLink = link
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let nextVSync = CMTime(
            seconds: link.targetTimestamp,
            preferredTimescale: 600
        )
        renderFrame(forHostTime: nextVSync)
    }
    #endif

    // MARK: — Frame Rendering

    private func renderFrame(forHostTime hostTime: CMTime) {
        // Check if a new frame is available
        let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())

        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(
                forItemTime: itemTime,
                itemTimeForDisplay: nil
              ) else { return }

        // Convert CVPixelBuffer → MTLTexture (zero-copy via IOSurface)
        guard let texture = makeTexture(from: pixelBuffer) else { return }

        // Render through Metal pipeline
        guard let drawable = metalView.currentDrawable,
              let descriptor = metalView.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(renderPipeline!)
        encoder.setFragmentTexture(texture, index: 0)
        // Draw fullscreen quad
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Zero-copy conversion from CVPixelBuffer to MTLTexture.
    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard let cvTex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTex)
    }

    private func setupRenderPipeline() {
        // Standard fullscreen textured quad pipeline
        // (shader code omitted for brevity — see Metal rendering docs)
    }
}

#if os(macOS)
extension MetalVideoFrameTap: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(
        _ link: CAMetalDisplayLink,
        needsUpdate update: CAMetalDisplayLink.Update
    ) {
        let hostTime = CMTime(
            seconds: update.targetTimestamp,
            preferredTimescale: 600
        )
        renderFrame(forHostTime: hostTime)
    }
}
#endif
```

### Key Points

1. **`hasNewPixelBuffer(forItemTime:)`** — Check before copying; avoids duplicate renders
2. **`copyPixelBuffer(forItemTime:itemTimeForDisplay:)`** — Returns the latest decoded frame
3. **`kCVPixelBufferMetalCompatibilityKey`** — Critical for zero-copy Metal texture creation
4. **`alwaysCopiesSampleData = false`** — Avoid unnecessary memory copies
5. **CAMetalDisplayLink** (macOS 14+) replaces deprecated CVDisplayLink; provides vsync-aligned callbacks directly on the Metal layer

### HDR/EDR Rendering with AVPlayerItemVideoOutput

For HDR content, request a wider pixel format:

```swift
let hdrAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf, // 16-bit float
    kCVPixelBufferMetalCompatibilityKey as String: true
]
let hdrOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: hdrAttributes)

// Set Metal view for EDR
metalView.colorPixelFormat = .rgba16Float
metalView.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
// Set wantsExtendedDynamicRangeContent on the layer
if let metalLayer = metalView.layer as? CAMetalLayer {
    metalLayer.wantsExtendedDynamicRangeContent = true
    metalLayer.pixelFormat = .rgba16Float
}
```

---

## 6. Multi-Cam Editing — Sync, Switch, and Composite

### Multi-Cam Clip Architecture

A multi-cam clip represents multiple camera angles synchronized to a shared timeline. The editor shows all angles simultaneously and lets the user cut between them.

```swift
import AVFoundation
import CoreMedia

/// Represents a single camera angle within a multi-cam clip.
struct CameraAngle: Identifiable {
    let id: UUID
    let name: String              // "Camera A", "Wireless Lav", etc.
    let asset: AVAsset
    let mediaType: AVMediaType    // .video, .audio, or both
    let syncOffset: CMTime        // Offset from multi-cam anchor point
    let timecodeStart: CMTime?    // If timecode metadata exists
}

/// A multi-cam clip: multiple angles sharing a synchronized timeline.
final class MultiCamClip {
    let id: UUID
    var angles: [CameraAngle]
    var activeVideoAngle: UUID     // Which angle is currently "cut to"
    var activeAudioAngles: Set<UUID> // Which audio angles are active (can be multiple)
    let anchorTimecode: CMTime     // Reference timecode for sync

    init(angles: [CameraAngle]) {
        self.id = UUID()
        self.angles = angles
        self.activeVideoAngle = angles.first?.id ?? UUID()
        self.activeAudioAngles = Set(angles.filter { $0.mediaType == .audio || $0.mediaType == .video }.map(\.id))
        self.anchorTimecode = .zero
    }
}
```

### Sync Method 1: Timecode-Based Alignment

If cameras recorded matching timecode (jam-synced, LTC, or NTP-synced):

```swift
import AVFoundation
import CoreMedia

/// Extracts timecode from an asset's timecode track.
func extractTimecodeStart(from asset: AVAsset) async throws -> CMTime? {
    // Look for a timecode track
    let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)
    guard let tcTrack = timecodeTracks.first else { return nil }

    // Read the first timecode sample
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: tcTrack, outputSettings: nil)
    reader.add(output)
    reader.startReading()

    guard let sampleBuffer = output.copyNextSampleBuffer() else { return nil }

    // Parse timecode from the sample buffer
    let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
    let mediaType = CMFormatDescriptionGetMediaType(formatDescription!)

    // Get the timecode value
    let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
    var length: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    CMBlockBufferGetDataPointer(blockBuffer!, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

    guard let ptr = dataPointer, length >= 4 else { return nil }

    // Timecode is stored as frame count (big-endian Int32)
    let frameCount = ptr.withMemoryRebound(to: Int32.self, capacity: 1) {
        Int32(bigEndian: $0.pointee)
    }

    // Convert frame count to CMTime (assuming 30fps — adjust per format)
    let fps: Int32 = 30
    return CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(fps))
}

/// Synchronize multiple angles by their timecode.
func syncByTimecode(angles: [CameraAngle]) async throws -> [CameraAngle] {
    var synced: [CameraAngle] = []
    var timecodes: [(angle: CameraAngle, tc: CMTime)] = []

    for angle in angles {
        if let tc = try await extractTimecodeStart(from: angle.asset) {
            timecodes.append((angle, tc))
        }
    }

    guard let earliest = timecodes.min(by: { CMTimeCompare($0.tc, $1.tc) < 0 }) else {
        return angles // No timecode found, return as-is
    }

    // Calculate offsets relative to earliest timecode
    for (angle, tc) in timecodes {
        let offset = CMTimeSubtract(tc, earliest.tc)
        synced.append(CameraAngle(
            id: angle.id,
            name: angle.name,
            asset: angle.asset,
            mediaType: angle.mediaType,
            syncOffset: offset,
            timecodeStart: tc
        ))
    }

    return synced
}
```

### Sync Method 2: Audio Waveform Cross-Correlation

When timecode is not available, use audio waveform matching (like FCP's "Use audio for synchronization"):

```swift
import Accelerate
import AVFoundation

/// Audio waveform-based synchronization using cross-correlation.
final class AudioWaveformSyncer {

    /// Extract audio samples from an asset as a Float array.
    func extractAudioSamples(
        from asset: AVAsset,
        maxDuration: TimeInterval = 30 // First 30 seconds is usually enough
    ) async throws -> [Float] {
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first!
        let duration = try await asset.load(.duration)
        let sampleDuration = min(CMTimeGetSeconds(duration), maxDuration)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 8000,  // Downsample for speed
            AVNumberOfChannelsKey: 1, // Mono
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTimeMakeWithSeconds(sampleDuration, preferredTimescale: 8000)
        )
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            let blockBuffer = CMSampleBufferGetDataBuffer(buffer)!
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                        lengthAtOffsetOut: nil,
                                        totalLengthOut: &length,
                                        dataPointerOut: &dataPointer)
            let floatCount = length / MemoryLayout<Float>.size
            let floatPointer = UnsafeMutableRawPointer(dataPointer!).bindMemory(
                to: Float.self, capacity: floatCount
            )
            samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
        }

        return samples
    }

    /// Find the time offset between two audio signals using cross-correlation.
    /// Returns the offset in samples (divide by sample rate for seconds).
    func findOffset(reference: [Float], target: [Float]) -> Int {
        let n = reference.count
        let m = target.count
        let correlationLength = n + m - 1

        // Use Accelerate for fast cross-correlation via FFT
        let fftLength = vDSP_Length(1 << Int(ceil(log2(Double(correlationLength)))))
        let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(fftLength))), FFTRadix(kFFTRadix2))!

        // Zero-pad both signals
        var refPadded = [Float](repeating: 0, count: Int(fftLength))
        var tgtPadded = [Float](repeating: 0, count: Int(fftLength))
        refPadded.replaceSubrange(0..<n, with: reference)
        tgtPadded.replaceSubrange(0..<m, with: target)

        // Convert to split complex
        var refReal = [Float](repeating: 0, count: Int(fftLength / 2))
        var refImag = [Float](repeating: 0, count: Int(fftLength / 2))
        var tgtReal = [Float](repeating: 0, count: Int(fftLength / 2))
        var tgtImag = [Float](repeating: 0, count: Int(fftLength / 2))

        var refSplit = DSPSplitComplex(realp: &refReal, imagp: &refImag)
        var tgtSplit = DSPSplitComplex(realp: &tgtReal, imagp: &tgtImag)

        // Pack and FFT
        refPadded.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Int(fftLength / 2)) { complex in
                vDSP_ctoz(complex, 2, &refSplit, 1, fftLength / 2)
            }
        }
        tgtPadded.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Int(fftLength / 2)) { complex in
                vDSP_ctoz(complex, 2, &tgtSplit, 1, fftLength / 2)
            }
        }

        let log2n = vDSP_Length(log2(Double(fftLength)))
        vDSP_fft_zrip(fftSetup, &refSplit, 1, log2n, FFTDirection(kFFTDirection_Forward))
        vDSP_fft_zrip(fftSetup, &tgtSplit, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // Multiply ref * conj(tgt) in frequency domain
        // (conjugate of tgt: negate imaginary part)
        vDSP_vneg(tgtImag, 1, &tgtImag, 1, fftLength / 2)

        var resultReal = [Float](repeating: 0, count: Int(fftLength / 2))
        var resultImag = [Float](repeating: 0, count: Int(fftLength / 2))
        var resultSplit = DSPSplitComplex(realp: &resultReal, imagp: &resultImag)

        vDSP_zvmul(&refSplit, 1, &tgtSplit, 1, &resultSplit, 1, fftLength / 2, 1)

        // Inverse FFT
        vDSP_fft_zrip(fftSetup, &resultSplit, 1, log2n, FFTDirection(kFFTDirection_Inverse))

        // Find peak
        var correlation = [Float](repeating: 0, count: Int(fftLength))
        resultSplit.withUnsafeBufferPointer { ptr in
            // Unpack
        }

        var maxValue: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(resultReal, 1, &maxValue, &maxIndex, fftLength / 2)

        vDSP_destroy_fftsetup(fftSetup)

        // Convert index to offset
        let offset = Int(maxIndex)
        return offset > Int(fftLength / 2) ? offset - Int(fftLength) : offset
    }

    /// Compute the sync offset in CMTime between reference and target assets.
    func computeSyncOffset(
        reference: AVAsset,
        target: AVAsset,
        sampleRate: Double = 8000
    ) async throws -> CMTime {
        let refSamples = try await extractAudioSamples(from: reference)
        let tgtSamples = try await extractAudioSamples(from: target)

        let offsetSamples = findOffset(reference: refSamples, target: tgtSamples)
        let offsetSeconds = Double(offsetSamples) / sampleRate

        return CMTimeMakeWithSeconds(offsetSeconds, preferredTimescale: 600)
    }
}
```

### Real-Time Angle Switching

```swift
/// Manages real-time angle switching during multi-cam playback.
final class MultiCamSwitcher {
    private let composition: AVMutableComposition
    private let videoComposition: AVMutableVideoComposition
    private var angles: [UUID: AVMutableCompositionTrack] = [:]
    private var currentAngle: UUID?

    // For recording cut decisions
    struct CutDecision {
        let angleID: UUID
        let time: CMTime
    }
    var cutList: [CutDecision] = []

    init() {
        composition = AVMutableComposition()
        videoComposition = AVMutableVideoComposition()
    }

    /// Switch to a different camera angle at the current playback time.
    /// This records the cut point for later composition building.
    func switchAngle(to angleID: UUID, at time: CMTime) {
        cutList.append(CutDecision(angleID: angleID, time: time))
        currentAngle = angleID

        // In live preview mode: swap which AVPlayerLayer is foregrounded
        // OR rebuild the composition with the new cut decision
        NotificationCenter.default.post(
            name: .init("MultiCamAngleChanged"),
            object: nil,
            userInfo: ["angleID": angleID, "time": time]
        )
    }

    /// Build a final composition from the recorded cut decisions.
    func buildComposition(
        from multiCam: MultiCamClip,
        renderSize: CGSize
    ) async throws -> (AVMutableComposition, AVMutableVideoComposition) {
        let comp = AVMutableComposition()
        comp.naturalSize = renderSize

        guard let videoTrack = comp.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw NSError(domain: "MultiCam", code: -1) }

        // Sort cuts by time
        let sortedCuts = cutList.sorted { CMTimeCompare($0.time, $1.time) < 0 }

        for (index, cut) in sortedCuts.enumerated() {
            guard let angle = multiCam.angles.first(where: { $0.id == cut.angleID }) else { continue }

            let nextTime: CMTime
            if index + 1 < sortedCuts.count {
                nextTime = sortedCuts[index + 1].time
            } else {
                nextTime = try await multiCam.angles[0].asset.load(.duration)
            }

            let sourceTrack = try await angle.asset.loadTracks(withMediaType: .video).first!
            let insertRange = CMTimeRange(
                start: CMTimeAdd(cut.time, angle.syncOffset),
                duration: CMTimeSubtract(nextTime, cut.time)
            )

            try videoTrack.insertTimeRange(
                insertRange,
                of: sourceTrack,
                at: cut.time
            )
        }

        return (comp, videoComposition)
    }
}
```

### Multi-Cam Preview Grid

For displaying all angles simultaneously in a grid:

```swift
import AVFoundation
import AppKit

/// Displays a grid of synchronized camera angles for multi-cam preview.
final class MultiCamGridView {
    private var playerViews: [(player: AVPlayer, layer: AVPlayerLayer)] = []
    private let syncController = SynchronizedMultiPlayerController()

    /// Set up the multi-cam grid with all angles.
    func configure(with angles: [CameraAngle]) {
        for angle in angles where angle.mediaType != .audio {
            let player = syncController.addPlayer(for: (angle.asset as! AVURLAsset).url)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            playerViews.append((player, layer))
        }
    }

    /// Layout angles in a grid pattern.
    func layoutGrid(in bounds: CGRect) {
        let count = playerViews.count
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let cellWidth = bounds.width / CGFloat(cols)
        let cellHeight = bounds.height / CGFloat(rows)

        for (index, pv) in playerViews.enumerated() {
            let col = index % cols
            let row = index / cols
            pv.layer.frame = CGRect(
                x: CGFloat(col) * cellWidth,
                y: CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
        }
    }

    /// Start synchronized playback of all angles.
    func play() {
        syncController.synchronizedPlay()
    }
}
```

---

## 7. Composition Performance — Handling 20+ Tracks

### The Scaling Problem

When an NLE timeline has 20+ video tracks, 20+ audio tracks, transitions, and effects, the `AVMutableComposition` can become a bottleneck. Key issues:

1. **Track count**: Each `insertTimeRange` synchronously inspects the source asset
2. **Composition rebuild**: Any edit requires rebuilding the entire composition
3. **Memory**: Each track segment holds references; many segments = memory pressure
4. **Decode**: Playing 20+ tracks simultaneously requires decoding all of them

### Strategy 1: Async Asset Loading Before Composition

```swift
import AVFoundation

/// Pre-loads all asset metadata before building the composition to avoid
/// synchronous loading during insertTimeRange.
final class CompositionBuilder {

    struct PreloadedClip {
        let asset: AVAsset
        let videoTrack: AVAssetTrack?
        let audioTrack: AVAssetTrack?
        let duration: CMTime
        let timeRange: CMTimeRange
    }

    /// Pre-load all clip metadata concurrently.
    func preloadClips(_ assets: [AVAsset]) async throws -> [PreloadedClip] {
        try await withThrowingTaskGroup(of: PreloadedClip.self) { group in
            for asset in assets {
                group.addTask {
                    async let videoTracks = asset.loadTracks(withMediaType: .video)
                    async let audioTracks = asset.loadTracks(withMediaType: .audio)
                    async let duration = asset.load(.duration)

                    let vt = try? await videoTracks.first
                    let at = try? await audioTracks.first
                    let dur = try await duration

                    // Pre-load the track properties we'll need
                    if let vt {
                        _ = try? await vt.load(.timeRange, .naturalSize, .preferredTransform)
                    }
                    if let at {
                        _ = try? await at.load(.timeRange)
                    }

                    return PreloadedClip(
                        asset: asset,
                        videoTrack: vt,
                        audioTrack: at,
                        duration: dur,
                        timeRange: CMTimeRange(start: .zero, duration: dur)
                    )
                }
            }

            var results: [PreloadedClip] = []
            for try await clip in group {
                results.append(clip)
            }
            return results
        }
    }
}
```

### Strategy 2: Differential Composition Updates

Instead of rebuilding the entire composition on every edit, track changes and apply only the delta:

```swift
/// Manages incremental updates to an AVMutableComposition without full rebuilds.
final class IncrementalCompositionManager {
    private(set) var composition = AVMutableComposition()
    private(set) var videoComposition = AVMutableVideoComposition()

    // Track allocation — reuse composition tracks across edits
    private var videoTrackPool: [AVMutableCompositionTrack] = []
    private var audioTrackPool: [AVMutableCompositionTrack] = []

    /// Allocate or reuse a composition track.
    func allocateVideoTrack() -> AVMutableCompositionTrack {
        // Try to reuse an existing empty track
        if let reusable = videoTrackPool.first(where: { trackIsEmpty($0) }) {
            return reusable
        }
        // Allocate new
        let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        videoTrackPool.append(track)
        return track
    }

    /// Apply a single edit operation (insert, remove, move) without full rebuild.
    enum EditOperation {
        case insert(clip: CompositionBuilder.PreloadedClip, at: CMTime, onTrack: Int)
        case remove(timeRange: CMTimeRange, onTrack: Int)
        case move(fromTime: CMTime, toTime: CMTime, duration: CMTime, onTrack: Int)
    }

    func apply(_ operation: EditOperation) throws {
        switch operation {
        case .insert(let clip, let at, let trackIndex):
            let track = videoTrackPool[trackIndex]
            if let sourceTrack = clip.videoTrack {
                try track.insertTimeRange(clip.timeRange, of: sourceTrack, at: at)
            }

        case .remove(let timeRange, let trackIndex):
            let track = videoTrackPool[trackIndex]
            track.removeTimeRange(timeRange)

        case .move(let from, let to, let duration, let trackIndex):
            let track = videoTrackPool[trackIndex]
            let range = CMTimeRange(start: from, duration: duration)
            // Sadly AVMutableCompositionTrack has no "move" — we must remove + re-insert
            // For complex timelines, a higher-level data model is essential
            track.removeTimeRange(range)
            // Re-insert would require the original source reference
        }

        // Only rebuild video composition instructions (not the full composition)
        rebuildVideoCompositionInstructions()
    }

    private func trackIsEmpty(_ track: AVMutableCompositionTrack) -> Bool {
        return track.segments.isEmpty
    }

    private func rebuildVideoCompositionInstructions() {
        // Rebuild only the AVVideoCompositionInstruction array
        // based on current track segments
    }
}
```

### Strategy 3: Visible-Region-Only Composition

For very large timelines, only compose the visible/playable region:

```swift
/// Builds a composition containing only the time range currently visible
/// in the timeline, plus a buffer for smooth scrubbing.
final class WindowedCompositionBuilder {
    private let bufferDuration = CMTime(seconds: 10, preferredTimescale: 600)

    struct TimelineClip {
        let asset: AVAsset
        let sourceRange: CMTimeRange    // Range within the source asset
        let timelinePosition: CMTime     // Position on the timeline
        let trackIndex: Int
    }

    /// Build a composition for only the visible time window.
    func buildWindowedComposition(
        clips: [TimelineClip],
        visibleRange: CMTimeRange,
        renderSize: CGSize
    ) async throws -> AVMutableComposition {
        // Expand visible range by buffer
        let expandedRange = CMTimeRange(
            start: CMTimeMaximum(
                CMTimeSubtract(visibleRange.start, bufferDuration),
                .zero
            ),
            duration: CMTimeAdd(
                visibleRange.duration,
                CMTimeMultiplyByRatio(bufferDuration, multiplier: 2, divisor: 1)
            )
        )

        // Filter clips that intersect the expanded range
        let visibleClips = clips.filter { clip in
            let clipRange = CMTimeRange(
                start: clip.timelinePosition,
                duration: clip.sourceRange.duration
            )
            return CMTimeRangeGetIntersection(clipRange, otherRange: expandedRange).duration > .zero
        }

        let composition = AVMutableComposition()
        composition.naturalSize = renderSize

        // Group by track
        let byTrack = Dictionary(grouping: visibleClips, by: \.trackIndex)

        for (_, trackClips) in byTrack {
            guard let track = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in trackClips {
                let sourceVideoTrack = try await clip.asset.loadTracks(withMediaType: .video).first!
                // Clip the source range to the visible window
                let clipTimelineRange = CMTimeRange(
                    start: clip.timelinePosition,
                    duration: clip.sourceRange.duration
                )
                let intersection = CMTimeRangeGetIntersection(clipTimelineRange, otherRange: expandedRange)

                // Compute the corresponding source range
                let sourceOffset = CMTimeSubtract(intersection.start, clip.timelinePosition)
                let clippedSourceRange = CMTimeRange(
                    start: CMTimeAdd(clip.sourceRange.start, sourceOffset),
                    duration: intersection.duration
                )

                try track.insertTimeRange(
                    clippedSourceRange,
                    of: sourceVideoTrack,
                    at: intersection.start
                )
            }
        }

        return composition
    }
}
```

### Strategy 4: Composition Caching

```swift
import Foundation

/// Caches built compositions keyed by a hash of the edit state.
final class CompositionCache {
    private let cache = NSCache<NSString, CachedComposition>()

    final class CachedComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix

        init(composition: AVMutableComposition,
             videoComposition: AVMutableVideoComposition,
             audioMix: AVMutableAudioMix) {
            self.composition = composition
            self.videoComposition = videoComposition
            self.audioMix = audioMix
        }
    }

    /// Retrieve or build a composition for the given edit state.
    func composition(
        for editStateHash: String,
        builder: () throws -> CachedComposition
    ) rethrows -> CachedComposition {
        let key = editStateHash as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let built = try builder()
        cache.setObject(built, forKey: key)
        return built
    }

    /// Invalidate when edits change
    func invalidate(for editStateHash: String) {
        cache.removeObject(forKey: editStateHash as NSString)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }
}
```

### Performance Tips for Large Compositions

| Technique | Impact | When to Use |
|-----------|--------|-------------|
| Async pre-load tracks | Eliminates main-thread blocking | Always |
| Track pool (reuse tracks) | Reduces allocation overhead | Frequent edits |
| Windowed composition | Dramatically reduces decode load | 50+ clips |
| Composition caching | Avoids redundant rebuilds | Undo/redo |
| Proxy media | Reduces decode cost per frame | 4K+ media |
| Lazy audio mix | Only mix audible tracks | Many audio tracks |

---

## 8. Live Effect Preview During Playback

### Custom AVVideoCompositing with Metal

The `AVVideoCompositing` protocol is the hook for applying real-time effects during both playback and export. When set on an `AVVideoComposition`, the system calls your compositor for every frame.

```swift
import AVFoundation
import Metal
import CoreVideo

/// Custom video compositor that applies Metal-based effects during playback.
final class MetalEffectsCompositor: NSObject, AVVideoCompositing {

    // Required pixel buffer attributes
    var sourcePixelBufferAttributes: [String: Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    // Metal resources
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private var currentEffectPipeline: MTLComputePipelineState?

    // Thread safety
    private let renderQueue = DispatchQueue(label: "com.nle.compositor.render")
    private var pendingRequests: [AVAsynchronousVideoCompositionRequest] = []

    override init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache!

        super.init()

        setupEffectPipelines()
    }

    // MARK: — AVVideoCompositing Protocol

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Called when render size changes — update Metal resources if needed
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            self?.processRequest(request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.async { [weak self] in
            self?.pendingRequests.removeAll()
        }
    }

    // MARK: — Frame Processing

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Get the custom instruction (carries effect parameters)
        guard let instruction = request.videoCompositionInstruction
                as? MetalEffectsInstruction else {
            request.finish(with: NSError(domain: "Compositor", code: -1))
            return
        }

        // Get source pixel buffers for all tracks involved
        let sourceTrackIDs = request.sourceTrackIDs

        guard let primaryTrackID = sourceTrackIDs.first,
              let sourceBuffer = request.sourceFrame(
                byTrackID: primaryTrackID.int32Value
              ) else {
            request.finish(with: NSError(domain: "Compositor", code: -2))
            return
        }

        // Get or create output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Compositor", code: -3))
            return
        }

        // Convert to Metal textures
        guard let sourceTexture = metalTexture(from: sourceBuffer),
              let outputTexture = metalTexture(from: outputBuffer) else {
            // Fallback: copy source to output unmodified
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Apply effects through Metal compute pipeline
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Apply each effect in the chain
        for effect in instruction.effects {
            encoder.setComputePipelineState(effect.pipeline)
            encoder.setTexture(sourceTexture, index: 0)
            encoder.setTexture(outputTexture, index: 1)

            // Set effect parameters
            var params = effect.parameters
            encoder.setBytes(&params, length: MemoryLayout.size(ofValue: params), index: 0)

            // Set time for animated effects
            var time = Float(CMTimeGetSeconds(request.compositionTime))
            encoder.setBytes(&time, length: MemoryLayout<Float>.size, index: 1)

            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroups = MTLSize(
                width: (sourceTexture.width + 15) / 16,
                height: (sourceTexture.height + 15) / 16,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    private func metalTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &texture
        )
        return texture.flatMap { CVMetalTextureGetTexture($0) }
    }

    private func setupEffectPipelines() {
        // Load Metal shader library and create compute pipelines for each effect type
    }
}

/// Custom instruction that carries effect parameters per-segment.
final class MetalEffectsInstruction: NSObject, AVVideoCompositionInstruction {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    struct Effect {
        let pipeline: MTLComputePipelineState
        let parameters: EffectParameters
    }

    struct EffectParameters {
        var intensity: Float
        var param1: Float
        var param2: Float
        var param3: Float
    }

    let effects: [Effect]

    init(timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID], effects: [Effect]) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        self.effects = effects
    }
}
```

### Triggering Live Effect Updates During Playback

When the user adjusts an effect parameter during playback, the video composition must be invalidated so the compositor re-renders:

```swift
/// Updates effect parameters during playback without stopping.
final class LiveEffectController {
    private weak var player: AVPlayer?
    private var videoComposition: AVMutableVideoComposition

    init(player: AVPlayer, videoComposition: AVMutableVideoComposition) {
        self.player = player
        self.videoComposition = videoComposition
    }

    /// Update an effect parameter in real-time.
    /// Must create a new videoComposition or modify and re-assign.
    func updateEffectParameter(
        _ parameter: String,
        value: Float,
        at timeRange: CMTimeRange
    ) {
        // Update the instruction's effect parameters
        guard var instructions = videoComposition.instructions as? [MetalEffectsInstruction] else { return }

        for (index, instruction) in instructions.enumerated() {
            if CMTimeRangeContainsTimeRange(instruction.timeRange, otherRange: timeRange) {
                // Modify the instruction's effects
                // (In practice, create a new instruction with updated params)
            }
        }

        // Re-assign the video composition to trigger re-render
        // This is the key: AVPlayer detects the change and re-requests frames
        let newVideoComposition = videoComposition.mutableCopy() as! AVMutableVideoComposition
        newVideoComposition.instructions = instructions
        player?.currentItem?.videoComposition = newVideoComposition
    }
}
```

**Critical insight**: Simply mutating the existing `AVVideoComposition`'s instructions does NOT trigger a re-render. You must either:
1. Create a new `AVMutableVideoComposition` and assign it, OR
2. Set `player.currentItem.videoComposition = nil` then re-assign it

---

## 9. Audio Monitoring — Real-Time Peak/RMS Metering

### MTAudioProcessingTap

`MTAudioProcessingTap` is a real-time audio tap that sits in AVFoundation's audio pipeline. It gives you access to decoded PCM audio buffers during playback — perfect for level metering, waveform display, and audio analysis.

```swift
import AVFoundation
import CoreMedia
import Accelerate

/// Real-time audio level metering using MTAudioProcessingTap.
final class AudioMeterTap {

    /// Current metering values, updated in real time.
    struct MeterLevels {
        var peakDB: Float = -160
        var rmsDB: Float = -160
        var peakLinear: Float = 0
        var rmsLinear: Float = 0
    }

    // Published levels (thread-safe)
    private(set) var levels = MeterLevels()
    var onLevelsUpdated: ((MeterLevels) -> Void)?

    /// Create and attach a metering tap to an audio track.
    func createAudioMix(for audioTrack: AVAssetTrack) -> AVMutableAudioMix {
        let audioMix = AVMutableAudioMix()

        let params = AVMutableAudioMixInputParameters(track: audioTrack)

        // Create the processing tap
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, // Tap after effects
            &tap
        )

        guard status == noErr, let processingTap = tap else {
            print("Failed to create MTAudioProcessingTap: \(status)")
            return audioMix
        }

        params.audioTapProcessor = processingTap.takeUnretainedValue()
        audioMix.inputParameters = [params]

        return audioMix
    }
}

// MARK: — MTAudioProcessingTap C Callbacks

private func tapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    // Pass through the client info (our AudioMeterTap instance)
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {
    // Release the retained reference
}

private func tapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    // Called when the tap is about to start processing
    // The processingFormat tells us the sample rate, channels, etc.
}

private func tapUnprepare(tap: MTAudioProcessingTap) {
    // Called when the tap stops processing
}

private func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    // Get the audio data from upstream
    var sourceFlags = MTAudioProcessingTapFlags()
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        &sourceFlags,
        nil,
        numberFramesOut
    )
    guard status == noErr else { return }

    // Get our AudioMeterTap instance
    let storage = MTAudioProcessingTapGetStorage(tap)
    let meterTap = Unmanaged<AudioMeterTap>.fromOpaque(storage).takeUnretainedValue()

    // Process the audio buffer for metering
    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    guard let buffer = bufferList.first,
          let data = buffer.mData else { return }

    let frameCount = Int(numberFramesOut.pointee)
    let samples = data.assumingMemoryBound(to: Float.self)

    // Calculate RMS using Accelerate
    var rms: Float = 0
    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))

    // Calculate Peak using Accelerate
    var peak: Float = 0
    vDSP_maxmgv(samples, 1, &peak, vDSP_Length(frameCount))

    // Convert to dB
    let rmsDB = 20 * log10(max(rms, 1e-10))
    let peakDB = 20 * log10(max(peak, 1e-10))

    // Update levels (will be read from main thread)
    var levels = AudioMeterTap.MeterLevels()
    levels.rmsDB = rmsDB
    levels.peakDB = peakDB
    levels.rmsLinear = rms
    levels.peakLinear = peak

    meterTap.levels = levels

    // Notify on main thread (debounced — don't call too frequently)
    DispatchQueue.main.async {
        meterTap.onLevelsUpdated?(levels)
    }
}
```

### Using the Audio Meter Tap

```swift
func setupMetering(player: AVPlayer, audioTrack: AVAssetTrack) {
    let meterTap = AudioMeterTap()

    meterTap.onLevelsUpdated = { levels in
        // Update UI meters
        print("Peak: \(levels.peakDB) dB, RMS: \(levels.rmsDB) dB")
    }

    let audioMix = meterTap.createAudioMix(for: audioTrack)
    player.currentItem?.audioMix = audioMix
}
```

### Multi-Track Audio Metering

For metering multiple audio tracks independently:

```swift
/// Manages audio metering taps for all audio tracks in a composition.
final class MultiTrackMeterManager {
    private var taps: [CMPersistentTrackID: AudioMeterTap] = []

    /// Create audio mix with metering taps for all audio tracks.
    func createAudioMix(
        for composition: AVMutableComposition
    ) -> AVMutableAudioMix {
        let audioMix = AVMutableAudioMix()
        var allParams: [AVMutableAudioMixInputParameters] = []

        for track in composition.tracks(withMediaType: .audio) {
            let tap = AudioMeterTap()
            taps[track.trackID] = tap

            let params = AVMutableAudioMixInputParameters(track: track)
            // Attach the tap's audio mix parameters
            // (reusing the tap creation from AudioMeterTap)
            let tapMix = tap.createAudioMix(for: track)
            if let tapParams = tapMix.inputParameters.first {
                params.audioTapProcessor = tapParams.audioTapProcessor
            }
            allParams.append(params)
        }

        audioMix.inputParameters = allParams
        return audioMix
    }

    /// Get current levels for a specific track.
    func levels(for trackID: CMPersistentTrackID) -> AudioMeterTap.MeterLevels? {
        return taps[trackID]?.levels
    }
}
```

### Important Constraints of MTAudioProcessingTap

- **Real-time thread**: The `process` callback runs on a real-time audio thread. No allocations, no locks, no Objective-C messaging
- **No HTTP Live Streaming**: MTAudioProcessingTap does not work with HLS streams
- **Post-effects vs pre-effects**: `kMTAudioProcessingTapCreationFlag_PostEffects` taps after volume/pan; `kMTAudioProcessingTapCreationFlag_PreEffects` taps raw decoded audio
- **One tap per track**: You can only attach one processing tap per audio track
- **Callback frequency**: The process callback is called per audio buffer (~10-50ms of audio each call, depending on sample rate and buffer size)

---

## 10. Reverse Playback and Variable Speed

### AVPlayer Negative Rate (Simple but Limited)

AVPlayer supports negative rates, but quality is poor for most codecs:

```swift
func playReverse(player: AVPlayer) {
    // Check if the asset supports reverse playback
    guard let item = player.currentItem,
          item.canPlayReverse else {
        print("Asset does not support reverse playback")
        return
    }

    // For smooth reverse, check fine-grained capabilities
    let canPlaySlowReverse = item.canPlaySlowReverse   // Rates between -1 and 0
    let canPlayFastReverse = item.canPlayFastReverse    // Rates < -1

    // Set audio pitch algorithm for reverse
    item.audioTimePitchAlgorithm = .timeDomain

    // Play in reverse at normal speed
    player.rate = -1.0
}
```

**Limitations of AVPlayer reverse:**
- Only works with assets that have sufficient keyframe density
- Extremely choppy for long-GOP codecs (H.264, H.265)
- Audio is typically muted during reverse playback
- Many assets report `canPlayReverse = false`

### Robust Reverse Playback via AVAssetReader

For professional reverse playback (like DaVinci Resolve's), decode frames with AVAssetReader and display them in reverse order using AVSampleBufferDisplayLayer:

```swift
import AVFoundation
import CoreMedia

/// Generates frames in reverse order from an asset for smooth reverse playback.
final class ReversePlaybackEngine {
    private let asset: AVAsset
    private let displayLayer: AVSampleBufferDisplayLayer
    private let decodeQueue = DispatchQueue(label: "com.nle.reverse.decode")

    // Chunked reading to limit memory usage
    private let chunkDurationSeconds: Double = 2.0
    private var isPlaying = false

    init(asset: AVAsset, displayLayer: AVSampleBufferDisplayLayer) {
        self.asset = asset
        self.displayLayer = displayLayer
    }

    /// Play in reverse from the given time.
    func playReverse(from startTime: CMTime, rate: Float = -1.0) async throws {
        isPlaying = true

        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        var currentTime = startTime

        while isPlaying && CMTimeCompare(currentTime, .zero) > 0 {
            // Read a chunk of frames forward, then display them in reverse
            let chunkDuration = CMTimeMakeWithSeconds(chunkDurationSeconds, preferredTimescale: 600)
            let chunkStart = CMTimeMaximum(
                CMTimeSubtract(currentTime, chunkDuration),
                .zero
            )
            let chunkRange = CMTimeRange(start: chunkStart, end: currentTime)

            // Decode all frames in this chunk
            let frames = try await decodeFrames(track: videoTrack, timeRange: chunkRange)

            // Display them in reverse order
            for frame in frames.reversed() {
                guard isPlaying else { break }

                // Re-stamp with the correct reverse-order presentation time
                if let retimed = retimeSampleBuffer(
                    frame,
                    newPTS: currentTime,
                    duration: frameDuration
                ) {
                    displayLayer.enqueue(retimed)
                }

                currentTime = CMTimeSubtract(currentTime, frameDuration)

                // Pace the display (approximate real-time at given rate)
                let delay = UInt64(abs(1.0 / (Double(frameRate) * Double(abs(rate)))) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func stop() {
        isPlaying = false
        displayLayer.flush()
    }

    /// Decode all frames within a time range using AVAssetReader.
    private func decodeFrames(
        track: AVAssetTrack,
        timeRange: CMTimeRange
    ) async throws -> [CMSampleBuffer] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var frames: [CMSampleBuffer] = []
        while let buffer = output.copyNextSampleBuffer() {
            frames.append(buffer)
        }

        return frames
    }

    /// Create a new CMSampleBuffer with a different presentation timestamp.
    private func retimeSampleBuffer(
        _ original: CMSampleBuffer,
        newPTS: CMTime,
        duration: CMTime
    ) -> CMSampleBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(original) else { return nil }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &format
        )
        guard let fmt = format else { return nil }

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &newBuffer
        )

        return newBuffer
    }
}
```

### Variable Speed Playback

```swift
/// Complete variable speed playback controller with appropriate audio handling.
final class VariableSpeedController {
    private let player: AVPlayer

    /// Audio pitch algorithm options and their use cases:
    ///
    /// - `.spectral`:             Best quality, high CPU. For music at moderate speeds (0.5x-2x)
    /// - `.timeDomain`:           Good for speech at moderate speeds (0.5x-2x)
    /// - `.varispeed`:            Changes pitch with speed (like a tape deck). Low CPU
    /// - `.lowQualityZeroLatency`: Lowest CPU, worst quality. For preview/scrubbing

    init(player: AVPlayer) {
        self.player = player
    }

    func setSpeed(_ speed: Float) {
        guard let item = player.currentItem else { return }

        // Choose pitch algorithm based on speed
        switch abs(speed) {
        case 0..<0.5:
            // Very slow — timeDomain handles speech well
            item.audioTimePitchAlgorithm = .timeDomain
        case 0.5...2.0:
            // Normal range — spectral for best quality
            item.audioTimePitchAlgorithm = .spectral
        case 2.0...4.0:
            // Fast — lowQualityZeroLatency to reduce CPU
            item.audioTimePitchAlgorithm = .lowQualityZeroLatency
        default:
            // Very fast — mute audio entirely
            item.audioTimePitchAlgorithm = .lowQualityZeroLatency
            player.isMuted = true
        }

        // Check if the item supports this rate
        if speed > 0 {
            if speed > 2.0 && !item.canPlayFastForward {
                print("Warning: Asset may not support fast forward at \(speed)x")
            }
        } else {
            if speed < -1.0 && !item.canPlayFastReverse {
                print("Warning: Asset does not support fast reverse")
                return
            }
        }

        player.rate = speed
    }

    /// Speed ramp: gradually change speed over a duration.
    func rampSpeed(
        from startSpeed: Float,
        to endSpeed: Float,
        over duration: TimeInterval,
        steps: Int = 30
    ) {
        let stepDuration = duration / Double(steps)
        let speedIncrement = (endSpeed - startSpeed) / Float(steps)

        for i in 0..<steps {
            let delay = stepDuration * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                let speed = startSpeed + speedIncrement * Float(i)
                self?.setSpeed(speed)
            }
        }
    }
}
```

### Time Remapping for Speed Changes in Composition

For precise speed changes baked into the composition (not just playback rate):

```swift
/// Apply a speed change to a segment of a composition track.
func applySpeedChange(
    to track: AVMutableCompositionTrack,
    sourceRange: CMTimeRange,
    speed: Double
) {
    // Calculate the new duration after speed change
    let newDuration = CMTimeMultiplyByFloat64(sourceRange.duration, multiplier: 1.0 / speed)

    // Scale the segment using scaleTimeRange
    track.scaleTimeRange(
        sourceRange,
        toDuration: newDuration
    )
}

/// Create a time-remapped composition for variable speed effects.
/// Handles both constant speed changes and speed ramps.
func createSpeedRamp(
    track: AVMutableCompositionTrack,
    sourceRange: CMTimeRange,
    startSpeed: Double,
    endSpeed: Double
) {
    // For smooth speed ramps, divide into small segments with graduated speeds
    let segmentCount = 30
    let segmentSourceDuration = CMTimeMultiplyByRatio(
        sourceRange.duration,
        multiplier: 1,
        divisor: Int32(segmentCount)
    )

    var currentTime = sourceRange.start
    for i in 0..<segmentCount {
        let progress = Double(i) / Double(segmentCount)
        let speed = startSpeed + (endSpeed - startSpeed) * progress

        let segmentRange = CMTimeRange(start: currentTime, duration: segmentSourceDuration)
        let newDuration = CMTimeMultiplyByFloat64(segmentSourceDuration, multiplier: 1.0 / speed)

        track.scaleTimeRange(segmentRange, toDuration: newDuration)

        currentTime = CMTimeAdd(currentTime, newDuration)
    }
}
```

---

## 11. Preroll and Buffer Management for Gapless Playback

### AVPlayer Preroll

`preroll(atRate:)` primes the decode pipeline so playback starts with minimal latency:

```swift
/// Preroll management for instant playback start.
final class PrerollManager {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    /// Preroll at a specific rate, then play immediately when ready.
    func prerollAndPlay(at rate: Float = 1.0) {
        // Disable automatic stall waiting — we're managing it
        player.automaticallyWaitsToMinimizeStalling = false

        player.preroll(atRate: rate) { [weak self] finished in
            guard finished else {
                // Preroll was interrupted (e.g., seek happened during preroll)
                print("Preroll interrupted, retrying...")
                self?.prerollAndPlay(at: rate)
                return
            }

            // Pipeline is primed — play with minimal latency
            self?.player.rate = rate
        }
    }

    /// Cancel any in-progress preroll (e.g., before a seek)
    func cancelPreroll() {
        player.cancelPendingPrerolls()
    }

    /// Preroll for playback at a specific time (seek + preroll).
    func seekAndPreroll(to time: CMTime, rate: Float = 1.0) async {
        // 1. Seek
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)

        // 2. Preroll (wraps the callback in a continuation)
        await withCheckedContinuation { continuation in
            player.preroll(atRate: rate) { _ in
                continuation.resume()
            }
        }
    }
}
```

### AVQueuePlayer for Gapless Playback

`AVQueuePlayer` is designed for sequential playback of multiple items:

```swift
import AVFoundation

/// Manages gapless sequential playback of multiple clips.
final class GaplessPlaybackManager {
    let queuePlayer: AVQueuePlayer
    private var playerItems: [AVPlayerItem] = []

    init() {
        queuePlayer = AVQueuePlayer()
        queuePlayer.automaticallyWaitsToMinimizeStalling = false

        // Observe end of each item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    /// Load a sequence of clips for gapless playback.
    func loadSequence(_ urls: [URL]) {
        // Only enqueue a few items ahead — not the entire timeline
        let lookAhead = 3
        for url in urls.prefix(lookAhead) {
            let item = AVPlayerItem(url: url)
            playerItems.append(item)
            queuePlayer.insert(item, after: nil) // Append to queue
        }
    }

    /// Enqueue the next item when the current one finishes.
    @objc private func itemDidFinish(_ notification: Notification) {
        // If there are more items to play, enqueue the next one
        // This keeps the queue short to minimize memory usage
    }

    /// Pre-warm the next clip transition for gapless playback.
    func preWarmNextItem() {
        guard let nextItem = queuePlayer.items().dropFirst().first else { return }
        // Accessing the asset triggers loading
        Task {
            _ = try? await nextItem.asset.load(.duration)
        }
    }
}
```

### Buffer Status Monitoring

```swift
import AVFoundation
import Combine

/// Monitors buffer health and playback status for an AVPlayerItem.
final class BufferMonitor: ObservableObject {
    @Published var isBufferEmpty = false
    @Published var isBufferFull = false
    @Published var isLikelyToKeepUp = true
    @Published var loadedTimeRanges: [CMTimeRange] = []

    private var observations: [NSKeyValueObservation] = []

    func monitor(item: AVPlayerItem) {
        observations.removeAll()

        observations.append(
            item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.isBufferEmpty = item.isPlaybackBufferEmpty
                }
            }
        )

        observations.append(
            item.observe(\.isPlaybackBufferFull) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.isBufferFull = item.isPlaybackBufferFull
                }
            }
        )

        observations.append(
            item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.isLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
                }
            }
        )

        observations.append(
            item.observe(\.loadedTimeRanges) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.loadedTimeRanges = item.loadedTimeRanges.map(\.timeRangeValue)
                }
            }
        )
    }

    /// Calculate how much buffer remains ahead of current time.
    func bufferedDuration(from currentTime: CMTime) -> CMTime {
        for range in loadedTimeRanges {
            if CMTimeRangeContainsTime(range, time: currentTime) {
                return CMTimeSubtract(range.end, currentTime)
            }
        }
        return .zero
    }
}
```

### Custom Buffer Strategy for NLE

Professional NLEs need different buffering depending on the operation:

```swift
/// Adaptive buffer configuration for different playback modes.
enum PlaybackMode {
    case normalPlayback     // Standard 1x playback
    case scrubbing          // User is dragging the playhead
    case jklShuttle         // Variable speed shuttle
    case loopPreview        // Looping a short region (in/out preview)
    case exportPreview      // Full-quality preview before export
}

/// Configures AVPlayer and related objects for optimal performance in each mode.
final class AdaptivePlaybackConfigurator {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    func configure(for mode: PlaybackMode) {
        guard let item = player.currentItem else { return }

        switch mode {
        case .normalPlayback:
            player.automaticallyWaitsToMinimizeStalling = true
            item.preferredForwardBufferDuration = 0 // System default
            item.audioTimePitchAlgorithm = .spectral

        case .scrubbing:
            player.automaticallyWaitsToMinimizeStalling = false
            item.preferredForwardBufferDuration = 1 // Minimal buffer
            // Mute audio during scrub
            player.isMuted = true

        case .jklShuttle:
            player.automaticallyWaitsToMinimizeStalling = false
            item.preferredForwardBufferDuration = 3
            item.audioTimePitchAlgorithm = .lowQualityZeroLatency

        case .loopPreview:
            player.automaticallyWaitsToMinimizeStalling = false
            item.preferredForwardBufferDuration = 0 // Let system buffer the loop
            item.audioTimePitchAlgorithm = .spectral

        case .exportPreview:
            player.automaticallyWaitsToMinimizeStalling = true
            item.preferredForwardBufferDuration = 10
            item.audioTimePitchAlgorithm = .spectral
        }
    }
}
```

### Loop Playback (In/Out Point Preview)

```swift
import AVFoundation

/// Seamlessly loops playback between in and out points.
final class LoopPlaybackController {
    private let player: AVPlayer
    private var loopObserver: Any?
    private var timeObserver: Any?

    init(player: AVPlayer) {
        self.player = player
    }

    /// Start looping between in and out points.
    func startLoop(inPoint: CMTime, outPoint: CMTime) {
        // Seek to in point
        player.seek(to: inPoint, toleranceBefore: .zero, toleranceAfter: .zero)

        // Use a boundary time observer to detect when we reach the out point
        let outTimes = [NSValue(time: outPoint)]
        timeObserver = player.addBoundaryTimeObserver(
            forTimes: outTimes,
            queue: .main
        ) { [weak self] in
            guard let self else { return }
            // Immediately seek back to in point
            self.player.seek(
                to: inPoint,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                // Continue playing
            }
        }

        player.play()
    }

    /// Stop looping.
    func stopLoop() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    deinit {
        stopLoop()
    }
}
```

---

## Architecture Decision Matrix

### Choosing the Right Playback Architecture

| Use Case | Recommended Stack | Why |
|----------|-------------------|-----|
| Simple timeline playback | AVPlayer + AVVideoComposition | Simplest, handles A/V sync automatically |
| Multi-cam preview (2-4 angles) | Multiple AVPlayers + masterClock | Good quality, manageable complexity |
| Multi-cam preview (5+ angles) | AVSampleBufferDisplayLayer grid + Synchronizer | Lower overhead per stream |
| Frame-accurate scrubbing | AVPlayer + coalesced seeks + thumbnail overlay | Responsive UX with frame accuracy |
| Real-time Metal effects | AVPlayerItemVideoOutput + CAMetalDisplayLink | Tap frames into Metal pipeline |
| Custom decode pipeline | AVAssetReader + AVSampleBufferDisplayLayer + Synchronizer | Full control, lowest latency |
| Reverse playback | AVAssetReader (chunked reverse) + DisplayLayer | Only reliable approach |
| Audio metering | MTAudioProcessingTap on AVAudioMix | Real-time PCM access |
| Export preview | AVPlayer + AVVideoComposition (same as export) | WYSIWYG — identical to final render |

### Performance Budgets

| Operation | Target Latency | Acceptable |
|-----------|---------------|------------|
| Play after press | < 100ms | < 200ms |
| Frame step | < 33ms (one frame) | < 66ms |
| Scrub response | < 50ms (thumbnail), < 150ms (full frame) | < 250ms |
| Shuttle speed change | < 50ms | < 100ms |
| Multi-cam angle switch | < 1 frame | < 2 frames |
| Effect parameter change (live) | < 33ms | < 66ms |
| Audio meter update | < 20ms | < 50ms |

---

## Summary of Key APIs

| API | Purpose | Platform |
|-----|---------|----------|
| `AVPlayer.setRate(_:time:atHostTime:)` | Synchronized multi-player start | All |
| `AVPlayer.masterClock` | Lock player to external clock | All |
| `AVPlayer.preroll(atRate:)` | Pre-prime decode pipeline | All |
| `AVPlaybackCoordinationMedium` | Automatic multi-player sync | macOS 26+ / iOS 19+ |
| `AVSampleBufferDisplayLayer` | Direct frame display | All |
| `AVSampleBufferAudioRenderer` | Direct audio rendering | All |
| `AVSampleBufferRenderSynchronizer` | A/V sync for sample buffers | All |
| `AVPlayerItemVideoOutput` | Tap decoded frames | All |
| `CAMetalDisplayLink` | Vsync-aligned Metal callbacks | macOS 14+ |
| `AVVideoCompositing` protocol | Custom frame compositing | All |
| `MTAudioProcessingTap` | Real-time audio access | All (not HLS) |
| `AVPlayerItem.step(byCount:)` | Frame stepping | All |
| `AVAssetImageGenerator` | Thumbnail generation | All |
| `AVQueuePlayer` | Gapless sequential playback | All |
| `preferredForwardBufferDuration` | Buffer size control | All |
| `audioTimePitchAlgorithm` | Audio quality vs speed tradeoff | All |
