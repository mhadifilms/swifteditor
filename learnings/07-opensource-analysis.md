# Open-Source Swift/macOS Video Editor Analysis

## Executive Summary

After exhaustive analysis of open-source video editing projects on GitHub, the Swift ecosystem has **no production-grade NLE** comparable to DaVinci Resolve, Final Cut Pro, or even basic editors like Shotcut. The most complete composition framework is **Cabbage/VFCabbage** (1,575 stars), which provides a proper AVFoundation abstraction layer with Timeline, TrackItem, Resource, and Transition concepts. For Metal-based video processing, **GPUImage3** (2,858 stars) and **BBMetalImage** (1,033 stars) provide the best pipeline architectures. The most instructive NLE-like project is **mini-cut** (86 stars), a WWDC 2021 Swift Student Challenge winner that implements a complete multi-track timeline editor using SpriteKit.

---

## Tier 1: Composition Frameworks (Most Important for NLE Architecture)

### 1. Cabbage (VFCabbage)
- **URL**: https://github.com/VideoFlint/Cabbage
- **Stars**: 1,575
- **Language**: Swift
- **Status**: Most mature video composition framework in Swift

#### Architecture Summary
Cabbage provides a clean abstraction over AVFoundation's composition APIs. Its architecture is the closest to what a professional NLE needs at the composition layer.

**Key Architecture Concepts:**

```
Timeline
├── videoChannel: [TransitionableVideoProvider]   // Main video track (supports transitions)
├── audioChannel: [TransitionableAudioProvider]   // Main audio track
├── overlays: [VideoProvider]                     // Picture-in-picture, titles
├── audios: [AudioProvider]                       // Additional audio tracks
├── renderSize: CGSize
├── backgroundColor: CIColor
└── passingThroughVideoCompositionProvider        // Global effects
```

**Key Protocols (from CompositionProvider.swift):**
```swift
public protocol CompositionTimeRangeProvider: AnyObject {
    var startTime: CMTime { get set }
    var duration: CMTime { get }
}

public protocol VideoCompositionProvider: AnyObject {
    func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage
}

public protocol VideoProvider: CompositionTimeRangeProvider, VideoCompositionTrackProvider, VideoCompositionProvider {}
public protocol TransitionableVideoProvider: VideoProvider {
    var videoTransition: VideoTransition? { get }
}
```

**TrackItem (from TrackItem.swift):**
```swift
open class TrackItem: NSObject, NSCopying, TransitionableVideoProvider, TransitionableAudioProvider {
    public var identifier: String
    public var resource: Resource
    public var videoConfiguration: VideoConfiguration
    public var audioConfiguration: AudioConfiguration
    public var videoTransition: VideoTransition?
    public var audioTransition: AudioTransition?
    open var startTime: CMTime = CMTime.zero
    open var duration: CMTime { get/set via resource.scaledDuration }
}
```

**Resource System (from Resource.swift):**
```swift
open class Resource: NSObject, NSCopying, ResourceTrackInfoProvider {
    open var duration: CMTime
    open var selectedTimeRange: CMTimeRange
    public var scaledDuration: CMTime  // Enables speed changes
    open var size: CGSize
    open func tracks(for type: AVMediaType) -> [AVAssetTrack]

    // Subclasses: AVAssetTrackResource, ImageResource, PHAssetTrackResource,
    //             AVAssetReaderImageResource, AVAssetReverseImageResource
}
```

**CompositionGenerator (from CompositionGenerator.swift):**
- Builds AVComposition, AVVideoComposition, and AVAudioMix from Timeline
- Handles track ID management (AVFoundation limits to ~16 tracks)
- Calculates time range "slices" for instructions (overlapping regions)
- Custom VideoCompositor using CIImage-based rendering pipeline
- Supports transitions via tween factor calculation

**VideoTransition Protocol:**
```swift
public protocol VideoTransition: AnyObject {
    var identifier: String { get }
    var duration: CMTime { get }
    func renderImage(foregroundImage: CIImage, backgroundImage: CIImage,
                     forTweenFactor tween: Float64, renderSize: CGSize) -> CIImage
}
// Built-in: CrossDissolve, Swipe, Push, BoundingUp, Fade
```

