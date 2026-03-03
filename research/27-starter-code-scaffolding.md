# Starter Code Scaffolding

> Copy-paste-ready Swift code to bootstrap the SwiftEditor project. Every file listed here is a real, compilable source file. The code provides the complete Package.swift, all protocol definitions at module boundaries, core value types, key class stubs with real method signatures, and the macOS app entry point with menu bar.

---

## Table of Contents

1. [Package.swift](#1-packageswift)
2. [CoreMediaPlus Module](#2-coremediaplus-module)
3. [PluginKit Module](#3-pluginkit-module)
4. [ProjectModel Module](#4-projectmodel-module)
5. [TimelineKit Module](#5-timelinekit-module)
6. [EffectsEngine Module](#6-effectsengine-module)
7. [RenderEngine Module](#7-renderengine-module)
8. [ViewerKit Module](#8-viewerkit-module)
9. [MediaManager Module](#9-mediamanager-module)
10. [AudioEngine Module](#10-audioengine-module)
11. [App Entry Point & Menu Bar](#11-app-entry-point--menu-bar)
12. [Bootstrap Script](#12-bootstrap-script)

---

## 1. Package.swift

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
    dependencies: [],
    targets: [
        // ── Foundation Layer ──────────────────────────────
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

        // ── Plugin Contract Layer ────────────────────────
        .target(
            name: "PluginKit",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/PluginKit"
        ),

        // ── Data Layer ───────────────────────────────────
        .target(
            name: "ProjectModel",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/ProjectModel"
        ),
        .testTarget(
            name: "ProjectModelTests",
            dependencies: ["ProjectModel"],
            path: "Tests/ProjectModelTests"
        ),

        // ── Effects Layer ────────────────────────────────
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

        // ── Render Layer ─────────────────────────────────
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

        // ── Edit Model Layer ─────────────────────────────
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

        // ── Playback Layer ───────────────────────────────
        .target(
            name: "ViewerKit",
            dependencies: ["CoreMediaPlus", "RenderEngine", "TimelineKit"],
            path: "Sources/ViewerKit"
        ),
        .testTarget(
            name: "ViewerKitTests",
            dependencies: ["ViewerKit"],
            path: "Tests/ViewerKitTests"
        ),

        // ── Media Layer ──────────────────────────────────
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

        // ── Audio Layer ──────────────────────────────────
        .target(
            name: "AudioEngine",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/AudioEngine"
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"],
            path: "Tests/AudioEngineTests"
        ),
    ]
)
```

---

## 2. CoreMediaPlus Module

### Sources/CoreMediaPlus/Rational.swift

```swift
import CoreMedia
import Foundation

/// Exact rational time representation wrapping CMTime.
/// Eliminates floating-point accumulation errors in timeline arithmetic.
/// Timescale 600 is the default (LCM of 24, 25, 30, 60 fps).
public struct Rational: Sendable, Hashable, Comparable, Codable {
    public let numerator: Int64
    public let denominator: Int64

    public static let zero = Rational(0, 1)
    public static let invalid = Rational(0, 0)

    public init(_ numerator: Int64, _ denominator: Int64) {
        if denominator == 0 {
            self.numerator = 0
            self.denominator = 0
            return
        }
        let g = Self.gcd(Swift.abs(numerator), Swift.abs(denominator))
        let sign: Int64 = denominator < 0 ? -1 : 1
        self.numerator = sign * numerator / g
        self.denominator = sign * denominator / g
    }

    public init(_ cmTime: CMTime) {
        guard cmTime.isValid, !cmTime.isIndefinite else {
            self = .invalid
            return
        }
        self.init(cmTime.value, Int64(cmTime.timescale))
    }

    public init(seconds: Double, preferredTimescale: Int32 = 600) {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
        self.init(cmTime)
    }

    public var isValid: Bool { denominator != 0 }

    public var cmTime: CMTime {
        guard isValid else { return .invalid }
        return CMTime(value: numerator, timescale: CMTimeScale(denominator))
    }

    public var seconds: Double {
        guard denominator != 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    public func frameNumber(at frameRate: Rational) -> Int64 {
        let product = self * frameRate
        guard product.denominator != 0 else { return 0 }
        return product.numerator / product.denominator
    }

    // MARK: - Arithmetic

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

    public var abs: Rational {
        Rational(Swift.abs(numerator), denominator)
    }

    // MARK: - Codable

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

    // MARK: - Private

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        b == 0 ? a : gcd(b, a % b)
    }
}

extension Rational: CustomStringConvertible {
    public var description: String {
        guard isValid else { return "invalid" }
        return "\(numerator)/\(denominator)"
    }
}
```

### Sources/CoreMediaPlus/TimeRange.swift

```swift
import Foundation

/// A range of time on the timeline defined by start + duration.
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

    public static let zero = TimeRange(start: .zero, duration: .zero)

    public func contains(_ time: Rational) -> Bool {
        time >= start && time < end
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    public func intersection(_ other: TimeRange) -> TimeRange? {
        let overlapStart = Swift.max(start, other.start)
        let overlapEnd = Swift.min(end, other.end)
        guard overlapStart < overlapEnd else { return nil }
        return TimeRange(start: overlapStart, end: overlapEnd)
    }

    public func union(_ other: TimeRange) -> TimeRange {
        let unionStart = Swift.min(start, other.start)
        let unionEnd = Swift.max(end, other.end)
        return TimeRange(start: unionStart, end: unionEnd)
    }
}
```

### Sources/CoreMediaPlus/VideoParams.swift

```swift
import Foundation

/// Video format parameters used throughout the pipeline.
public struct VideoParams: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var pixelFormat: PixelFormat
    public var colorSpace: ColorSpace

    public init(
        width: Int,
        height: Int,
        pixelFormat: PixelFormat = .bgra8Unorm,
        colorSpace: ColorSpace = .rec709
    ) {
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
        case bgra8Unorm
        case rgba16Float
        case bgr10a2Unorm
        case yuv420BiPlanar8
        case yuv420BiPlanar10
    }
}
```

### Sources/CoreMediaPlus/AudioParams.swift

```swift
import Foundation

/// Audio format parameters.
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
```

### Sources/CoreMediaPlus/ColorSpace.swift

```swift
import Foundation

/// Color space identifiers for the rendering pipeline.
public enum ColorSpace: String, Codable, Sendable {
    case sRGB
    case rec709
    case rec2020
    case p3
    case acescg
    case acesCCT
    case sLog3
    case logC
    case vLog
}
```

### Sources/CoreMediaPlus/MediaTypes.swift

```swift
import Foundation

/// Track type discriminator.
public enum TrackType: String, Codable, Sendable {
    case video
    case audio
    case subtitle
}

/// Which edge of a clip is being trimmed.
public enum TrimEdge: Sendable {
    case leading
    case trailing
}

/// Compositing blend modes.
public enum BlendMode: String, Codable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    case difference
}

/// Type-safe parameter values for effects.
public enum ParameterValue: Codable, Sendable, Hashable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case string(String)
    case color(r: Double, g: Double, b: Double, a: Double)
    case point(x: Double, y: Double)
    case size(width: Double, height: Double)
}

/// Describes a parameter exposed by an effect.
public enum ParameterDescriptor: Codable, Sendable {
    case float(name: String, displayName: String, defaultValue: Double, min: Double, max: Double)
    case int(name: String, displayName: String, defaultValue: Int, min: Int, max: Int)
    case bool(name: String, displayName: String, defaultValue: Bool)
    case color(name: String, displayName: String, defaultR: Double, defaultG: Double, defaultB: Double, defaultA: Double)
    case point(name: String, displayName: String, defaultX: Double, defaultY: Double)
    case choice(name: String, displayName: String, options: [String], defaultIndex: Int)
}

/// Runtime parameter values for an effect instance.
public struct ParameterValues: Sendable {
    private var values: [String: ParameterValue]

    public init(_ values: [String: ParameterValue] = [:]) {
        self.values = values
    }

    public subscript(name: String) -> ParameterValue? {
        get { values[name] }
        set { values[name] = newValue }
    }

    public func floatValue(_ name: String, default defaultValue: Double = 0) -> Double {
        if case .float(let v) = values[name] { return v }
        return defaultValue
    }

    public func boolValue(_ name: String, default defaultValue: Bool = false) -> Bool {
        if case .bool(let v) = values[name] { return v }
        return defaultValue
    }

    public func intValue(_ name: String, default defaultValue: Int = 0) -> Int {
        if case .int(let v) = values[name] { return v }
        return defaultValue
    }
}

/// Selection state for the timeline.
public struct SelectionState: Sendable {
    public var selectedClipIDs: Set<UUID>
    public var selectedTrackIDs: Set<UUID>
    public var selectedRange: TimeRange?

    public init(
        selectedClipIDs: Set<UUID> = [],
        selectedTrackIDs: Set<UUID> = [],
        selectedRange: TimeRange? = nil
    ) {
        self.selectedClipIDs = selectedClipIDs
        self.selectedTrackIDs = selectedTrackIDs
        self.selectedRange = selectedRange
    }

    public static let empty = SelectionState()

    public var isEmpty: Bool {
        selectedClipIDs.isEmpty && selectedTrackIDs.isEmpty && selectedRange == nil
    }
}

/// Protocols for time-based types.
public protocol TimeRangeProviding {
    var timeRange: TimeRange { get }
}

public protocol TimePositionable: TimeRangeProviding {
    var startTime: Rational { get set }
    var duration: Rational { get }
}

/// Log level for plugin logging.
public enum LogLevel: Sendable {
    case debug, info, warning, error
}

/// Status of an asset in the media manager.
public enum AssetStatus: String, Codable, Sendable {
    case importing
    case ready
    case offline
    case error
}

/// Proxy generation presets.
public enum ProxyPreset: String, Codable, Sendable {
    case halfResolution
    case quarterResolution
    case proresProxy
}
```

---

## 3. PluginKit Module

### Sources/PluginKit/PluginManifest.swift

```swift
import Foundation

/// Metadata describing a plugin.
public struct PluginManifest: Codable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let author: String
    public let category: PluginCategory
    public let minimumHostVersion: String
    public let capabilities: Set<PluginCapability>

    public init(
        identifier: String,
        name: String,
        version: String,
        author: String,
        category: PluginCategory,
        minimumHostVersion: String,
        capabilities: Set<PluginCapability> = []
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.category = category
        self.minimumHostVersion = minimumHostVersion
        self.capabilities = capabilities
    }

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
```

### Sources/PluginKit/PluginProtocols.swift

```swift
import Foundation
import CoreMediaPlus
#if canImport(Metal)
import Metal
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Entry point protocol for plugin bundles.
public protocol PluginBundle: AnyObject, Sendable {
    static var manifest: PluginManifest { get }
    init()
    func activate(host: any PluginHost) throws
    func deactivate()
    func createNodes() -> [any ProcessingNode]
}

/// Host services provided to plugins by the application.
public protocol PluginHost: Sendable {
    func log(_ message: String, level: LogLevel)
    #if canImport(Metal)
    var metalDevice: (any MTLDevice)? { get }
    #endif
}

/// Base protocol for all processing nodes (Olive-inspired).
public protocol ProcessingNode: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var category: String { get }
    var parameters: [ParameterDescriptor] { get }
}

/// A video effect that processes frames.
public protocol VideoEffect: ProcessingNode {
    #if canImport(Metal)
    func apply(to texture: any MTLTexture, at time: Rational,
               parameters: ParameterValues,
               commandBuffer: any MTLCommandBuffer) throws -> any MTLTexture
    #endif
}

/// A transition between two clips.
public protocol VideoTransition: ProcessingNode {
    var defaultDuration: Rational { get }
    #if canImport(Metal)
    func apply(from textureA: any MTLTexture, to textureB: any MTLTexture,
               progress: Double, parameters: ParameterValues,
               commandBuffer: any MTLCommandBuffer) throws -> any MTLTexture
    #endif
}

/// A generator that creates frames from nothing.
public protocol VideoGenerator: ProcessingNode {
    #if canImport(Metal)
    func generate(at time: Rational, size: CGSize,
                  parameters: ParameterValues,
                  commandBuffer: any MTLCommandBuffer) throws -> any MTLTexture
    #endif
}

/// An audio effect.
public protocol AudioEffect: ProcessingNode {
    #if canImport(AVFoundation)
    func process(buffer: AVAudioPCMBuffer, at time: Rational,
                 parameters: ParameterValues) throws -> AVAudioPCMBuffer
    #endif
}

/// Custom codec plugin.
public protocol CodecPlugin: ProcessingNode {
    var codecIdentifier: String { get }
    var isEncoder: Bool { get }
    var isDecoder: Bool { get }
}

/// Custom export format plugin.
public protocol ExportFormatPlugin: ProcessingNode {
    var fileExtension: String { get }
    var mimeType: String { get }
}
```

### Sources/PluginKit/PluginRegistry.swift

```swift
import Foundation
import CoreMediaPlus

/// Central registry for all available processing nodes.
/// Thread-safe via actor isolation.
public actor PluginRegistry {
    public static let shared = PluginRegistry()

    private var videoEffects: [String: any VideoEffect] = [:]
    private var videoTransitions: [String: any VideoTransition] = [:]
    private var videoGenerators: [String: any VideoGenerator] = [:]
    private var audioEffects: [String: any AudioEffect] = [:]
    private var loadedBundles: [String: any PluginBundle] = [:]

    private init() {}

    // MARK: - Registration

    public func register(videoEffect: any VideoEffect, id: String) {
        videoEffects[id] = videoEffect
    }

    public func register(videoTransition: any VideoTransition, id: String) {
        videoTransitions[id] = videoTransition
    }

    public func register(videoGenerator: any VideoGenerator, id: String) {
        videoGenerators[id] = videoGenerator
    }

    public func register(audioEffect: any AudioEffect, id: String) {
        audioEffects[id] = audioEffect
    }

    // MARK: - Discovery

    public func loadPlugins(from directory: URL, host: any PluginHost) async throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents where url.pathExtension == "plugin" {
            guard let bundle = Bundle(url: url), bundle.load(),
                  let principalClass = bundle.principalClass as? any PluginBundle.Type else {
                continue
            }
            let instance = principalClass.init()
            try instance.activate(host: host)
            let manifest = type(of: instance).manifest
            loadedBundles[manifest.identifier] = instance

            for node in instance.createNodes() {
                let key = "\(manifest.identifier).\(node.name)"
                if let effect = node as? any VideoEffect {
                    videoEffects[key] = effect
                } else if let transition = node as? any VideoTransition {
                    videoTransitions[key] = transition
                } else if let generator = node as? any VideoGenerator {
                    videoGenerators[key] = generator
                } else if let audio = node as? any AudioEffect {
                    audioEffects[key] = audio
                }
            }
        }
    }

    // MARK: - Lookup

    public func allVideoEffects() -> [(id: String, name: String)] {
        videoEffects.map { ($0.key, $0.value.name) }.sorted { $0.1 < $1.1 }
    }

    public func allVideoTransitions() -> [(id: String, name: String)] {
        videoTransitions.map { ($0.key, $0.value.name) }.sorted { $0.1 < $1.1 }
    }

    public func allVideoGenerators() -> [(id: String, name: String)] {
        videoGenerators.map { ($0.key, $0.value.name) }.sorted { $0.1 < $1.1 }
    }

    public func videoEffect(id: String) -> (any VideoEffect)? {
        videoEffects[id]
    }

    public func videoTransition(id: String) -> (any VideoTransition)? {
        videoTransitions[id]
    }
}
```

---

## 4. ProjectModel Module

### Sources/ProjectModel/Project.swift

```swift
import Foundation
import CoreMediaPlus

/// Top-level project document. Codable for JSON serialization.
public struct Project: Codable, Sendable, Identifiable {
    public static let currentVersion = 1
    public static let fileExtension = "nleproj"

    public var version: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var settings: ProjectSettings
    public var sequences: [Sequence]
    public var bin: MediaBinModel
    public var metadata: ProjectMetadata

    public init(name: String, settings: ProjectSettings = .defaultHD) {
        self.version = Self.currentVersion
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

public struct ProjectSettings: Codable, Sendable, Equatable {
    public var videoParams: VideoParams
    public var audioParams: AudioParams
    public var colorSpace: ColorSpace
    public var frameRate: Rational

    public init(
        videoParams: VideoParams,
        audioParams: AudioParams,
        colorSpace: ColorSpace = .rec709,
        frameRate: Rational = Rational(24, 1)
    ) {
        self.videoParams = videoParams
        self.audioParams = audioParams
        self.colorSpace = colorSpace
        self.frameRate = frameRate
    }

    public static let defaultHD = ProjectSettings(
        videoParams: VideoParams(width: 1920, height: 1080),
        audioParams: AudioParams(sampleRate: 48000, channelCount: 2),
        colorSpace: .rec709,
        frameRate: Rational(24, 1)
    )

    public static let default4K = ProjectSettings(
        videoParams: VideoParams(width: 3840, height: 2160),
        audioParams: AudioParams(sampleRate: 48000, channelCount: 2),
        colorSpace: .rec709,
        frameRate: Rational(24, 1)
    )
}

public struct Sequence: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var settings: ProjectSettings
    public var videoTracks: [TrackData]
    public var audioTracks: [TrackData]
    public var markers: [Marker]

    public init(name: String, settings: ProjectSettings) {
        self.id = UUID()
        self.name = name
        self.settings = settings
        self.videoTracks = [TrackData(name: "V1", type: .video)]
        self.audioTracks = [TrackData(name: "A1", type: .audio)]
        self.markers = []
    }
}

public struct TrackData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var type: TrackType
    public var clips: [ClipData]
    public var isMuted: Bool
    public var isLocked: Bool
    public var height: Double

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

public struct ClipData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sourceAssetID: UUID
    public var startTime: Rational
    public var sourceIn: Rational
    public var sourceOut: Rational
    public var speed: Double
    public var isEnabled: Bool
    public var effects: [EffectData]
    public var volume: Double
    public var opacity: Double
    public var position: CGPoint
    public var scale: CGSize
    public var rotation: Double

    public init(sourceAssetID: UUID, startTime: Rational, sourceIn: Rational, sourceOut: Rational) {
        self.id = UUID()
        self.sourceAssetID = sourceAssetID
        self.startTime = startTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.speed = 1.0
        self.isEnabled = true
        self.effects = []
        self.volume = 1.0
        self.opacity = 1.0
        self.position = .zero
        self.scale = CGSize(width: 1.0, height: 1.0)
        self.rotation = 0.0
    }

    public var duration: Rational {
        let sourceDuration = sourceOut - sourceIn
        guard speed != 0 else { return sourceDuration }
        return Rational(Int64(Double(sourceDuration.numerator) / speed), sourceDuration.denominator)
    }
}

public struct EffectData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var pluginID: String
    public var isEnabled: Bool
    public var parameters: [String: ParameterValue]
    public var keyframes: [String: [KeyframeData]]

    public init(pluginID: String) {
        self.id = UUID()
        self.pluginID = pluginID
        self.isEnabled = true
        self.parameters = [:]
        self.keyframes = [:]
    }
}

public struct KeyframeData: Codable, Sendable {
    public var time: Rational
    public var value: ParameterValue
    public var interpolation: InterpolationType

    public init(time: Rational, value: ParameterValue, interpolation: InterpolationType = .linear) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }

    public enum InterpolationType: String, Codable, Sendable {
        case linear
        case hold
        case bezier
    }
}

public struct Marker: Codable, Sendable, Identifiable {
    public var id: UUID
    public var time: Rational
    public var name: String
    public var color: MarkerColor
    public var comment: String

    public init(time: Rational, name: String, color: MarkerColor = .blue) {
        self.id = UUID()
        self.time = time
        self.name = name
        self.color = color
        self.comment = ""
    }

    public enum MarkerColor: String, Codable, Sendable {
        case red, orange, yellow, green, blue, purple, pink
    }
}

public struct MediaBinModel: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [BinItemData]
    public var subfolders: [MediaBinModel]

    public init(name: String = "Root") {
        self.id = UUID()
        self.name = name
        self.items = []
        self.subfolders = []
    }
}

public struct BinItemData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var relativePath: String
    public var originalPath: String
    public var proxyPath: String?
    public var duration: Rational
    public var videoParams: VideoParams?
    public var audioParams: AudioParams?
    public var importDate: Date

    public init(name: String, relativePath: String, originalPath: String, duration: Rational) {
        self.id = UUID()
        self.name = name
        self.relativePath = relativePath
        self.originalPath = originalPath
        self.duration = duration
        self.importDate = .now
    }
}

public struct ProjectMetadata: Codable, Sendable {
    public var description: String
    public var tags: [String]
    public var author: String

    public init(description: String = "", tags: [String] = [], author: String = "") {
        self.description = description
        self.tags = tags
        self.author = author
    }
}
```

### Sources/ProjectModel/ProjectDocument.swift

```swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// macOS document type for project files.
/// Integrates with SwiftUI's document-based app architecture.
public struct ProjectDocument: FileDocument {
    public var project: Project

    public static var readableContentTypes: [UTType] {
        [.init(exportedAs: "com.swifteditor.project")]
    }

    public init(project: Project = Project(name: "Untitled")) {
        self.project = project
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.project = try decoder.decode(Project.self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
```

---

## 5. TimelineKit Module

### Sources/TimelineKit/UndoSystem.swift

```swift
import Foundation
import Observation

/// A closure that performs an undoable operation. Returns true on success.
public typealias UndoAction = @Sendable () -> Bool

/// Append an operation to a redo chain.
public func appendOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = { previous() && operation() }
}

/// Prepend an operation to an undo chain (undo runs in reverse order).
public func prependOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = { operation() && previous() }
}

/// An entry in the undo stack.
public struct UndoEntry: Sendable {
    public let undo: UndoAction
    public let redo: UndoAction
    public let description: String
    public let timestamp: Date
}

/// Lambda-based undo/redo manager (Kdenlive-inspired).
@Observable
public final class TimelineUndoManager: @unchecked Sendable {
    public private(set) var undoStack: [UndoEntry] = []
    public private(set) var redoStack: [UndoEntry] = []
    public private(set) var canUndo: Bool = false
    public private(set) var canRedo: Bool = false
    public var maxUndoLevels: Int = 200

    public init() {}

    public func record(undo: @escaping UndoAction, redo: @escaping UndoAction,
                       description: String) {
        let entry = UndoEntry(undo: undo, redo: redo,
                              description: description, timestamp: .now)
        undoStack.append(entry)
        redoStack.removeAll()
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        canUndo = true
        canRedo = false
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        guard entry.undo() else {
            undoStack.append(entry)
            return false
        }
        redoStack.append(entry)
        canUndo = !undoStack.isEmpty
        canRedo = true
        return true
    }

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

    public var undoDescription: String? {
        undoStack.last?.description
    }

    public var redoDescription: String? {
        redoStack.last?.description
    }
}
```

### Sources/TimelineKit/TimelineEventBus.swift

```swift
import Foundation
import Combine
import CoreMediaPlus

/// Events emitted by the timeline model for cross-module communication.
public enum TimelineEvent: Sendable {
    case clipAdded(clipID: UUID, trackID: UUID)
    case clipRemoved(clipID: UUID, trackID: UUID)
    case clipMoved(clipID: UUID, toTrack: UUID, at: Rational)
    case clipResized(clipID: UUID)
    case clipSplit(clipID: UUID, newClipID: UUID, at: Rational)
    case trackAdded(trackID: UUID, type: TrackType, at: Int)
    case trackRemoved(trackID: UUID)
    case effectChanged(clipID: UUID)
    case playheadMoved(time: Rational)
    case selectionChanged
    case undoPerformed(description: String)
    case redoPerformed(description: String)
}

/// Combine-based event bus for timeline events.
public final class TimelineEventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<TimelineEvent, Never>()

    public init() {}

    public var publisher: AnyPublisher<TimelineEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public func send(_ event: TimelineEvent) {
        subject.send(event)
    }

    public var clipEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter {
            switch $0 {
            case .clipAdded, .clipRemoved, .clipMoved, .clipResized, .clipSplit: return true
            default: return false
            }
        }.eraseToAnyPublisher()
    }

    public var effectEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter {
            if case .effectChanged = $0 { return true }
            return false
        }.eraseToAnyPublisher()
    }
}
```

### Sources/TimelineKit/TimelineModel.swift

```swift
import Foundation
import Observation
import CoreMediaPlus
import ProjectModel

