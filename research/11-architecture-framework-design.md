# Architecture & Reusable Framework Design for Swift NLE

## Table of Contents

1. [Swift Package Manager Module Structure](#1-swift-package-manager-module-structure)
2. [Module Dependency Graph](#2-module-dependency-graph)
3. [Package.swift Definition](#3-packageswift-definition)
4. [Protocol-Oriented Design for Extensibility](#4-protocol-oriented-design-for-extensibility)
5. [Plugin Architecture](#5-plugin-architecture)
6. [State Management Strategy](#6-state-management-strategy)
7. [Command Pattern for Undo/Redo](#7-command-pattern-for-undoredo)
8. [Event-Driven Architecture with Combine](#8-event-driven-architecture-with-combine)
9. [Data Flow for Real-Time Preview](#9-data-flow-for-real-time-preview)
10. [Project Document Model](#10-project-document-model)
11. [Framework API Design](#11-framework-api-design)
12. [Concurrency Architecture](#12-concurrency-architecture)
13. [Complete Architecture Synthesis](#13-complete-architecture-synthesis)

---

## 1. Swift Package Manager Module Structure

### Design Philosophy

The NLE is decomposed into six primary modules plus supporting packages, each with a single responsibility. Modules communicate through protocol interfaces, enabling independent development, testing, and reuse. The architecture draws from Olive's node-based flexibility, Kdenlive's request-pattern discipline, and MLT's composable pipeline model.

### Module Overview

```
SwiftEditor (App)
├── ProjectModel      — Document model, serialization, versioning
├── TimelineKit       — Timeline editing model, undo/redo, snap/group
├── ViewerKit         — Playback engine, scrubbing, transport controls
├── RenderEngine      — Metal rendering, compositing, caching
├── EffectsEngine     — Effects, transitions, generators, plugin host
├── MediaManager      — Asset import, proxy generation, bin management
│
├── CoreMedia+        — Shared types: Rational time, TimeRange, etc.
├── PluginKit         — Plugin protocol definitions and discovery
└── TestSupport       — Shared mocks and test utilities
```

### Module Responsibilities

**ProjectModel**: The document container. Owns the canonical representation of a project including sequences, bin items, metadata, and settings. All data is `Codable` and versioned. Has zero UI dependencies.

**TimelineKit**: The editing model. Owns `TimelineModel`, `TrackModel`, `ClipModel`, `GroupsModel`, `SnapModel`. All mutations go through `request*()` methods that compose undo/redo lambdas. This is the brain of the editor -- it validates edits, maintains consistency, and publishes state changes.

**ViewerKit**: The playback controller. Wraps `AVPlayer`, manages transport state (play, pause, seek, loop, shuttle), provides frame-accurate scrubbing, and coordinates with `RenderEngine` for custom compositing. Exposes a SwiftUI-friendly `ViewerViewModel`.

**RenderEngine**: GPU rendering via Metal. Implements `AVVideoCompositing` for real-time preview, manages texture pools, frame hash caching, and background auto-caching. Provides both a real-time preview path and an offline export path.

**EffectsEngine**: Effect processing. Hosts built-in and plugin effects, transitions, and generators. Provides the effect stack model, keyframe interpolation, and shader compilation. Effects operate on `RenderFrame` values, not raw textures.

**MediaManager**: Asset lifecycle management. Handles import (drag-and-drop, file browser, Photos library), generates proxies and thumbnails in background, maintains the media bin, and provides asset metadata (duration, codecs, resolution).

**CoreMedia+**: Shared value types with zero external dependencies. Contains `Rational`, `TimeRange`, `VideoParams`, `AudioParams`, `ColorSpace`, and other types used across all modules.

**PluginKit**: Protocol definitions for the plugin system. This is a pure protocol package -- no implementations. Any module that needs to host plugins imports PluginKit for the contracts.

---

## 2. Module Dependency Graph

```
                    ┌─────────────┐
                    │ SwiftEditor │  (App target)
                    │   (App)     │
                    └──────┬──────┘
                           │ imports all modules
           ┌───────────────┼───────────────────┐
           │               │                   │
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────────▼────────┐
    │ ViewerKit   │ │ TimelineKit │ │   MediaManager     │
    │             │ │             │ │                    │
    └──────┬──────┘ └──────┬──────┘ └────────┬───────────┘
           │               │                  │
           │        ┌──────▼──────┐           │
           │        │ProjectModel │           │
           │        └──────┬──────┘           │
           │               │                  │
    ┌──────▼──────┐        │                  │
    │RenderEngine │◄───────┘                  │
    │             │                           │
    └──────┬──────┘                           │
           │                                  │
    ┌──────▼───────┐                          │
    │EffectsEngine │                          │
    └──────┬───────┘                          │
           │                                  │
    ┌──────▼──────┐                           │
    │  PluginKit  │                           │
    └──────┬──────┘                           │
           │                                  │
    ┌──────▼──────────────────────────────────▼──┐
    │              CoreMedia+                     │
    │  (Rational, TimeRange, VideoParams, etc.)   │
    └─────────────────────────────────────────────┘
```

### Dependency Rules

1. **CoreMedia+** depends on nothing (Foundation only)
2. **PluginKit** depends on CoreMedia+ only
3. **EffectsEngine** depends on PluginKit + CoreMedia+
4. **RenderEngine** depends on EffectsEngine + CoreMedia+ (Metal, AVFoundation)
5. **ProjectModel** depends on CoreMedia+ only
6. **TimelineKit** depends on ProjectModel + CoreMedia+
7. **ViewerKit** depends on RenderEngine + TimelineKit + CoreMedia+
8. **MediaManager** depends on CoreMedia+ (AVFoundation, Photos)
9. **SwiftEditor** (app) imports everything

**Key constraint**: No circular dependencies. Information flows downward. UI modules never import other UI modules directly -- they communicate through the ProjectModel and TimelineKit state.

---

## 3. Package.swift Definition

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftEditor",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        // Public frameworks -- each can be used independently
        .library(name: "CoreMediaPlus", targets: ["CoreMediaPlus"]),
        .library(name: "PluginKit", targets: ["PluginKit"]),
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "TimelineKit", targets: ["TimelineKit"]),
        .library(name: "EffectsEngine", targets: ["EffectsEngine"]),
        .library(name: "RenderEngine", targets: ["RenderEngine"]),
        .library(name: "ViewerKit", targets: ["ViewerKit"]),
        .library(name: "MediaManager", targets: ["MediaManager"]),
    ],
    dependencies: [
        // External dependencies kept minimal
        // VersionedCodable for document migration
        .package(url: "https://github.com/jrothwell/VersionedCodable.git", from: "1.0.0"),
    ],
    targets: [
        // ── CoreMedia+ ─────────────────────────────────
        // Shared value types with zero external dependencies
        .target(
            name: "CoreMediaPlus",
            dependencies: [],
            path: "Sources/CoreMediaPlus"
        ),
        .testTarget(
            name: "CoreMediaPlusTests",
            dependencies: ["CoreMediaPlus"],
            path: "Tests/CoreMediaPlusTests"
        ),

        // ── PluginKit ───────────────────────────────────
        // Protocol definitions for the plugin system
        .target(
            name: "PluginKit",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/PluginKit"
        ),

        // ── ProjectModel ────────────────────────────────
        // Document model, serialization, versioning
        .target(
            name: "ProjectModel",
            dependencies: [
                "CoreMediaPlus",
                .product(name: "VersionedCodable", package: "VersionedCodable"),
            ],
            path: "Sources/ProjectModel"
        ),
        .testTarget(
            name: "ProjectModelTests",
            dependencies: ["ProjectModel"],
            path: "Tests/ProjectModelTests"
        ),

        // ── EffectsEngine ───────────────────────────────
        // Effect processing, keyframes, shader compilation
        .target(
            name: "EffectsEngine",
            dependencies: ["CoreMediaPlus", "PluginKit"],
            path: "Sources/EffectsEngine"
        ),
        .testTarget(
            name: "EffectsEngineTests",
            dependencies: ["EffectsEngine"],
            path: "Tests/EffectsEngineTests"
        ),

        // ── RenderEngine ────────────────────────────────
        // Metal rendering, compositing, caching
        .target(
            name: "RenderEngine",
            dependencies: ["CoreMediaPlus", "EffectsEngine"],
            path: "Sources/RenderEngine"
        ),
        .testTarget(
            name: "RenderEngineTests",
            dependencies: ["RenderEngine"],
            path: "Tests/RenderEngineTests"
        ),

        // ── TimelineKit ─────────────────────────────────
        // Timeline editing model, undo/redo, snap/group
        .target(
            name: "TimelineKit",
            dependencies: ["CoreMediaPlus", "ProjectModel"],
            path: "Sources/TimelineKit"
        ),
        .testTarget(
            name: "TimelineKitTests",
            dependencies: ["TimelineKit"],
            path: "Tests/TimelineKitTests"
        ),

        // ── ViewerKit ───────────────────────────────────
        // Playback engine, scrubbing, transport controls
        .target(
            name: "ViewerKit",
            dependencies: [
                "CoreMediaPlus",
                "RenderEngine",
                "TimelineKit",
            ],
            path: "Sources/ViewerKit"
        ),
        .testTarget(
            name: "ViewerKitTests",
            dependencies: ["ViewerKit"],
            path: "Tests/ViewerKitTests"
        ),

        // ── MediaManager ────────────────────────────────
        // Asset import, proxy generation, bin management
        .target(
            name: "MediaManager",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/MediaManager"
        ),
        .testTarget(
            name: "MediaManagerTests",
            dependencies: ["MediaManager"],
            path: "Tests/MediaManagerTests"
        ),
    ]
)
```

### Source Layout

```
SwiftEditor/
├── Package.swift
├── Sources/
│   ├── CoreMediaPlus/
│   │   ├── Rational.swift
│   │   ├── TimeRange.swift
│   │   ├── VideoParams.swift
│   │   ├── AudioParams.swift
│   │   ├── ColorSpace.swift
│   │   └── MediaType.swift
│   ├── PluginKit/
│   │   ├── EffectPlugin.swift
│   │   ├── TransitionPlugin.swift
│   │   ├── GeneratorPlugin.swift
│   │   ├── CodecPlugin.swift
│   │   ├── ExportFormatPlugin.swift
│   │   └── PluginRegistry.swift
│   ├── ProjectModel/
│   │   ├── Project.swift
│   │   ├── Sequence.swift
│   │   ├── BinItem.swift
│   │   ├── ProjectSettings.swift
│   │   ├── Versioning/
│   │   │   ├── ProjectV1.swift
│   │   │   ├── ProjectV2.swift
│   │   │   └── ProjectMigration.swift
│   │   └── Serialization/
│   │       ├── ProjectEncoder.swift
│   │       └── ProjectDecoder.swift
│   ├── TimelineKit/
│   │   ├── Models/
│   │   │   ├── TimelineModel.swift
│   │   │   ├── TrackModel.swift
│   │   │   ├── ClipModel.swift
│   │   │   ├── TransitionModel.swift
│   │   │   ├── GroupsModel.swift
│   │   │   └── SnapModel.swift
│   │   ├── Editing/
│   │   │   ├── EditOperations.swift
│   │   │   ├── UndoSystem.swift
│   │   │   └── EditValidation.swift
│   │   └── Selection/
│   │       └── SelectionModel.swift
│   ├── EffectsEngine/
│   │   ├── EffectStack.swift
│   │   ├── EffectInstance.swift
│   │   ├── Keyframe/
│   │   │   ├── KeyframeTrack.swift
│   │   │   ├── KeyframeInterpolation.swift
│   │   │   └── BezierCurve.swift
│   │   ├── BuiltIn/
│   │   │   ├── ColorCorrection.swift
│   │   │   ├── Transform.swift
│   │   │   ├── Crop.swift
│   │   │   └── Blur.swift
│   │   └── Shader/
│   │       ├── ShaderCompiler.swift
│   │       └── ShaderLibrary.swift
│   ├── RenderEngine/
│   │   ├── Compositor/
│   │   │   ├── MetalCompositor.swift
│   │   │   └── CompositionInstruction.swift
│   │   ├── Pipeline/
│   │   │   ├── RenderPipeline.swift
│   │   │   ├── RenderJob.swift
│   │   │   └── RenderPlan.swift
│   │   ├── Cache/
│   │   │   ├── FrameHashCache.swift
│   │   │   ├── TexturePool.swift
│   │   │   └── AutoCacher.swift
│   │   └── Export/
│   │       ├── ExportSession.swift
│   │       └── ExportPreset.swift
│   ├── ViewerKit/
│   │   ├── ViewerViewModel.swift
│   │   ├── TransportController.swift
│   │   ├── ScrubController.swift
│   │   └── ViewerConfiguration.swift
│   └── MediaManager/
│       ├── AssetImporter.swift
│       ├── ProxyGenerator.swift
│       ├── ThumbnailGenerator.swift
│       ├── MediaBin.swift
│       └── AssetMetadata.swift
├── Tests/
│   ├── CoreMediaPlusTests/
│   ├── ProjectModelTests/
│   ├── TimelineKitTests/
│   ├── EffectsEngineTests/
│   ├── RenderEngineTests/
│   ├── ViewerKitTests/
│   └── MediaManagerTests/
└── Plugins/
    ├── BuiltInEffects/           (bundled plugin package)
    └── ExampleThirdPartyEffect/  (sample external plugin)
```

---

## 4. Protocol-Oriented Design for Extensibility

### Core Protocols

Every module boundary is defined by protocols. This enables mocking for tests, alternative implementations, and runtime extensibility.

### CoreMedia+ Protocols

```swift
// MARK: - Time Protocols

/// Any type that occupies a range on the timeline
public protocol TimeRangeProviding {
    var timeRange: TimeRange { get }
}

/// Any type that can be positioned on the timeline
public protocol TimePositionable: TimeRangeProviding {
    var startTime: Rational { get set }
    var duration: Rational { get }
}

/// Any type that represents a media source with intrinsic duration
public protocol MediaSource: Sendable {
    var sourceID: UUID { get }
    var naturalDuration: Rational { get }
    var videoParams: VideoParams? { get }
    var audioParams: AudioParams? { get }
}
```

### TimelineKit Protocols

```swift
// MARK: - Timeline Editing Protocols

/// A single track in the timeline
public protocol Track: AnyObject, Identifiable, Observable {
    associatedtype ClipType: Clip

    var id: UUID { get }
    var name: String { get set }
    var clips: [ClipType] { get }
    var isMuted: Bool { get set }
    var isLocked: Bool { get set }

    func clip(at time: Rational) -> ClipType?
    func clips(in range: TimeRange) -> [ClipType]
    func insertClip(_ clip: ClipType, at time: Rational) throws
    func removeClip(_ clipID: UUID) throws
}

/// A clip on a track
public protocol Clip: AnyObject, Identifiable, TimePositionable, Observable {
    var id: UUID { get }
    var sourceRef: any MediaSource { get }
    var sourceIn: Rational { get set }
    var sourceOut: Rational { get set }
    var speed: Double { get set }
    var effectStack: EffectStack { get }
    var isEnabled: Bool { get set }
}

/// The top-level timeline model
public protocol Timeline: AnyObject, Observable {
    associatedtype VideoTrackType: Track
    associatedtype AudioTrackType: Track

    var videoTracks: [VideoTrackType] { get }
    var audioTracks: [AudioTrackType] { get }
    var duration: Rational { get }
    var playhead: Rational { get set }

    // All mutations go through request methods (Kdenlive pattern)
    func requestClipMove(clipID: UUID, toTrack: UUID, at: Rational) -> Bool
    func requestClipResize(clipID: UUID, edge: TrimEdge, to: Rational) -> Bool
    func requestClipSplit(clipID: UUID, at: Rational) -> Bool
    func requestTrackInsert(at index: Int, type: TrackType) -> Bool
    func requestTrackRemove(trackID: UUID) -> Bool
}
```

### RenderEngine Protocols

```swift
// MARK: - Rendering Protocols

/// A frame produced by the rendering pipeline
public protocol RenderFrame: Sendable {
    var texture: (any MTLTexture)? { get }
    var time: Rational { get }
    var videoParams: VideoParams { get }
}

/// Abstract renderer that can execute render jobs
public protocol Renderer: Sendable {
    func createTexture(params: VideoParams) -> (any MTLTexture)?
    func execute(job: RenderJob) async throws -> any RenderFrame
    func returnTexture(_ texture: any MTLTexture)
}

/// Compositing engine that combines multiple layers
public protocol CompositorProtocol: AVVideoCompositing {
    var renderer: any Renderer { get }
}

/// Frame cache for rendered frames
public protocol FrameCache: Sendable {
    func cachedFrame(at time: Rational, hash: UInt64) -> (any RenderFrame)?
    func store(frame: any RenderFrame, hash: UInt64) async
    func invalidate(range: TimeRange)
    func invalidateAll()
}

/// Background auto-caching controller
public protocol AutoCaching: Sendable {
    func startCaching(around time: Rational, range: TimeRange) async
    func stopCaching()
    var cachingProgress: AsyncStream<Double> { get }
}
```

### EffectsEngine Protocols

```swift
// MARK: - Effect Protocols

/// Base protocol for all processing nodes (inspired by Olive's node system)
public protocol ProcessingNode: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var category: String { get }
    var parameters: [ParameterDescriptor] { get }

    func process(input: NodeValueTable, at time: Rational) -> NodeValueTable
}

/// A video effect that processes frames
public protocol VideoEffect: ProcessingNode {
    func apply(to frame: any RenderFrame, at time: Rational,
               parameters: ParameterValues) async throws -> any RenderFrame
}

/// A transition between two clips
public protocol VideoTransition: ProcessingNode {
    func apply(from frameA: any RenderFrame, to frameB: any RenderFrame,
               progress: Double, parameters: ParameterValues) async throws -> any RenderFrame
}

/// A generator that creates frames from nothing (solid, text, etc.)
public protocol VideoGenerator: ProcessingNode {
    func generate(at time: Rational, size: CGSize,
                  parameters: ParameterValues) async throws -> any RenderFrame
}

/// An audio effect
public protocol AudioEffect: ProcessingNode {
    func process(buffer: AVAudioPCMBuffer, at time: Rational,
                 parameters: ParameterValues) throws -> AVAudioPCMBuffer
}

/// An audio transition
public protocol AudioTransition: ProcessingNode {
    func process(bufferA: AVAudioPCMBuffer, bufferB: AVAudioPCMBuffer,
                 progress: Double, parameters: ParameterValues) throws -> AVAudioPCMBuffer
}
```

### MediaManager Protocols

```swift
// MARK: - Media Management Protocols

/// Represents an imported media asset
public protocol ManagedAsset: Identifiable, Sendable {
    var id: UUID { get }
    var url: URL { get }
    var proxyURL: URL? { get }
    var thumbnailURL: URL? { get }
    var metadata: AssetMetadata { get }
    var status: AssetStatus { get }
}

/// Imports media into the project
public protocol AssetImporting: Sendable {
    func importAssets(from urls: [URL]) async throws -> [any ManagedAsset]
    func importFromPhotosLibrary(identifiers: [String]) async throws -> [any ManagedAsset]
}

/// Generates proxy files for editing performance
public protocol ProxyGenerating: Sendable {
    func generateProxy(for asset: any ManagedAsset,
                       preset: ProxyPreset) async throws -> URL
    func generateThumbnails(for asset: any ManagedAsset,
                            interval: Rational) async throws -> [CGImage]
}
```

### ViewerKit Protocols

```swift
// MARK: - Viewer Protocols

/// Transport control states
public enum TransportState: Sendable {
    case stopped
    case playing
    case paused
    case shuttling(speed: Double)
    case scrubbing
}

/// Viewer playback controller
public protocol ViewerController: Observable {
    var currentTime: Rational { get }
    var transportState: TransportState { get }
    var isPlaying: Bool { get }

    func play()
    func pause()
    func stop()
    func seek(to time: Rational) async
    func shuttle(speed: Double)
    func stepForward(frames: Int)
    func stepBackward(frames: Int)
    func setInPoint(_ time: Rational)
    func setOutPoint(_ time: Rational)
}
```

---

## 5. Plugin Architecture

### Design: Protocol + Bundle Discovery

The plugin system uses Swift's protocol-oriented design combined with macOS Bundle loading for third-party extensibility. Inspired by MLT's module registry and Swift by Sundell's plugin patterns.

### PluginKit Protocol Definitions

```swift
// Sources/PluginKit/PluginManifest.swift

/// Metadata about a plugin
public struct PluginManifest: Codable, Sendable {
    public let identifier: String          // Reverse-DNS: "com.example.blur-effect"
    public let name: String                // Human-readable name
    public let version: String             // Semantic version
    public let author: String
    public let category: PluginCategory
    public let minimumHostVersion: String  // Minimum app version required
    public let capabilities: Set<PluginCapability>

    public enum PluginCategory: String, Codable, Sendable {
        case videoEffect
        case audioEffect
        case transition
        case generator
        case codec
        case exportFormat
    }

    public enum PluginCapability: String, Codable, Sendable {
        case gpuAccelerated
        case realTimeCapable
        case supportsHDR
        case supportsMultiChannel
        case keyframeable
    }
}

/// The entry point protocol that all plugin bundles must expose
public protocol PluginBundle: AnyObject, Sendable {
    static var manifest: PluginManifest { get }

    /// Called once when the plugin is loaded
    func activate(host: any PluginHost) throws

    /// Called when the plugin is about to be unloaded
    func deactivate()

    /// Factory method -- returns the processing nodes this plugin provides
    func createNodes() -> [any ProcessingNode]
}

/// Host services provided to plugins
public protocol PluginHost: Sendable {
    func log(_ message: String, level: LogLevel)
    func requestTexture(params: VideoParams) -> (any MTLTexture)?
    func returnTexture(_ texture: any MTLTexture)
    var metalDevice: (any MTLDevice)? { get }
}
```

### Plugin Discovery and Loading

```swift
// Sources/PluginKit/PluginRegistry.swift

/// Central registry for all available processing nodes
public actor PluginRegistry {
    public static let shared = PluginRegistry()

    // Registered nodes by category
    private var videoEffects: [String: any VideoEffect.Type] = [:]
    private var audioEffects: [String: any AudioEffect.Type] = [:]
    private var transitions: [String: any VideoTransition.Type] = [:]
    private var generators: [String: any VideoGenerator.Type] = [:]
    private var codecs: [String: any CodecPlugin.Type] = [:]
    private var exportFormats: [String: any ExportFormatPlugin.Type] = [:]

    // Loaded plugin bundles
    private var loadedBundles: [String: any PluginBundle] = [:]

    /// Register a built-in effect (called at app startup)
    public func registerBuiltIn<T: VideoEffect>(_ effectType: T.Type, id: String) {
        videoEffects[id] = effectType
    }

    /// Discover and load plugins from a directory
    public func loadPlugins(from directory: URL, host: any PluginHost) async throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in contents where url.pathExtension == "plugin" {
            try await loadPlugin(at: url, host: host)
        }
    }

    private func loadPlugin(at url: URL, host: any PluginHost) async throws {
        guard let bundle = Bundle(url: url),
              bundle.load() else {
            throw PluginError.loadFailed(url)
        }

        // The plugin bundle must declare its principal class
        guard let principalClass = bundle.principalClass as? any PluginBundle.Type else {
            throw PluginError.noPrincipalClass(url)
        }

        let instance = principalClass.init()
        try instance.activate(host: host)

        let manifest = type(of: instance).manifest
        loadedBundles[manifest.identifier] = instance

        // Register all nodes from this plugin
        for node in instance.createNodes() {
            switch node {
            case let effect as any VideoEffect:
                videoEffects[manifest.identifier + "." + node.name] = type(of: effect)
            case let transition as any VideoTransition:
                transitions[manifest.identifier + "." + node.name] = type(of: transition)
            case let generator as any VideoGenerator:
                generators[manifest.identifier + "." + node.name] = type(of: generator)
            default:
                break
            }
        }
    }

    /// Get all registered effects for UI display
    public func allVideoEffects() -> [(id: String, name: String, category: String)] {
        videoEffects.map { (id: $0.key, name: String(describing: $0.value), category: "Video") }
    }

    /// Create an instance of a registered effect by ID
    public func createVideoEffect(id: String) -> (any VideoEffect)? {
        guard let effectType = videoEffects[id] else { return nil }
        return effectType.init() as? any VideoEffect
    }
}

public enum PluginError: Error {
    case loadFailed(URL)
    case noPrincipalClass(URL)
    case incompatibleVersion(String)
}
```

### Example Plugin Implementation

```swift
// ExampleBlurPlugin/BlurPlugin.swift

import PluginKit
import CoreMediaPlus
import Metal

public final class BlurPlugin: NSObject, PluginBundle, @unchecked Sendable {
    public static let manifest = PluginManifest(
        identifier: "com.swifteditor.blur",
        name: "Gaussian Blur",
        version: "1.0.0",
        author: "SwiftEditor",
        category: .videoEffect,
        minimumHostVersion: "1.0.0",
        capabilities: [.gpuAccelerated, .realTimeCapable, .keyframeable]
    )

    private var host: (any PluginHost)?

    public func activate(host: any PluginHost) throws {
        self.host = host
        host.log("Blur plugin activated", level: .info)
    }

    public func deactivate() {
        host = nil
    }

    public func createNodes() -> [any ProcessingNode] {
        [GaussianBlurEffect()]
    }
}

public final class GaussianBlurEffect: VideoEffect, @unchecked Sendable {
    public let id = UUID()
    public let name = "Gaussian Blur"
    public let category = "Blur"

    public let parameters: [ParameterDescriptor] = [
        .float(name: "radius", displayName: "Radius",
               defaultValue: 10.0, range: 0.0...100.0),
        .bool(name: "horizontal", displayName: "Horizontal", defaultValue: true),
        .bool(name: "vertical", displayName: "Vertical", defaultValue: true),
    ]

    public func process(input: NodeValueTable, at time: Rational) -> NodeValueTable {
        var output = input
        // Process using compute shader
        return output
    }

    public func apply(to frame: any RenderFrame, at time: Rational,
                      parameters: ParameterValues) async throws -> any RenderFrame {
        // Metal compute shader execution
        // Uses MPS (Metal Performance Shaders) for Gaussian blur
        fatalError("Implementation uses Metal compute pipeline")
    }
}
```

### Export Format Plugin Example

```swift
// Sources/PluginKit/ExportFormatPlugin.swift

/// Plugin protocol for custom export formats
public protocol ExportFormatPlugin: ProcessingNode {
    var fileExtension: String { get }
    var mimeType: String { get }
    var supportedCodecs: [CodecIdentifier] { get }

    func createExportSession(
        outputURL: URL,
        videoParams: VideoParams,
        audioParams: AudioParams,
        settings: ExportSettings
    ) throws -> any ExportSessionProtocol
}

/// Plugin protocol for custom codecs (via FFmpeg or custom)
public protocol CodecPlugin: ProcessingNode {
    var codecID: CodecIdentifier { get }
    var isEncoder: Bool { get }
    var isDecoder: Bool { get }

    func createDecoder(params: VideoParams) throws -> any VideoDecoder
    func createEncoder(params: VideoParams, settings: EncoderSettings) throws -> any VideoEncoder
}
```

---

## 6. State Management Strategy

### Recommendation: Custom Observable + Unidirectional Flow

For a professional NLE, neither MVVM nor TCA is ideal on its own. TCA's strict reducers add too much ceremony for real-time media operations, while vanilla MVVM lacks the discipline needed for complex interacting state. The recommended approach is a **custom unidirectional architecture** using Swift's `@Observable` macro with explicit mutation channels.

### Rationale

- **TCA** is powerful for composable UI state but adds overhead for performance-critical paths (render pipeline, playback). Its strict reducer pattern does not map well to the lambda-based undo/redo system needed for NLE editing.
- **MVVM** is simpler but lacks structure for complex cross-cutting concerns (playback + timeline + effects all reacting to the same state change).
- **Custom Observable** with Kdenlive's request pattern gives us: explicit mutation (all changes through `request*()` methods), automatic undo/redo composition, and direct `@Observable` integration with SwiftUI without conversion overhead.

### Architecture: Request-Based Observable Model

```swift
// Sources/TimelineKit/Models/TimelineModel.swift

import Observation
import CoreMediaPlus
import ProjectModel

/// The central editing model. All mutations go through request*() methods.
/// Inspired by Kdenlive's TimelineModel.
@Observable
public final class TimelineModel {
    // ── Published State ──────────────────────────────
    public private(set) var videoTracks: [VideoTrack] = []
    public private(set) var audioTracks: [AudioTrack] = []
    public private(set) var duration: Rational = .zero
    public private(set) var selection: SelectionState = .empty

    // ── Internal State ───────────────────────────────
    private var allClips: [UUID: ClipModel] = [:]
    private var allTracks: [UUID: any TrackModelProtocol] = [:]
    public let undoManager: TimelineUndoManager
    public let groupsModel: GroupsModel
    public let snapModel: SnapModel

    // ── Combine Event Bus ────────────────────────────
    // For cross-module communication without tight coupling
    public let events = TimelineEventBus()

    public init() {
        self.undoManager = TimelineUndoManager()
        self.groupsModel = GroupsModel()
        self.snapModel = SnapModel()
    }

    // ── Request Methods (Single Entry Point) ─────────

    /// Move a clip to a new position. Returns false if the move is invalid.
    @discardableResult
    public func requestClipMove(
        clipID: UUID,
        toTrackID: UUID,
        at position: Rational,
        updateLayout: Bool = true
    ) -> Bool {
        guard let clip = allClips[clipID],
              let destTrack = allTracks[toTrackID] else {
            return false
        }

        // Validate the move
        guard validateClipPlacement(clip, on: destTrack, at: position) else {
            return false
        }

        // Compose undo/redo (Kdenlive lambda pattern)
        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        let sourceTrackID = clip.trackID
        let sourcePosition = clip.startTime

        // Step 1: Remove from source track
        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: clipID, fromTrack: sourceTrackID)
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipInsert(clipID: clipID, toTrack: sourceTrackID,
                                   at: sourcePosition)
            return true
        }

        // Step 2: Insert at destination
        appendOperation(&redo) { [weak self] in
            self?.performClipInsert(clipID: clipID, toTrack: toTrackID,
                                   at: position)
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRemove(clipID: clipID, fromTrack: toTrackID)
            return true
        }

        // Execute redo
        guard redo() else {
            undo() // Rollback on failure
            return false
        }

        // Record for undo stack
        undoManager.record(undo: undo, redo: redo, description: "Move Clip")

        // Notify observers
        if updateLayout {
            recalculateDuration()
            events.send(.clipMoved(clipID: clipID, toTrack: toTrackID, at: position))
        }

        return true
    }

    /// Resize a clip by trimming an edge
    @discardableResult
    public func requestClipResize(
        clipID: UUID,
        edge: TrimEdge,
        to newTime: Rational
    ) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldStartTime = clip.startTime
        let oldSourceIn = clip.sourceIn
        let oldSourceOut = clip.sourceOut

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        switch edge {
        case .leading:
            let delta = newTime - clip.startTime
            let newSourceIn = clip.sourceIn + delta

            guard newSourceIn >= .zero,
                  newSourceIn < clip.sourceOut else { return false }

            appendOperation(&redo) { [weak self] in
                self?.performClipTrim(clipID: clipID, startTime: newTime,
                                     sourceIn: newSourceIn, sourceOut: clip.sourceOut)
                return true
            }
            prependOperation(&undo) { [weak self] in
                self?.performClipTrim(clipID: clipID, startTime: oldStartTime,
                                     sourceIn: oldSourceIn, sourceOut: oldSourceOut)
                return true
            }

        case .trailing:
            let newSourceOut = clip.sourceIn + (newTime - clip.startTime)

            guard newSourceOut > clip.sourceIn,
                  newSourceOut <= clip.sourceRef.naturalDuration else { return false }

            appendOperation(&redo) { [weak self] in
                self?.performClipTrim(clipID: clipID, startTime: clip.startTime,
                                     sourceIn: clip.sourceIn, sourceOut: newSourceOut)
                return true
            }
            prependOperation(&undo) { [weak self] in
                self?.performClipTrim(clipID: clipID, startTime: oldStartTime,
                                     sourceIn: oldSourceIn, sourceOut: oldSourceOut)
                return true
            }
        }

        guard redo() else { undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Trim Clip")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    /// Split a clip at the given time
    @discardableResult
    public func requestClipSplit(clipID: UUID, at time: Rational) -> Bool {
        guard let clip = allClips[clipID],
              time > clip.startTime,
              time < clip.startTime + clip.duration else {
            return false
        }

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        let newClipID = UUID()
        let splitSourceTime = clip.sourceIn + (time - clip.startTime)

        appendOperation(&redo) { [weak self] in
            self?.performClipSplit(clipID: clipID, newClipID: newClipID,
                                  at: time, splitSource: splitSourceTime)
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipUnsplit(originalID: clipID, splitID: newClipID)
            return true
        }

        guard redo() else { undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Split Clip")
        events.send(.clipSplit(clipID: clipID, newClipID: newClipID, at: time))
        return true
    }

    // ── Private Mutation Methods ─────────────────────

    private func performClipRemove(clipID: UUID, fromTrack trackID: UUID) {
        // Direct state mutation -- only called from request methods
    }

    private func performClipInsert(clipID: UUID, toTrack trackID: UUID, at time: Rational) {
        // Direct state mutation
    }

    private func performClipTrim(clipID: UUID, startTime: Rational,
                                 sourceIn: Rational, sourceOut: Rational) {
        // Direct state mutation
    }

    private func performClipSplit(clipID: UUID, newClipID: UUID,
                                  at time: Rational, splitSource: Rational) {
        // Direct state mutation
    }

    private func performClipUnsplit(originalID: UUID, splitID: UUID) {
        // Direct state mutation
    }

    private func recalculateDuration() {
        // Recompute timeline duration from all track endpoints
    }

    private func validateClipPlacement(_ clip: ClipModel, on track: any TrackModelProtocol,
                                       at time: Rational) -> Bool {
        // Check for overlaps, locked tracks, etc.
        return true
    }
}
```

### State Flow Diagram

```
User Action (UI)
       │
       ▼
┌──────────────────────┐
│ TimelineModel        │
│ .requestClipMove()   │  ← Single entry point
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Compose undo/redo    │  ← Lambda composition (Kdenlive pattern)
│ Validate mutation    │
│ Execute redo()       │
└──────────┬───────────┘
           │
     ┌─────┴──────┐
     │             │
     ▼             ▼
┌─────────┐  ┌──────────────┐
│ @Observ │  │ EventBus     │
│ -able   │  │ .clipMoved() │
│ state   │  └──────┬───────┘
│ update  │         │
└────┬────┘    ┌────▼─────────────┐
     │         │ RenderEngine     │
     ▼         │ invalidates cache│
  SwiftUI      └─────────────────┘
  re-renders
  timeline
```

---

## 7. Command Pattern for Undo/Redo

### Lambda-Based Undo System (Kdenlive-Inspired)

The undo system uses closure composition rather than command objects. Each editing operation constructs forward (redo) and backward (undo) closures. Operations are composed by chaining closures, and if any step in a composite operation fails, the accumulated undo closure rolls everything back.

```swift
// Sources/TimelineKit/Editing/UndoSystem.swift

/// A closure that performs an operation and returns success/failure
public typealias UndoAction = () -> Bool

/// Append an operation to a redo chain
public func appendOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = {
        guard previous() else { return false }
        return operation()
    }
}

/// Prepend an operation to an undo chain (undo runs in reverse order)
public func prependOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = {
        guard operation() else { return false }
        return previous()
    }
}

/// An entry in the undo stack
public struct UndoEntry {
    let undo: UndoAction
    let redo: UndoAction
    let description: String
    let timestamp: Date
}

/// Manages the undo/redo stack
@Observable
public final class TimelineUndoManager {
    public private(set) var undoStack: [UndoEntry] = []
    public private(set) var redoStack: [UndoEntry] = []
    public private(set) var canUndo: Bool = false
    public private(set) var canRedo: Bool = false

    /// Maximum number of undo entries
    public var maxUndoLevels: Int = 200

    /// Record a completed operation for potential undo
    public func record(undo: @escaping UndoAction, redo: @escaping UndoAction,
                       description: String) {
        let entry = UndoEntry(undo: undo, redo: redo,
                              description: description, timestamp: .now)
        undoStack.append(entry)
        redoStack.removeAll() // New action invalidates redo history

        // Trim if over limit
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }

        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    /// Undo the most recent operation
    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        guard entry.undo() else {
            // Failed to undo -- push back and report error
            undoStack.append(entry)
            return false
        }
        redoStack.append(entry)
        canUndo = !undoStack.isEmpty
        canRedo = true
        return true
    }

    /// Redo the most recently undone operation
    @discardableResult
    public func redo() -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        guard entry.redo() else {
            redoStack.append(entry)
            return false
        }
        undoStack.append(entry)
        canUndo = true
        canRedo = !redoStack.isEmpty
        return true
    }

    /// Begin a macro (group multiple operations into one undo step)
    public func beginMacro(_ description: String) -> UndoMacro {
        UndoMacro(manager: self, description: description)
    }
}

/// Groups multiple operations into a single undo step
public final class UndoMacro {
    private let manager: TimelineUndoManager
    private let description: String
    private var undo: UndoAction = { true }
    private var redo: UndoAction = { true }
    private var committed = false

    init(manager: TimelineUndoManager, description: String) {
        self.manager = manager
        self.description = description
    }

    /// Add an operation to this macro
    public func addOperation(undo undoOp: @escaping UndoAction,
                             redo redoOp: @escaping UndoAction) {
        appendOperation(&redo, redoOp)
        prependOperation(&undo, undoOp)
    }

    /// Commit the macro to the undo stack
    public func commit() {
        guard !committed else { return }
        committed = true
        manager.record(undo: undo, redo: redo, description: description)
    }

    deinit {
        if !committed {
            // Auto-rollback if the macro was never committed
            _ = undo()
        }
    }
}
```

### Integration with Apple's UndoManager

```swift
// Bridge to NSUndoManager for macOS menu integration

extension TimelineUndoManager {
    /// Bridge to NSUndoManager for Edit menu integration
    public func bridgeToNSUndoManager(_ nsUndoManager: UndoManager) {
        // Observe our undo stack changes and sync to NSUndoManager
        // This enables Cmd+Z and Edit > Undo menu items
    }
}
```

---

## 8. Event-Driven Architecture with Combine

### Timeline Event Bus

Combine publishers provide loose coupling between modules. The timeline publishes events, and any module (render engine, viewer, UI) can subscribe.

```swift
// Sources/TimelineKit/Models/TimelineEventBus.swift

import Combine
import CoreMediaPlus

/// Events emitted by the timeline model
public enum TimelineEvent: Sendable {
    // Clip events
    case clipAdded(clipID: UUID, trackID: UUID)
    case clipRemoved(clipID: UUID, trackID: UUID)
    case clipMoved(clipID: UUID, toTrack: UUID, at: Rational)
    case clipResized(clipID: UUID)
    case clipSplit(clipID: UUID, newClipID: UUID, at: Rational)

    // Track events
    case trackAdded(trackID: UUID, type: TrackType, at: Int)
    case trackRemoved(trackID: UUID)
    case trackReordered(trackID: UUID, from: Int, to: Int)
    case trackMutedChanged(trackID: UUID, muted: Bool)

    // Effect events
    case effectAdded(clipID: UUID, effectID: UUID)
    case effectRemoved(clipID: UUID, effectID: UUID)
    case effectParameterChanged(clipID: UUID, effectID: UUID, parameter: String)

    // Playhead events
    case playheadMoved(time: Rational)
    case selectionChanged(selection: SelectionState)

    // Undo/redo
    case undoPerformed(description: String)
    case redoPerformed(description: String)
}

/// Central event bus for timeline-related events
public final class TimelineEventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<TimelineEvent, Never>()

    public var publisher: AnyPublisher<TimelineEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public func send(_ event: TimelineEvent) {
        subject.send(event)
    }

    // Convenience filtered publishers
    public var clipEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter { event in
            switch event {
            case .clipAdded, .clipRemoved, .clipMoved, .clipResized, .clipSplit:
                return true
            default:
                return false
            }
        }.eraseToAnyPublisher()
    }

    public var effectEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter { event in
            switch event {
            case .effectAdded, .effectRemoved, .effectParameterChanged:
                return true
            default:
                return false
            }
        }.eraseToAnyPublisher()
    }
}
```

### RenderEngine Subscribing to Timeline Events

```swift
// Sources/RenderEngine/Cache/AutoCacher.swift

import Combine
import CoreMediaPlus

/// Subscribes to timeline events to manage cache invalidation
public final class AutoCacher: @unchecked Sendable {
    private var cancellables = Set<AnyCancellable>()
    private let frameCache: any FrameCache
    private let renderer: any Renderer

    public init(frameCache: any FrameCache, renderer: any Renderer) {
        self.frameCache = frameCache
        self.renderer = renderer
    }

    /// Connect to a timeline's event bus
    public func observe(events: TimelineEventBus) {
        // Invalidate cache when clips change
        events.clipEvents
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.global())
            .sink { [weak self] event in
                Task { await self?.handleClipEvent(event) }
            }
            .store(in: &cancellables)

        // Invalidate effect cache when parameters change
        events.effectEvents
            .sink { [weak self] event in
                Task { await self?.handleEffectEvent(event) }
            }
            .store(in: &cancellables)
    }

    private func handleClipEvent(_ event: TimelineEvent) async {
        switch event {
        case .clipMoved(_, _, let time):
            // Invalidate cache around the affected area
            let range = TimeRange(start: time - Rational(2, 1),
                                  duration: Rational(4, 1))
            await frameCache.invalidate(range: range)

        case .clipRemoved(_, _):
            await frameCache.invalidateAll()

        default:
            break
        }
    }

    private func handleEffectEvent(_ event: TimelineEvent) async {
        // Effect parameter changes only invalidate specific ranges
    }
}
```

### Playback Synchronization

```swift
// Sources/ViewerKit/TransportController.swift