**Reusable Patterns:**
- Protocol-based composition providers allow flexible resource types
- Resource abstraction decouples media sources from timeline logic
- CompositionGenerator pattern for building AVFoundation objects from a model
- VideoCompositor with CIImage pipeline for custom rendering
- Audio processing tap chain for real-time audio effects

**Limitations:**
- Single main video channel (no true multi-track timeline)
- CIImage-based rendering (no Metal compute pipeline)
- No undo/redo system
- No UI components (backend only)
- iOS-focused (no macOS-specific adaptations)

---

### 2. MetalVideoProcess
- **URL**: https://github.com/GhostZephyr/MetalVideoProcess
- **Stars**: 161
- **Language**: Swift
- **Status**: Active Metal-based video processing framework

#### Architecture Summary
Built on top of GPUImage3 and Cabbage patterns, adds Metal-accelerated video processing with motion effects and transitions.

**Key Class - MetalVideoEditor:**
```swift
open class MetalVideoEditor: NSObject {
    public var timeline: Timeline
    public var editorItems: [MetalVideoEditorItem] = []
    public var overlayItems: [MetalVideoEditorItem] = []
    public var customVideoCompositorClass: AVVideoCompositing.Type

    // Edit operations
    public func insertItem(videoItem:) throws
    public func removeItem(videoItem:) throws
    public func split(videoItem:, splitTime:) throws  // Split at playhead
    public func cut(videoItem:, range:) throws        // Trim clip
    public func buildPlayerItem() -> AVPlayerItem
}
```

**MetalVideoEditorItem extends TrackItem:**
```swift
open class MetalVideoEditorItem: TrackItem {
    public var itemType: OMItemType  // .image, .video, .imageFrames
    public var isMute: Bool
    public weak var transitoin: MetalVideoProcessTransition?
}
```

**Motion Effects System:**
Provides a rich set of motion animations (zoom, pan, rotate, fade, wiper, pendulum, etc.) that can be applied to clips.

**Reusable Patterns:**
- Metal-accelerated custom AVVideoCompositing compositor
- Motion effects system with time-based animation
- Editor operations (split, cut, insert, remove) as methods
- Overlay/PiP support via separate overlayItems array

---

## Tier 2: Complete NLE-Like Applications

### 3. mini-cut (WWDC 2021 Winner)
- **URL**: https://github.com/fwcd/mini-cut
- **Stars**: 86
- **Language**: Swift (Swift Playground)
- **Status**: Complete but minimal NLE in SpriteKit

#### Architecture Summary
The most instructive NLE-like project. Implements a complete multi-track video editor with timeline, library, inspector, and preview as a Swift Playground using SpriteKit for rendering.

**Data Model (Model layer):**
```swift
struct Timeline {
    var tracks: [Track] = []
    var maxOffset: TimeInterval { ... }
    func playingClips(at offset: TimeInterval) -> [PlayingClip]
}

struct Track: Identifiable {
    var id: UUID
    var name: String
    var clipsById: [UUID: OffsetClip] = [:]

    mutating func cut(clipId: UUID, at trackOffset: TimeInterval)
        -> (leftId: UUID, rightId: UUID)?  // Split operation
}

struct OffsetClip: Identifiable {
    var id: UUID
    var clip: Clip
    var offset: TimeInterval
    func isPlaying(at trackOffset: TimeInterval) -> Bool
}

struct Clip: Identifiable {
    var id: UUID
    var name: String
    var category: ClipCategory  // .video, .audio, .other
    var content: ClipContent    // .text, .audiovisual, .image, .color
    var start: TimeInterval     // In-point
    var length: TimeInterval    // Duration
    var visualOffsetDx/Dy: Double
    var visualScale: Double
    var visualAlpha: Double
    var volume: Double
}
```

**State Management (MiniCutState):**
```swift
final class MiniCutState {
    var library: Library          // Available clips
    var timeline: Timeline        // Project timeline
    var cursor: TimeInterval      // Playhead position
    var selection: Selection?     // Selected clip
    var timelineZoom: Double      // Zoom level
    var timelineOffset: TimeInterval  // Scroll offset
    var isPlaying: Bool

    // Observer pattern using ListenerList
    var timelineDidChange = ListenerList<Timeline>()
    var cursorDidChange = ListenerList<TimeInterval>()
    var selectionDidChange = ListenerList<Selection?>()

    func cut()  // Cut selected clip at cursor
}
```