/// The central editing model. All mutations go through request*() methods.
/// Inspired by Kdenlive's TimelineModel with lambda undo/redo composition.
@Observable
public final class TimelineModel: @unchecked Sendable {
    // MARK: - Published State

    public private(set) var videoTracks: [VideoTrackModel] = []
    public private(set) var audioTracks: [AudioTrackModel] = []
    public private(set) var duration: Rational = .zero
    public var selection: SelectionState = .empty

    // MARK: - Subsystems

    public let undoManager = TimelineUndoManager()
    public let groupsModel = GroupsModel()
    public let snapModel = SnapModel()
    public let events = TimelineEventBus()

    // MARK: - Internal State

    private var allClips: [UUID: ClipModel] = [:]

    public init() {}

    // MARK: - Load from ProjectModel

    public func load(from sequence: Sequence) {
        videoTracks = sequence.videoTracks.map { VideoTrackModel(from: $0) }
        audioTracks = sequence.audioTracks.map { AudioTrackModel(from: $0) }
        rebuildInternalState()
    }

    // MARK: - Request Methods (Single Entry Point for All Mutations)

    @discardableResult
    public func requestClipMove(clipID: UUID, toTrackID: UUID, at position: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let sourceTrackID = clip.trackID
        let sourcePosition = clip.startTime

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipMove(clipID: clipID, toTrack: toTrackID, at: position) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipMove(clipID: clipID, toTrack: sourceTrackID, at: sourcePosition) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Move Clip")
        recalculateDuration()
        events.send(.clipMoved(clipID: clipID, toTrack: toTrackID, at: position))
        return true
    }