import Combine
import AVFoundation
import CoreMediaPlus

/// Coordinates playback with timeline state
@Observable
public final class TransportController: ViewerController {
    public private(set) var currentTime: Rational = .zero
    public private(set) var transportState: TransportState = .stopped

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    // Combine subjects for internal coordination
    private let timeSubject = CurrentValueSubject<Rational, Never>(.zero)
    private let stateSubject = CurrentValueSubject<TransportState, Never>(.stopped)

    /// Current time as a Combine publisher (for other modules to observe)
    public var timePublisher: AnyPublisher<Rational, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    public var isPlaying: Bool {
        if case .playing = transportState { return true }
        return false
    }

    public func play() {
        player?.play()
        transportState = .playing
        stateSubject.send(.playing)
    }

    public func pause() {
        player?.pause()
        transportState = .paused
        stateSubject.send(.paused)
    }

    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        currentTime = .zero
        transportState = .stopped
        stateSubject.send(.stopped)
        timeSubject.send(.zero)
    }

    public func seek(to time: Rational) async {
        let cmTime = time.cmTime
        await player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        timeSubject.send(time)
    }

    public func shuttle(speed: Double) {
        player?.rate = Float(speed)
        transportState = .shuttling(speed: speed)
        stateSubject.send(.shuttling(speed: speed))
    }

    public func stepForward(frames: Int = 1) {
        // Step by frame duration
    }

    public func stepBackward(frames: Int = 1) {
        // Step backward by frame duration
    }

    public func setInPoint(_ time: Rational) {
        // Set in point for the current sequence
    }

    public func setOutPoint(_ time: Rational) {
        // Set out point for the current sequence
    }

    /// Setup periodic time observation
    func setupTimeObserver(interval: CMTime = CMTime(value: 1, timescale: 60)) {
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            guard let self else { return }
            let time = Rational(cmTime)
            self.currentTime = time
            self.timeSubject.send(time)
        }
    }
}
```

---

## 9. Data Flow for Real-Time Preview

### Architecture Overview

The real-time preview pipeline combines AVFoundation's pull-based compositing with Metal rendering. The architecture has two parallel paths: a fast preview path for real-time playback, and a high-quality path for export.

```
┌─────────────────────────────────────────────────────────────┐
│                     Real-Time Preview Path                   │
│                                                             │
│  AVPlayer ──► AVVideoComposition ──► MetalCompositor        │
│                                          │                   │
│              ┌───────────────────────────┤                   │
│              │                           │                   │
│              ▼                           ▼                   │
│        FrameHashCache             TexturePool                │
│        (disk-backed)          (reusable MTLTextures)         │
│              │                           │                   │
│              ▼                           ▼                   │
│         Cache Hit?  ──yes──►  Return cached texture          │
│              │no                                             │
│              ▼                                               │
│        Build RenderPlan                                      │
│        (traverse node graph)                                 │
│              │                                               │
│              ▼                                               │
│        Execute RenderJobs                                    │
│        (Metal compute/render)                                │
│              │                                               │
│              ▼                                               │
│        Composited Frame ──► CAMetalLayer ──► Display         │
└─────────────────────────────────────────────────────────────┘
```

### MetalCompositor Implementation

```swift
// Sources/RenderEngine/Compositor/MetalCompositor.swift