**Timeline View (SpriteKit-based):**
```swift
final class TimelineView: SKNode, SKInputHandler, DropTarget {
    // Bijection-based coordinate transforms
    private var toViewScale: AnyBijection<TimeInterval, CGFloat>  // Time -> pixels
    private var toViewX: AnyBijection<TimeInterval, CGFloat>      // Time -> screen X

    // Drag state machine
    private enum DragState {
        case scrolling(ScrollDragState)
        case cursor
        case clip(ClipDragState)
        case trimming(TrackClipView)
        case inactive
    }
}
```

**Key Patterns:**
- Clean separation: Model (structs) / ViewModel (class with observers) / View (SpriteKit nodes)
- Bijection-based coordinate transforms (time <-> pixel) - very elegant
- Drag state machine for timeline interaction
- ListenerList observer pattern (similar to Combine but manual)
- Diff-based track/clip view updates
- Drag and drop from library to timeline

**Layout (from MiniCutScene.swift):**
```
┌──────────────────────────────────┐
│          Title ("MiniCut")        │
├──────────┬──────────┬────────────┤
│ Library  │  Video   │ Inspector  │
│          │ Preview  │            │
├──────────┴──────────┴────────────┤
│ [+] [🗑] [✂] │ ⏮ ⏪ ▶ ⏩ ⏭ │ [zoom] │
├──────────────────────────────────┤
│         Timeline View            │
│  Track 1: [clip][  clip  ]      │
│  Track 2: [   clip   ]          │
└──────────────────────────────────┘
```

**Limitations:**
- SpriteKit-based (not AppKit/SwiftUI) - playground only
- No export functionality
- No audio waveform display
- No transitions or effects
- Simple observer pattern (not Combine/TCA)

---

### 4. Vulcan
- **URL**: https://github.com/hadiidbouk/Vulcan
- **Stars**: 8
- **Language**: Swift (macOS)
- **Status**: Early-stage macOS video editor

#### Architecture Summary
A macOS video editing application built with **SwiftUI + The Composable Architecture (TCA)**. Most significant for demonstrating a modern SwiftUI NLE architecture pattern.

**Module Structure:**
```
Vulcan/
├── Vulcan/App/          # Main app (AppCore, AppView)
├── Shared/              # Swift Package - shared models & helpers
├── Timeline/            # Swift Package - timeline feature
├── MediaLibrary/        # Swift Package - media library
└── Player/              # Swift Package - video player
```

**TCA State Architecture:**
```swift
// App level
struct AppState: Equatable {
    var timeline = TimelineState()
    var mainFrame: CGRect = .zero
}

// Timeline feature
public struct TimelineState: Equatable {
    var rows: IdentifiedArrayOf<TimelineRowState> = []
    var defaultRowsCount = 5
    var timelineTools = TimelineToolsState()
    var movieEndDuration: TimeInterval = .zero
}

// Row level
public struct TimelineRowState: Equatable, Identifiable {
    public let id: Int
    var items: [TimelineRowItem] = []
    var axisUnitTime: TimeInterval
    var movieEndDuration: TimeInterval
}
```

**TCA Reducer Composition:**
```swift
public let timelineReducer = Reducer.combine(
    mainReducer.binding(),
    timelineRowReducer.forEach(state: \.rows, action: /TimelineAction.row),
    timelineToolsReducer.pullback(state: \.timelineTools, action: /TimelineAction.timelineTools)
)
```

**Key Patterns:**
- SwiftUI with TCA for predictable state management
- Feature modules as Swift Packages (excellent separation)
- ForEachStore for timeline rows (scalable track rendering)
- Drop target for adding media from Finder
- MediaDisplayManager for async frame extraction

**Reusable for Our Project:**
- Module structure pattern (separate packages per feature)
- TCA-based timeline state management
- SwiftUI timeline rendering approach
- Horizontal ScrollView with axis markers

**Limitations:**
- Very early stage (minimal functionality)
- No playback, export, effects
- Using older TCA API patterns
- No clip trimming or splitting