    @discardableResult
    public func requestClipResize(clipID: UUID, edge: TrimEdge, to newTime: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldStart = clip.startTime
        let oldSourceIn = clip.sourceIn
        let oldSourceOut = clip.sourceOut

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipResize(clipID: clipID, edge: edge, to: newTime) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestoreTrim(clipID: clipID, startTime: oldStart,
                                         sourceIn: oldSourceIn, sourceOut: oldSourceOut) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Trim Clip")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    @discardableResult
    public func requestClipSplit(clipID: UUID, at time: Rational) -> Bool {
        guard let clip = allClips[clipID],
              time > clip.startTime,
              time < clip.startTime + clip.duration else { return false }

        let newClipID = UUID()

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipSplit(clipID: clipID, newClipID: newClipID, at: time) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipUnsplit(originalID: clipID, splitID: newClipID) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Split Clip")
        events.send(.clipSplit(clipID: clipID, newClipID: newClipID, at: time))
        return true
    }

    @discardableResult
    public func requestClipDelete(clipID: UUID) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let trackID = clip.trackID
        let clipData = clip.snapshot()

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: clipID) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestore(clipData, trackID: trackID) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Delete Clip")
        recalculateDuration()
        events.send(.clipRemoved(clipID: clipID, trackID: trackID))
        return true
    }

    @discardableResult
    public func requestTrackInsert(at index: Int, type: TrackType) -> Bool {
        let trackID = UUID()
        let name = type == .video ? "V\(videoTracks.count + 1)" : "A\(audioTracks.count + 1)"

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performTrackInsert(id: trackID, name: name, type: type, at: index) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performTrackRemove(trackID: trackID, type: type) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Add Track")
        events.send(.trackAdded(trackID: trackID, type: type, at: index))
        return true
    }

    // MARK: - Private Mutation Methods

    private func performClipMove(clipID: UUID, toTrack: UUID, at position: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        clip.trackID = toTrack
        clip.startTime = position
        return true
    }

    private func performClipResize(clipID: UUID, edge: TrimEdge, to newTime: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        switch edge {
        case .leading:
            let delta = newTime - clip.startTime
            clip.sourceIn = clip.sourceIn + delta
            clip.startTime = newTime
        case .trailing:
            clip.sourceOut = clip.sourceIn + (newTime - clip.startTime)
        }
        return true
    }

    private func performClipRestoreTrim(clipID: UUID, startTime: Rational,
                                         sourceIn: Rational, sourceOut: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        clip.startTime = startTime
        clip.sourceIn = sourceIn
        clip.sourceOut = sourceOut
        return true
    }

    private func performClipSplit(clipID: UUID, newClipID: UUID, at time: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        let splitSourceTime = clip.sourceIn + (time - clip.startTime)

        let newClip = ClipModel(
            id: newClipID,
            sourceAssetID: clip.sourceAssetID,
            trackID: clip.trackID,
            startTime: time,
            sourceIn: splitSourceTime,
            sourceOut: clip.sourceOut
        )

        clip.sourceOut = splitSourceTime
        allClips[newClipID] = newClip
        return true
    }

    private func performClipUnsplit(originalID: UUID, splitID: UUID) -> Bool {
        guard let original = allClips[originalID],
              let split = allClips[splitID] else { return false }
        original.sourceOut = split.sourceOut
        allClips.removeValue(forKey: splitID)
        return true
    }

    private func performClipRemove(clipID: UUID) -> Bool {
        allClips.removeValue(forKey: clipID) != nil
    }

    private func performClipRestore(_ data: ClipModel.Snapshot, trackID: UUID) -> Bool {
        let clip = ClipModel(from: data, trackID: trackID)
        allClips[clip.id] = clip
        return true
    }

    private func performTrackInsert(id: UUID, name: String, type: TrackType, at index: Int) -> Bool {
        switch type {
        case .video:
            let track = VideoTrackModel(id: id, name: name)
            let safeIndex = min(index, videoTracks.count)
            videoTracks.insert(track, at: safeIndex)
        case .audio:
            let track = AudioTrackModel(id: id, name: name)
            let safeIndex = min(index, audioTracks.count)
            audioTracks.insert(track, at: safeIndex)
        case .subtitle:
            return false
        }
        return true
    }

    private func performTrackRemove(trackID: UUID, type: TrackType) -> Bool {
        switch type {
        case .video: videoTracks.removeAll { $0.id == trackID }
        case .audio: audioTracks.removeAll { $0.id == trackID }
        case .subtitle: return false
        }
        return true
    }

    private func recalculateDuration() {
        var maxEnd = Rational.zero
        for clip in allClips.values {
            let clipEnd = clip.startTime + clip.duration
            if clipEnd > maxEnd { maxEnd = clipEnd }
        }
        duration = maxEnd
    }

    private func rebuildInternalState() {
        allClips.removeAll()
        // Rebuild from track data
    }
}