import AVFoundation
import Metal
import CoreMediaPlus
import EffectsEngine

/// Custom AVVideoCompositing implementation using Metal
public final class MetalCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    // ── AVVideoCompositing Requirements ──────────────

    public var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String:
            [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]]  // HDR support
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    public var supportsHDRSourceFrames: Bool { true }
    public var supportsWideColorSourceFrames: Bool { true }

    // ── Internal State ──────────────────────────────

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let texturePool: TexturePool
    private let frameCache: FrameHashCache
    private let renderQueue = DispatchQueue(label: "com.swifteditor.render",
                                            qos: .userInteractive)
    private var isCancelled = false

    public init(device: any MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.texturePool = TexturePool(device: device)
        self.frameCache = FrameHashCache()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache!

        super.init()
    }

    // ── Frame Rendering ─────────────────────────────

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [self] in
            guard !isCancelled else {
                request.finishCancelledRequest()
                return
            }

            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction
                        as? NLECompositionInstruction else {
                    request.finish(with: NSError(domain: "MetalCompositor",
                                                  code: -1))
                    return
                }

                do {
                    let compositionTime = Rational(request.compositionTime)

                    // Check frame cache first
                    let hash = instruction.contentHash(at: compositionTime)
                    if let cached = frameCache.cachedFrame(at: compositionTime,
                                                           hash: hash) {
                        if let pixelBuffer = cached.toPixelBuffer(
                            pool: request.renderContext.pixelBufferPool) {
                            request.finish(withComposedVideoFrame: pixelBuffer)
                            return
                        }
                    }

                    // Build render plan from instruction
                    let plan = try buildRenderPlan(
                        instruction: instruction,
                        request: request,
                        at: compositionTime
                    )

                    // Execute the plan on Metal
                    let result = try executePlan(plan)

                    // Cache the result
                    Task {
                        await frameCache.store(frame: result, hash: hash)
                    }

                    // Convert to pixel buffer and finish
                    if let pixelBuffer = result.toPixelBuffer(
                        pool: request.renderContext.pixelBufferPool) {
                        request.finish(withComposedVideoFrame: pixelBuffer)
                    } else {
                        request.finish(with: NSError(domain: "MetalCompositor",
                                                      code: -2))
                    }
                } catch {
                    request.finish(with: error as NSError)
                }
            }
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        isCancelled = true
        renderQueue.async { [self] in
            isCancelled = false
        }
    }

    public func renderContextChanged(
        _ newRenderContext: AVVideoCompositionRenderContext
    ) {
        texturePool.resize(for: VideoParams(
            width: Int(newRenderContext.size.width),
            height: Int(newRenderContext.size.height)
        ))
    }

    // ── Render Plan Construction ─────────────────────
    // Two-phase rendering (inspired by Olive):
    // Phase 1: Traverse the node graph and collect render jobs
    // Phase 2: Execute jobs on the GPU

    private func buildRenderPlan(
        instruction: NLECompositionInstruction,
        request: AVAsynchronousVideoCompositionRequest,
        at time: Rational
    ) throws -> RenderPlan {
        var plan = RenderPlan(time: time, renderSize: request.renderContext.size)

        // For each active layer in the instruction
        for layer in instruction.layers {
            // Get source frame from AVFoundation
            guard let sourceBuffer = request.sourceFrame(
                byTrackID: layer.trackID) else {
                continue
            }

            // Convert CVPixelBuffer to MTLTexture (zero-copy via IOSurface)
            let sourceTexture = try createTexture(from: sourceBuffer)

            // Add decode job
            plan.addJob(.decodeSource(
                trackID: layer.trackID,
                texture: sourceTexture
            ))

            // Add effect jobs for this layer
            for effect in layer.effectStack.effects {
                plan.addJob(.applyEffect(
                    effect: effect,
                    parameters: effect.currentValues(at: time)
                ))
            }

            // Add transform job (position, scale, rotation, opacity)
            if let transform = layer.transform {
                plan.addJob(.applyTransform(transform: transform.value(at: time)))
            }
        }

        // Add transition job if this is a transition region
        if let transition = instruction.transition {
            plan.addJob(.applyTransition(
                transition: transition,
                progress: instruction.transitionProgress(at: time)
            ))
        }

        // Add final composite job
        plan.addJob(.composite(
            blendMode: .normal,
            layers: plan.layerCount
        ))

        return plan
    }

    private func executePlan(_ plan: RenderPlan) throws -> MetalRenderFrame {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RenderError.commandBufferCreationFailed
        }

        var outputTexture = texturePool.checkout(params: plan.outputParams)

        for job in plan.jobs {
            switch job {
            case .decodeSource(_, let texture):
                // YUV to RGB conversion if needed
                break
            case .applyEffect(let effect, let params):
                // Execute effect shader
                break
            case .applyTransform(let transform):
                // Apply affine transform
                break
            case .applyTransition(let transition, let progress):
                // Execute transition shader
                break
            case .composite(let blendMode, _):
                // Final layer compositing
                break
            }
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return MetalRenderFrame(texture: outputTexture, time: plan.time,
                                videoParams: plan.outputParams)
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer) throws -> any MTLTexture {
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else {
            throw RenderError.textureCreationFailed
        }

        return texture
    }
}
```

### Render Job and Plan Types

```swift
// Sources/RenderEngine/Pipeline/RenderJob.swift

