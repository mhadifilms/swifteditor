# SwiftEditor: Master Implementation Blueprint

> The definitive reference document for building a professional native macOS Non-Linear Editor (NLE) in Swift. Synthesized from 16 research documents covering AVFoundation, Metal rendering, timeline UI, audio engine, effects/transitions, export/codecs, open-source analysis, UI/UX design, media management, motion graphics, architecture design, deep-dive repos, Metal shaders/plugins/scopes, C++ NLE patterns, professional delivery/color, playback optimization, and advanced GPU compute.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Tech Stack](#2-tech-stack)
3. [Module Architecture](#3-module-architecture)
4. [Implementation Phases](#4-implementation-phases)
5. [Core Data Models](#5-core-data-models)
6. [Rendering Pipeline](#6-rendering-pipeline)
7. [Audio Engine](#7-audio-engine)
8. [Timeline UI Architecture](#8-timeline-ui-architecture)
9. [Effects & Plugin System](#9-effects--plugin-system)
10. [Media Management](#10-media-management)
11. [Export System](#11-export-system)
12. [Key Technical Decisions](#12-key-technical-decisions)
13. [Risk Register](#13-risk-register)
14. [Feature Matrix](#14-feature-matrix)
15. [Project Structure](#15-project-structure)
16. [Third-Party Dependencies](#16-third-party-dependencies)
17. [Performance Targets](#17-performance-targets)
18. [Reference Architecture Summary](#18-reference-architecture-summary)

---

## 1. Executive Summary

### Vision

SwiftEditor is a professional-grade, native macOS Non-Linear Editor built entirely in Swift. It fills a gap in the open-source ecosystem: there is currently no production-quality NLE written in Swift. The closest existing projects are Cabbage (composition framework, no UI), mini-cut (student project), and Vulcan (early TCA skeleton). None approach the feature set needed for professional work.

### Core Differentiators

- **100% Native Swift/Metal**: No C++ dependencies for core functionality (FFmpeg optional for exotic codecs)
- **Protocol-Oriented Modular Architecture**: Every component usable independently as a framework
- **GPU-First Rendering**: Metal compute pipeline for all video processing, zero-copy CVPixelBuffer to MTLTexture
- **Professional Color Pipeline**: Rec.709, Rec.2020, HDR10/HLG, ProRes RAW, ACES color management
- **Lambda-Based Undo/Redo**: Kdenlive-inspired composable closure system with automatic rollback
- **Plugin Extensibility**: Third-party effects, transitions, generators, codecs, and export formats

### Architecture Heritage

The architecture synthesizes proven patterns from three families of prior art:

| Source | What We Take |
|--------|-------------|
| **Olive Editor** (C++) | Node-based processing, job-based deferred rendering, frame hash caching, rational time, texture pooling, background auto-caching |
| **MLT/Kdenlive** (C++) | Pull-based frame delivery, lambda undo/redo, request-pattern mutations, dual-playlist tracks, hierarchical effect stacks, plugin registry |
| **Cabbage/GPUImage3** (Swift) | Protocol-oriented composition providers, Metal pipeline architecture, TrackItem/Resource separation, AVVideoCompositing integration |

---

## 2. Tech Stack

### Platform & Language

| Component | Choice | Minimum Version |
|-----------|--------|----------------|
| Language | Swift 6.0 | Xcode 16+ |
| Platform | macOS | 15.0 (Sequoia) |
| iOS (future) | iOS | 18.0 |
| Build System | Swift Package Manager | swift-tools-version: 6.0 |
| Concurrency | Swift Structured Concurrency | async/await, actors, TaskGroup |

### Apple Frameworks

| Framework | Purpose |
|-----------|---------|
| **AVFoundation** | Media playback, composition, export, asset I/O |
| **Metal** | GPU rendering, compute shaders, texture management |
| **MetalKit** | MTKView for display, Metal device management |
| **Metal Performance Shaders** | Gaussian blur, histogram, image statistics |
| **Core Image** | CIFilter integration, CIKernel for custom effects |
| **Core Video** | CVPixelBuffer, CVMetalTextureCache, IOSurface |
| **VideoToolbox** | Hardware-accelerated H.264/H.265/ProRes encode/decode |
| **Core Media** | CMTime, CMSampleBuffer, CMFormatDescription |
| **AVAudioEngine** | Real-time audio mixing, effects, metering |
| **AudioToolbox** | Audio Unit v3 plugins, MTAudioProcessingTap |
| **Vision** | Object tracking, scene detection, face detection |
| **Core ML** | AI-powered features (scene classification, auto-color) |
| **SwiftUI** | Inspector panels, dialogs, preferences |
| **AppKit** | Timeline view (NSView), window management, menus |
| **Combine** | Event bus, reactive bindings, cross-module communication |
| **UniformTypeIdentifiers** | File type declarations for drag-and-drop |

### Optional External Dependencies

| Library | Purpose | When Needed |
|---------|---------|-------------|
| FFmpeg (via Swift C bridge) | Exotic codecs (VP9, AV1, DNxHR) | Phase 3+ |
| VersionedCodable | Schema-versioned Codable migration | Phase 1 |

---

## 3. Module Architecture

### Module Map

```
SwiftEditor/
├── CoreMediaPlus     Zero-dependency shared types (Rational, TimeRange, VideoParams)
├── PluginKit         Pure protocol definitions for plugin system
├── ProjectModel      Document model, Codable serialization, schema versioning
├── TimelineKit       Timeline editing model, undo/redo, snap, groups
├── EffectsEngine     Effects, transitions, generators, keyframes, plugin host
├── RenderEngine      Metal compositor, texture pool, frame cache, auto-cacher
├── ViewerKit         Playback controller, transport, scrubbing, AVPlayer wrapper
├── MediaManager      Import, proxy generation, thumbnails, media bin
├── AudioEngine       AVAudioEngine wrapper, real-time mixing, metering
└── SwiftEditor.app   macOS application (SwiftUI + AppKit)
```

### Dependency Graph

```
                         SwiftEditor.app
                        /    |    |    \
               ViewerKit TimelineKit MediaManager AudioEngine
                  |          |           |            |
              RenderEngine ProjectModel  |            |
                  |          |           |            |
             EffectsEngine   |           |            |
                  |          |           |            |
               PluginKit     |           |            |
                  \          |          /            /
                   CoreMediaPlus ──────────────────
```

**Dependency rules**:
- CoreMediaPlus: depends on Foundation only
- PluginKit: depends on CoreMediaPlus
- ProjectModel: depends on CoreMediaPlus (+ VersionedCodable)
- EffectsEngine: depends on PluginKit + CoreMediaPlus
- RenderEngine: depends on EffectsEngine + CoreMediaPlus (Metal, AVFoundation)
- TimelineKit: depends on ProjectModel + CoreMediaPlus
- ViewerKit: depends on RenderEngine + TimelineKit + CoreMediaPlus
- MediaManager: depends on CoreMediaPlus (AVFoundation)
- AudioEngine: depends on CoreMediaPlus (AVAudioEngine)
- SwiftEditor.app: imports all modules

**No circular dependencies. No module imports a sibling at the same level.**

### Package.swift (Summary)

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "SwiftEditor",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CoreMediaPlus", targets: ["CoreMediaPlus"]),
        .library(name: "PluginKit", targets: ["PluginKit"]),
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "TimelineKit", targets: ["TimelineKit"]),
        .library(name: "EffectsEngine", targets: ["EffectsEngine"]),
        .library(name: "RenderEngine", targets: ["RenderEngine"]),
        .library(name: "ViewerKit", targets: ["ViewerKit"]),
        .library(name: "MediaManager", targets: ["MediaManager"]),
        .library(name: "AudioEngine", targets: ["AudioEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jrothwell/VersionedCodable.git", from: "1.0.0"),
    ],
    targets: [/* each module as .target with appropriate dependencies */]
)
```

---

## 4. Implementation Phases

### Phase 1: MVP Foundation (Months 1-3)

**Goal**: Import media, place clips on a multi-track timeline, play back with basic cuts, and export.

| Module | Deliverables |
|--------|-------------|
| **CoreMediaPlus** | Rational time, TimeRange, VideoParams, AudioParams, ColorSpace, TrackType |
| **ProjectModel** | Project, Sequence, TrackData, ClipData structs; JSON serialization; V1 schema |
| **TimelineKit** | TimelineModel with request pattern; ClipModel, TrackModel; basic undo/redo (move, trim, split, delete); SnapModel; SelectionModel |
| **RenderEngine** | MetalCompositor (AVVideoCompositing); basic layer compositing; YUV-to-RGB conversion; TexturePool actor |
| **ViewerKit** | TransportController (play/pause/seek/stop); AVPlayer integration; periodic time observer |
| **MediaManager** | Import from Finder (drag-and-drop); AVAsset metadata extraction; basic thumbnail generation |
| **AudioEngine** | Pass-through audio via AVAudioMix; volume per clip |
| **App UI** | Single-window layout: media bin (left), viewer (center-top), timeline (bottom); basic track headers; clip rendering with thumbnails; playhead; time ruler |

**Export**: AVAssetExportSession with preset-based output (H.264/ProRes in MOV container)

**Key milestone**: User can import 3 video clips, arrange them on 2 video tracks, trim edges, split at playhead, undo/redo all operations, play back in real time, and export to ProRes 422.

### Phase 2: Professional Editing (Months 4-6)

**Goal**: Effects, transitions, keyframes, audio mixing, and proxy workflow.

| Module | Deliverables |
|--------|-------------|
| **EffectsEngine** | PluginKit protocols; built-in effects (brightness, contrast, saturation, gamma, blur, sharpen, color wheels); VideoTransition protocol + built-in transitions (cross dissolve, dip to black, wipe, push); KeyframeTrack with linear/bezier/hold interpolation; EffectStack model |
| **RenderEngine** | Two-phase rendering (RenderPlan then execute); frame hash caching; background auto-caching; compute shader dispatch for effects |
| **TimelineKit** | Same-track transitions; grouped clips; ripple/roll/slip/slide edit modes; markers; razor tool |
| **MediaManager** | Proxy generation (background transcoding to ProRes Proxy); proxy/original toggle; smart relink for moved media; security-scoped bookmarks |
| **AudioEngine** | Multi-track AVAudioEngine mixing; per-track volume/pan automation; audio waveform generation; peak/RMS metering |
| **ViewerKit** | Frame-accurate scrubbing via AVPlayerItemVideoOutput + DisplayLink; in/out point marking; JKL shuttle |
| **App UI** | Inspector panel (clip properties, effect parameters, keyframe editor); effects browser; audio waveforms on timeline; transition handles |

**Export**: AVAssetWriter with custom video compositor; H.264, H.265, ProRes 422/4444 output

**Key milestone**: User can apply color correction + blur to a clip, animate position with bezier keyframes, add a cross-dissolve between clips, mix 4 audio tracks with volume automation, edit with proxies, and export at full resolution.

### Phase 3: Color & Advanced Features (Months 7-9)

**Goal**: Professional color grading, video scopes, text/titles, advanced motion.

| Module | Deliverables |
|--------|-------------|
| **EffectsEngine** | Color wheels (lift/gamma/gain); curves; color match; LUT import (.cube, .3dl); chroma key; speed ramp (time remapping) |
| **RenderEngine** | Video scopes (histogram, waveform, RGB parade, vectorscope) via compute shaders; HDR pipeline (EDR, Rec.2020, PQ/HLG); ProRes RAW decode support |
| **TimelineKit** | Compound clips (nested sequences); multicam editing with angle switching; subtitle track |
| **App UI** | Color grading workspace; video scopes panel; text/title editor (CoreText to Metal); workspace presets (edit, color, audio); detachable panels |
| **AudioEngine** | Audio effects via AUAudioUnit v3 (EQ, compressor, reverb); audio-only export |

**Key milestone**: Full color grading workflow with scopes, multicam editing, text overlay with animation, and HDR monitoring.

### Phase 4: Polish & Ecosystem (Months 10-12)

**Goal**: Plugin ecosystem, performance optimization, advanced I/O.

| Module | Deliverables |
|--------|-------------|
| **PluginKit** | Bundle-based plugin loading; PluginHost services; sample third-party plugin project |
| **RenderEngine** | Metal 4 adoption (unified command encoder, ML integration); multi-GPU support; smart rendering (pass-through unmodified segments) |
| **MediaManager** | AI-powered scene detection (Vision); auto-tagging; smart bins with metadata filters |
| **App UI** | Full keyboard shortcut system (200+ shortcuts); touch bar support; accessibility (VoiceOver); Liquid Glass UI integration |
| **Export** | Batch export; render queue; YouTube/social media presets; FFmpeg bridge for AV1/VP9 |

### Phase 5: v2.0 Aspirational Features (Months 13+)

- Node-based compositing graph editor (Olive-style)
- Collaboration features (project locking, shared project files)
- AI auto-edit (scene-based assembly from rough footage)
- AI audio cleanup (noise reduction, voice isolation via Core ML)
- Motion tracking with linked effects (Vision framework)
- Stabilization (Core Motion + Vision)
- Closed captions / subtitle workflow with SRT/VTT import/export
- AAF/XML interchange with Premiere/Resolve
- iPad companion app (shared framework modules)

---

## 5. Core Data Models

### Time System

All time values use rational arithmetic (CMTime-backed `Rational` type). No floating-point time anywhere in the editing model. Timescale 600 is the default (LCM of 24, 25, 30, 60 fps).

```swift
struct Rational: Sendable, Hashable, Comparable, Codable {
    let numerator: Int64
    let denominator: Int64
    // Arithmetic: +, -, *, /
    // Conversions: init(CMTime), .cmTime, .seconds, .frameNumber(at:)
}

struct TimeRange: Sendable, Hashable, Codable {
    let start: Rational
    let duration: Rational
    var end: Rational { start + duration }
    func contains(_ time: Rational) -> Bool
    func overlaps(_ other: TimeRange) -> Bool
    func intersection(_ other: TimeRange) -> TimeRange?
}
```

### Project Document Model

```
Project (Codable, versioned)
├── id: UUID
├── name: String
├── version: Int (schema version for migration)
├── settings: ProjectSettings
│   ├── videoParams: VideoParams (width, height, pixelFormat, colorSpace)
│   ├── audioParams: AudioParams (sampleRate, channelCount, bitDepth)
│   ├── frameRate: Rational
│   └── fieldOrder: FieldOrder
├── sequences: [Sequence]
│   ├── id: UUID
│   ├── name: String
│   ├── videoTracks: [TrackData]
│   │   └── clips: [ClipData]
│   │       ├── sourceAssetID: UUID (references MediaBin)
│   │       ├── startTime: Rational (position on timeline)
│   │       ├── sourceIn / sourceOut: Rational
│   │       ├── speed: Double
│   │       ├── effects: [EffectData]
│   │       │   ├── pluginID: String
│   │       │   ├── parameters: [String: ParameterValue]
│   │       │   └── keyframes: [String: [KeyframeData]]
│   │       └── transform: (position, scale, rotation, opacity)
│   ├── audioTracks: [TrackData]
│   └── markers: [Marker]
├── bin: MediaBinModel (hierarchical folders)
│   └── items: [BinItemData]
│       ├── relativePath: String
│       ├── proxyPath: String?
│       ├── duration, videoParams, audioParams
│       └── metadata (codecs, creation date, camera info)
└── metadata: ProjectMetadata
```

**File format**: Directory bundle (`.nleproj/`) containing `project.json` + `autosave.json` + media reference cache. Human-readable JSON with pretty-printing. Schema migration from V(n) to V(n+1) via VersionedCodable.

### Timeline Runtime Model

```
TimelineModel (@Observable)
├── videoTracks: [VideoTrack]
├── audioTracks: [AudioTrack]
├── duration: Rational (computed)
├── selection: SelectionState
├── undoManager: TimelineUndoManager
├── groupsModel: GroupsModel (tree: parent->children, child->parent)
├── snapModel: SnapModel (position -> refcount)
├── events: TimelineEventBus (Combine)
│
├── request*() methods (single entry point for all mutations):
│   requestClipMove, requestClipResize, requestClipSplit,
│   requestClipDelete, requestTrackInsert, requestTrackRemove,
│   requestEffectAdd, requestEffectRemove, requestGroupCreate, ...
│
└── Each request composes undo/redo lambdas:
    var undo: () -> Bool = { true }
    var redo: () -> Bool = { true }
    appendOperation(&redo, forwardAction)
    prependOperation(&undo, reverseAction)
    guard redo() else { undo(); return false }
    undoManager.record(undo, redo, description)
```

---

## 6. Rendering Pipeline

### Architecture: Two-Phase Rendering

Inspired by Olive's job-based deferred rendering. Phase 1 traverses the composition graph and builds a plan (no GPU needed). Phase 2 executes the plan on Metal.

```
Phase 1: Build RenderPlan (CPU)          Phase 2: Execute on Metal (GPU)
─────────────────────────────            ─────────────────────────────
For each active layer at time T:          For each job in plan:
  Get source CVPixelBuffer                  .decodeSource -> YUV-to-RGB shader
  Collect effect stack                      .applyEffect  -> compute dispatch
  Collect transform                         .applyTransform -> vertex transform
  Add RenderJobs                            .applyTransition -> blend shader
If transition: add transition job           .composite -> multi-layer blend
Add composite job                        Commit command buffer
                                         Return MTLTexture / CVPixelBuffer
```

### MetalCompositor (AVVideoCompositing)

```swift
final class MetalCompositor: NSObject, AVVideoCompositing {
    // Pull-based: AVFoundation calls startRequest(_:) when it needs a frame
    // 1. Check FrameHashCache (content-addressable, disk-backed)
    // 2. If miss: buildRenderPlan() from instruction
    // 3. executePlan() on Metal command queue
    // 4. Cache result, return CVPixelBuffer

    // Supports HDR: supportsHDRSourceFrames = true
    // Supports wide color: supportsWideColorSourceFrames = true
}
```

### Texture Management

- **CVMetalTextureCache**: Zero-copy CVPixelBuffer to MTLTexture mapping via IOSurface
- **TexturePool (actor)**: Reusable MTLTexture pool indexed by (width, height, pixelFormat). Prevents allocation churn during playback.
- **Triple buffering**: Three sets of textures rotate between encode, render, and display
- **Texture format**: `.bgra8Unorm` for SDR, `.rgba16Float` for HDR

### Caching Strategy

| Cache | Scope | Storage | Invalidation |
|-------|-------|---------|-------------|
| **FrameHashCache** | Rendered frame by content hash | Disk (UUID-keyed files) | On clip/effect change |
| **TexturePool** | Reusable MTLTextures | GPU memory | Pool size limit |
| **ThumbnailCache** | Timeline waveform/thumbnails | Disk + memory | On source media change |
| **ShaderCache** | Compiled pipeline states | MTLBinaryArchive | On shader source change |
| **DecoderCache** | VideoToolbox sessions | Memory | LRU eviction |

### Background Auto-Caching (Olive Pattern)

The `BackgroundRenderer` actor pre-renders frames around the playhead in background threads using TaskGroup with bounded concurrency (max 4 parallel renders to avoid GPU contention). When the user moves the playhead, caching refocuses on the new position.

---

## 7. Audio Engine

### Dual-Path Architecture

The audio system has two independent paths:

**Real-Time Playback** (AVAudioEngine):
```
[AVAudioPlayerNode per track] -> [per-track effects] -> [AVAudioMixerNode] -> [Master effects] -> [Output]
```
- Sample-accurate sync via AVAudioTime
- Real-time peak/RMS metering via installTap
- Per-track volume/pan automation
- AU v3 effect plugin hosting

**Export Path** (MTAudioProcessingTap + AVAudioMix):
```
AVAssetReader -> MTAudioProcessingTap (per track) -> process callback -> AVAssetWriter
```
- Identical effect chain as playback
- Offline rendering at maximum speed
- Sample-accurate cross-fades

### Key Capabilities

| Feature | Implementation |
|---------|---------------|
| Multi-track mixing | AVAudioMixerNode with per-track volume/pan |
| Volume automation | Keyframeable volume envelope via MTAudioProcessingTap |
| Audio effects | AUAudioUnit v3 (EQ, compressor, reverb, noise gate) |
| Waveform display | Offline analysis: read samples, compute min/max per pixel column |
| Peak metering | installTap on mixer output, compute peak/RMS per buffer |
| Crossfades | Overlapping clips with linear/equal-power/S-curve fade shapes |
| Voiceover recording | AVAudioEngine capture input -> write to file |
| Scrubbing audio | Short audio snippets played at scrub position |

---

## 8. Timeline UI Architecture

### Hybrid SwiftUI + AppKit Approach

The timeline is the most performance-critical UI component. SwiftUI alone cannot handle the demands of a professional timeline (hundreds of clips, pixel-precise dragging, 60fps updates during scrubbing). The recommended approach:

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Timeline track area | NSView (custom drawing + CALayer) | Pixel-precise control, virtualization, 60fps drag |
| Track headers | SwiftUI (in NSHostingView) | Standard controls, easy layout |
| Time ruler | NSView (custom drawing) | Tick marks at variable zoom, timecode display |
| Inspector panel | SwiftUI | Form-based layouts, bindings |
| Effects browser | SwiftUI | List/grid with search |
| Viewer | MTKView (Metal) | Zero-copy frame display |
| Dialogs/preferences | SwiftUI | Standard macOS patterns |

### Timeline View Architecture

```
TimelineContainerView (NSSplitView)
├── TrackHeadersView (NSStackView of SwiftUI NSHostingViews)
│   └── Per track: name, mute/solo/lock buttons, volume slider
├── TrackAreaView (NSScrollView wrapping custom NSView)
│   ├── Virtualized: only draws visible clips (O(visible) not O(total))
│   ├── Clip rendering: CALayer per clip with thumbnail strip + waveform
│   ├── Transition indicators between adjacent clips
│   ├── Selection overlay (blue highlight, multi-select rect)
│   └── Drag-and-drop (NSView drag session)
├── PlayheadView (CALayer, positioned by transport controller)
└── TimeRulerView (custom NSView, tick marks + timecode)
```

### Coordinate System

Bijection-based transforms (from mini-cut pattern):
```swift
// Time <-> Pixel mapping
let pixelsPerSecond: CGFloat  // zoom level
let scrollOffset: Rational    // horizontal scroll position

func timeToPixel(_ time: Rational) -> CGFloat
func pixelToTime(_ pixel: CGFloat) -> Rational
```

### Interaction State Machine

```
                    ┌─────────┐
                    │  Idle   │
                    └────┬────┘
                         │
           ┌─────────────┼─────────────┐
           │             │             │
    ┌──────▼──────┐ ┌────▼────┐ ┌─────▼──────┐
    │  Dragging   │ │Trimming │ │  Selecting  │
    │  clip(s)    │ │ (L/R)   │ │  (marquee)  │
    └─────────────┘ └─────────┘ └────────────┘
```

### Keyboard Shortcuts (200+ mapped)

Core editing: J/K/L (shuttle), I/O (in/out), Space (play/pause), Cmd+Z/Shift+Cmd+Z (undo/redo), C (razor), V (select), B (blade), N (snap toggle), Cmd+S (save), Cmd+Shift+E (export).

---

## 9. Effects & Plugin System

### Effect Architecture

Every effect is a `ProcessingNode` (protocol-oriented, Olive-inspired):

```swift
protocol ProcessingNode: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var category: String { get }
    var parameters: [ParameterDescriptor] { get }
    func process(input: NodeValueTable, at time: Rational) -> NodeValueTable
}

protocol VideoEffect: ProcessingNode { /* apply(to:at:parameters:) */ }
protocol VideoTransition: ProcessingNode { /* apply(from:to:progress:parameters:) */ }
protocol VideoGenerator: ProcessingNode { /* generate(at:size:parameters:) */ }
protocol AudioEffect: ProcessingNode { /* process(buffer:at:parameters:) */ }
```

### Built-In Effects (Phase 2-3)

| Category | Effects |
|----------|---------|
| **Color** | Brightness, Contrast, Saturation, Gamma, Exposure, White Balance, Hue/Saturation, Color Wheels (Lift/Gamma/Gain), Curves, Color Match |
| **Blur** | Gaussian Blur, Directional Blur, Radial Blur, Zoom Blur |
| **Sharpen** | Unsharp Mask, Sharpen |
| **Distort** | Transform (position/scale/rotation), Crop, Lens Distortion |
| **Keying** | Chroma Key (green/blue screen), Luma Key |
| **Style** | Vignette, Film Grain, Glow |
| **Generate** | Solid Color, Gradient, Text/Title, Shape, Noise |
| **Time** | Speed Ramp, Freeze Frame, Reverse |

### Built-In Transitions (Phase 2)

Cross Dissolve, Dip to Black, Dip to White, Wipe (left/right/up/down), Push, Slide, Zoom, Spin

### Keyframe System

Per-parameter keyframe tracks with independent interpolation per component (Olive pattern):

```swift
struct KeyframeTrack {
    var keyframes: [Keyframe]
    struct Keyframe {
        var time: Rational
        var value: ParameterValue
        var interpolation: InterpolationType  // .linear, .hold, .bezier
        var bezierIn: CGPoint?   // Tangent handles
        var bezierOut: CGPoint?
    }
    func value(at time: Rational) -> ParameterValue  // Interpolated
}
```

Multi-dimensional parameters (color, position) have separate tracks per component for independent easing.

### Plugin System

**Architecture**: Protocol (PluginKit) + macOS Bundle discovery

```
Plugin loading flow:
1. App scans ~/Library/Application Support/SwiftEditor/Plugins/ and app bundle
2. Each .plugin bundle loaded via Bundle(url:).load()
3. Principal class conforms to PluginBundle protocol
4. Plugin registers its ProcessingNodes with PluginRegistry actor
5. Nodes appear in effects browser alongside built-in effects
```

**Plugin capabilities declared via manifest**: GPU-accelerated, real-time capable, HDR support, keyframeable.

### Video Scopes (Phase 3)

All implemented as Metal compute shaders reading the current viewer frame:

| Scope | Shader Strategy |
|-------|----------------|
| **Histogram** | Atomic histogram accumulation into shared memory buffer |
| **Waveform** | Column-by-column luminance scatter plot |
| **RGB Parade** | Three-channel separated waveform |
| **Vectorscope** | UV chrominance mapped to circular display |

---

## 10. Media Management

### Import Pipeline

```
User drops files / uses File > Import
    │
    ▼
AssetImporter validates file types (UTType)
    │
    ├── Copy to project media folder (or reference in-place)
    ├── Extract metadata (AVAsset: duration, codecs, resolution, fps)
    ├── Create BinItemData in ProjectModel
    ├── Queue thumbnail generation (AVAssetImageGenerator, background)
    ├── Queue proxy generation if enabled (background AVAssetWriter)
    └── Queue waveform analysis for audio (background)
```

### Proxy Workflow (Phase 2)

| Aspect | Implementation |
|--------|---------------|
| Proxy codec | ProRes Proxy (422 Proxy) |
| Proxy resolution | 1/2 or 1/4 of original |
| Generation | Background AVAssetWriter transcoding |
| Toggle | Global switch: Use Proxy / Use Original |
| Export | Always uses original media |
| Storage | `ProjectFolder/Proxies/` with matching filenames |

### Media Bin

Hierarchical folder structure (DaVinci Resolve pattern):
- Rating system (1-5 stars + favorites)
- Color labels
- Smart bins (filtered by metadata: codec, resolution, date range, rating)
- Keyword tagging
- Search by name, metadata, tags

### Persistent File Access

Security-scoped bookmarks (macOS sandbox):
```swift
// On import: create bookmark
let bookmark = try url.bookmarkData(options: .withSecurityScope)
// Store bookmark in project
// On project open: resolve bookmark
var isStale = false
let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
_ = url.startAccessingSecurityScopedResource()
```

Relink workflow for moved/renamed media: search by filename, then by file attributes (size, creation date).

---

## 11. Export System

### Export Architecture

```
ExportSession
├── Input: TimelineModel + RenderEngine
├── Pipeline: AVAssetReader + Custom Video Compositor + AVAssetWriter
├── Audio: MTAudioProcessingTap chain (mirrors playback effects)
├── Progress: Combine publisher (0.0 -> 1.0)
└── Output: File at destination URL
```

### Supported Output Formats

| Codec | Container | Hardware Accelerated | Phase |
|-------|-----------|---------------------|-------|
| H.264 | MOV, MP4 | Yes (VideoToolbox) | 1 |
| H.265/HEVC | MOV, MP4 | Yes (VideoToolbox) | 1 |
| ProRes 422 | MOV | Yes (Apple Silicon) | 1 |
| ProRes 4444 | MOV | Yes (Apple Silicon) | 2 |
| ProRes 422 HQ/LT/Proxy | MOV | Yes | 2 |
| AAC audio | MOV, MP4, M4A | Yes | 1 |
| Linear PCM | MOV, WAV | N/A (uncompressed) | 1 |
| AV1 | MP4 | Via FFmpeg bridge | 4 |
| VP9 | WebM | Via FFmpeg bridge | 4 |

### Smart Rendering (Phase 4)

Pass through unmodified segments without re-encoding:
1. Detect timeline segments where source codec matches output codec
2. Copy compressed samples directly (AVAssetReaderTrackOutput -> AVAssetWriterInput)
3. Only re-encode segments with effects, transitions, or format changes

### Render Queue (Phase 4)

Background render queue for batch exports:
- Multiple export jobs with different presets
- Priority ordering
- Pause/resume
- Notification on completion

---

## 12. Key Technical Decisions

| # | Decision | Choice | Alternatives Considered | Rationale |
|---|----------|--------|------------------------|-----------|
| 1 | **State management** | Custom @Observable + request pattern | TCA, MVVM, ReSwift | TCA adds too much ceremony for real-time media. MVVM lacks mutation discipline. Request pattern from Kdenlive gives explicit mutations with lambda undo/redo and direct @Observable SwiftUI integration. |
| 2 | **Undo/redo** | Lambda composition (Kdenlive) | Command objects (Olive), NSUndoManager | Lambda closures are composable, self-healing (automatic rollback on failure), and require zero boilerplate classes. Bridged to NSUndoManager for Edit menu. |
| 3 | **Rendering model** | Two-phase: plan then execute (Olive) | Single-pass render, Core Image only | Separates graph traversal from GPU execution. Enables frame hash caching at plan level. Allows different backends. |
| 4 | **Frame delivery** | Pull-based (AVVideoCompositing) | Push-based, manual frame loop | Aligns with AVFoundation's design. Consumer controls timing. Natural frame dropping and seeking. |
| 5 | **Time representation** | Rational (CMTime-based) | Double, Int frames | Exact arithmetic prevents floating-point accumulation. Frame-accurate at all rates. |
| 6 | **Timeline UI** | AppKit NSView (custom draw + CALayer) | SwiftUI Canvas, SpriteKit, Metal direct | SwiftUI lacks precision for professional timeline. AppKit NSView gives pixel control, native drag-and-drop, and proven virtualization. |
| 7 | **GPU pipeline** | Metal compute shaders | Core Image only, OpenGL | Metal compute gives full control over GPU execution, supports HDR natively, aligns with Apple's direction. Core Image used for interop where convenient. |
| 8 | **Audio mixing** | AVAudioEngine (playback) + MTAudioProcessingTap (export) | Core Audio directly, FMOD | AVAudioEngine is the modern Apple API with AU v3 support. MTAudioProcessingTap provides sample-accurate export mixing. |
| 9 | **Plugin system** | Protocol + Bundle loading (MLT pattern) | Dynamic library (dlopen), XPC | Bundle loading is the standard macOS pattern. Safe, sandboxable, discoverable. XPC too complex for v1. |
| 10 | **Project format** | JSON directory bundle (.nleproj/) | SQLite, binary, XML | Human-readable, diffable, Codable-native. Directory bundle allows co-located autosave and cache files. |
| 11 | **Color pipeline** | Rec.709 default, Rec.2020/HDR opt-in | ACES throughout | Most source material is Rec.709. ACES conversion available for professional workflows but not forced by default. |
| 12 | **Concurrency model** | Actors for shared state, TaskGroup for parallel render | GCD queues, manual locks | Compiler-enforced isolation. No manual locking. Structured concurrency prevents resource leaks. |
| 13 | **Module system** | SPM multi-target package | CocoaPods, Carthage, monolith | Native Xcode integration. Each module independently testable and usable. No external build tools. |

---

## 13. Risk Register

| # | Risk | Impact | Probability | Mitigation |
|---|------|--------|-------------|------------|
| 1 | **AVFoundation 16-track limit** | High | Certain | Track multiplexing: reuse track IDs across non-overlapping time ranges. Cabbage's CompositionGenerator demonstrates this pattern. |
| 2 | **Timeline UI performance at scale** (1000+ clips) | High | Medium | Virtualization: only instantiate views/layers for visible clips. CALayer-based rendering with off-screen pre-rendering. Incremental layout updates. |
| 3 | **Metal compute shader complexity** | Medium | Medium | Start with MPS (Metal Performance Shaders) for common operations. Custom shaders only where MPS is insufficient. Maintain shader unit test suite. |
| 4 | **Undo/redo correctness with complex edits** | High | Medium | Extensive unit tests for every request*() method. Lambda composition guarantees atomic rollback. Fuzzing with random edit sequences. |
| 5 | **Memory pressure with 4K/8K media** | High | High | Aggressive texture pooling. Proxy workflow. Background thumbnail generation with disk cache. CVMetalTextureCache for zero-copy textures. IOSurface sharing. |
| 6 | **Audio-video sync drift** | High | Medium | Shared master clock (CMClockGetHostTimeClock). AVPlayer.masterClock. Periodic sync correction. Comprehensive A/V sync tests. |
| 7 | **Plugin security and stability** | Medium | Low | Plugins run in-process but are loaded from signed bundles. Hardened runtime. Future: XPC isolation for untrusted plugins. |
| 8 | **Project file corruption** | High | Low | Atomic writes (Data.write(options: .atomic)). Autosave with backup rotation. Undo stack persistence. Schema validation on load. |
| 9 | **Swift 6 strict concurrency adoption** | Medium | Medium | Use `@Sendable` and actors from day one. All shared mutable state in actors. Incremental adoption with `@unchecked Sendable` only where proven safe. |
| 10 | **HDR display pipeline correctness** | Medium | Medium | Follow Apple's EDR guidelines (WWDC 2022). Test on HDR displays. Use `.rgba16Float` textures and extended linear sRGB color space. CAMetalLayer.wantsExtendedDynamicRangeContent = true. |
| 11 | **FFmpeg integration complexity** | Medium | High (if needed) | Defer FFmpeg to Phase 4. Use AVFoundation for all Phase 1-3 codecs. FFmpeg only for exotic formats (AV1, DNxHR). Consider pre-built XCFramework via artifact bundles. |
| 12 | **Scope creep** | High | High | Strict phase gating. MVP must work end-to-end before adding features. Feature matrix with priority tiers (P0/P1/P2/P3). |

---

## 14. Feature Matrix

### P0: Must Have for MVP (Phase 1)

| Feature | Module | Status |
|---------|--------|--------|
| Import video/audio from Finder | MediaManager | Phase 1 |
| Multi-track timeline (video + audio) | TimelineKit | Phase 1 |
| Clip placement, move, delete | TimelineKit | Phase 1 |
| Trim (ripple) | TimelineKit | Phase 1 |
| Split at playhead | TimelineKit | Phase 1 |
| Undo/redo (all edit operations) | TimelineKit | Phase 1 |
| Real-time playback | ViewerKit | Phase 1 |
| Basic export (H.264/ProRes) | RenderEngine | Phase 1 |
| Save/load project | ProjectModel | Phase 1 |
| Thumbnail strip on clips | MediaManager | Phase 1 |
| Time ruler with timecode | App UI | Phase 1 |
| Playhead with scrubbing | ViewerKit | Phase 1 |

### P1: Core Professional Features (Phase 2)

| Feature | Module | Status |
|---------|--------|--------|
| Video transitions (cross dissolve + 6 more) | EffectsEngine | Phase 2 |
| Color correction (brightness/contrast/saturation) | EffectsEngine | Phase 2 |
| Keyframe animation (linear/bezier) | EffectsEngine | Phase 2 |
| Transform (position/scale/rotation/opacity) | EffectsEngine | Phase 2 |
| Effect stack per clip | EffectsEngine | Phase 2 |
| Audio waveform display | AudioEngine | Phase 2 |
| Per-track volume/pan | AudioEngine | Phase 2 |
| Audio crossfades | AudioEngine | Phase 2 |
| Proxy workflow | MediaManager | Phase 2 |
| Markers | TimelineKit | Phase 2 |
| Snap to edges/markers/playhead | TimelineKit | Phase 2 |
| Grouped clips | TimelineKit | Phase 2 |
| Roll/slip/slide edit modes | TimelineKit | Phase 2 |
| Inspector panel | App UI | Phase 2 |
| Effects browser | App UI | Phase 2 |
| Frame-accurate scrubbing | ViewerKit | Phase 2 |
| JKL shuttle playback | ViewerKit | Phase 2 |
| Frame hash caching | RenderEngine | Phase 2 |
| Background auto-caching | RenderEngine | Phase 2 |

### P2: Advanced Professional (Phase 3)

| Feature | Module | Status |
|---------|--------|--------|
| Color wheels (lift/gamma/gain) | EffectsEngine | Phase 3 |
| Curves editor | EffectsEngine | Phase 3 |
| LUT import (.cube, .3dl) | EffectsEngine | Phase 3 |
| Chroma key | EffectsEngine | Phase 3 |
| Video scopes (histogram/waveform/vectorscope/parade) | RenderEngine | Phase 3 |
| HDR pipeline (Rec.2020, PQ/HLG) | RenderEngine | Phase 3 |
| ProRes RAW decode | RenderEngine | Phase 3 |
| Text/title generator | EffectsEngine | Phase 3 |
| Speed ramp / time remapping | TimelineKit | Phase 3 |
| Compound clips / nested sequences | TimelineKit | Phase 3 |
| Multicam editing | TimelineKit | Phase 3 |
| Subtitle track | TimelineKit | Phase 3 |
| Workspace presets (edit/color/audio) | App UI | Phase 3 |
| Audio effects (EQ, compressor) | AudioEngine | Phase 3 |
| Audio metering (peak/RMS/LUFS) | AudioEngine | Phase 3 |

### P3: Ecosystem & Polish (Phase 4+)

| Feature | Module | Status |
|---------|--------|--------|
| Third-party plugin support | PluginKit | Phase 4 |
| Metal 4 adoption | RenderEngine | Phase 4 |
| Smart rendering (pass-through) | Export | Phase 4 |
| Batch export / render queue | Export | Phase 4 |
| AI scene detection | MediaManager | Phase 4 |
| Full keyboard shortcut system | App UI | Phase 4 |
| Accessibility (VoiceOver) | App UI | Phase 4 |
| FFmpeg bridge (AV1, VP9) | Export | Phase 4 |
| Node-based compositing | Future | v2.0 |
| Collaboration | Future | v2.0 |
| AAF/XML interchange | Future | v2.0 |
| iPad companion | Future | v2.0 |

---

## 15. Project Structure

```
SwiftEditor/
├── Package.swift
├── Sources/
│   ├── CoreMediaPlus/
│   │   ├── Rational.swift              # Exact rational time arithmetic
│   │   ├── TimeRange.swift             # Time range with set operations
│   │   ├── VideoParams.swift           # Width, height, pixel format, color space
│   │   ├── AudioParams.swift           # Sample rate, channels, bit depth
│   │   ├── ColorSpace.swift            # Rec.709, Rec.2020, P3, ACES, log formats
│   │   ├── MediaType.swift             # TrackType, TrimEdge, BlendMode
│   │   └── ParameterValue.swift        # Type-safe parameter union
│   ├── PluginKit/
│   │   ├── PluginManifest.swift        # Plugin metadata declaration
│   │   ├── PluginBundle.swift          # Entry point protocol for plugins
│   │   ├── PluginHost.swift            # Services provided to plugins
│   │   ├── PluginRegistry.swift        # Actor: discovery, loading, lookup
│   │   ├── EffectPlugin.swift          # VideoEffect / AudioEffect protocols
│   │   ├── TransitionPlugin.swift      # VideoTransition protocol
│   │   ├── GeneratorPlugin.swift       # VideoGenerator protocol
│   │   ├── CodecPlugin.swift           # Custom codec protocol
│   │   └── ExportFormatPlugin.swift    # Custom export format protocol
│   ├── ProjectModel/
│   │   ├── Project.swift               # Top-level document model
│   │   ├── Sequence.swift              # Timeline sequence
│   │   ├── TrackData.swift             # Serializable track
│   │   ├── ClipData.swift              # Serializable clip
│   │   ├── EffectData.swift            # Serializable effect instance
│   │   ├── KeyframeData.swift          # Serializable keyframe
│   │   ├── BinItem.swift               # Media bin entries
│   │   ├── ProjectSettings.swift       # Resolution, frame rate, color space
│   │   ├── Versioning/
│   │   │   ├── ProjectV1.swift         # V1 schema
│   │   │   └── ProjectMigration.swift  # V(n) -> V(n+1) migration
│   │   └── Serialization/
│   │       └── ProjectFileManager.swift # Save/load/autosave
│   ├── TimelineKit/
│   │   ├── Models/
│   │   │   ├── TimelineModel.swift     # @Observable, request*() methods
│   │   │   ├── TrackModel.swift        # Track with clips array
│   │   │   ├── ClipModel.swift         # Runtime clip with effect stack
│   │   │   ├── TransitionModel.swift   # Same-track transition
│   │   │   ├── GroupsModel.swift       # Tree-based clip grouping
│   │   │   ├── SnapModel.swift         # Reference-counted snap points
│   │   │   └── SelectionModel.swift    # Selected clips/tracks/range
│   │   ├── Editing/
│   │   │   ├── UndoSystem.swift        # Lambda undo/redo + UndoMacro
│   │   │   ├── EditOperations.swift    # Move, trim, split, delete impl
│   │   │   └── EditValidation.swift    # Overlap/lock/bounds checking
│   │   └── Events/
│   │       └── TimelineEventBus.swift  # Combine publisher for events
│   ├── EffectsEngine/
│   │   ├── EffectStack.swift           # Ordered effect list per clip
│   │   ├── EffectInstance.swift        # Runtime effect with parameter state
│   │   ├── NodeValueTable.swift        # Heterogeneous value stack (Olive)
│   │   ├── Keyframe/
│   │   │   ├── KeyframeTrack.swift     # Per-parameter keyframe list
│   │   │   ├── Interpolation.swift     # Linear, bezier, hold
│   │   │   └── BezierCurve.swift       # Cubic bezier evaluation
│   │   ├── BuiltIn/
│   │   │   ├── ColorCorrection.swift   # Brightness, contrast, saturation
│   │   │   ├── Transform.swift         # Position, scale, rotation
│   │   │   ├── Blur.swift              # Gaussian, directional
│   │   │   ├── ChromaKey.swift         # Green/blue screen
│   │   │   └── Transitions/            # Cross dissolve, wipe, push, etc.
│   │   └── Shader/
│   │       ├── ShaderLibrary.swift     # MTLLibrary management
│   │       └── ShaderCompiler.swift    # Dynamic compilation + caching
│   ├── RenderEngine/
│   │   ├── Compositor/
│   │   │   ├── MetalCompositor.swift   # AVVideoCompositing implementation
│   │   │   └── CompositionInstruction.swift  # Per-frame instruction
│   │   ├── Pipeline/
│   │   │   ├── RenderPipeline.swift    # Metal device, queue, state objects
│   │   │   ├── RenderJob.swift         # Job enum (decode, effect, composite)
│   │   │   └── RenderPlan.swift        # Ordered list of jobs for one frame
│   │   ├── Cache/
│   │   │   ├── FrameHashCache.swift    # Content-addressable disk cache
│   │   │   ├── TexturePool.swift       # Actor: reusable MTLTexture pool
│   │   │   └── AutoCacher.swift        # Background pre-rendering
│   │   ├── Scopes/
│   │   │   ├── HistogramCompute.swift  # Histogram compute shader
│   │   │   ├── WaveformCompute.swift   # Waveform monitor shader
│   │   │   ├── VectorscopeCompute.swift # Vectorscope shader
│   │   │   └── ScopeRenderer.swift     # Scope visualization
│   │   └── Export/
│   │       ├── ExportSession.swift     # AVAssetWriter-based export
│   │       └── ExportPreset.swift      # Codec/container/quality presets
│   ├── ViewerKit/
│   │   ├── ViewerViewModel.swift       # @Observable viewer state
│   │   ├── TransportController.swift   # Play/pause/seek/shuttle
│   │   ├── ScrubController.swift       # Frame-accurate scrub via VideoOutput
│   │   └── ViewerConfiguration.swift   # Display settings (zoom, guides)
│   ├── MediaManager/
│   │   ├── AssetImporter.swift         # File validation, copy, metadata
│   │   ├── ProxyGenerator.swift        # Background proxy transcoding
│   │   ├── ThumbnailGenerator.swift    # AVAssetImageGenerator wrapper
│   │   ├── WaveformAnalyzer.swift      # Audio sample analysis
│   │   ├── MediaBin.swift              # Runtime bin state
│   │   └── AssetMetadata.swift         # Parsed metadata types
│   ├── AudioEngine/
│   │   ├── AudioMixer.swift            # AVAudioEngine multi-track mixer
│   │   ├── AudioMeteringTap.swift      # Peak/RMS metering
│   │   ├── AudioEffectChain.swift      # AU v3 effect hosting
│   │   └── AudioExportMix.swift        # MTAudioProcessingTap for export
│   └── SwiftEditorApp/
│       ├── SwiftEditorApp.swift        # @main entry point
│       ├── AppState.swift              # Top-level observable state
│       ├── Views/
│       │   ├── MainWindowView.swift    # Primary window layout
│       │   ├── Timeline/
│       │   │   ├── TimelineNSView.swift # AppKit timeline container
│       │   │   ├── TrackLaneView.swift  # Custom clip drawing
│       │   │   ├── TrackHeaderView.swift # SwiftUI track header
│       │   │   └── TimeRulerView.swift  # Timecode ruler
│       │   ├── Viewer/
│       │   │   ├── ViewerView.swift     # MTKView wrapper
│       │   │   └── TransportBar.swift   # Play/pause/shuttle controls
│       │   ├── Inspector/
│       │   │   ├── InspectorView.swift  # Tab-based inspector
│       │   │   ├── ClipInspector.swift
│       │   │   ├── EffectInspector.swift
│       │   │   └── KeyframeEditor.swift
│       │   ├── MediaBin/
│       │   │   ├── MediaBinView.swift   # Grid/list media browser
│       │   │   └── ImportDropView.swift # Drag-and-drop target
│       │   └── EffectsBrowser/
│       │       └── EffectsBrowserView.swift
│       ├── Commands/
│       │   └── MenuCommands.swift       # macOS menu bar structure
│       └── Resources/
│           ├── Shaders/
│           │   ├── YUVtoRGB.metal       # Color space conversion
│           │   ├── Composite.metal      # Layer blending
│           │   ├── ColorCorrection.metal # LGG, curves, exposure
│           │   ├── Blur.metal           # Gaussian, directional
│           │   ├── Transition.metal     # Cross dissolve, wipe
│           │   ├── ChromaKey.metal      # Green screen
│           │   ├── Histogram.metal      # Scope compute
│           │   ├── Waveform.metal       # Scope compute
│           │   └── Vectorscope.metal    # Scope compute
│           └── Assets.xcassets
├── Tests/
│   ├── CoreMediaPlusTests/              # Rational arithmetic, TimeRange
│   ├── ProjectModelTests/               # Serialization, migration, round-trip
│   ├── TimelineKitTests/                # Every request*() method + undo
│   ├── EffectsEngineTests/              # Keyframe interpolation, effects
│   ├── RenderEngineTests/               # Cache, texture pool, compositor
│   ├── ViewerKitTests/                  # Transport state machine
│   ├── MediaManagerTests/               # Import, metadata, proxy
│   └── AudioEngineTests/                # Mixing, metering
└── Plugins/
    ├── BuiltInEffects/                  # Bundled plugin package
    └── ExampleThirdPartyEffect/         # Sample external plugin
```

---

## 16. Third-Party Dependencies

### Required (Phase 1)

| Dependency | Purpose | License |
|-----------|---------|---------|
| **VersionedCodable** | Schema-versioned Codable migration | MIT |

### Optional (Phase 4+)

| Dependency | Purpose | License | Notes |
|-----------|---------|---------|-------|
| **FFmpeg** (via C bridge) | AV1, VP9, DNxHR codecs | LGPL/GPL | XCFramework artifact bundle; only for exotic codecs |

### Explicitly Avoided

| Library | Reason |
|---------|--------|
| TCA (Composable Architecture) | Overhead for real-time media; incompatible with lambda undo pattern |
| RxSwift | Replaced by native Combine |
| Realm/Core Data | Project files are document-based Codable, not database |
| GPUImage3 | Patterns adopted but direct dependency avoided; we write our own Metal pipeline |
| Alamofire/Moya | No network layer needed for v1 |

**Philosophy**: Minimize external dependencies. Use Apple frameworks wherever possible. Each dependency is a maintenance liability and a risk for App Store review.

---

## 17. Performance Targets

### Playback

| Metric | Target | How Measured |
|--------|--------|-------------|
| 1080p playback frame rate | 60 fps sustained | Metal frame time < 16.6ms |
| 4K playback frame rate | 30 fps sustained | Metal frame time < 33.3ms |
| Playback start latency | < 200ms from press Play | Stopwatch from input to first frame |
| Seek latency (frame-accurate) | < 100ms | Time from seek call to frame display |
| Scrubbing responsiveness | Every frame during drag | No dropped frames during slow scrub |

### Timeline UI

| Metric | Target |
|--------|--------|
| Timeline scroll | 60 fps with 500+ clips visible |
| Clip drag responsiveness | < 16ms per frame during drag |
| Zoom in/out | 60 fps during pinch/scroll zoom |
| Undo/redo execution | < 10ms per operation |

### Rendering

| Metric | Target |
|--------|--------|
| 1080p export speed | >= 2x real-time (ProRes 422) |
| 4K export speed | >= 0.5x real-time (H.265) |
| Background caching | 5 seconds cached in < 2 seconds |
| Frame hash cache hit rate | > 90% during playback of cached range |

### Memory

| Metric | Target |
|--------|--------|
| Base memory (empty project) | < 150 MB |
| Per 1080p clip overhead | < 20 MB (metadata + thumbnails) |
| Texture pool size | 8-32 textures (configurable) |
| Peak memory (4K, 8 tracks, effects) | < 2 GB |

### Startup

| Metric | Target |
|--------|--------|
| Cold launch to usable | < 3 seconds |
| Project open (50 clips) | < 2 seconds |
| Project open (500 clips) | < 5 seconds |

---

## 18. Reference Architecture Summary

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           SwiftEditor.app                                │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                    SwiftUI + AppKit UI Layer                        │ │
│  │  ┌───────────┐ ┌──────────┐ ┌───────────┐ ┌──────────────────────┐│ │
│  │  │ Media Bin │ │  Viewer  │ │ Inspector │ │ Timeline (NSView)    ││ │
│  │  │ (SwiftUI) │ │ (MTKView)│ │ (SwiftUI) │ │ + TrackLanes        ││ │
│  │  └─────┬─────┘ └────┬─────┘ └─────┬─────┘ │ + Playhead          ││ │
│  │        │             │             │        │ + Ruler             ││ │
│  │        │             │             │        └──────────┬───────────┘│ │
│  └────────┼─────────────┼─────────────┼───────────────────┼───────────┘ │
│           │             │             │                   │             │
│  ┌────────▼─────────────▼─────────────▼───────────────────▼───────────┐ │
│  │                  TimelineModel (@Observable)                       │ │
│  │  ├── videoTracks, audioTracks          ├── groupsModel            │ │
│  │  ├── request*() methods                ├── snapModel              │ │
│  │  ├── undoManager (lambda closures)     └── events (Combine bus)   │ │
│  └────────────────────────────┬──────────────────────────────────────┘ │
│                               │                                        │
│  ┌──────────────┐  ┌──────────▼─────────┐  ┌──────────────────────┐   │
│  │ MediaManager │  │ TransportController │  │   AudioMixer         │   │
│  │ Import/Proxy │  │ Play/Pause/Seek     │  │ AVAudioEngine        │   │
│  │ Thumbnails   │  │ AVPlayer wrapper    │  │ Per-track effects    │   │
│  └──────────────┘  └────────┬────────────┘  └──────────────────────┘   │
│                              │                                          │
│  ┌───────────────────────────▼────────────────────────────────────────┐ │
│  │                    MetalCompositor (AVVideoCompositing)            │ │
│  │  ┌──────────────┐  ┌─────────────┐  ┌────────────────────┐       │ │
│  │  │ RenderPlan   │  │ TexturePool │  │ FrameHashCache     │       │ │
│  │  │ (build jobs) │  │ (actor)     │  │ (disk-backed)      │       │ │
│  │  └──────┬───────┘  └─────────────┘  └────────────────────┘       │ │
│  │         │                                                         │ │
│  │  ┌──────▼───────────────────────────────────────────────────────┐ │ │
│  │  │              Metal GPU Pipeline                              │ │ │
│  │  │  CVPixelBuffer -> CVMetalTextureCache -> MTLTexture          │ │ │
│  │  │  -> YUV-RGB -> Effects (compute) -> Composite -> Display    │ │ │
│  │  └──────────────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │                    EffectsEngine + PluginKit                     │ │
│  │  Built-in: Color, Blur, Transform, Chroma Key, Generators       │ │
│  │  Plugins: PluginRegistry actor -> Bundle discovery -> Register   │ │
│  │  Keyframes: Per-parameter tracks, bezier interpolation          │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │                    ProjectModel                                  │ │
│  │  Codable document -> JSON directory bundle (.nleproj/)          │ │
│  │  Versioned schema -> V1 -> V2 -> ... migration chain            │ │
│  │  Autosave -> atomic writes -> backup rotation                   │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Summary

```
1. User edits timeline
   -> TimelineModel.request*()
   -> Compose undo/redo lambdas
   -> Execute mutation
   -> Publish event via Combine

2. @Observable triggers SwiftUI/AppKit update
   -> Timeline redraws affected clips
   -> Inspector updates if selection changed

3. Event reaches RenderEngine
   -> Invalidate affected frame cache entries
   -> AutoCacher re-queues background renders

4. User presses Play
   -> TransportController starts AVPlayer
   -> AVPlayer pulls frames via AVVideoCompositing
   -> MetalCompositor.startRequest()
   -> Check FrameHashCache (hit? return cached)
   -> Build RenderPlan from instruction
   -> Execute on Metal GPU
   -> Return CVPixelBuffer to AVPlayer
   -> AVPlayer displays via MTKView

5. User exports
   -> ExportSession creates AVAssetReader + AVAssetWriter
   -> Same MetalCompositor processes every frame
   -> MTAudioProcessingTap handles audio effects
   -> Progress published via Combine
   -> File written to disk
```

### Patterns Heritage Map

| Pattern | Source | Where Used |
|---------|--------|-----------|
| Request-based mutations | Kdenlive | TimelineModel.request*() |
| Lambda undo/redo composition | Kdenlive | UndoSystem |
| Dual-playlist tracks | Kdenlive | TrackModel (same-track transitions) |
| Groups/Snap as separate models | Kdenlive | GroupsModel, SnapModel |
| Two-phase rendering (plan/execute) | Olive | RenderPlan + MetalCompositor |
| Frame hash caching | Olive | FrameHashCache |
| Background auto-caching | Olive | AutoCacher |
| Texture pooling | Olive | TexturePool actor |
| Rational time arithmetic | Olive | Rational (wrapping CMTime) |
| NodeValueTable | Olive | EffectsEngine value passing |
| Per-component keyframe tracks | Olive | KeyframeTrack |
| Pull-based frame delivery | MLT | AVVideoCompositing |
| Plugin registry | MLT | PluginRegistry actor |
| Filter attachment chain | MLT | EffectStack |
| Protocol composition providers | Cabbage | VideoEffect, VideoTransition protocols |
| CompositionGenerator | Cabbage | MetalCompositor instruction building |
| Metal pipeline architecture | GPUImage3 | RenderPipeline |
| Bijection coordinate transforms | mini-cut | Timeline time<->pixel mapping |

---

*This document synthesizes research from 16 detailed analysis files totaling over 1.1 MB of technical content. Each learning document is available in the `learnings/` directory for deep-dive reference on any specific topic.*