// MARK: - Supporting Types

@Observable
public final class ClipModel: @unchecked Sendable {
    public let id: UUID
    public let sourceAssetID: UUID
    public var trackID: UUID
    public var startTime: Rational
    public var sourceIn: Rational
    public var sourceOut: Rational
    public var speed: Double = 1.0
    public var isEnabled: Bool = true

    public var duration: Rational { sourceOut - sourceIn }

    public init(id: UUID = UUID(), sourceAssetID: UUID, trackID: UUID,
                startTime: Rational, sourceIn: Rational, sourceOut: Rational) {
        self.id = id
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.startTime = startTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }

    public struct Snapshot: Sendable {
        public let id: UUID
        public let sourceAssetID: UUID
        public let startTime: Rational
        public let sourceIn: Rational
        public let sourceOut: Rational
        public let speed: Double
    }

    public func snapshot() -> Snapshot {
        Snapshot(id: id, sourceAssetID: sourceAssetID, startTime: startTime,
                 sourceIn: sourceIn, sourceOut: sourceOut, speed: speed)
    }

    public convenience init(from snapshot: Snapshot, trackID: UUID) {
        self.init(id: snapshot.id, sourceAssetID: snapshot.sourceAssetID,
                  trackID: trackID, startTime: snapshot.startTime,
                  sourceIn: snapshot.sourceIn, sourceOut: snapshot.sourceOut)
        self.speed = snapshot.speed
    }
}