import Metal
import CoreMediaPlus

/// A single unit of work in the render pipeline
/// Inspired by Olive's job-based deferred rendering
public enum RenderJob: Sendable {
    case decodeSource(trackID: CMPersistentTrackID, texture: any MTLTexture)
    case applyEffect(effect: any VideoEffect, parameters: ParameterValues)
    case applyTransform(transform: AffineTransform)
    case applyTransition(transition: any VideoTransition, progress: Double)
    case composite(blendMode: BlendMode, layers: Int)
    case colorTransform(source: ColorSpace, destination: ColorSpace)
}

/// A sequence of render jobs that produces one frame
public struct RenderPlan: Sendable {
    public let time: Rational
    public let renderSize: CGSize
    public private(set) var jobs: [RenderJob] = []
    public private(set) var layerCount: Int = 0

    public var outputParams: VideoParams {
        VideoParams(width: Int(renderSize.width), height: Int(renderSize.height))
    }

    public mutating func addJob(_ job: RenderJob) {
        jobs.append(job)
        if case .decodeSource = job {
            layerCount += 1
        }
    }
}
```

---

## 10. Project Document Model

### Versioned Codable Design

The project file format uses a versioned Codable schema, enabling forward migration of older project files. Inspired by the VersionedCodable pattern and SwiftData's VersionedSchema.

```swift
// Sources/ProjectModel/Project.swift