---

### 5. VideoCat
- **URL**: https://github.com/vitoziv/VideoCat
- **Stars**: 86
- **Language**: Swift (iOS)
- **Status**: Advanced iOS video editor

#### Architecture Summary
The most feature-complete iOS video editor using Cabbage/VFCabbage as its composition backend, with RxSwift for reactive bindings.

**Key Components:**
```
VideoCat/
├── ViewControllers/
│   ├── ViewModel/Timeline/
│   │   ├── TimelineViewModel.swift       # Uses VFCabbage Timeline
│   │   ├── TimeRangeStore.swift          # Time-indexed data store
│   │   └── Filter/FilterItemProvider.swift
│   ├── View/Timeline/
│   │   ├── TimeLineView.swift            # Scroll-based timeline
│   │   ├── VideoRangeView.swift          # Individual clip view with trim handles
│   │   ├── VideoRangeContentView.swift   # Thumbnail strip
│   │   └── DisplayTriggerMachine.swift   # Frame-synced display updates
│   └── View/PlayerView/
│       └── VideoView.swift               # AVPlayer wrapper
├── Component/
│   ├── TimeRangePicker/
│   └── Waveform/
│       ├── WaveformView.swift
│       └── AudioSampleOperation.swift
└── Util/
    ├── AVPlayerSeeker.swift              # Smooth seeking
    └── ImageGenerator.swift              # Thumbnail generation
```

**Timeline View Implementation (UIScrollView-based):**
```swift
class TimeLineView: UIView {
    private(set) var scrollView: UIScrollView!
    private(set) var rangeViews: [VideoRangeView] = []
    var widthPerSecond: CGFloat = 60  // Pixels per second

    // Center-line based scrubbing (stationary playhead, scrolling content)
    private(set) var centerLineView: UIView!

    // Player sync
    func bindPlayer(_ player: AVPlayer?)
    func playerTimeChanged()  // Sync scroll position to playback time
    func adjustCollectionViewOffset(time: CMTime)  // Seek on scroll
}
```

**VideoRangeView (Clip Trimming):**
```swift
class VideoRangeView: TimeLineRangeView {
    // Left/right drag handles ("ears") for trimming
    private(set) var leftEar: RangeViewEarView!
    private(set) var rightEar: RangeViewEarView!
    var contentInset: UIEdgeInsets  // Ear width

    // Trim delegates
    weak var delegate: VideoRangeViewDelegate?

    // Auto-scroll when dragging near edges
    var autoScrollInset: CGFloat = 100
    private var autoScrollSpeed: CGFloat = 0
}
```

**Reusable Patterns:**
- Center-line playhead with scrolling content (industry standard)
- Trim handles with auto-scroll at edges
- DisplayTriggerMachine for frame-synced thumbnail loading
- Lazy thumbnail loading (only for visible clips)
- Player time <-> scroll position bidirectional sync
- Waveform display from audio samples
- Transition duration visualization between clips

**Limitations:**
- iOS only (UIKit, not AppKit/SwiftUI)
- Single video channel (no multi-track)
- RxSwift dependency (consider Combine instead)
- No undo/redo

---

### 6. Silkscreen
- **URL**: https://github.com/jcampbell05/Silkscreen
- **Stars**: 4
- **Language**: Swift
- **Status**: Abandoned early-stage open source NLE

#### Architecture Summary
Designed as an open-source video editor with proper NLE architecture using UICollectionView for the timeline.

**Key Architecture Files:**

**TimelineCollectionViewLayout (Custom UICollectionViewLayout):**
```swift
class TimelineCollectionViewLayout: UICollectionViewLayout {
    // Constants
    private let TimelineHeaderHeight: CGFloat = 30
    private let TimelineTrackHeight: CGFloat = 60
    private let TimelineTrackHeaderWidth: CGFloat = 100
    private let TimelineTimeMarkerWidth: CGFloat = 50

    // Sections = tracks, Items = clips
    // Supplementary views for time markers and track headers
    // Decoration views for track backgrounds

    func trackIdAtPoint(point: CGPoint) -> Int
    func timeIdAtPoint(point: CGPoint) -> Int
}
```