@Observable
public final class VideoTrackModel: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isMuted: Bool = false
    public var isLocked: Bool = false

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public init(from data: TrackData) {
        self.id = data.id
        self.name = data.name
        self.isMuted = data.isMuted
        self.isLocked = data.isLocked
    }
}

@Observable
public final class AudioTrackModel: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isMuted: Bool = false
    public var isLocked: Bool = false
    public var isSolo: Bool = false
    public var volume: Double = 1.0
    public var pan: Double = 0.0

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public init(from data: TrackData) {
        self.id = data.id
        self.name = data.name
        self.isMuted = data.isMuted
        self.isLocked = data.isLocked
    }
}
```

### Sources/TimelineKit/GroupsModel.swift

```swift
import Foundation
import Observation

/// Manages clip grouping. Linked clips move together.
@Observable
public final class GroupsModel: @unchecked Sendable {
    private var downLinks: [UUID: Set<UUID>] = [:]
    private var upLink: [UUID: UUID] = [:]

    public init() {}

    @discardableResult
    public func group(_ itemIDs: Set<UUID>) -> UUID {
        let groupID = UUID()
        downLinks[groupID] = itemIDs
        for itemID in itemIDs {
            if let oldParent = upLink[itemID] {
                downLinks[oldParent]?.remove(itemID)
            }
            upLink[itemID] = groupID
        }
        return groupID
    }

    public func ungroup(_ groupID: UUID) {
        guard let children = downLinks[groupID] else { return }
        for child in children { upLink.removeValue(forKey: child) }
        downLinks.removeValue(forKey: groupID)
    }

    public func rootGroup(for itemID: UUID) -> UUID {
        var current = itemID
        while let parent = upLink[current] { current = parent }
        return current
    }

    public func leaves(of groupID: UUID) -> Set<UUID> {
        guard let children = downLinks[groupID] else { return [groupID] }
        var result = Set<UUID>()
        for child in children { result.formUnion(leaves(of: child)) }
        return result
    }

    public func isGrouped(_ itemID: UUID) -> Bool {
        upLink[itemID] != nil
    }
}
```

### Sources/TimelineKit/SnapModel.swift

```swift
import Foundation
import Observation
import CoreMediaPlus

/// Reference-counted snap points on the timeline.
@Observable
public final class SnapModel: @unchecked Sendable {
    private var points: [Rational: Int] = [:]
    public var snapThreshold: Rational = Rational(1, 10)
    public var isEnabled: Bool = true

    public init() {}

    public func addPoint(_ position: Rational) {
        points[position, default: 0] += 1
    }

    public func removePoint(_ position: Rational) {
        guard let count = points[position] else { return }
        if count <= 1 { points.removeValue(forKey: position) }
        else { points[position] = count - 1 }
    }

    public func snap(_ position: Rational) -> Rational {
        guard isEnabled else { return position }
        var closest: Rational?
        var minDistance = snapThreshold
        for point in points.keys {
            let distance = (point - position).abs
            if distance < minDistance {
                minDistance = distance
                closest = point
            }
        }
        return closest ?? position
    }

    public func rebuild(clipEdges: [(start: Rational, end: Rational)]) {
        points.removeAll()
        for edge in clipEdges {
            addPoint(edge.start)
            addPoint(edge.end)
        }
    }
}
```

---

## 6. EffectsEngine Module

### Sources/EffectsEngine/EffectStack.swift

```swift
import Foundation
import Observation
import CoreMediaPlus
import PluginKit

/// Ordered list of effects applied to a clip or track.
@Observable
public final class EffectStack: @unchecked Sendable {
    public private(set) var effects: [EffectInstance] = []
    public var isEnabled: Bool = true

    public init() {}

    public func append(_ effect: EffectInstance) {
        effects.append(effect)
    }

    public func remove(at index: Int) {
        guard effects.indices.contains(index) else { return }
        effects.remove(at: index)
    }

    public func move(from source: Int, to destination: Int) {
        guard effects.indices.contains(source) else { return }
        let effect = effects.remove(at: source)
        let safeDestination = min(destination, effects.count)
        effects.insert(effect, at: safeDestination)
    }

    public var activeEffects: [EffectInstance] {
        guard isEnabled else { return [] }
        return effects.filter(\.isEnabled)
    }
}
```

### Sources/EffectsEngine/EffectInstance.swift

```swift
import Foundation
import Observation
import CoreMediaPlus

/// A runtime instance of an effect with its parameter state.
@Observable
public final class EffectInstance: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let pluginID: String
    public let name: String
    public var isEnabled: Bool = true
    public var parameters: ParameterValues
    public var keyframeTracks: [String: KeyframeTrack] = [:]

    public init(id: UUID = UUID(), pluginID: String, name: String,
                defaults: [String: ParameterValue] = [:]) {
        self.id = id
        self.pluginID = pluginID
        self.name = name
        self.parameters = ParameterValues(defaults)
    }

    /// Get the interpolated parameter values at a given time.
    public func currentValues(at time: Rational) -> ParameterValues {
        var values = parameters
        for (paramName, track) in keyframeTracks {
            if let interpolated = track.value(at: time) {
                values[paramName] = interpolated
            }
        }
        return values
    }
}
```

### Sources/EffectsEngine/KeyframeTrack.swift

```swift
import Foundation
import CoreMediaPlus

/// A sequence of keyframes for a single parameter.
public struct KeyframeTrack: Sendable {
    public var keyframes: [Keyframe] = []

    public init() {}

    public struct Keyframe: Sendable {
        public var time: Rational
        public var value: ParameterValue
        public var interpolation: InterpolationType

        public init(time: Rational, value: ParameterValue,
                    interpolation: InterpolationType = .linear) {
            self.time = time
            self.value = value
            self.interpolation = interpolation
        }

        public enum InterpolationType: Sendable {
            case linear
            case hold
            case bezier(inTangent: CGPoint, outTangent: CGPoint)
        }
    }

    /// Add a keyframe, maintaining sorted order by time.
    public mutating func addKeyframe(_ keyframe: Keyframe) {
        if let index = keyframes.firstIndex(where: { $0.time >= keyframe.time }) {
            if keyframes[index].time == keyframe.time {
                keyframes[index] = keyframe
            } else {
                keyframes.insert(keyframe, at: index)
            }
        } else {
            keyframes.append(keyframe)
        }
    }

    /// Remove the keyframe closest to the given time.
    public mutating func removeKeyframe(at time: Rational) {
        keyframes.removeAll { $0.time == time }
    }

