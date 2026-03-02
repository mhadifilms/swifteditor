# Timeline UI Implementation Patterns for NLE

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Data Models](#2-data-models)
3. [SwiftUI vs AppKit: Choosing the Right Approach](#3-swiftui-vs-appkit-choosing-the-right-approach)
4. [Multi-Track Timeline Layout](#4-multi-track-timeline-layout)
5. [Clip Representation & Thumbnail Generation](#5-clip-representation--thumbnail-generation)
6. [Zoom & Scroll Behavior](#6-zoom--scroll-behavior)
7. [Playhead / Scrubber Implementation](#7-playhead--scrubber-implementation)
8. [Drag & Drop Clip Arrangement](#8-drag--drop-clip-arrangement)
9. [Trimming Handles & Edit Types](#9-trimming-handles--edit-types)
10. [Snapping Behavior](#10-snapping-behavior)
11. [Time Ruler & Timecode Display](#11-time-ruler--timecode-display)
12. [Track Headers](#12-track-headers)
13. [Audio Waveform Rendering](#13-audio-waveform-rendering)
14. [Keyframe Visualization](#14-keyframe-visualization)
15. [Performance for Large Projects](#15-performance-for-large-projects)
16. [Professional NLE Timeline Architectures](#16-professional-nle-timeline-architectures)
17. [Open-Source Reference Implementations](#17-open-source-reference-implementations)
18. [Recommended Architecture for SwiftEditor](#18-recommended-architecture-for-swifteditor)

---

## 1. Architecture Overview

### Timeline UI Component Hierarchy
```
TimelineContainerView (NSView / SwiftUI)
 +-- TimeRulerView (timecode display, tick marks)
 +-- TrackHeadersView (vertical stack of track controls)
 |   +-- TrackHeaderView (per-track: name, mute, solo, lock)
 +-- TrackAreaScrollView (synchronized scroll)
     +-- TracksContainerView
         +-- TrackLaneView (per-track, horizontal)
             +-- ClipView (per-clip)
                 +-- ThumbnailStripView (video clips)
                 +-- WaveformView (audio clips)
                 +-- TrimHandleLeft / TrimHandleRight
                 +-- KeyframeOverlayView
 +-- PlayheadView (overlay, not part of scroll content)
```

### Key Design Principles
- **Separation of model and view**: Timeline data model is completely independent of the UI representation
- **Time-to-pixel mapping**: A central `TimelineScale` object converts between time (CMTime) and pixel coordinates
- **Virtualized rendering**: Only visible clips and thumbnails are rendered at any given time
- **Layer-backed views**: Use CALayer-backed NSViews for GPU-accelerated compositing on macOS
- **Hybrid approach**: SwiftUI for app chrome, AppKit/UIKit for the actual timeline canvas where gesture precision matters

---

## 2. Data Models

### Core Timeline Data Model

```swift
import AVFoundation
import Foundation

// MARK: - Timeline Model

/// Represents the entire editing timeline
struct Timeline: Identifiable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var duration: CMTime { tracks.map(\.duration).max() ?? .zero }

    /// Timeline-level settings
    var frameRate: CMTime = CMTime(value: 1, timescale: 30) // 30fps
    var resolution: CGSize = CGSize(width: 1920, height: 1080)

    /// Markers placed on the timeline
    var markers: [TimelineMarker] = []
}

/// A single track (video or audio lane)
struct Track: Identifiable {
    let id: UUID
    var name: String
    var type: TrackType
    var clips: [Clip]
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isLocked: Bool = false
    var isVisible: Bool = true // for video tracks
    var height: CGFloat = 60   // UI height in points

    var duration: CMTime {
        clips.map { $0.timelineRange.end }.max() ?? .zero
    }

    enum TrackType: String, Codable {
        case video
        case audio
        case subtitle
        case effect
    }
}

/// A clip placed on a track
struct Clip: Identifiable {
    let id: UUID
    var mediaReference: MediaReference  // reference to source asset

    /// Position on the timeline
    var timelineRange: CMTimeRange      // where it sits on the timeline

    /// Source media range (in/out points within the source)
    var sourceRange: CMTimeRange

    /// Speed/rate adjustment (1.0 = normal)
    var speed: Double = 1.0

    /// Visual properties
    var opacity: Float = 1.0
    var blendMode: BlendMode = .normal

    /// Effects applied to this clip
    var effects: [Effect] = []

    /// Keyframes for animated properties
    var keyframes: [String: [Keyframe]] = [:]

    /// Transitions at edges
    var inTransition: Transition?
    var outTransition: Transition?

    /// Display color in timeline
    var color: ClipColor = .blue

    /// Computed: actual duration accounting for speed
    var effectiveDuration: CMTime {
        CMTimeMultiplyByFloat64(sourceRange.duration, multiplier: 1.0 / speed)
    }
}

/// Reference to a media asset on disk
struct MediaReference: Identifiable {
    let id: UUID
    let url: URL
    let type: MediaType
    var duration: CMTime
    var naturalSize: CGSize?
    var audioChannels: Int?

    enum MediaType {
        case video, audio, image, sequence
    }
}

/// A keyframe for animatable properties
struct Keyframe {
    var time: CMTime           // relative to clip start
    var value: Double
    var interpolation: InterpolationType
    var inTangent: CGPoint?    // bezier handle
    var outTangent: CGPoint?   // bezier handle

    enum InterpolationType {
        case linear
        case bezier
        case hold
        case easeIn
        case easeOut
        case easeInOut
    }
}

/// Timeline marker
struct TimelineMarker: Identifiable {
    let id: UUID
    var time: CMTime
    var name: String
    var color: MarkerColor
    var duration: CMTime?  // nil = point marker, non-nil = range marker

    enum MarkerColor { case red, green, blue, yellow, orange, purple }
}

/// Clip colors for visual identification
enum ClipColor: String, CaseIterable {
    case blue, green, red, orange, purple, teal, pink, yellow
}

/// Blend modes
enum BlendMode: String, Codable {
    case normal, add, multiply, screen, overlay
}
```

### Timeline Scale Model (Time-to-Pixel Mapping)

```swift
import CoreMedia

/// Manages the mapping between time and pixel coordinates
/// This is the CRITICAL object for timeline UI - everything depends on it
class TimelineScale: ObservableObject {
    /// Pixels per second at current zoom level
    @Published var pixelsPerSecond: CGFloat = 100.0

    /// Scroll offset in pixels (horizontal)
    @Published var scrollOffset: CGFloat = 0.0

    /// The frame rate for timecode display
    var frameRate: Double = 30.0

    // Zoom constraints
    let minPixelsPerSecond: CGFloat = 5.0     // fully zoomed out
    let maxPixelsPerSecond: CGFloat = 2000.0  // fully zoomed in (frame-level)

    /// Convert a CMTime to a pixel X position
    func xPosition(for time: CMTime) -> CGFloat {
        CGFloat(time.seconds) * pixelsPerSecond - scrollOffset
    }

    /// Convert a pixel X position to CMTime
    func time(for xPosition: CGFloat) -> CMTime {
        let seconds = (xPosition + scrollOffset) / pixelsPerSecond
        return CMTime(seconds: Double(seconds), preferredTimescale: 600)
    }

    /// Width in pixels for a given duration
    func width(for duration: CMTime) -> CGFloat {
        CGFloat(duration.seconds) * pixelsPerSecond
    }

    /// Duration for a given pixel width
    func duration(for width: CGFloat) -> CMTime {
        CMTime(seconds: Double(width / pixelsPerSecond), preferredTimescale: 600)
    }

    /// Zoom centered on a specific time position
    func zoom(by factor: CGFloat, centeredOn time: CMTime) {
        let oldX = xPosition(for: time) + scrollOffset
        let newPPS = (pixelsPerSecond * factor).clamped(to: minPixelsPerSecond...maxPixelsPerSecond)
        let newX = CGFloat(time.seconds) * newPPS

        pixelsPerSecond = newPPS
        scrollOffset += (newX - oldX)
    }

    /// Snap-to-grid zoom levels (powers of 2 for even divisions)
    var snapZoomLevels: [CGFloat] {
        var levels: [CGFloat] = []
        var level = minPixelsPerSecond
        while level <= maxPixelsPerSecond {
            levels.append(level)
            level *= 2
        }
        return levels
    }

    /// Nearest snap zoom level
    func nearestSnapLevel(to pps: CGFloat) -> CGFloat {
        snapZoomLevels.min(by: { abs($0 - pps) < abs($1 - pps) }) ?? pps
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

---

## 3. SwiftUI vs AppKit: Choosing the Right Approach

### The Hybrid Approach (Recommended)

Based on extensive research including IMG.LY's engineering blog and Apple Developer Forums discussions, the consensus is clear: **use a hybrid approach**.

> "Fine-tuning timeline interactions with pure SwiftUI proved unexpectedly difficult... many teams stick to SwiftUI for app chrome and flows while using UIKit/AppKit for the timeline and other advanced pieces." - IMG.LY Blog

#### SwiftUI for:
- Application frame / chrome (toolbar, sidebar, inspector panels)
- Track header controls (mute, solo, lock buttons)
- Property editors and inspectors
- Media browser
- Settings / preferences

#### AppKit (NSView) for:
- The main timeline canvas (custom drawing)
- Clip rendering with thumbnails/waveforms
- Playhead animation
- Gesture handling (drag, trim, zoom, snap)
- Time ruler drawing

### Why AppKit for the Timeline Canvas

1. **Gesture Precision**: UIPanGestureRecognizer / NSPanGestureRecognizer offer fine-grained control over gesture states (began, changed, ended, cancelled) that SwiftUI's DragGesture lacks
2. **Custom Hit Testing**: Override `hitTest(_:)` to expand touch targets for trim handles (see PryntTrimmerView's `HandlerView`)
3. **Direct Drawing**: `draw(_:)` / CALayer drawing gives pixel-precise control
4. **Scroll Synchronization**: NSScrollView with linked scroll views for ruler/track header sync
5. **Performance**: Layer-backed NSViews with `wantsUpdateLayer` for GPU-cached rendering

### NSViewRepresentable Bridge

```swift
import SwiftUI
import AppKit

/// Bridge the AppKit timeline into SwiftUI
struct TimelineViewRepresentable: NSViewRepresentable {
    @ObservedObject var timelineModel: TimelineViewModel

    func makeNSView(context: Context) -> TimelineCanvasView {
        let view = TimelineCanvasView()
        view.viewModel = timelineModel
        return view
    }

    func updateNSView(_ nsView: TimelineCanvasView, context: Context) {
        nsView.needsDisplay = true
    }
}
```

---

## 4. Multi-Track Timeline Layout

### AppKit Implementation: Synchronized Scroll Views

The timeline requires three synchronized scroll regions:
1. **Track Headers** (scrolls vertically only)
2. **Time Ruler** (scrolls horizontally only)
3. **Track Content Area** (scrolls both directions)

```swift
import AppKit

class TimelineContainerView: NSView {

    // The three synchronized scroll views
    let rulerScrollView = NSScrollView()
    let headerScrollView = NSScrollView()
    let contentScrollView = NSScrollView()

    // Document views inside each scroll view
    let rulerView = TimeRulerView()
    let headerStackView = NSStackView()
    let tracksContainerView = TracksContainerView()

    // Playhead overlay (not part of scroll content)
    let playheadView = PlayheadView()

    var timelineScale: TimelineScale!

    func setupLayout() {
        // Content scroll view - main area
        contentScrollView.documentView = tracksContainerView
        contentScrollView.hasVerticalScroller = true
        contentScrollView.hasHorizontalScroller = true
        contentScrollView.autohidesScrollers = false
        contentScrollView.drawsBackground = false

        // Ruler scroll view - horizontal only, synced with content
        rulerScrollView.documentView = rulerView
        rulerScrollView.hasVerticalScroller = false
        rulerScrollView.hasHorizontalScroller = false

        // Header scroll view - vertical only, synced with content
        headerScrollView.documentView = headerStackView
        headerScrollView.hasVerticalScroller = false
        headerScrollView.hasHorizontalScroller = false

        // Synchronize scrolling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentScrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentScrollView.contentView
        )
        contentScrollView.contentView.postsBoundsChangedNotifications = true

        // Add playhead as overlay
        addSubview(playheadView)
        playheadView.wantsLayer = true
        playheadView.layer?.zPosition = 100
    }

    @objc func contentScrolled(_ notification: Notification) {
        let contentBounds = contentScrollView.contentView.bounds

        // Sync ruler horizontal scroll
        var rulerOrigin = rulerScrollView.contentView.bounds.origin
        rulerOrigin.x = contentBounds.origin.x
        rulerScrollView.contentView.scroll(to: rulerOrigin)
        rulerScrollView.reflectScrolledClipView(rulerScrollView.contentView)

        // Sync header vertical scroll
        var headerOrigin = headerScrollView.contentView.bounds.origin
        headerOrigin.y = contentBounds.origin.y
        headerScrollView.contentView.scroll(to: headerOrigin)
        headerScrollView.reflectScrolledClipView(headerScrollView.contentView)

        // Update playhead position
        playheadView.needsDisplay = true
    }
}
```

### Track Lane View

```swift
class TrackLaneView: NSView {
    var track: Track!
    var timelineScale: TimelineScale!
    var clipViews: [UUID: ClipView] = [:]

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = trackBackgroundColor.cgColor
    }

    var trackBackgroundColor: NSColor {
        switch track.type {
        case .video: return NSColor(white: 0.18, alpha: 1.0)
        case .audio: return NSColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1.0)
        default: return NSColor(white: 0.16, alpha: 1.0)
        }
    }

    func layoutClips() {
        for clip in track.clips {
            let x = timelineScale.xPosition(for: clip.timelineRange.start)
            let width = timelineScale.width(for: clip.timelineRange.duration)

            let clipView = clipViews[clip.id] ?? createClipView(for: clip)
            clipView.frame = NSRect(x: x, y: 2, width: width, height: bounds.height - 4)
            clipViews[clip.id] = clipView
        }
    }

    private func createClipView(for clip: Clip) -> ClipView {
        let view = ClipView(clip: clip, scale: timelineScale)
        addSubview(view)
        return view
    }
}
```

---

## 5. Clip Representation & Thumbnail Generation

### AVAssetImageGenerator for Thumbnail Strips

The key to efficient thumbnail generation is:
1. Generate thumbnails asynchronously on background threads
2. Use tolerance settings to balance speed vs accuracy
3. Only generate thumbnails for visible clips
4. Cache generated thumbnails
5. Scale maximumSize to match display needs (not source resolution)

```swift
import AVFoundation
import AppKit

/// Manages thumbnail generation for video clips
actor ThumbnailGenerator {

    private var cache = NSCache<NSString, NSImage>()
    private var activeGenerators: [UUID: AVAssetImageGenerator] = [:]

    init() {
        cache.countLimit = 500     // max cached thumbnails
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB
    }

    /// Generate thumbnails for a clip at specified times
    func generateThumbnails(
        for asset: AVAsset,
        clipId: UUID,
        times: [CMTime],
        size: CGSize
    ) -> AsyncStream<(CMTime, NSImage)> {
        // Cancel any existing generation for this clip
        activeGenerators[clipId]?.cancelAllCGImageGeneration()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: size.width * NSScreen.main!.backingScaleFactor,
            height: size.height * NSScreen.main!.backingScaleFactor
        )

        // Tolerance: wider = faster but less accurate
        // For timeline thumbnails, moderate tolerance is fine
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        activeGenerators[clipId] = generator

        return AsyncStream { continuation in
            Task {
                // Modern async/await API (iOS 16+ / macOS 13+)
                for await result in generator.images(for: times) {
                    switch result {
                    case .success(requestedTime: let time, image: let cgImage, actualTime: _):
                        let nsImage = NSImage(cgImage: cgImage, size: size)
                        let cacheKey = "\(clipId)-\(time.seconds)" as NSString
                        self.cache.setObject(nsImage, forKey: cacheKey)
                        continuation.yield((time, nsImage))
                    case .failure:
                        break
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Get cached thumbnail
    func cachedThumbnail(clipId: UUID, time: CMTime) -> NSImage? {
        let cacheKey = "\(clipId)-\(time.seconds)" as NSString
        return cache.object(forKey: cacheKey)
    }

    /// Cancel generation for a specific clip
    func cancel(clipId: UUID) {
        activeGenerators[clipId]?.cancelAllCGImageGeneration()
        activeGenerators.removeValue(forKey: clipId)
    }
}

/// Legacy approach using generateCGImagesAsynchronously (pre-macOS 13)
extension ThumbnailGenerator {
    func generateThumbnailsLegacy(
        for asset: AVAsset,
        times: [CMTime],
        size: CGSize,
        handler: @escaping (CMTime, NSImage) -> Void
    ) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: size.width * 2,
            height: size.height * 2
        )
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

        let nsValues = times.map { NSValue(time: $0) }
        generator.generateCGImagesAsynchronously(forTimes: nsValues) {
            requestedTime, cgImage, actualTime, result, error in
            guard let cgImage = cgImage, result == .succeeded else { return }
            let nsImage = NSImage(cgImage: cgImage, size: size)
            DispatchQueue.main.async {
                handler(requestedTime, nsImage)
            }
        }
    }
}
```

### Thumbnail Strip View (inside ClipView)

```swift
class ThumbnailStripView: NSView {
    var clip: Clip!
    var timelineScale: TimelineScale!
    var thumbnailGenerator: ThumbnailGenerator!

    private var thumbnailLayers: [CALayer] = []
    private var thumbnailSize: CGSize = .zero

    override var wantsUpdateLayer: Bool { true }

    func updateThumbnails() {
        guard let clip = clip else { return }

        // Calculate how many thumbnails we need
        let viewWidth = bounds.width
        let viewHeight = bounds.height

        // Each thumbnail should be roughly square-ish based on the video aspect ratio
        let aspectRatio: CGFloat = 16.0 / 9.0  // or from source media
        let thumbWidth = viewHeight * aspectRatio
        let thumbCount = max(1, Int(ceil(viewWidth / thumbWidth)))

        thumbnailSize = CGSize(width: thumbWidth, height: viewHeight)

        // Calculate times for each thumbnail position
        let clipDuration = clip.sourceRange.duration.seconds
        var times: [CMTime] = []
        for i in 0..<thumbCount {
            let fraction = Double(i) / Double(max(1, thumbCount - 1))
            let time = CMTime(
                seconds: clip.sourceRange.start.seconds + fraction * clipDuration,
                preferredTimescale: 600
            )
            times.append(time)
        }

        // Clear old layers
        thumbnailLayers.forEach { $0.removeFromSuperlayer() }
        thumbnailLayers.removeAll()

        // Create placeholder layers
        for i in 0..<thumbCount {
            let thumbLayer = CALayer()
            thumbLayer.frame = CGRect(
                x: CGFloat(i) * thumbWidth,
                y: 0,
                width: thumbWidth,
                height: viewHeight
            )
            thumbLayer.contentsGravity = .resizeAspectFill
            thumbLayer.masksToBounds = true
            thumbLayer.backgroundColor = NSColor.darkGray.cgColor
            layer?.addSublayer(thumbLayer)
            thumbnailLayers.append(thumbLayer)
        }

        // Request thumbnail generation
        Task {
            let stream = await thumbnailGenerator.generateThumbnails(
                for: AVURLAsset(url: clip.mediaReference.url),
                clipId: clip.id,
                times: times,
                size: thumbnailSize
            )

            for await (time, image) in stream {
                // Find the matching layer
                if let index = times.firstIndex(where: { abs($0.seconds - time.seconds) < 0.1 }) {
                    await MainActor.run {
                        thumbnailLayers[index].contents = image.cgImage(
                            forProposedRect: nil, context: nil, hints: nil
                        )
                    }
                }
            }
        }
    }
}
```

---

## 6. Zoom & Scroll Behavior

### Zoom Implementation

Professional NLE timelines support:
- **Pinch-to-zoom** (trackpad gesture on macOS)
- **Keyboard shortcuts** (Cmd+/Cmd- or +/-)
- **Scroll wheel zoom** (with modifier key)
- **Zoom to fit** (entire timeline fills view)
- **Zoom to selection** (selected clips fill view)

The key principle: **zoom should be centered on the cursor position** (or playhead if using keyboard).

```swift
class TimelineCanvasView: NSView {
    var timelineScale: TimelineScale!

    override func magnify(with event: NSEvent) {
        // Pinch-to-zoom on trackpad
        let locationInView = convert(event.locationInWindow, from: nil)
        let timeAtCursor = timelineScale.time(for: locationInView.x)

        let zoomFactor = 1.0 + event.magnification
        timelineScale.zoom(by: zoomFactor, centeredOn: timeAtCursor)

        // Snap to power-of-2 zoom levels on gesture end
        if event.phase == .ended {
            let snapped = timelineScale.nearestSnapLevel(to: timelineScale.pixelsPerSecond)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                timelineScale.pixelsPerSecond = snapped
            }
        }

        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            // Option+scroll = zoom
            let locationInView = convert(event.locationInWindow, from: nil)
            let timeAtCursor = timelineScale.time(for: locationInView.x)
            let zoomFactor: CGFloat = 1.0 + (event.scrollingDeltaY * 0.01)
            timelineScale.zoom(by: zoomFactor, centeredOn: timeAtCursor)
        } else {
            // Normal scroll = pan
            timelineScale.scrollOffset -= event.scrollingDeltaX
            // Vertical scrolling handled by NSScrollView
            super.scrollWheel(with: event)
        }
        needsDisplay = true
    }

    /// Zoom to fit entire timeline
    func zoomToFit(timeline: Timeline) {
        let totalDuration = timeline.duration
        let availableWidth = bounds.width - 40  // margin
        let targetPPS = availableWidth / CGFloat(totalDuration.seconds)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            timelineScale.pixelsPerSecond = targetPPS.clamped(
                to: timelineScale.minPixelsPerSecond...timelineScale.maxPixelsPerSecond
            )
            timelineScale.scrollOffset = 0
        }
    }

    /// Zoom to show selected time range
    func zoomToRange(_ range: CMTimeRange) {
        let availableWidth = bounds.width - 40
        let targetPPS = availableWidth / CGFloat(range.duration.seconds)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            timelineScale.pixelsPerSecond = targetPPS.clamped(
                to: timelineScale.minPixelsPerSecond...timelineScale.maxPixelsPerSecond
            )
            timelineScale.scrollOffset = CGFloat(range.start.seconds) * timelineScale.pixelsPerSecond
        }
    }
}
```

### Snap-Width Zoom (from VideoTimelineView)

VideoTimelineView implements an interesting approach where zoom levels snap to power-of-2 widths, ensuring thumbnails always align cleanly:

```swift
/// Calculate nearest snap-to-grid zoom width
/// This ensures thumbnail boundaries always align to pixel grid
func snapWidth(_ width: CGFloat, max: CGFloat) -> CGFloat {
    let n = log2((2 * max) / width)
    var intN = CGFloat(Int(n))
    if n - intN >= 0.5 {
        intN += 1
    }
    return (2 * max) / pow(2, intN)
}
```

---

## 7. Playhead / Scrubber Implementation

### macOS Display Sync

On macOS, use the modern display link API (macOS 14+) or CVDisplayLink for frame-accurate playhead positioning:

```swift
class PlayheadView: NSView {
    var timelineScale: TimelineScale!
    var currentTime: CMTime = .zero {
        didSet { needsDisplay = true }
    }

    private var displayLink: CVDisplayLink?
    private var player: AVPlayer?

    // Modern approach (macOS 14+): NSView.displayLink
    func startPlayback(player: AVPlayer) {
        self.player = player

        // Use NSView's displayLink (macOS 14+)
        let link = self.displayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
    }

    @objc private func displayLinkFired(_ sender: Any) {
        guard let player = player else { return }
        let time = player.currentTime()
        if time != currentTime {
            currentTime = time
        }
    }

    // Legacy approach using CVDisplayLink (pre-macOS 14)
    func startPlaybackLegacy(player: AVPlayer) {
        self.player = player
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let displayLink = link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<PlayheadView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                if let time = view.player?.currentTime() {
                    view.currentTime = time
                }
            }
            return kCVReturnSuccess
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, pointer)
        CVDisplayLinkStart(displayLink)
        self.displayLink = displayLink
    }

    override func draw(_ dirtyRect: NSRect) {
        let x = timelineScale.xPosition(for: currentTime)

        // Draw playhead line
        let lineColor = NSColor.red
        lineColor.setFill()

        let lineRect = NSRect(x: x - 1, y: 0, width: 2, height: bounds.height)
        lineRect.fill()

        // Draw playhead triangle at top
        let trianglePath = NSBezierPath()
        let triangleSize: CGFloat = 10
        trianglePath.move(to: NSPoint(x: x - triangleSize, y: bounds.height))
        trianglePath.line(to: NSPoint(x: x + triangleSize, y: bounds.height))
        trianglePath.line(to: NSPoint(x: x, y: bounds.height - triangleSize))
        trianglePath.close()
        lineColor.setFill()
        trianglePath.fill()
    }

    // Scrubbing via mouse drag on the ruler area
    override func mouseDown(with event: NSEvent) {
        scrubToEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        scrubToEvent(event)
    }

    private func scrubToEvent(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let time = timelineScale.time(for: location.x)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
}
```

### AVPlayer Time Observation (alternative to display link)

```swift
/// Observe player time with high-frequency periodic observer
func observePlayerTime(player: AVPlayer) -> Any {
    let interval = CMTime(seconds: 1.0/60.0, preferredTimescale: 600) // 60fps updates
    return player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
        self?.currentTime = time
    }
}
```

---

## 8. Drag & Drop Clip Arrangement

### AppKit Drag & Drop Implementation

```swift
class TrackLaneView: NSView {

    // MARK: - Drag Source (moving clips)

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let clipView = hitClipView(at: location) else { return }

        // Store drag offset within the clip
        dragState = DragState(
            clipId: clipView.clip.id,
            offsetInClip: location.x - clipView.frame.origin.x,
            originalPosition: clipView.frame.origin
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = dragState else { return }
        let location = convert(event.locationInWindow, from: nil)

        let newX = location.x - drag.offsetInClip
        let newTime = timelineScale.time(for: newX + timelineScale.scrollOffset)

        // Apply snapping
        let snappedTime = snapEngine.snap(
            time: newTime,
            clip: drag.clipId,
            inTimeline: timeline
        )

        // Move the clip visually
        if let clipView = clipViews[drag.clipId] {
            clipView.frame.origin.x = timelineScale.xPosition(for: snappedTime)
        }

        // Show snap indicator if snapping occurred
        if snappedTime != newTime {
            showSnapIndicator(at: snappedTime)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag = dragState else { return }

        // Commit the move
        let location = convert(event.locationInWindow, from: nil)
        let newTime = timelineScale.time(for: location.x - drag.offsetInClip + timelineScale.scrollOffset)
        let snappedTime = snapEngine.snap(time: newTime, clip: drag.clipId, inTimeline: timeline)

        // Update the model
        timelineController.moveClip(drag.clipId, to: snappedTime, onTrack: track.id)

        dragState = nil
    }

    private var dragState: DragState?

    struct DragState {
        let clipId: UUID
        let offsetInClip: CGFloat
        let originalPosition: CGPoint
    }
}
```

### SwiftUI Drag & Drop (for Media Browser to Timeline)

```swift
struct MediaBrowserItem: View {
    let mediaRef: MediaReference

    var body: some View {
        VStack {
            Image(nsImage: mediaRef.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
            Text(mediaRef.name)
                .font(.caption)
        }
        .draggable(mediaRef.url.absoluteString) {
            // Drag preview
            Image(nsImage: mediaRef.thumbnail)
                .frame(width: 100, height: 60)
        }
    }
}

// Drop target on the timeline (via NSViewRepresentable)
class TimelineDropTarget: NSView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasteboard = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }
        let url = URL(string: pasteboard)!
        let location = convert(sender.draggingLocation, from: nil)
        let time = timelineScale.time(for: location.x + timelineScale.scrollOffset)

        // Import and place the clip
        timelineController.importAndPlace(url: url, at: time, onTrack: targetTrack)
        return true
    }
}
```

---

## 9. Trimming Handles & Edit Types

### Trim Handle Implementation

Based on analysis of PryntTrimmerView and VideoTimelineView, trim handles are implemented as:
1. Small NSViews (or CALayers) positioned at clip edges
2. Extended hit-test regions (typically 20px wider than visible area)
3. Pan gesture recognizers for drag interaction
4. Constraint-based positioning tied to clip in/out points

```swift
class ClipView: NSView {
    var clip: Clip!
    var timelineScale: TimelineScale!

    let leftTrimHandle = TrimHandleView()
    let rightTrimHandle = TrimHandleView()

    private let handleWidth: CGFloat = 8
    private let handleHitWidth: CGFloat = 20  // expanded hit target

    func setupTrimHandles() {
        // Left handle (in point)
        leftTrimHandle.frame = NSRect(x: 0, y: 0, width: handleWidth, height: bounds.height)
        leftTrimHandle.side = .left
        addSubview(leftTrimHandle)

        // Right handle (out point)
        rightTrimHandle.frame = NSRect(
            x: bounds.width - handleWidth, y: 0,
            width: handleWidth, height: bounds.height
        )
        rightTrimHandle.side = .right
        addSubview(rightTrimHandle)
    }

    override func cursorUpdate(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if location.x < handleHitWidth || location.x > bounds.width - handleHitWidth {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.openHand.set()
        }
    }
}

class TrimHandleView: NSView {
    enum Side { case left, right }
    var side: Side = .left

    // Expand hit-test area for easier grabbing (learned from PryntTrimmerView)
    override func hitTest(_ point: CGPoint) -> NSView? {
        let hitFrame = bounds.insetBy(dx: -20, dy: -10)
        return hitFrame.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw handle visual: rounded rectangle with grip lines
        let handleColor = NSColor.white.withAlphaComponent(0.9)
        handleColor.setFill()

        let path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        path.fill()

        // Draw grip lines
        let lineColor = NSColor.gray
        lineColor.setStroke()
        let centerX = bounds.midX
        let lineY1 = bounds.height * 0.3
        let lineY2 = bounds.height * 0.7

        for offset: CGFloat in [-2, 0, 2] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: centerX + offset, y: lineY1))
            line.line(to: NSPoint(x: centerX + offset, y: lineY2))
            line.lineWidth = 1
            line.stroke()
        }
    }
}
```

### Edit Types: Ripple, Roll, Slip, Slide

These four edit types are fundamental to professional NLEs:

```swift
/// The four fundamental NLE edit operations
enum EditType {
    case ripple   // Trim + shift all subsequent clips
    case roll     // Trim edit point between two clips (total duration unchanged)
    case slip     // Change source in/out while keeping timeline position
    case slide    // Move clip, adjusting neighbors to fill gaps
}

class TrimController {
    var timeline: Timeline
    var undoManager: UndoManager

    /// Ripple Edit: Trim the in/out point of a clip and shift
    /// all subsequent clips to compensate for the duration change
    func rippleTrim(clipId: UUID, edge: TrimEdge, delta: CMTime) {
        guard var clip = findClip(clipId) else { return }
        let oldDuration = clip.timelineRange.duration

        switch edge {
        case .left:
            // Trim in-point: adjust sourceRange.start and timelineRange.start
            clip.sourceRange = CMTimeRange(
                start: clip.sourceRange.start + delta,
                duration: clip.sourceRange.duration - delta
            )
            clip.timelineRange = CMTimeRange(
                start: clip.timelineRange.start + delta,
                duration: clip.timelineRange.duration - delta
            )
        case .right:
            // Trim out-point: adjust sourceRange.duration and timelineRange.duration
            clip.sourceRange = CMTimeRange(
                start: clip.sourceRange.start,
                duration: clip.sourceRange.duration + delta
            )
            clip.timelineRange = CMTimeRange(
                start: clip.timelineRange.start,
                duration: clip.timelineRange.duration + delta
            )
        }

        let durationChange = clip.timelineRange.duration - oldDuration

        // Shift all subsequent clips on the same track
        shiftClipsAfter(clip.timelineRange.end - durationChange, by: durationChange, onTrack: clip.trackId)

        updateClip(clip)
    }

    /// Roll Edit: Move the edit point between two adjacent clips
    /// Total duration remains the same
    func rollEdit(leftClipId: UUID, rightClipId: UUID, delta: CMTime) {
        guard var leftClip = findClip(leftClipId),
              var rightClip = findClip(rightClipId) else { return }

        // Extend left clip's out point
        leftClip.sourceRange = CMTimeRange(
            start: leftClip.sourceRange.start,
            duration: leftClip.sourceRange.duration + delta
        )
        leftClip.timelineRange = CMTimeRange(
            start: leftClip.timelineRange.start,
            duration: leftClip.timelineRange.duration + delta
        )

        // Adjust right clip's in point
        rightClip.sourceRange = CMTimeRange(
            start: rightClip.sourceRange.start + delta,
            duration: rightClip.sourceRange.duration - delta
        )
        rightClip.timelineRange = CMTimeRange(
            start: rightClip.timelineRange.start + delta,
            duration: rightClip.timelineRange.duration - delta
        )

        updateClip(leftClip)
        updateClip(rightClip)
    }

    /// Slip Edit: Change which part of the source media is shown
    /// Timeline position and duration remain the same
    func slipEdit(clipId: UUID, delta: CMTime) {
        guard var clip = findClip(clipId) else { return }

        // Only change the source range start; duration stays the same
        let newSourceStart = clip.sourceRange.start + delta

        // Clamp to valid range
        let maxSourceStart = clip.mediaReference.duration - clip.sourceRange.duration
        let clampedStart = max(.zero, min(newSourceStart, maxSourceStart))

        clip.sourceRange = CMTimeRange(
            start: clampedStart,
            duration: clip.sourceRange.duration
        )

        updateClip(clip)
    }

    /// Slide Edit: Move a clip, adjusting its neighbors
    /// The clip's content stays the same, but its neighbors adjust
    func slideEdit(clipId: UUID, delta: CMTime) {
        guard var clip = findClip(clipId),
              let leftNeighbor = findLeftNeighbor(of: clipId),
              let rightNeighbor = findRightNeighbor(of: clipId) else { return }

        var left = leftNeighbor
        var right = rightNeighbor

        // Move the clip
        clip.timelineRange = CMTimeRange(
            start: clip.timelineRange.start + delta,
            duration: clip.timelineRange.duration
        )

        // Adjust left neighbor's out point
        left.sourceRange = CMTimeRange(
            start: left.sourceRange.start,
            duration: left.sourceRange.duration + delta
        )
        left.timelineRange = CMTimeRange(
            start: left.timelineRange.start,
            duration: left.timelineRange.duration + delta
        )

        // Adjust right neighbor's in point
        right.sourceRange = CMTimeRange(
            start: right.sourceRange.start - delta,
            duration: right.sourceRange.duration + delta  // note: -delta for shortened
        )
        right.timelineRange = CMTimeRange(
            start: right.timelineRange.start, // stays same (clip covers gap)
            duration: right.timelineRange.duration
        )

        updateClip(clip)
        updateClip(left)
        updateClip(right)
    }

    enum TrimEdge { case left, right }
}
```

---

## 10. Snapping Behavior

### Snap Engine

Snapping is essential for precise editing. Clips should snap to:
- Other clip edges (in/out points)
- Playhead position
- Markers
- Grid lines (frame boundaries at high zoom)

```swift
/// Handles snapping logic for timeline elements
class SnapEngine {
    var isEnabled: Bool = true
    var snapThreshold: CGFloat = 10.0  // pixels
    var timelineScale: TimelineScale!

    struct SnapResult {
        let snappedTime: CMTime
        let didSnap: Bool
        let snapTarget: SnapTarget?
    }

    enum SnapTarget {
        case clipEdge(clipId: UUID, edge: TrimEdge)
        case playhead
        case marker(markerId: UUID)
        case gridLine
    }

    /// Find the nearest snap point for a given time
    func snap(time: CMTime, clip movingClipId: UUID, inTimeline timeline: Timeline) -> CMTime {
        guard isEnabled else { return time }

        var candidates: [(CMTime, SnapTarget)] = []

        // Collect all snap candidates
        for track in timeline.tracks {
            for clip in track.clips where clip.id != movingClipId {
                // Snap to clip start
                candidates.append((clip.timelineRange.start, .clipEdge(clipId: clip.id, edge: .left)))
                // Snap to clip end
                candidates.append((clip.timelineRange.end, .clipEdge(clipId: clip.id, edge: .right)))
            }
        }

        // Snap to markers
        for marker in timeline.markers {
            candidates.append((marker.time, .marker(markerId: marker.id)))
        }

        // Snap to playhead (if available)
        // candidates.append((playheadTime, .playhead))

        // Find nearest candidate within threshold
        let thresholdTime = timelineScale.duration(for: snapThreshold)

        var bestCandidate: (CMTime, SnapTarget)?
        var bestDistance: CMTime = thresholdTime

        for (candidateTime, target) in candidates {
            let distance = CMTimeAbsoluteValue(time - candidateTime)
            if distance < bestDistance {
                bestDistance = distance
                bestCandidate = (candidateTime, target)
            }
        }

        return bestCandidate?.0 ?? time
    }

    /// Toggle snapping (keyboard shortcut: N)
    func toggle() {
        isEnabled.toggle()
    }
}

/// CMTime arithmetic helpers
func CMTimeAbsoluteValue(_ time: CMTime) -> CMTime {
    return time.seconds < 0 ? CMTimeNegate(time) : time
}

func -(lhs: CMTime, rhs: CMTime) -> CMTime {
    return CMTimeSubtract(lhs, rhs)
}

func +(lhs: CMTime, rhs: CMTime) -> CMTime {
    return CMTimeAdd(lhs, rhs)
}
```

### Visual Snap Indicator

```swift
class SnapIndicatorView: NSView {
    var snapTime: CMTime?
    var timelineScale: TimelineScale!

    override func draw(_ dirtyRect: NSRect) {
        guard let time = snapTime else { return }

        let x = timelineScale.xPosition(for: time)

        // Draw dashed vertical line
        let dashPattern: [CGFloat] = [4, 4]
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: 0))
        path.line(to: NSPoint(x: x, y: bounds.height))
        path.setLineDash(dashPattern, count: 2, phase: 0)
        path.lineWidth = 1

        NSColor.yellow.withAlphaComponent(0.8).setStroke()
        path.stroke()
    }

    func show(at time: CMTime) {
        snapTime = time
        isHidden = false
        needsDisplay = true

        // Auto-hide after brief delay
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(hide), with: nil, afterDelay: 0.5)
    }

    @objc func hide() {
        isHidden = true
        snapTime = nil
    }
}
```

---

## 11. Time Ruler & Timecode Display

### Custom NSRulerView Subclass

```swift
import AppKit

class TimeRulerView: NSView {
    var timelineScale: TimelineScale!
    var frameRate: Double = 30.0

    // Drawing configuration
    let rulerHeight: CGFloat = 24
    let majorTickHeight: CGFloat = 14
    let minorTickHeight: CGFloat = 8
    let microTickHeight: CGFloat = 4

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor(white: 0.15, alpha: 1.0).setFill()
        dirtyRect.fill()

        // Bottom border
        NSColor(white: 0.3, alpha: 1.0).setFill()
        NSRect(x: 0, y: rulerHeight - 1, width: bounds.width, height: 1).fill()

        // Calculate visible time range
        let startTime = timelineScale.time(for: dirtyRect.minX)
        let endTime = timelineScale.time(for: dirtyRect.maxX)

        // Determine tick interval based on zoom level
        let tickConfig = tickConfiguration(for: timelineScale.pixelsPerSecond)

        // Draw ticks and labels
        drawTicks(from: startTime, to: endTime, config: tickConfig)
    }

    struct TickConfiguration {
        let majorInterval: Double    // seconds between major ticks
        let minorDivisions: Int      // minor ticks per major interval
        let microDivisions: Int      // micro ticks per minor interval
        let labelFormat: LabelFormat

        enum LabelFormat {
            case hoursMinutes      // HH:MM
            case minutesSeconds    // MM:SS
            case secondsFrames     // SS:FF
            case frames            // FFFF
        }
    }

    private func tickConfiguration(for pixelsPerSecond: CGFloat) -> TickConfiguration {
        // Adaptive tick spacing based on zoom level
        switch pixelsPerSecond {
        case 0..<10:
            return TickConfiguration(majorInterval: 60, minorDivisions: 6, microDivisions: 2, labelFormat: .hoursMinutes)
        case 10..<50:
            return TickConfiguration(majorInterval: 10, minorDivisions: 10, microDivisions: 2, labelFormat: .minutesSeconds)
        case 50..<200:
            return TickConfiguration(majorInterval: 1, minorDivisions: 4, microDivisions: 0, labelFormat: .minutesSeconds)
        case 200..<500:
            return TickConfiguration(majorInterval: 1, minorDivisions: Int(frameRate), microDivisions: 0, labelFormat: .secondsFrames)
        default:
            return TickConfiguration(majorInterval: 1.0/frameRate, minorDivisions: 1, microDivisions: 0, labelFormat: .frames)
        }
    }

    private func drawTicks(from startTime: CMTime, to endTime: CMTime, config: TickConfiguration) {
        let majorInterval = config.majorInterval
        let firstMajor = floor(startTime.seconds / majorInterval) * majorInterval

        var t = firstMajor
        while t <= endTime.seconds {
            let x = timelineScale.xPosition(for: CMTime(seconds: t, preferredTimescale: 600))

            // Major tick
            drawTick(at: x, height: majorTickHeight, color: .white)
            drawLabel(at: x, time: t, format: config.labelFormat)

            // Minor ticks
            let minorInterval = majorInterval / Double(config.minorDivisions)
            for i in 1..<config.minorDivisions {
                let minorT = t + Double(i) * minorInterval
                let minorX = timelineScale.xPosition(for: CMTime(seconds: minorT, preferredTimescale: 600))
                drawTick(at: minorX, height: minorTickHeight, color: NSColor(white: 0.6, alpha: 1))

                // Micro ticks
                if config.microDivisions > 0 {
                    let microInterval = minorInterval / Double(config.microDivisions)
                    for j in 1..<config.microDivisions {
                        let microT = minorT - minorInterval + Double(j) * microInterval
                        let microX = timelineScale.xPosition(for: CMTime(seconds: microT, preferredTimescale: 600))
                        drawTick(at: microX, height: microTickHeight, color: NSColor(white: 0.4, alpha: 1))
                    }
                }
            }

            t += majorInterval
        }
    }

    private func drawTick(at x: CGFloat, height: CGFloat, color: NSColor) {
        color.setFill()
        NSRect(x: x, y: rulerHeight - height, width: 1, height: height).fill()
    }

    private func drawLabel(at x: CGFloat, time: Double, format: TickConfiguration.LabelFormat) {
        let text = formatTimecode(time, format: format)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor(white: 0.8, alpha: 1.0)
        ]
        let nsString = text as NSString
        let size = nsString.size(withAttributes: attrs)
        nsString.draw(at: NSPoint(x: x + 3, y: rulerHeight - majorTickHeight - size.height - 1), withAttributes: attrs)
    }

    private func formatTimecode(_ seconds: Double, format: TickConfiguration.LabelFormat) -> String {
        let totalFrames = Int(seconds * frameRate)
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let frames = totalFrames % Int(frameRate)

        switch format {
        case .hoursMinutes:
            return String(format: "%02d:%02d", hours, minutes)
        case .minutesSeconds:
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        case .secondsFrames:
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
        case .frames:
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
        }
    }
}
```

### TimecodeKit Integration

For production use, the [orchetect/TimecodeKit](https://github.com/orchetect/TimecodeKit) (also known as swift-timecode) library provides complete SMPTE/EBU timecode support:

```swift
import TimecodeKit

// Create timecode from components
let tc = Timecode(.components(h: 1, m: 23, s: 45, f: 12), at: .fps29_97d)

// Convert to/from CMTime
let cmTime = tc.cmTimeValue
let fromCMTime = try Timecode(.cmTime(cmTime), at: .fps29_97d)

// Display as string: "01:23:45;12" (drop-frame uses semicolons)
let display = tc.stringValue

// Supported frame rates: 23.976, 24, 25, 29.97, 29.97df, 30, 48, 50, 59.94, 60, etc.
```

---

## 12. Track Headers

### SwiftUI Track Header Implementation

Track headers are an excellent use case for SwiftUI since they are standard UI controls:

```swift
import SwiftUI

struct TrackHeaderView: View {
    @ObservedObject var track: TrackViewModel

    var body: some View {
        HStack(spacing: 4) {
            // Track type icon
            Image(systemName: track.type == .video ? "film" : "speaker.wave.2")
                .font(.system(size: 10))
                .foregroundColor(.gray)

            // Track name (editable)
            TextField("", text: $track.name)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(maxWidth: 80)

            Spacer()

            // Control buttons
            HStack(spacing: 2) {
                // Mute button (M)
                TrackControlButton(
                    isActive: $track.isMuted,
                    label: "M",
                    activeColor: .blue,
                    tooltip: "Mute"
                )

                // Solo button (S)
                TrackControlButton(
                    isActive: $track.isSolo,
                    label: "S",
                    activeColor: .yellow,
                    tooltip: "Solo"
                )

                // Lock button
                TrackControlButton(
                    isActive: $track.isLocked,
                    label: track.isLocked ? "lock.fill" : "lock.open",
                    isSystemImage: true,
                    activeColor: .red,
                    tooltip: "Lock"
                )

                // Visibility (video tracks only)
                if track.type == .video {
                    TrackControlButton(
                        isActive: $track.isVisible,
                        label: track.isVisible ? "eye" : "eye.slash",
                        isSystemImage: true,
                        activeColor: .green,
                        tooltip: "Visibility"
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: CGFloat(track.height))
        .background(Color(white: 0.2))
        .border(Color(white: 0.15), width: 0.5)
    }
}

struct TrackControlButton: View {
    @Binding var isActive: Bool
    let label: String
    var isSystemImage: Bool = false
    let activeColor: Color
    let tooltip: String

    var body: some View {
        Button(action: { isActive.toggle() }) {
            Group {
                if isSystemImage {
                    Image(systemName: label)
                        .font(.system(size: 9))
                } else {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .frame(width: 18, height: 18)
            .background(isActive ? activeColor.opacity(0.6) : Color(white: 0.3))
            .cornerRadius(3)
            .foregroundColor(isActive ? .white : .gray)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
```

---

## 13. Audio Waveform Rendering

### Waveform Analysis Pipeline

Based on DSWaveformImage library analysis, the pipeline is:
1. Read audio samples using AVAssetReader + AVAssetReaderTrackOutput
2. Convert Int16 samples to Float using vDSP_vflt16 (Accelerate framework)
3. Take absolute values: vDSP_vabs
4. Convert to decibels: vDSP_vdbcon
5. Clip to noise floor: vDSP_vclip
6. Downsample using vDSP_desamp
7. Normalize to 0..1 range

```swift
import AVFoundation
import Accelerate

/// Audio waveform data extractor using Accelerate framework
struct WaveformExtractor {

    let noiseFloorDB: Float = -50.0  // silence threshold

    /// Extract waveform samples from an audio asset
    func extractSamples(from url: URL, targetSampleCount: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let reader = try AVAssetReader(asset: asset)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)

        // Calculate total samples
        let descriptions = try await audioTrack.load(.formatDescriptions)
        let timeRange = try await audioTrack.load(.timeRange)
        var totalSamples = 0
        for desc in descriptions {
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                let channels = Int(basic.pointee.mChannelsPerFrame)
                let sampleRate = basic.pointee.mSampleRate
                totalSamples = Int(sampleRate * timeRange.duration.seconds) * channels
            }
        }

        let samplesPerPixel = max(1, totalSamples / targetSampleCount)

        reader.startReading()
        var sampleBuffer = Data()
        var outputSamples: [Float] = []

        while reader.status == .reading {
            guard let nextBuffer = trackOutput.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(nextBuffer) else { break }

            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length,
                                        totalLengthOut: nil, dataPointerOut: &pointer)
            sampleBuffer.append(UnsafeBufferPointer(start: pointer, count: length))
            CMSampleBufferInvalidate(nextBuffer)

            let processed = downsample(sampleBuffer, stride: samplesPerPixel)
            outputSamples += processed

            if !processed.isEmpty {
                sampleBuffer.removeFirst(processed.count * samplesPerPixel * MemoryLayout<Int16>.size)
                sampleBuffer = Data(sampleBuffer) // prevent memory leak
            }
        }

        // Normalize to 0...1
        return outputSamples.prefix(targetSampleCount).map { $0 / noiseFloorDB }
    }

    private func downsample(_ data: Data, stride: Int) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount / stride > 0 else { return [] }

        return data.withUnsafeBytes { rawPointer -> [Float] in
            let int16Pointer = rawPointer.bindMemory(to: Int16.self)
            let count = vDSP_Length(sampleCount)
            var floatBuffer = [Float](repeating: 0, count: Int(count))

            // Int16 -> Float
            vDSP_vflt16(int16Pointer.baseAddress!, 1, &floatBuffer, 1, count)
            // Absolute value
            vDSP_vabs(floatBuffer, 1, &floatBuffer, 1, count)
            // Convert to dB
            var zero: Float = Float(Int16.max)
            vDSP_vdbcon(floatBuffer, 1, &zero, &floatBuffer, 1, count, 1)
            // Clip to noise floor
            var lo = noiseFloorDB
            var hi: Float = 0
            vDSP_vclip(floatBuffer, 1, &lo, &hi, &floatBuffer, 1, count)

            // Downsample
            let outputCount = sampleCount / stride
            var output = [Float](repeating: 0, count: outputCount)
            let filter = [Float](repeating: 1.0 / Float(stride), count: stride)
            vDSP_desamp(floatBuffer, vDSP_Stride(stride), filter, &output,
                        vDSP_Length(outputCount), vDSP_Length(stride))

            return output
        }
    }

    enum WaveformError: Error {
        case noAudioTrack
    }
}
```

### Waveform Drawing View

```swift
class WaveformView: NSView {
    var samples: [Float] = []
    var waveformColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.7)

    override var wantsUpdateLayer: Bool { false } // use draw() for waveform

    override func draw(_ dirtyRect: NSRect) {
        guard !samples.isEmpty else { return }

        let width = bounds.width
        let height = bounds.height
        let midY = height / 2

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: midY))

        // Draw upper half
        for (i, sample) in samples.enumerated() {
            let x = (CGFloat(i) / CGFloat(samples.count)) * width
            let amplitude = CGFloat(1.0 - sample) * (height / 2) * 0.9
            path.line(to: NSPoint(x: x, y: midY - amplitude))
        }

        // Draw lower half (mirror)
        for (i, sample) in samples.enumerated().reversed() {
            let x = (CGFloat(i) / CGFloat(samples.count)) * width
            let amplitude = CGFloat(1.0 - sample) * (height / 2) * 0.9
            path.line(to: NSPoint(x: x, y: midY + amplitude))
        }

        path.close()
        waveformColor.setFill()
        path.fill()
    }
}
```

---

## 14. Keyframe Visualization

### Keyframe Diamond Overlay on Clips

```swift
class KeyframeOverlayView: NSView {
    var keyframes: [Keyframe] = []
    var clip: Clip!
    var timelineScale: TimelineScale!
    var propertyName: String = "opacity"

    let diamondSize: CGFloat = 6

    override func draw(_ dirtyRect: NSRect) {
        guard let clip = clip,
              let keyframes = clip.keyframes[propertyName] else { return }

        // Draw interpolation curve
        if keyframes.count >= 2 {
            let curvePath = NSBezierPath()
            for (i, kf) in keyframes.enumerated() {
                let x = xForKeyframe(kf, in: clip)
                let y = yForValue(kf.value)

                if i == 0 {
                    curvePath.move(to: NSPoint(x: x, y: y))
                } else {
                    switch kf.interpolation {
                    case .linear:
                        curvePath.line(to: NSPoint(x: x, y: y))
                    case .bezier:
                        let prev = keyframes[i - 1]
                        let prevX = xForKeyframe(prev, in: clip)
                        let prevY = yForValue(prev.value)
                        let cp1 = NSPoint(
                            x: prevX + (prev.outTangent?.x ?? 0),
                            y: prevY + (prev.outTangent?.y ?? 0)
                        )
                        let cp2 = NSPoint(
                            x: x + (kf.inTangent?.x ?? 0),
                            y: y + (kf.inTangent?.y ?? 0)
                        )
                        curvePath.curve(to: NSPoint(x: x, y: y),
                                       controlPoint1: cp1,
                                       controlPoint2: cp2)
                    case .hold:
                        let prevY = yForValue(keyframes[i-1].value)
                        curvePath.line(to: NSPoint(x: x, y: prevY))
                        curvePath.line(to: NSPoint(x: x, y: y))
                    default:
                        curvePath.line(to: NSPoint(x: x, y: y))
                    }
                }
            }

            NSColor.white.withAlphaComponent(0.5).setStroke()
            curvePath.lineWidth = 1
            curvePath.stroke()
        }

        // Draw keyframe diamonds
        for kf in keyframes {
            let x = xForKeyframe(kf, in: clip)
            let y = yForValue(kf.value)

            let diamond = NSBezierPath()
            diamond.move(to: NSPoint(x: x, y: y - diamondSize))
            diamond.line(to: NSPoint(x: x + diamondSize, y: y))
            diamond.line(to: NSPoint(x: x, y: y + diamondSize))
            diamond.line(to: NSPoint(x: x - diamondSize, y: y))
            diamond.close()

            NSColor.yellow.setFill()
            diamond.fill()
            NSColor.orange.setStroke()
            diamond.lineWidth = 1
            diamond.stroke()
        }
    }

    private func xForKeyframe(_ kf: Keyframe, in clip: Clip) -> CGFloat {
        let absoluteTime = clip.timelineRange.start + kf.time
        return timelineScale.xPosition(for: absoluteTime) - timelineScale.xPosition(for: clip.timelineRange.start)
    }

    private func yForValue(_ value: Double) -> CGFloat {
        // Map 0...1 value to view height (inverted: 0 at top, 1 at bottom)
        return bounds.height * (1.0 - CGFloat(value)) * 0.8 + bounds.height * 0.1
    }
}
```

---

## 15. Performance for Large Projects

### Key Performance Strategies

#### 1. Virtualized Clip Rendering
Only render clips that are currently visible in the viewport:

```swift
class TracksContainerView: NSView {
    var timeline: Timeline!
    var timelineScale: TimelineScale!

    /// Only create/update views for visible clips
    func updateVisibleClips() {
        let visibleTimeRange = visibleRange()

        for track in timeline.tracks {
            for clip in track.clips {
                let isVisible = clip.timelineRange.intersection(visibleTimeRange).duration > .zero

                if isVisible {
                    ensureClipViewExists(for: clip)
                } else {
                    recycleClipView(for: clip.id)
                }
            }
        }
    }

    private func visibleRange() -> CMTimeRange {
        let startTime = timelineScale.time(for: 0)
        let endTime = timelineScale.time(for: bounds.width)
        return CMTimeRange(start: startTime, end: endTime)
    }

    // View recycling pool
    private var recycledClipViews: [ClipView] = []

    private func recycleClipView(for clipId: UUID) {
        if let view = activeClipViews.removeValue(forKey: clipId) {
            view.removeFromSuperview()
            view.prepareForReuse()
            recycledClipViews.append(view)
        }
    }

    private func dequeueClipView() -> ClipView {
        if let recycled = recycledClipViews.popLast() {
            return recycled
        }
        return ClipView()
    }

    private var activeClipViews: [UUID: ClipView] = [:]
}
```

#### 2. Thumbnail LOD (Level of Detail)
Generate thumbnails at different resolutions based on zoom level:

```swift
enum ThumbnailLOD {
    case low     // 1 thumbnail per clip (zoomed way out)
    case medium  // thumbnails every 5 seconds
    case high    // thumbnails every 1 second
    case ultra   // thumbnails every frame (zoomed way in)

    static func forZoom(_ pixelsPerSecond: CGFloat) -> ThumbnailLOD {
        switch pixelsPerSecond {
        case 0..<20:   return .low
        case 20..<100: return .medium
        case 100..<500: return .high
        default:        return .ultra
        }
    }

    var interval: Double {
        switch self {
        case .low:    return 30.0
        case .medium: return 5.0
        case .high:   return 1.0
        case .ultra:  return 1.0/30.0
        }
    }
}
```

#### 3. Layer-Backed Drawing for GPU Compositing

```swift
class TimelineClipLayer: CALayer {
    var clipColor: CGColor = NSColor.systemBlue.cgColor

    override func draw(in ctx: CGContext) {
        // Rounded rectangle clip background
        let path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                         cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(clipColor)
        ctx.fillPath()

        // Draw clip name
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let text = "Clip Name" as NSString
        let textRect = CGRect(x: 4, y: 2, width: bounds.width - 8, height: 14)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        text.draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
```

#### 4. Waveform Caching

```swift
/// Cache computed waveforms to disk for instant reload
class WaveformCache {
    let cacheDirectory: URL

    init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WaveformCache")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cacheKey(for url: URL, sampleCount: Int) -> String {
        let hash = url.absoluteString.data(using: .utf8)!.base64EncodedString()
        return "\(hash)_\(sampleCount)"
    }

    func loadCached(for url: URL, sampleCount: Int) -> [Float]? {
        let key = cacheKey(for: url, sampleCount: sampleCount)
        let cacheFile = cacheDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    func cache(samples: [Float], for url: URL, sampleCount: Int) {
        let key = cacheKey(for: url, sampleCount: sampleCount)
        let cacheFile = cacheDirectory.appendingPathComponent(key)
        let data = samples.withUnsafeBytes { Data($0) }
        try? data.write(to: cacheFile)
    }
}
```

#### 5. SwiftUI Canvas for Custom Drawing (alternative to AppKit)

If using SwiftUI for simpler timeline views, the Canvas view provides high-performance immediate-mode rendering:

```swift
import SwiftUI

struct TimelineCanvasView: View {
    let clips: [Clip]
    let scale: TimelineScale

    var body: some View {
        Canvas { context, size in
            // This is GPU-backed immediate mode drawing
            for clip in clips {
                let x = scale.xPosition(for: clip.timelineRange.start)
                let width = scale.width(for: clip.timelineRange.duration)
                let rect = CGRect(x: x, y: 2, width: width, height: size.height - 4)

                // Only draw if visible
                guard rect.maxX > 0 && rect.minX < size.width else { continue }

                let path = RoundedRectangle(cornerRadius: 4).path(in: rect)
                context.fill(path, with: .color(.blue.opacity(0.7)))

                // Clip name
                context.draw(
                    Text(clip.mediaReference.url.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.minX + 4, y: rect.minY + 2),
                    anchor: .topLeading
                )
            }
        }
    }
}
```

---

## 16. Professional NLE Timeline Architectures

### DaVinci Resolve Timeline Architecture

- **Track-based**: Traditional multi-track timeline with unlimited video and audio tracks
- **Tracks are layers**: Higher-numbered tracks are composited on top
- **Compound clips**: Timelines can be nested within timelines
- **Resolution independent**: All parameters recalculate when resolution changes
- **Unified trim tool**: Ripple, roll, slip, slide all accessed through one tool (Trim Edit Mode) with context-sensitive behavior based on cursor position
- **Snapping**: Toggle with N key; snaps to clip edges, playhead, markers
- **Track controls**: Mute (M), Solo (S), Lock, Auto Select, Destination Track routing

### Final Cut Pro Magnetic Timeline Architecture

- **Storyline-based**: Uses a primary storyline (spine) instead of traditional tracks
- **Connected clips**: B-roll, titles, and effects anchor to positions on the spine
- **Gap-free**: Removing a clip automatically closes the gap (magnetic behavior)
- **Roles**: Instead of tracks, clips have roles (Dialogue, Music, Effects, Video, Titles)
- **Compound clips & multicam**: Nested editing and multi-angle synchronization
- **Frameworks**: Uses TLKit.framework for timeline logic, Ozone.framework (headless Motion) for rendering

### Adobe Premiere Pro Architecture

- **Traditional track-based**: Multiple numbered video and audio tracks
- **Source/Program monitor**: Dual-monitor paradigm with separate source and timeline viewers
- **Nested sequences**: Sequences can be placed within other sequences
- **Dynamic Link**: Live connection to After Effects compositions
- **Trim modes**: Ripple, Roll, Slip, Slide with dedicated tools

### Common Patterns Across All NLEs

1. **Undo/Redo**: Every edit operation is undoable - use Command pattern
2. **Timecode-based**: Everything is addressed by timecode, not pixel position
3. **Non-destructive**: Original media is never modified
4. **Real-time preview**: Timeline compositing must happen in real-time
5. **Keyboard-driven**: Power users rely heavily on keyboard shortcuts
6. **Multi-selection**: Can select and manipulate multiple clips simultaneously

---

## 17. Open-Source Reference Implementations

### Analyzed Repositories

#### PryntTrimmerView (iOS, UIKit)
- **URL**: https://github.com/HHK1/PryntTrimmerView
- **Key patterns**:
  - UIScrollView-based thumbnail strip with lazy image generation
  - Trim handles using UIPanGestureRecognizer with expanded hit-test regions (-20px inset)
  - Position bar (playhead) synced to AVPlayer
  - Constraint-based handle positioning (leftConstraint/rightConstraint)
  - Time<->position conversion: `position / scrollWidth * duration`
  - Minimum duration enforcement for trim handles

#### VideoTimelineView (iOS, UIKit)
- **URL**: https://github.com/Tomohiro-Yamashita/VideoTimelineView
- **Key patterns**:
  - Center-line design (playhead stays centered, content scrolls)
  - Power-of-2 zoom level snapping for clean thumbnail alignment
  - Pinch-to-zoom with center-point preservation
  - Edge-scrolling when dragging trim handles near edges
  - Thumbnail LOD system: visible thumbnails get high-res, others get placeholders
  - Audio scrubbing with dual AVPlayer trick (alternating players for smooth audio)
  - Timer-based playback sync (0.01s interval)

#### DSWaveformImage (iOS/macOS, SwiftUI & UIKit)
- **URL**: https://github.com/dmrschmidt/DSWaveformImage
- **Key patterns**:
  - Accelerate framework (vDSP) for high-performance audio processing
  - AVAssetReader pipeline: Int16 -> Float -> abs -> dB -> clip -> downsample
  - Multiple render styles: filled, outlined, gradient, striped
  - Cross-platform NSImage/UIImage type aliases
  - Configuration-based drawing with scale awareness
  - Live waveform rendering with Canvas (SwiftUI)

#### TimecodeKit / swift-timecode
- **URL**: https://github.com/orchetect/TimecodeKit
- **Key patterns**:
  - Complete SMPTE timecode implementation
  - 23+ industry-standard frame rates
  - Drop-frame timecode support
  - CMTime integration via AVFoundation extensions
  - SwiftUI TimecodeField component for timecode input
  - NSTextField-based AppKit integration

---

## 18. Recommended Architecture for SwiftEditor

### Summary of Recommendations

1. **Hybrid SwiftUI + AppKit**: Use SwiftUI for panels, inspectors, and track headers. Use AppKit (NSView subclasses) for the timeline canvas, ruler, and clip rendering.

2. **Core Data Model**: The `Timeline -> Track -> Clip` hierarchy with `TimelineScale` for time-to-pixel mapping forms the foundation. All UI components reference the same scale object.

3. **AppKit Timeline Canvas**: Subclass NSView with layer-backed rendering. Use synchronized NSScrollViews for ruler/header/content. Custom draw methods for clip visualization.

4. **Thumbnail Pipeline**: Use AVAssetImageGenerator with async/await API. Implement LOD based on zoom level. Cache aggressively with NSCache + disk cache.

5. **Waveform Pipeline**: Use Accelerate framework (vDSP) for audio analysis. Cache computed waveforms. Consider DSWaveformImage as a dependency.

6. **Gesture Handling**: NSGestureRecognizer subclasses for drag, trim, zoom. Expanded hit-test regions for trim handles (PryntTrimmerView pattern).

7. **Display Sync**: Use NSView.displayLink (macOS 14+) or CVDisplayLink for frame-accurate playhead animation. Fall back to AVPlayer.addPeriodicTimeObserver.

8. **Edit Operations**: Implement Ripple/Roll/Slip/Slide as model-level operations with undo/redo support.

9. **Snap Engine**: Collect snap candidates (clip edges, playhead, markers), find nearest within pixel threshold, show visual indicator.

10. **Timecode**: Use TimecodeKit for SMPTE-compliant timecode handling and display.

11. **Performance**: Virtualize clip views (only render visible). Use view recycling. Layer-backed drawing with GPU compositing. LOD thumbnails. Waveform caching.

12. **Keyboard Shortcuts**: N for snap toggle, I/O for in/out points, J/K/L for transport, +/- for zoom, T for trim mode selection.

---

## Key Third-Party Dependencies to Consider

| Library | Purpose | License |
|---------|---------|---------|
| [TimecodeKit](https://github.com/orchetect/TimecodeKit) | SMPTE timecode handling | MIT |
| [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) | Audio waveform rendering | MIT |
| [SwiftUIIntrospect](https://github.com/siteline/SwiftUI-Introspect) | Access UIKit/AppKit views from SwiftUI | MIT |

---

## References

- [Apple AVAssetImageGenerator Documentation](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)
- [Apple NSScrollView Documentation](https://developer.apple.com/documentation/appkit/nsscrollview)
- [Apple CVDisplayLink Documentation](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k)
- [Creating Images from a Video Asset](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset)
- [WWDC 2013: Optimizing Drawing and Scrolling on OS X](https://asciiwwdc.com/2013/sessions/215)
- [WWDC 2012: Layer-Backed Views](https://nonstrict.eu/wwdcindex/wwdc2012/217/)
- [WWDC 2022: Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/)
- [WWDC 2022: Create a More Responsive Media App](https://developer.apple.com/videos/play/wwdc2022/110379/)
- [Apple Magnetic Timeline Patent](https://alex4d.com/notes/item/apple-magnetic-timeline-fcpx-patent)
- [IMG.LY: Designing a Timeline for Mobile Video Editing](https://img.ly/blog/designing-a-timeline-for-mobile-video-editing/)
- [Apple Developer Forums: SwiftUI Video Editing Timeline](https://developer.apple.com/forums/thread/763999)
- [PryntTrimmerView Source](https://github.com/HHK1/PryntTrimmerView)
- [VideoTimelineView Source](https://github.com/Tomohiro-Yamashita/VideoTimelineView)
- [DSWaveformImage Source](https://github.com/dmrschmidt/DSWaveformImage)
- [TimecodeKit Source](https://github.com/orchetect/TimecodeKit)