**RenderEngine (GPUImage-based):**
```swift
class RenderEngine: GPUImageFilter {
    func render(context: EditorContext) {
        context.tracks.value.reverse().forEach { track in
            let renderTrack = RenderTrack()
            renderTrack.addTarget(self)
            renderTrack.render(track)
        }
    }
}
```

**Reusable Patterns:**
- UICollectionView for timeline (sections=tracks, items=clips)
- Custom layout for time-based positioning
- Track headers as supplementary views
- Time markers as supplementary views (virtualized)
- Signal-based change notification
- Frozen immutable collections for thread safety

---

### 7. VideoEditorSwiftUI (BogdanZyk)
- **URL**: https://github.com/BogdanZyk/VideoEditorSwiftUI
- **Stars**: 52
- **Language**: Swift (iOS SwiftUI)
- **Status**: SwiftUI video editor with modern patterns

---

## Tier 3: GPU/Metal Processing Frameworks

### 8. GPUImage3
- **URL**: https://github.com/BradLarson/GPUImage3
- **Stars**: 2,858
- **Language**: Swift
- **Status**: The gold standard for Metal-based image/video processing in Swift

#### Architecture Summary
Rewrites GPUImage for Metal (from OpenGL ES). Uses a pipeline architecture where sources produce textures, operations process them, and consumers display/record them.

**Core Pipeline Protocol (from Pipeline.swift):**
```swift
public protocol ImageSource {
    var targets: TargetContainer { get }
    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt)
}

public protocol ImageConsumer: AnyObject {
    var maximumInputs: UInt { get }
    var sources: SourceContainer { get }
    func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt)
}

public protocol ImageProcessingOperation: ImageConsumer, ImageSource {}

// Pipeline operator
@discardableResult public func --> <T: ImageConsumer>(source: ImageSource, destination: T) -> T
```

**Usage Pattern:**
```swift
let camera = Camera()
let filter = SaturationAdjustment()
let renderView = RenderView()

camera --> filter --> renderView
```

**MetalRenderingDevice (Singleton):**
```swift
public class MetalRenderingDevice {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let shaderLibrary: MTLLibrary
    public let metalPerformanceShadersAreSupported: Bool
}
```

**Key Design Patterns:**
- **Pipeline operator (`-->`)**: Chain-based processing graph
- **Source/Consumer protocol**: Decoupled, composable processing nodes
- **Texture passing**: Efficient GPU texture forwarding between nodes
- **Weak target references**: Prevents retain cycles in processing chains
- **Thread-safe target container**: DispatchQueue-protected access
- **ImageRelay**: Passthrough node for dynamic graph modification

**Operations Available:** 50+ filters including color adjustments, blurs, blends, distortions, edge detection, etc.

**Reusable for Our Project:**
- Pipeline architecture for effects chain
- Metal rendering device singleton pattern
- Texture management approach
- Filter/operation protocol design
- Thread-safe target container

---

### 9. BBMetalImage
- **URL**: https://github.com/Silence-GitHub/BBMetalImage
- **Stars**: 1,033
- **Language**: Swift
- **Status**: Active Metal-based image/video processing

#### Architecture Summary
Similar to GPUImage3 but with additional features like multi-camera support, video watermarking, and video blending. Good reference for Metal pipeline implementation.

**Key Features:**
- Camera/video source to filter chain
- Multi-input blend filters
- Video recording with filters
- Depth camera support
- Metal compute shader support
- PiP (Picture in Picture) filter

---

### 10. GPUImage2
- **URL**: https://github.com/BradLarson/GPUImage2
- **Stars**: 4,938
- **Language**: Swift
- **Status**: Legacy (OpenGL ES), predecessor to GPUImage3

Still relevant for understanding the evolution of the pipeline pattern, but GPUImage3 (Metal) is the one to reference for new development.

---

## Tier 4: Related Libraries and Tools

### 11. AVFoundationEditor (tapharmonic)
- **URL**: https://github.com/tapharmonic/AVFoundationEditor
- **Stars**: 176
- **Language**: Objective-C
- **Status**: Classic reference for AVFoundation editing

Bob McCune's iMovie-like demo from his "Mastering Video" talks. Demonstrates the fundamental AVFoundation composition pattern that all Swift video editors build upon.