    /// Interpolate the value at a given time.
    public func value(at time: Rational) -> ParameterValue? {
        guard !keyframes.isEmpty else { return nil }
        guard keyframes.count > 1 else { return keyframes.first?.value }

        // Before first keyframe
        if time <= keyframes.first!.time { return keyframes.first!.value }
        // After last keyframe
        if time >= keyframes.last!.time { return keyframes.last!.value }

        // Find surrounding keyframes
        for i in 0..<(keyframes.count - 1) {
            let kf0 = keyframes[i]
            let kf1 = keyframes[i + 1]
            if time >= kf0.time && time < kf1.time {
                return interpolate(from: kf0, to: kf1, at: time)
            }
        }

        return keyframes.last?.value
    }

    private func interpolate(from kf0: Keyframe, to kf1: Keyframe,
                              at time: Rational) -> ParameterValue {
        switch kf0.interpolation {
        case .hold:
            return kf0.value
        case .linear, .bezier:
            let totalDuration = (kf1.time - kf0.time).seconds
            guard totalDuration > 0 else { return kf0.value }
            let elapsed = (time - kf0.time).seconds
            let t = elapsed / totalDuration

            // Linear interpolation for float values
            if case .float(let v0) = kf0.value, case .float(let v1) = kf1.value {
                return .float(v0 + (v1 - v0) * t)
            }
            // For non-float types, snap at midpoint
            return t < 0.5 ? kf0.value : kf1.value
        }
    }
}
```

---

## 7. RenderEngine Module

### Sources/RenderEngine/MetalRenderingDevice.swift

```swift
import Metal
import MetalKit
import CoreMediaPlus

/// Singleton holder for the Metal device and command queue.
/// All Metal operations flow through this shared device.
public final class MetalRenderingDevice: @unchecked Sendable {
    public static let shared = MetalRenderingDevice()

    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let defaultLibrary: (any MTLLibrary)?

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.device = device
        self.commandQueue = queue
        self.defaultLibrary = device.makeDefaultLibrary()
    }
}
```

### Sources/RenderEngine/TexturePool.swift

```swift
import Metal
import CoreMediaPlus

/// Thread-safe reusable texture pool. Reduces allocation churn during playback.
public actor TexturePool {
    private let device: any MTLDevice
    private var available: [TextureKey: [any MTLTexture]] = [:]
    private var maxPoolSize: Int = 32

    private struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }

    public init(device: any MTLDevice) {
        self.device = device
    }

    public func checkout(width: Int, height: Int,
                         pixelFormat: MTLPixelFormat = .bgra8Unorm) -> (any MTLTexture)? {
        let key = TextureKey(width: width, height: height, pixelFormat: pixelFormat)

        if var textures = available[key], let texture = textures.popLast() {
            available[key] = textures
            return texture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    public func returnTexture(_ texture: any MTLTexture) {
        let key = TextureKey(width: texture.width, height: texture.height,
                             pixelFormat: texture.pixelFormat)
        var textures = available[key] ?? []
        guard textures.count < maxPoolSize else { return }
        textures.append(texture)
        available[key] = textures
    }

    public func drain() {
        available.removeAll()
    }
}
```

### Sources/RenderEngine/CompositionBuilder.swift

```swift
import AVFoundation
import CoreMediaPlus
import EffectsEngine

/// Builds AVMutableComposition + AVVideoComposition from a timeline model.
/// This is the bridge between the editing model and AVFoundation's playback/export pipeline.
public final class CompositionBuilder: @unchecked Sendable {

    public struct CompositionResult {
        public let composition: AVMutableComposition
        public let videoComposition: AVMutableVideoComposition
        public let audioMix: AVMutableAudioMix?
    }

    public init() {}

    /// Build an AVPlayerItem from timeline data.
    public func buildPlayerItem(
        videoTracks: [TrackBuildData],
        audioTracks: [TrackBuildData],
        renderSize: CGSize,
        frameDuration: CMTime
    ) throws -> AVPlayerItem {
        let result = try buildComposition(
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            renderSize: renderSize,
            frameDuration: frameDuration
        )
        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        if let audioMix = result.audioMix {
            playerItem.audioMix = audioMix
        }
        return playerItem
    }

    /// Build the AVFoundation composition objects.
    public func buildComposition(
        videoTracks: [TrackBuildData],
        audioTracks: [TrackBuildData],
        renderSize: CGSize,
        frameDuration: CMTime
    ) throws -> CompositionResult {
        let composition = AVMutableComposition()

        // Create AVFoundation tracks and insert time ranges
        for trackData in videoTracks {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            for clip in trackData.clips {
                guard let asset = clip.asset else { continue }
                guard let sourceTrack = asset.tracks(withMediaType: .video).first else { continue }

                let insertTime = clip.startTime.cmTime
                let sourceRange = CMTimeRange(
                    start: clip.sourceIn.cmTime,
                    duration: clip.duration.cmTime
                )

                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
            }
        }

        // Build video composition with custom compositor
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.customVideoCompositorClass = MetalCompositor.self

        // Build instructions (one per unique time slice)
        // TODO: Calculate time slices and create instructions
        videoComposition.instructions = []

        return CompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: nil
        )
    }

    /// Data needed to build a track.
    public struct TrackBuildData {
        public let trackID: UUID
        public let clips: [ClipBuildData]

        public init(trackID: UUID, clips: [ClipBuildData]) {
            self.trackID = trackID
            self.clips = clips
        }
    }

    /// Data needed to build a clip.
    public struct ClipBuildData {
        public let clipID: UUID
        public let asset: AVAsset?
        public let startTime: Rational
        public let sourceIn: Rational
        public let sourceOut: Rational
        public let effectStack: EffectStack?

        public var duration: Rational { sourceOut - sourceIn }

        public init(clipID: UUID, asset: AVAsset?, startTime: Rational,
                    sourceIn: Rational, sourceOut: Rational,
                    effectStack: EffectStack? = nil) {
            self.clipID = clipID
            self.asset = asset
            self.startTime = startTime
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
            self.effectStack = effectStack
        }
    }
}
```

### Sources/RenderEngine/MetalCompositor.swift

```swift
import AVFoundation
import Metal
import CoreVideo
import CoreMediaPlus