import Foundation
import CoreMediaPlus

/// The top-level project document
public struct Project: Codable, Sendable {
    public static let currentVersion = 2

    public var version: Int = Project.currentVersion
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var settings: ProjectSettings
    public var sequences: [Sequence]
    public var bin: MediaBinModel
    public var metadata: ProjectMetadata

    public init(name: String, settings: ProjectSettings = .defaultHD) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.modifiedAt = .now
        self.settings = settings
        self.sequences = [Sequence(name: "Sequence 1", settings: settings)]
        self.bin = MediaBinModel()
        self.metadata = ProjectMetadata()
    }
}

/// Project-wide settings
public struct ProjectSettings: Codable, Sendable, Equatable {
    public var videoParams: VideoParams
    public var audioParams: AudioParams
    public var colorSpace: ColorSpace
    public var frameRate: Rational
    public var fieldOrder: FieldOrder

    public static let defaultHD = ProjectSettings(
        videoParams: VideoParams(width: 1920, height: 1080),
        audioParams: AudioParams(sampleRate: 48000, channelCount: 2),
        colorSpace: .rec709,
        frameRate: Rational(24, 1),
        fieldOrder: .progressive
    )

    public static let default4K = ProjectSettings(
        videoParams: VideoParams(width: 3840, height: 2160),
        audioParams: AudioParams(sampleRate: 48000, channelCount: 2),
        colorSpace: .rec2020,
        frameRate: Rational(24, 1),
        fieldOrder: .progressive
    )