### 12. YiVideoEditor
- **URL**: https://github.com/coderyi/YiVideoEditor
- **Stars**: 137
- **Language**: Swift
- **Status**: Command pattern-based video operations

#### Key Pattern - Command Pattern for Video Operations:
```swift
open class YiVideoEditor: NSObject {
    var videoData: YiVideoEditorData
    var commands: [Any]

    public func rotate(rotateDegree:)  // Adds YiRotateCommand
    public func crop(cropFrame:)        // Adds YiCropCommand
    public func addLayer(layer:)        // Adds YiAddLayerCommand
    public func addAudio(asset:)        // Adds YiAddAudioCommand

    func applyCommands()  // Executes all commands sequentially
    public func export(exportURL:, completion:)
}
```

**Reusable Pattern:** Command pattern for video editing operations (good foundation for undo/redo).

### 13. IINA
- **URL**: https://github.com/iina/iina
- **Stars**: 43,946
- **Language**: Swift
- **Status**: The most popular macOS Swift media application

Not a video editor, but extremely relevant for:
- macOS Swift application architecture
- mpv integration for high-performance playback
- Keyboard shortcut system
- Multi-window management
- Plugin system architecture
- Subtitle handling

### 14. QEditor
- **URL**: https://github.com/qyz777/QEditor
- **Stars**: 72
- **Language**: Swift
- **Status**: GPUImage2-based video editor

Video editor built using AVFoundation + GPUImage2 with filter effects. Demonstrates integration of GPU processing pipeline with AVFoundation composition.

### 15. ffmpeg-swift-tutorial
- **URL**: https://github.com/oozoofrog/ffmpeg-swift-tutorial
- **Stars**: 56
- **Language**: C/Swift
- **Status**: FFmpeg integration tutorial

### 16. ffmpeg-swift (wendylabsinc)
- **URL**: https://github.com/wendylabsinc/ffmpeg-swift
- **Stars**: 3
- **Language**: Swift
- **Status**: Modern FFmpeg Swift bindings with Swift 6.2+ and artifact bundles

---

## Tier 5: C/C++ NLE Architecture References

### Olive Video Editor
- **URL**: https://github.com/olive-editor/olive
- **Language**: C++ / Qt
- **Stars**: ~4,000+
- **Status**: Active open-source NLE

Key architectural concepts transferable to Swift:
- **Node-based compositing**: Every effect/transform is a node in a graph
- **Multi-threaded rendering**: Separate render threads with frame caching
- **Disk caching**: Pre-rendered frames cached to disk
- **Project serialization**: XML-based project format
- **Timeline model**: Sequence > Track > Block > Clip hierarchy

### Shotcut / MLT Framework
- **URL**: https://github.com/mltframework/mlt
- **Language**: C
- **Status**: The most mature open-source media framework

Key concepts:
- **Producer/Consumer/Filter/Transition**: Core service types
- **Profiles**: Encapsulate frame rate, resolution, pixel aspect ratio
- **Multitrack**: Container for synchronized tracks
- **Playlist**: Ordered collection of producers
- **Field rendering**: Interlaced video support

### Kdenlive
- **URL**: https://invent.kde.org/multimedia/kdenlive
- **Language**: C++ / Qt
- **Status**: Production-quality NLE built on MLT

Key patterns:
- **Effect stack**: Ordered list of effects per clip
- **Clip groups**: Linked audio/video clips
- **Guide markers**: Named timeline positions
- **Proxy editing**: Low-res proxies for editing, full-res for export

---

## Architectural Patterns Summary

### 1. Timeline Data Model (Consensus Pattern)
All analyzed projects converge on a similar core model:

```
Project/Timeline
├── tracks: [Track]
│   └── clips: [Clip]
│       ├── resource: Resource (the media)
│       ├── startTime: CMTime (position on timeline)
│       ├── duration: CMTime
│       ├── selectedTimeRange: CMTimeRange (in/out points within resource)
│       ├── videoConfiguration: VideoConfig (transform, opacity, effects)
│       ├── audioConfiguration: AudioConfig (volume, processing)
│       └── transition: Transition? (to next/previous clip)
├── overlays: [OverlayItem]
├── audioTracks: [AudioTrack]
├── renderSize: CGSize
└── frameDuration: CMTime
```