/// Custom AVVideoCompositing implementation using Metal.
/// Pull-based: AVFoundation calls startRequest() when it needs a frame.
public final class MetalCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    public var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var supportsHDRSourceFrames: Bool { true }
    public var supportsWideColorSourceFrames: Bool { true }

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private let renderQueue = DispatchQueue(label: "com.swifteditor.compositor",
                                            qos: .userInteractive)
    private var isCancelled = false

    override public init() {
        let renderDevice = MetalRenderingDevice.shared
        self.device = renderDevice.device
        self.commandQueue = renderDevice.commandQueue
        super.init()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [self] in
            guard !isCancelled else {
                request.finishCancelledRequest()
                return
            }

            autoreleasepool {
                // Get source frames from AVFoundation
                let sourceTrackIDs = request.sourceTrackIDs
                guard !sourceTrackIDs.isEmpty else {
                    request.finish(with: NSError(domain: "MetalCompositor",
                                                  code: -1, userInfo: nil))
                    return
                }

                // For MVP: pass through the first source frame
                if let firstTrackID = sourceTrackIDs.first?.int32Value,
                   let sourceBuffer = request.sourceFrame(byTrackID: firstTrackID) {
                    request.finish(withComposedVideoFrame: sourceBuffer)
                } else {
                    request.finish(with: NSError(domain: "MetalCompositor",
                                                  code: -2, userInfo: nil))
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

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Resize texture pool if needed
    }
}
```

---

## 8. ViewerKit Module

### Sources/ViewerKit/TransportController.swift

```swift
import Foundation
import AVFoundation
import Observation
import Combine
import CoreMediaPlus

/// Transport state enum.
public enum TransportState: Sendable {
    case stopped
    case playing
    case paused
    case shuttling(speed: Double)
    case scrubbing
}

/// Controls playback of the timeline composition.
@Observable
public final class TransportController: @unchecked Sendable {
    public private(set) var currentTime: Rational = .zero
    public private(set) var transportState: TransportState = .stopped

    public var isPlaying: Bool {
        if case .playing = transportState { return true }
        return false
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private let timeSubject = CurrentValueSubject<Rational, Never>(.zero)

    public var timePublisher: AnyPublisher<Rational, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    public init() {}

    public func setPlayer(_ player: AVPlayer) {
        self.player = player
        setupTimeObserver()
    }

    public func play() {
        player?.play()
        transportState = .playing
    }

    public func pause() {
        player?.pause()
        transportState = .paused
    }

    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        currentTime = .zero
        transportState = .stopped
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
    }

    public func stepForward(frames: Int = 1, frameRate: Rational = Rational(24, 1)) {
        let frameDuration = Rational(1, 1) / frameRate
        let newTime = currentTime + frameDuration * Rational(Int64(frames), 1)
        Task { await seek(to: newTime) }
    }

    public func stepBackward(frames: Int = 1, frameRate: Rational = Rational(24, 1)) {
        let frameDuration = Rational(1, 1) / frameRate
        let newTime = currentTime - frameDuration * Rational(Int64(frames), 1)
        let clamped = newTime < .zero ? .zero : newTime
        Task { await seek(to: clamped) }
    }

    private func setupTimeObserver() {
        if let existing = timeObserver {
            player?.removeTimeObserver(existing)
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60),
            queue: .main
        ) { [weak self] cmTime in
            guard let self else { return }
            let time = Rational(cmTime)
            self.currentTime = time
            self.timeSubject.send(time)
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}
```

---

## 9. MediaManager Module

### Sources/MediaManager/AssetImporter.swift

```swift
import Foundation
import AVFoundation
import CoreMediaPlus

/// Imports media files and extracts metadata.
public final class AssetImporter: @unchecked Sendable {

    public init() {}

    /// Import media files and return metadata for each.
    public func importAssets(from urls: [URL]) async throws -> [ImportedAsset] {
        var results: [ImportedAsset] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let metadata = try await extractMetadata(from: asset, url: url)
            results.append(metadata)
        }
        return results
    }

    private func extractMetadata(from asset: AVURLAsset, url: URL) async throws -> ImportedAsset {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        var videoParams: VideoParams?
        var audioParams: AudioParams?

        for track in tracks {
            let mediaType = track.mediaType
            if mediaType == .video {
                let size = try await track.load(.naturalSize)
                videoParams = VideoParams(width: Int(size.width), height: Int(size.height))
            } else if mediaType == .audio {
                let desc = try await track.load(.formatDescriptions)
                if let first = desc.first {
                    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)
                    if let asbd = basic?.pointee {
                        audioParams = AudioParams(
                            sampleRate: Int(asbd.mSampleRate),
                            channelCount: Int(asbd.mChannelsPerFrame)
                        )
                    }
                }
            }
        }

        return ImportedAsset(
            id: UUID(),
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            duration: Rational(duration),
            videoParams: videoParams,
            audioParams: audioParams
        )
    }
}

/// Result of importing a media file.
public struct ImportedAsset: Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let duration: Rational
    public let videoParams: VideoParams?
    public let audioParams: AudioParams?
}
```

### Sources/MediaManager/ThumbnailGenerator.swift

```swift
import Foundation
import AVFoundation
import CoreMediaPlus

/// Generates thumbnail images from video assets.
public final class ThumbnailGenerator: @unchecked Sendable {

    public init() {}

    /// Generate a single thumbnail at the given time.
    public func generateThumbnail(for url: URL, at time: Rational,
                                   size: CGSize = CGSize(width: 160, height: 90)) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let (image, _) = try await generator.image(at: time.cmTime)
        return image
    }

    /// Generate a strip of thumbnails at regular intervals.
    public func generateThumbnailStrip(
        for url: URL,
        count: Int,
        size: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        generator.appliesPreferredTrackTransform = true

        let interval = CMTimeMultiplyByFloat64(duration, multiplier: 1.0 / Double(count))
        var times: [CMTime] = []
        for i in 0..<count {
            times.append(CMTimeMultiplyByFloat64(interval, multiplier: Double(i)))
        }

        var images: [CGImage] = []
        for time in times {
            if let (image, _) = try? await generator.image(at: time) {
                images.append(image)
            }
        }
        return images
    }
}
```

---

## 10. AudioEngine Module

### Sources/AudioEngine/AudioMixer.swift

```swift
import Foundation
import AVFoundation
import CoreMediaPlus

/// Multi-track audio mixer wrapping AVAudioEngine.
public final class AudioMixer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var playerNodes: [UUID: AVAudioPlayerNode] = [:]
    private let mainMixer: AVAudioMixerNode

    public init() {
        self.mainMixer = engine.mainMixerNode
    }

    /// Add a track to the mixer, returning a player node ID.
    public func addTrack(id: UUID) -> AVAudioPlayerNode {
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: mainMixer, format: nil)
        playerNodes[id] = node
        return node
    }

    /// Remove a track from the mixer.
    public func removeTrack(id: UUID) {
        guard let node = playerNodes.removeValue(forKey: id) else { return }
        engine.detach(node)
    }

    /// Set volume for a track (0.0 - 1.0).
    public func setVolume(_ volume: Float, for trackID: UUID) {
        playerNodes[trackID]?.volume = volume
    }

    /// Set pan for a track (-1.0 left, 0.0 center, 1.0 right).
    public func setPan(_ pan: Float, for trackID: UUID) {
        playerNodes[trackID]?.pan = pan
    }

    /// Start the audio engine.
    public func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    /// Stop the audio engine.
    public func stop() {
        engine.stop()
    }

    /// Install a metering tap on the main output.
    public func installMeteringTap(
        bufferSize: AVAudioFrameCount = 1024,
        handler: @escaping (Float, Float) -> Void
    ) {
        let format = mainMixer.outputFormat(forBus: 0)
        mainMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)

            var peakL: Float = 0
            var peakR: Float = 0

            if channelCount > 0 {
                for i in 0..<frameCount {
                    let sample = abs(channelData[0][i])
                    if sample > peakL { peakL = sample }
                }
            }
            if channelCount > 1 {
                for i in 0..<frameCount {
                    let sample = abs(channelData[1][i])
                    if sample > peakR { peakR = sample }
                }
            } else {
                peakR = peakL
            }

            handler(peakL, peakR)
        }
    }

    /// Remove the metering tap.
    public func removeMeteringTap() {
        mainMixer.removeTap(onBus: 0)
    }
}
```

---

## 11. App Entry Point & Menu Bar

### Sources/SwiftEditorApp/SwiftEditorApp.swift

```swift
import SwiftUI
import ProjectModel

@main
struct SwiftEditorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        DocumentGroup(newDocument: ProjectDocument()) { file in
            MainWindowView(document: file.$document, appState: appState)
        }
        .commands {
            EditCommands(appState: appState)
            TimelineCommands(appState: appState)
            ViewCommands(appState: appState)
            PlaybackCommands(appState: appState)
            MarkCommands(appState: appState)
        }

        #if os(macOS)
        Settings {
            PreferencesView()
        }
        #endif
    }
}
```

### Sources/SwiftEditorApp/AppState.swift

```swift
import Foundation
import Observation
import TimelineKit
import ViewerKit
import MediaManager
import AudioEngine
import CoreMediaPlus

/// Top-level application state shared across the window.
@Observable
final class AppState {
    var timeline = TimelineModel()
    var transport = TransportController()
    var audioMixer = AudioMixer()
    var assetImporter = AssetImporter()
    var thumbnailGenerator = ThumbnailGenerator()

    // UI state
    var timelineZoom: Double = 100.0  // pixels per second
    var isSnapEnabled: Bool = true
    var activeWorkspace: Workspace = .edit

    enum Workspace: String, CaseIterable {
        case edit = "Edit"
        case color = "Color"
        case audio = "Audio"
        case export = "Export"
    }
}
```

### Sources/SwiftEditorApp/MainWindowView.swift

```swift
import SwiftUI
import ProjectModel