    public enum FieldOrder: String, Codable, Sendable {
        case progressive
        case upperFirst
        case lowerFirst
    }
}

/// A sequence (timeline) within the project
public struct Sequence: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: ProjectSettings  // Can override project settings
    public var videoTracks: [TrackData]
    public var audioTracks: [TrackData]
    public var markers: [Marker]
    public var inPoint: Rational?
    public var outPoint: Rational?

    public init(name: String, settings: ProjectSettings) {
        self.id = UUID()
        self.name = name
        self.settings = settings
        self.videoTracks = [TrackData(name: "V1", type: .video)]
        self.audioTracks = [TrackData(name: "A1", type: .audio)]
        self.markers = []
    }
}

/// Serializable track data
public struct TrackData: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var type: TrackType
    public var clips: [ClipData]
    public var isMuted: Bool
    public var isLocked: Bool
    public var height: Double  // UI track height

    public init(name: String, type: TrackType) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.clips = []
        self.isMuted = false
        self.isLocked = false
        self.height = 60.0
    }
}

/// Serializable clip data
public struct ClipData: Codable, Identifiable, Sendable {
    public var id: UUID
    public var sourceAssetID: UUID    // Reference to MediaBin asset
    public var startTime: Rational    // Position on timeline
    public var sourceIn: Rational     // Source media in point
    public var sourceOut: Rational    // Source media out point
    public var speed: Double
    public var isEnabled: Bool
    public var effects: [EffectData]
    public var audioVolume: Double
    public var videoPan: CGPoint      // Position offset
    public var videoScale: CGSize     // Scale factor
    public var videoRotation: Double  // Rotation in degrees
    public var videoOpacity: Double
}

/// Serializable effect data
public struct EffectData: Codable, Identifiable, Sendable {
    public var id: UUID
    public var pluginID: String           // Plugin identifier
    public var isEnabled: Bool
    public var parameters: [String: ParameterValue]
    public var keyframes: [String: [KeyframeData]]
}

/// Serializable keyframe data
public struct KeyframeData: Codable, Sendable {
    public var time: Rational
    public var value: ParameterValue
    public var interpolation: InterpolationType
    public var bezierIn: CGPoint?
    public var bezierOut: CGPoint?

    public enum InterpolationType: String, Codable, Sendable {
        case linear
        case hold
        case bezier
    }
}

/// Type-safe parameter values
public enum ParameterValue: Codable, Sendable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case string(String)
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case point(x: Double, y: Double)
    case size(width: Double, height: Double)
    case rect(x: Double, y: Double, width: Double, height: Double)
}

/// Marker on the timeline
public struct Marker: Codable, Identifiable, Sendable {
    public var id: UUID
    public var time: Rational
    public var name: String
    public var color: MarkerColor
    public var comment: String

    public enum MarkerColor: String, Codable, Sendable {
        case red, orange, yellow, green, blue, purple, pink, white
    }
}

/// Media bin structure
public struct MediaBinModel: Codable, Sendable {
    public var id: UUID = UUID()
    public var name: String = "Root"
    public var items: [BinItemData] = []
    public var subfolders: [MediaBinModel] = []
}

/// Reference to a media asset in the bin
public struct BinItemData: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var relativePath: String  // Relative to project folder
    public var originalPath: String  // Original import location
    public var proxyPath: String?    // Proxy file relative path
    public var duration: Rational
    public var videoParams: VideoParams?
    public var audioParams: AudioParams?
    public var importDate: Date
}

/// Additional project metadata
public struct ProjectMetadata: Codable, Sendable {
    public var description: String = ""
    public var tags: [String] = []
    public var author: String = ""
    public var copyright: String = ""
    public var customFields: [String: String] = [:]
}
```

### Schema Versioning and Migration

```swift
// Sources/ProjectModel/Versioning/ProjectMigration.swift

import Foundation

/// V1 project format (initial release)
public struct ProjectV1: Codable {
    public var version: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var settings: ProjectSettingsV1
    public var sequences: [SequenceV1]
    // V1 did not have a media bin -- paths were inline in clips
}

public struct ProjectSettingsV1: Codable {
    public var width: Int
    public var height: Int
    public var frameRate: Double  // V1 used Double, not Rational
    public var sampleRate: Int
}

public struct SequenceV1: Codable {
    public var id: UUID
    public var name: String
    public var tracks: [TrackDataV1]
}

public struct TrackDataV1: Codable {
    public var id: UUID
    public var clips: [ClipDataV1]
}

public struct ClipDataV1: Codable {
    public var id: UUID
    public var filePath: String  // V1 used absolute paths
    public var startTime: Double
    public var duration: Double
    public var sourceOffset: Double
}

/// Migrate from V1 to V2 (current)
public enum ProjectMigration {

    /// Detect version and migrate to current
    public static func migrate(from data: Data) throws -> Project {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try current version first
        if let project = try? decoder.decode(Project.self, from: data),
           project.version == Project.currentVersion {
            return project
        }

        // Try V1
        if let v1 = try? decoder.decode(ProjectV1.self, from: data) {
            return migrateV1toV2(v1)
        }

        throw ProjectError.unsupportedVersion
    }

    private static func migrateV1toV2(_ v1: ProjectV1) -> Project {
        // Convert V1 format to current format
        let settings = ProjectSettings(
            videoParams: VideoParams(width: v1.settings.width,
                                     height: v1.settings.height),
            audioParams: AudioParams(sampleRate: v1.settings.sampleRate,
                                     channelCount: 2),
            colorSpace: .rec709,
            frameRate: Rational(Int64(v1.settings.frameRate * 1000), 1000),
            fieldOrder: .progressive
        )

        var project = Project(name: v1.name, settings: settings)
        project.id = v1.id
        project.createdAt = v1.createdAt

        // Migrate sequences, extracting file paths to media bin
        for seqV1 in v1.sequences {
            // Convert tracks, clips, and create bin items for referenced files
            // ... migration logic
        }

        return project
    }
}

public enum ProjectError: Error {
    case unsupportedVersion
    case corruptedData
    case assetNotFound(UUID)
}
```

### Project File I/O

```swift
// Sources/ProjectModel/Serialization/ProjectEncoder.swift

import Foundation

/// Encodes and decodes project files
public struct ProjectFileManager {

    /// File extension for project files
    public static let fileExtension = "nleproj"

    /// Save project to a file package (directory bundle)
    public static func save(_ project: Project, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(project)

        // Project file is a package (directory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        // Write project JSON
        let projectFileURL = url.appendingPathComponent("project.json")
        try data.write(to: projectFileURL)

        // Autosave backup
        let backupURL = url.appendingPathComponent("project.backup.json")
        try data.write(to: backupURL)
    }

    /// Load project from a file package
    public static func load(from url: URL) throws -> Project {
        let projectFileURL = url.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectFileURL)
        return try ProjectMigration.migrate(from: data)
    }

    /// Autosave to a temporary location
    public static func autosave(_ project: Project, projectURL: URL) throws {
        let autosaveURL = projectURL.appendingPathComponent("autosave.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: autosaveURL, options: .atomic)
    }
}
```

---

## 11. Framework API Design

### Design Principles for Independent Module Use

Each module is designed to work independently. A developer should be able to use `RenderEngine` for compositing without importing `TimelineKit`, or use `MediaManager` for asset management in a non-NLE app.

### CoreMedia+ Public API

```swift
// Sources/CoreMediaPlus/Rational.swift

import CoreMedia

/// Exact rational time representation, wrapping CMTime with safer arithmetic
/// Inspired by Olive's rational time system
public struct Rational: Sendable, Hashable, Comparable {
    public let numerator: Int64
    public let denominator: Int64

    public static let zero = Rational(0, 1)
    public static let invalid = Rational(0, 0)

    public init(_ numerator: Int64, _ denominator: Int64) {
        precondition(denominator != 0 || (numerator == 0 && denominator == 0),
                     "Denominator must not be zero for valid rationals")
        // Reduce to lowest terms
        if denominator == 0 {
            self.numerator = 0
            self.denominator = 0
        } else {
            let g = Self.gcd(abs(numerator), abs(denominator))
            let sign: Int64 = denominator < 0 ? -1 : 1
            self.numerator = sign * numerator / g
            self.denominator = sign * denominator / g
        }
    }

    /// Initialize from CMTime
    public init(_ cmTime: CMTime) {
        self.init(cmTime.value, Int64(cmTime.timescale))
    }

    /// Convert to CMTime
    public var cmTime: CMTime {
        CMTime(value: numerator, timescale: CMTimeScale(denominator))
    }

    /// Convert to seconds (Double)
    public var seconds: Double {
        guard denominator != 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    /// Convert to frame number at the given frame rate
    public func frameNumber(at frameRate: Rational) -> Int64 {
        let product = self * frameRate
        return product.numerator / product.denominator
    }

    // ── Arithmetic ──────────────────────────────────

    public static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    public static func / (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        b == 0 ? a : gcd(b, a % b)
    }
}

extension Rational: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let num = try container.decode(Int64.self)
        let den = try container.decode(Int64.self)
        self.init(num, den)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(numerator)
        try container.encode(denominator)
    }
}
```

```swift
// Sources/CoreMediaPlus/TimeRange.swift

/// A range of time on the timeline
public struct TimeRange: Sendable, Hashable, Codable {
    public let start: Rational
    public let duration: Rational

    public var end: Rational { start + duration }

    public init(start: Rational, duration: Rational) {
        self.start = start
        self.duration = duration
    }

    public init(start: Rational, end: Rational) {
        self.start = start
        self.duration = end - start
    }