### 2. Rendering Pipeline (Best Practice)
```
Source → [Filter1 → Filter2 → ...] → Output

// GPUImage3 style:
protocol ImageSource { func transmitPreviousImage(...) }
protocol ImageConsumer { func newTextureAvailable(_ texture:...) }

// Cabbage style:
protocol VideoCompositionProvider {
    func applyEffect(to sourceImage: CIImage, at time: CMTime, renderSize: CGSize) -> CIImage
}
```

### 3. Coordinate Transform (mini-cut Pattern)
```swift
// Bijection: Time ↔ Pixel position
var toViewScale: Bijection<TimeInterval, CGFloat>  // zoom factor
var toViewX: Bijection<TimeInterval, CGFloat>       // scale + scroll offset

// Usage:
let pixelX = toViewX.apply(timePosition)
let timePos = toViewX.inverseApply(pixelX)
```

### 4. State Management Options
| Pattern | Project | Pros | Cons |
|---------|---------|------|------|
| ListenerList (manual) | mini-cut | Simple, no deps | Boilerplate |
| RxSwift | VideoCat | Mature, powerful | Heavy dependency |
| TCA | Vulcan | Predictable, testable | Learning curve |
| Combine | (recommended) | Native, no deps | macOS 10.15+ |

### 5. Timeline View Approaches
| Approach | Project | Pros | Cons |
|----------|---------|------|------|
| SpriteKit | mini-cut | Full control, performant | Not standard UI |
| UIScrollView + custom views | VideoCat | Mature pattern | Manual layout |
| UICollectionView | Silkscreen | Virtualization built-in | Complex layout |
| SwiftUI ScrollView | Vulcan | Modern, declarative | Performance concerns |
| NSCollectionView | (recommended for macOS) | Native, virtualized | AppKit required |

### 6. Command Pattern for Operations (YiVideoEditor)
```swift
protocol EditCommand {
    func execute()
    func undo()  // Add for undo support
}
// Commands: rotate, crop, addLayer, addAudio, split, trim, move
```

---

## Recommendations for Our NLE

### Use Cabbage's Protocol Architecture
Adopt Cabbage's `VideoProvider`/`AudioProvider`/`Resource` protocol hierarchy as the foundation for the composition layer. This gives us:
- Clean AVFoundation abstraction
- Extensible resource system
- Transition support
- Testable composition generation

### Use GPUImage3's Pipeline Pattern for Effects
The `ImageSource --> ImageProcessingOperation --> ImageConsumer` pattern is ideal for building a real-time effects pipeline on Metal.

### Use mini-cut's Timeline Model as Inspiration
Its clean struct-based model (Timeline > Track > OffsetClip > Clip) with UUID-based identification and bijection coordinate transforms is elegant and suitable for a production NLE.

### Adopt a Modular Architecture (Vulcan Pattern)
Separate features into Swift Packages:
- `TimelineCore` - Data model and state
- `TimelineUI` - Timeline view
- `Composition` - AVFoundation/Metal composition
- `MediaLibrary` - Asset management
- `Player` - Playback engine
- `Effects` - Filter/effect processing
- `Export` - Rendering and export

### Consider TCA or Observable Pattern
For a macOS NLE, the @Observable macro (iOS 17 / macOS 14+) provides the best balance of simplicity and reactivity. TCA is suitable if strict testability and unidirectional data flow are priorities.

---

## Missing from Open Source (Opportunities)

1. **True multi-track NLE in Swift** - Nothing exists
2. **macOS-native timeline component** - No reusable macOS timeline
3. **Metal-based video compositor** - Cabbage uses CIImage, not direct Metal
4. **Audio waveform component for macOS** - Only iOS versions exist
5. **Keyframe animation system** - No open-source Swift implementation
6. **Project file format** - No standard NLE project format in Swift
7. **Proxy editing system** - Not implemented in any Swift project
8. **Real-time scopes (histogram, vectorscope)** - Not in Swift
9. **Color grading tools** - Basic filters only, no wheels/curves
10. **Media management with smart bins** - No Swift implementation