struct MainWindowView: View {
    @Binding var document: ProjectDocument
    var appState: AppState

    var body: some View {
        HSplitView {
            // Left: Media Bin
            MediaBinPanel(appState: appState)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)

            VSplitView {
                // Top: Viewer
                HStack(spacing: 0) {
                    ViewerPanel(appState: appState)
                    InspectorPanel(appState: appState)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
                .frame(minHeight: 300)

                // Bottom: Timeline
                TimelinePanel(appState: appState)
                    .frame(minHeight: 200)
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
    }
}

// MARK: - Panel Stubs

struct MediaBinPanel: View {
    var appState: AppState
    var body: some View {
        VStack {
            Text("Media Bin")
                .font(.headline)
                .padding()
            Spacer()
            Text("Drop media files here")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ViewerPanel: View {
    var appState: AppState
    var body: some View {
        VStack(spacing: 0) {
            // Viewer display area
            Rectangle()
                .fill(.black)
                .overlay {
                    Text("Viewer")
                        .foregroundStyle(.white)
                }

            // Transport bar
            TransportBar(appState: appState)
                .frame(height: 40)
        }
    }
}

struct TransportBar: View {
    var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Button(action: { appState.transport.stepBackward() }) {
                Image(systemName: "backward.frame")
            }
            Button(action: {
                if appState.transport.isPlaying {
                    appState.transport.pause()
                } else {
                    appState.transport.play()
                }
            }) {
                Image(systemName: appState.transport.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { appState.transport.stepForward() }) {
                Image(systemName: "forward.frame")
            }
            Spacer()

            Text(timecodeString(appState.transport.currentTime))
                .monospacedDigit()
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal)
    }

    private func timecodeString(_ time: Rational) -> String {
        let totalSeconds = time.seconds
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int(time.frameNumber(at: Rational(24, 1))) % 24
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

struct InspectorPanel: View {
    var appState: AppState
    var body: some View {
        VStack {
            Text("Inspector")
                .font(.headline)
                .padding()
            Spacer()
            Text("Select a clip to inspect")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct TimelinePanel: View {
    var appState: AppState
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Toggle("Snap", isOn: Binding(
                    get: { appState.isSnapEnabled },
                    set: { appState.isSnapEnabled = $0 }
                ))
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()

            // Timeline content placeholder
            Rectangle()
                .fill(Color(.controlBackgroundColor))
                .overlay {
                    Text("Timeline tracks will render here (AppKit NSView)")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            Text("General preferences")
                .tabItem { Label("General", systemImage: "gear") }
            Text("Playback preferences")
                .tabItem { Label("Playback", systemImage: "play.circle") }
            Text("Export preferences")
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500, height: 300)
    }
}
```

### Sources/SwiftEditorApp/Commands/MenuCommands.swift

```swift
import SwiftUI
import CoreMediaPlus

// MARK: - Edit Menu Commands

struct EditCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandGroup(after: .undoRedo) {
            Button("Undo \(appState.timeline.undoManager.undoDescription ?? "")") {
                appState.timeline.undoManager.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!appState.timeline.undoManager.canUndo)

            Button("Redo \(appState.timeline.undoManager.redoDescription ?? "")") {
                appState.timeline.undoManager.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!appState.timeline.undoManager.canRedo)

            Divider()

            Button("Select All") { /* TODO */ }
                .keyboardShortcut("a", modifiers: .command)

            Button("Deselect All") { /* TODO */ }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Timeline Menu Commands

struct TimelineCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("Timeline") {
            Button("Add Video Track") {
                appState.timeline.requestTrackInsert(
                    at: appState.timeline.videoTracks.count, type: .video)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button("Add Audio Track") {
                appState.timeline.requestTrackInsert(
                    at: appState.timeline.audioTracks.count, type: .audio)
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])

            Divider()

            Button("Split at Playhead") {
                for clipID in appState.timeline.selection.selectedClipIDs {
                    appState.timeline.requestClipSplit(
                        clipID: clipID, at: appState.transport.currentTime)
                }
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Delete Selected") {
                for clipID in appState.timeline.selection.selectedClipIDs {
                    appState.timeline.requestClipDelete(clipID: clipID)
                }
            }
            .keyboardShortcut(.delete)

            Divider()

            Toggle("Snapping", isOn: Binding(
                get: { appState.isSnapEnabled },
                set: { appState.isSnapEnabled = $0 }
            ))
            .keyboardShortcut("n")
        }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("View") {
            ForEach(AppState.Workspace.allCases, id: \.self) { workspace in
                Button(workspace.rawValue) {
                    appState.activeWorkspace = workspace
                }
            }
            Divider()
            Button("Zoom In") { appState.timelineZoom *= 1.5 }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { appState.timelineZoom /= 1.5 }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom to Fit") { /* TODO */ }
                .keyboardShortcut("0", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Playback Menu Commands

struct PlaybackCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("Playback") {
            Button(appState.transport.isPlaying ? "Pause" : "Play") {
                if appState.transport.isPlaying {
                    appState.transport.pause()
                } else {
                    appState.transport.play()
                }
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") { appState.transport.stop() }

            Divider()

            Button("Go to Start") {
                Task { await appState.transport.seek(to: .zero) }
            }
            .keyboardShortcut(.home)

            Button("Go to End") {
                Task { await appState.transport.seek(to: appState.timeline.duration) }
            }
            .keyboardShortcut(.end)

            Divider()

            Button("Step Forward") { appState.transport.stepForward() }
                .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Step Backward") { appState.transport.stepBackward() }
                .keyboardShortcut(.leftArrow, modifiers: [])
        }
    }
}

// MARK: - Mark Menu Commands

struct MarkCommands: Commands {
    var appState: AppState

    var body: some Commands {
        CommandMenu("Mark") {
            Button("Add Marker") { /* TODO */ }
                .keyboardShortcut("m")

            Button("Set In Point") { /* TODO */ }
                .keyboardShortcut("i")

            Button("Set Out Point") { /* TODO */ }
                .keyboardShortcut("o")

            Button("Clear In/Out") { /* TODO */ }
                .keyboardShortcut("x", modifiers: [.command, .option])
        }
    }
}
```

---

## 12. Bootstrap Script

Run this to create the directory structure and placeholder files:

```bash
#!/bin/bash
# bootstrap.sh -- Create SwiftEditor project directory structure

set -e

ROOT="SwiftEditor"
mkdir -p "$ROOT"

# Source directories
MODULES=(
    "CoreMediaPlus"
    "PluginKit"
    "ProjectModel"
    "TimelineKit"
    "EffectsEngine"
    "RenderEngine"
    "ViewerKit"
    "MediaManager"
    "AudioEngine"
    "SwiftEditorApp"
    "SwiftEditorApp/Commands"
    "SwiftEditorApp/Views"
)

for mod in "${MODULES[@]}"; do
    mkdir -p "$ROOT/Sources/$mod"
done

# Test directories
TEST_MODULES=(
    "CoreMediaPlusTests"
    "ProjectModelTests"
    "TimelineKitTests"
    "EffectsEngineTests"
    "RenderEngineTests"
    "ViewerKitTests"
    "MediaManagerTests"
    "AudioEngineTests"
)

for mod in "${TEST_MODULES[@]}"; do
    mkdir -p "$ROOT/Tests/$mod"
done

# Resource directories
mkdir -p "$ROOT/Sources/SwiftEditorApp/Resources/Shaders"
mkdir -p "$ROOT/Plugins"

echo "Directory structure created at ./$ROOT/"
echo "Copy the Swift files from the scaffolding document into the appropriate directories."
```

Save the Package.swift at `SwiftEditor/Package.swift` and copy each source file into its corresponding `Sources/<ModuleName>/` directory. All files are designed to compile together as a valid SPM package targeting macOS 15+.