    /// Check if this range contains a time point
    public func contains(_ time: Rational) -> Bool {
        time >= start && time < end
    }

    /// Check if this range overlaps with another
    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    /// Return the intersection of two ranges, or nil if no overlap
    public func intersection(_ other: TimeRange) -> TimeRange? {
        let overlapStart = max(start, other.start)
        let overlapEnd = min(end, other.end)
        guard overlapStart < overlapEnd else { return nil }
        return TimeRange(start: overlapStart, end: overlapEnd)
    }

    /// Return the union of two ranges
    public func union(_ other: TimeRange) -> TimeRange {
        let unionStart = min(start, other.start)
        let unionEnd = max(end, other.end)
        return TimeRange(start: unionStart, end: unionEnd)
    }
}
```

```swift
// Sources/CoreMediaPlus/VideoParams.swift

/// Video format parameters
public struct VideoParams: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var pixelFormat: PixelFormat
    public var colorSpace: ColorSpace

    public init(width: Int, height: Int,
                pixelFormat: PixelFormat = .bgra8Unorm,
                colorSpace: ColorSpace = .rec709) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.colorSpace = colorSpace
    }

    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    public enum PixelFormat: String, Codable, Sendable {
        case bgra8Unorm       // Standard 8-bit
        case rgba16Float      // HDR 16-bit float
        case bgr10a2Unorm     // 10-bit HDR
        case yuv420BiPlanar8  // Native decode format
        case yuv420BiPlanar10 // 10-bit native decode
    }
}

/// Audio format parameters
public struct AudioParams: Codable, Sendable, Hashable {
    public var sampleRate: Int
    public var channelCount: Int
    public var bitDepth: Int

    public init(sampleRate: Int = 48000, channelCount: Int = 2, bitDepth: Int = 32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
    }
}

/// Color space identifiers
public enum ColorSpace: String, Codable, Sendable {
    case sRGB
    case rec709
    case rec2020
    case p3
    case acescg   // ACES CG (scene-referred linear)
    case acesCCT  // ACES CCT (log encoding)
    case sLog3    // Sony S-Log3
    case logC     // ARRI LogC
    case vLog     // Panasonic V-Log
}
```

### TrackType and Supporting Types

```swift
// Sources/CoreMediaPlus/MediaType.swift

/// Track type
public enum TrackType: String, Codable, Sendable {
    case video
    case audio
    case subtitle
}

/// Which edge of a clip is being trimmed
public enum TrimEdge: Sendable {
    case leading   // Left/in edge
    case trailing  // Right/out edge
}

/// Blend modes for compositing
public enum BlendMode: String, Codable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    case difference
    case exclusion
    case colorDodge
    case colorBurn
}

/// Selection state for the timeline
public struct SelectionState: Sendable {
    public var selectedClipIDs: Set<UUID>
    public var selectedTrackIDs: Set<UUID>
    public var selectedRange: TimeRange?

    public static let empty = SelectionState(
        selectedClipIDs: [],
        selectedTrackIDs: [],
        selectedRange: nil
    )

    public var isEmpty: Bool {
        selectedClipIDs.isEmpty && selectedTrackIDs.isEmpty && selectedRange == nil
    }
}
```

---

## 12. Concurrency Architecture

### Actor-Based Isolation

The NLE uses Swift's structured concurrency with actors for thread safety. Critical subsystems are isolated into actors to prevent data races without manual locking.

```swift
// Sources/RenderEngine/Cache/TexturePool.swift

import Metal
import CoreMediaPlus

/// Thread-safe texture pool using actor isolation
/// Reuses MTLTextures to reduce allocation overhead (Olive pattern)
public actor TexturePool {
    private let device: any MTLDevice
    private var available: [TextureKey: [any MTLTexture]] = [:]
    private var inUse: Set<ObjectIdentifier> = []
    private var maxPoolSize: Int = 32

    struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }

    public init(device: any MTLDevice) {
        self.device = device
    }

    /// Check out a texture from the pool (or create a new one)
    public func checkout(params: VideoParams) -> any MTLTexture {
        let key = TextureKey(
            width: params.width,
            height: params.height,
            pixelFormat: params.pixelFormat.metalFormat
        )

        if var textures = available[key], let texture = textures.popLast() {
            available[key] = textures
            inUse.insert(ObjectIdentifier(texture))
            return texture
        }

        // Create new texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: key.pixelFormat,
            width: key.width,
            height: key.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private

        let texture = device.makeTexture(descriptor: descriptor)!
        inUse.insert(ObjectIdentifier(texture))
        return texture
    }

    /// Return a texture to the pool
    public func returnTexture(_ texture: any MTLTexture) {
        inUse.remove(ObjectIdentifier(texture))

        let key = TextureKey(
            width: texture.width,
            height: texture.height,
            pixelFormat: texture.pixelFormat
        )

        var textures = available[key] ?? []
        if textures.count < maxPoolSize {
            textures.append(texture)
            available[key] = textures
        }
        // Otherwise let the texture be deallocated
    }

    /// Resize pool for a new render context
    public func resize(for params: VideoParams) {
        // Keep textures matching the new size, release others
        let key = TextureKey(
            width: params.width,
            height: params.height,
            pixelFormat: params.pixelFormat.metalFormat
        )

        var newAvailable: [TextureKey: [any MTLTexture]] = [:]
        if let matching = available[key] {
            newAvailable[key] = matching
        }
        available = newAvailable
    }
}

extension VideoParams.PixelFormat {
    var metalFormat: MTLPixelFormat {
        switch self {
        case .bgra8Unorm: return .bgra8Unorm
        case .rgba16Float: return .rgba16Float
        case .bgr10a2Unorm: return .bgr10a2Unorm
        case .yuv420BiPlanar8: return .r8Unorm
        case .yuv420BiPlanar10: return .r16Unorm
        }
    }
}
```

### Background Rendering with Task Groups

```swift
// Sources/RenderEngine/Cache/BackgroundRenderer.swift

import CoreMediaPlus

/// Background rendering for auto-caching (Olive PreviewAutoCacher pattern)
/// Uses structured concurrency for safe parallel rendering
public actor BackgroundRenderer {
    private let renderer: any Renderer
    private let frameCache: any FrameCache
    private var currentTask: Task<Void, Never>?
    private var isCancelled = false

    public init(renderer: any Renderer, frameCache: any FrameCache) {
        self.renderer = renderer
        self.frameCache = frameCache
    }

    /// Cache frames in a range around the playhead
    public func cacheRange(_ range: TimeRange, frameRate: Rational,
                           planBuilder: @Sendable (Rational) async throws -> RenderPlan) {
        // Cancel any existing caching task
        currentTask?.cancel()
        isCancelled = false

        currentTask = Task { [weak self] in
            guard let self else { return }

            // Calculate frame times in the range
            let frameDuration = Rational(1, 1) / frameRate
            var time = range.start
            var frameTimes: [Rational] = []

            while time < range.end {
                frameTimes.append(time)
                time = time + frameDuration
            }

            // Render frames in parallel using task group
            // Limit concurrency to avoid GPU contention
            await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = 4
                var inFlight = 0

                for frameTime in frameTimes {
                    if Task.isCancelled { break }

                    if inFlight >= maxConcurrent {
                        await group.next()
                        inFlight -= 1
                    }

                    group.addTask {
                        do {
                            let plan = try await planBuilder(frameTime)
                            let frame = try await self.renderer.execute(job: plan.jobs.first!)
                            let hash = UInt64(frameTime.hashValue)
                            await self.frameCache.store(frame: frame, hash: hash)
                        } catch {
                            // Log error but continue caching other frames
                        }
                    }
                    inFlight += 1
                }

                await group.waitForAll()
            }
        }
    }

    /// Stop background caching
    public func stop() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
    }
}
```

---

## 13. Complete Architecture Synthesis

### How It All Fits Together

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SwiftEditor App                                  │
│                                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│  │ Timeline     │  │ Viewer       │  │ Inspector    │  SwiftUI Views   │
│  │ View         │  │ View         │  │ View         │                  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                 │
│         │  @Observable     │                 │                          │
│  ┌──────▼──────────────────▼─────────────────▼───────┐                 │
│  │              TimelineModel (@Observable)           │                 │
│  │  ├── videoTracks, audioTracks                      │                 │
│  │  ├── request*() methods (all edits enter here)     │   TimelineKit  │
│  │  ├── undoManager (lambda composition)              │                 │
│  │  ├── groupsModel, snapModel                        │                 │
│  │  └── events: TimelineEventBus (Combine)            │                 │
│  └──────────────────────────┬────────────────────────┘                 │
│                             │                                           │
│  ┌──────────────────────────▼────────────────────────┐                 │
│  │         TransportController (@Observable)          │   ViewerKit     │
│  │  ├── AVPlayer management                           │                 │
│  │  ├── play/pause/seek/shuttle                       │                 │
│  │  └── timePublisher (Combine)                       │                 │
│  └──────────────────────────┬────────────────────────┘                 │
│                             │                                           │
│  ┌──────────────────────────▼────────────────────────┐                 │
│  │              MetalCompositor                       │   RenderEngine  │
│  │  ├── AVVideoCompositing (pull-based)               │                 │
│  │  ├── buildRenderPlan → executePlan (2-phase)       │                 │
│  │  ├── TexturePool (actor, reuses MTLTextures)       │                 │
│  │  ├── FrameHashCache (content-addressable)          │                 │
│  │  └── BackgroundRenderer (auto-caching)             │                 │
│  └──────────────────────────┬────────────────────────┘                 │
│                             │                                           │
│  ┌──────────────────────────▼────────────────────────┐                 │
│  │              EffectStack + Plugin System            │  EffectsEngine  │
│  │  ├── VideoEffect / VideoTransition / Generator     │                 │
│  │  ├── KeyframeTrack (bezier interpolation)          │                 │
│  │  ├── PluginRegistry (actor, bundle loading)        │                 │
│  │  └── Built-in effects + third-party plugins        │                 │
│  └──────────────────────────┬────────────────────────┘                 │
│                             │                                           │
│  ┌──────────────────────────▼────────────────────────┐                 │
│  │                  ProjectModel                      │  ProjectModel   │
│  │  ├── Project (Codable, versioned schema)           │                 │
│  │  ├── Sequence, TrackData, ClipData                 │                 │
│  │  ├── MediaBinModel                                 │                 │
│  │  ├── Schema migration (V1 → V2 → ...)              │                 │
│  │  └── File package (.nleproj directory bundle)       │                 │
│  └───────────────────────────────────────────────────┘                 │
│                                                                        │
│  ┌───────────────────────────────────────────────────┐                 │
│  │                  MediaManager                      │  MediaManager   │
│  │  ├── AssetImporter (drag-and-drop, file browser)   │                 │
│  │  ├── ProxyGenerator (background transcoding)       │                 │
│  │  ├── ThumbnailGenerator (AVAssetImageGenerator)    │                 │
│  │  └── MediaBin (runtime asset state)                │                 │
│  └───────────────────────────────────────────────────┘                 │
│                                                                        │
│  ┌───────────────────────────────────────────────────┐                 │
│  │                  CoreMedia+                        │  Foundation     │
│  │  ├── Rational (exact time arithmetic)              │                 │
│  │  ├── TimeRange (start + duration)                  │                 │
│  │  ├── VideoParams, AudioParams, ColorSpace          │                 │
│  │  └── TrackType, BlendMode, ParameterValue          │                 │
│  └───────────────────────────────────────────────────┘                 │
└────────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module system | SPM multi-target package | Native Xcode integration, no external build tools |
| State management | Custom @Observable + request pattern | Combines SwiftUI compatibility with Kdenlive's disciplined mutation |
| Undo/redo | Lambda composition (Kdenlive) | Self-healing, composable, automatic rollback on failure |
| Rendering | Two-phase: RenderPlan then execute (Olive) | Separates graph traversal from GPU, enables caching at plan level |
| Frame delivery | Pull-based via AVVideoCompositing | Aligns with AVFoundation, consumer controls timing |
| Caching | Content-addressable frame hash cache (Olive) | Same content = same hash = skip re-render |
| Thread safety | Actors for shared mutable state | Compiler-enforced isolation, no manual locks |
| Plugin system | Protocol + Bundle discovery (MLT) | Third-party extensibility without modifying core |
| Cross-module comms | Combine event bus | Loose coupling, filtered subscriptions, debouncing |
| Time representation | Rational (exact fraction) | Frame-accurate, no floating-point accumulation errors |
| Project format | Versioned Codable + directory bundle | Forward migration, human-readable JSON, co-located media |
| Effect model | Protocol-based ProcessingNode (Olive) | Unified effect/transition/generator model |
| Keyframes | Per-parameter tracks with bezier (Olive) | Independent easing curves per channel |
| Track model | Dual-playlist ready (Kdenlive) | Enables same-track transitions |
| Concurrency | Swift structured concurrency + actors | Modern, safe, no callback hell |

### Patterns Inherited from Research

**From Olive Editor:**
- Everything-is-a-Node processing model (adapted to protocols)
- NodeValueTable for heterogeneous value passing
- Job-based deferred rendering (RenderPlan / RenderJob)
- Frame hash caching (content-addressable)
- Background auto-caching (PreviewAutoCacher)
- Texture pooling
- Rational time arithmetic
- Per-component keyframe tracks

**From MLT Framework:**
- Pull-based frame delivery (AVVideoCompositing)
- Service-is-a-PropertyBag (metadata through pipeline)
- Composable containers (Playlist IS a Producer)
- Filter attachment chains
- Module/plugin registry pattern

**From Kdenlive:**
- Lambda-based undo/redo composition (PUSH_LAMBDA)
- Request pattern for all mutations
- Dual-playlist tracks for same-track transitions
- Groups model and snap model as separate concerns
- Proxy workflow integration
- Hierarchical effect stack

**From Cabbage (Swift):**
- Protocol-oriented composition providers
- TrackItem/Resource separation
- CompositionGenerator pattern for building AVPlayerItems
- VideoCompositionInstruction rendering flow
- CIImage pipeline for effects

**From GPUImage3 (Swift):**
- Metal texture management patterns
- Pipeline state object caching
- Compute shader dispatch for image processing

---

## Appendix A: Parameter System

```swift
// Sources/EffectsEngine/ParameterDescriptor.swift

/// Describes a parameter that an effect exposes
public enum ParameterDescriptor: Codable, Sendable {
    case float(name: String, displayName: String,
               defaultValue: Double, range: ClosedRange<Double>)
    case int(name: String, displayName: String,
             defaultValue: Int, range: ClosedRange<Int>)
    case bool(name: String, displayName: String, defaultValue: Bool)
    case color(name: String, displayName: String,
               defaultValue: (r: Double, g: Double, b: Double, a: Double))
    case point(name: String, displayName: String,
               defaultValue: CGPoint)
    case choice(name: String, displayName: String,
                options: [String], defaultIndex: Int)
    case string(name: String, displayName: String, defaultValue: String)
}

/// Runtime parameter values for an effect instance
public struct ParameterValues: Sendable {
    private var values: [String: ParameterValue]

    public init(_ values: [String: ParameterValue] = [:]) {
        self.values = values
    }

    public subscript(name: String) -> ParameterValue? {
        get { values[name] }
        set { values[name] = newValue }
    }

    public func floatValue(_ name: String, default: Double = 0) -> Double {
        if case .float(let v) = values[name] { return v }
        return `default`
    }

    public func boolValue(_ name: String, default: Bool = false) -> Bool {
        if case .bool(let v) = values[name] { return v }
        return `default`
    }
}
```

## Appendix B: NodeValueTable (Olive-Inspired)

```swift
// Sources/EffectsEngine/NodeValueTable.swift

/// Heterogeneous stack for passing values through the processing graph
/// Inspired by Olive's NodeValueTable
public struct NodeValueTable: Sendable {
    public enum Value: Sendable {
        case texture(TextureRef)
        case samples(AudioSamplesRef)
        case float(Double)
        case int(Int)
        case bool(Bool)
        case color(r: Double, g: Double, b: Double, a: Double)
        case point(x: Double, y: Double)
        case matrix(simd_float4x4)
        case string(String)
        case videoParams(VideoParams)
        case audioParams(AudioParams)
    }

    private var stack: [Value] = []

    /// Push a value onto the stack
    public mutating func push(_ value: Value) {
        stack.append(value)
    }

    /// Find and return (without removing) the most recent value of a given type
    public func get<T>(_ type: T.Type) -> T? where T: Sendable {
        for value in stack.reversed() {
            switch (value, type) {
            case (.float(let v), is Double.Type): return v as? T
            case (.int(let v), is Int.Type): return v as? T
            case (.bool(let v), is Bool.Type): return v as? T
            default: continue
            }
        }
        return nil
    }

    /// Find and remove the most recent value of a given type
    public mutating func take<T>(_ type: T.Type) -> T? where T: Sendable {
        for i in stride(from: stack.count - 1, through: 0, by: -1) {
            switch (stack[i], type) {
            case (.float(let v), is Double.Type):
                stack.remove(at: i)
                return v as? T
            default: continue
            }
        }
        return nil
    }

    /// Merge multiple tables
    public static func merge(_ tables: [NodeValueTable]) -> NodeValueTable {
        var result = NodeValueTable()
        for table in tables {
            result.stack.append(contentsOf: table.stack)
        }
        return result
    }
}

/// Reference to a texture (opaque, to avoid MTLTexture protocol conformance issues)
public struct TextureRef: Sendable {
    public let id: UInt64
    // Internal reference to actual MTLTexture managed by RenderEngine
}

/// Reference to audio samples
public struct AudioSamplesRef: Sendable {
    public let id: UInt64
    // Internal reference to audio buffer
}
```

## Appendix C: Groups and Snap Models

```swift
// Sources/TimelineKit/Models/GroupsModel.swift

/// Manages clip grouping (linked clips move together)
/// Inspired by Kdenlive's GroupsModel
@Observable
public final class GroupsModel {
    // Tree structure: parent → children
    private var downLinks: [UUID: Set<UUID>] = [:]
    // Reverse lookup: child → parent
    private var upLink: [UUID: UUID] = [:]

    /// Group a set of items together, returning the group ID
    @discardableResult
    public func group(_ itemIDs: Set<UUID>) -> UUID {
        let groupID = UUID()
        downLinks[groupID] = itemIDs
        for itemID in itemIDs {
            // If this item was in another group, remove it
            if let oldParent = upLink[itemID] {
                downLinks[oldParent]?.remove(itemID)
            }
            upLink[itemID] = groupID
        }
        return groupID
    }

    /// Ungroup items
    public func ungroup(_ groupID: UUID) {
        guard let children = downLinks[groupID] else { return }
        for child in children {
            upLink.removeValue(forKey: child)
        }
        downLinks.removeValue(forKey: groupID)
    }

    /// Get the root group for an item
    public func rootGroup(for itemID: UUID) -> UUID {
        var current = itemID
        while let parent = upLink[current] {
            current = parent
        }
        return current
    }

    /// Get all leaf items in a group
    public func leaves(of groupID: UUID) -> Set<UUID> {
        guard let children = downLinks[groupID] else {
            return [groupID] // It is a leaf itself
        }
        var result = Set<UUID>()
        for child in children {
            result.formUnion(leaves(of: child))
        }
        return result
    }

    /// Check if an item belongs to any group
    public func isGrouped(_ itemID: UUID) -> Bool {
        upLink[itemID] != nil
    }
}
```

```swift
// Sources/TimelineKit/Models/SnapModel.swift

/// Reference-counted snap points on the timeline
/// Inspired by Kdenlive's SnapModel
@Observable
public final class SnapModel {
    // Position → reference count
    private var points: [Rational: Int] = [:]

    /// Snap threshold in timeline units
    public var snapThreshold: Rational = Rational(1, 10)

    /// Add a snap point (increment reference count)
    public func addPoint(_ position: Rational) {
        points[position, default: 0] += 1
    }

    /// Remove a snap point (decrement reference count)
    public func removePoint(_ position: Rational) {
        guard let count = points[position] else { return }
        if count <= 1 {
            points.removeValue(forKey: position)
        } else {
            points[position] = count - 1
        }
    }

    /// Find the closest snap point to a given position
    public func closestPoint(to position: Rational) -> Rational? {
        var closest: Rational?
        var minDistance = snapThreshold

        for point in points.keys {
            let distance = abs(point - position)
            if distance < minDistance {
                minDistance = distance
                closest = point
            }
        }

        return closest
    }

    /// Snap a position to the nearest point (returns original if no snap)
    public func snap(_ position: Rational) -> Rational {
        closestPoint(to: position) ?? position
    }

    /// Rebuild all snap points from timeline state
    public func rebuild(from clips: [any Clip]) {
        points.removeAll()
        for clip in clips {
            addPoint(clip.startTime)
            addPoint(clip.startTime + clip.duration)
        }
    }
}

/// Helper for absolute value of Rational
private func abs(_ r: Rational) -> Rational {
    r.numerator < 0 ? Rational(-r.numerator, r.denominator) : r
}
```
