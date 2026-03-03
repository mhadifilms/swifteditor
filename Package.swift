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
        .library(name: "CommandBus", targets: ["CommandBus"]),
        .library(name: "SwiftEditorAPI", targets: ["SwiftEditorAPI"]),
        .library(name: "CollaborationKit", targets: ["CollaborationKit"]),
        .library(name: "AIFeatures", targets: ["AIFeatures"]),
        .library(name: "InterchangeKit", targets: ["InterchangeKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
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

        // ── Command Infrastructure ───────────────────────
        .target(
            name: "CommandBus",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/CommandBus"
        ),
        .testTarget(
            name: "CommandBusTests",
            dependencies: ["CommandBus"],
            path: "Tests/CommandBusTests"
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

        // ── Collaboration Layer ─────────────────────────────
        .target(
            name: "CollaborationKit",
            dependencies: ["CoreMediaPlus", "TimelineKit"],
            path: "Sources/CollaborationKit"
        ),
        .testTarget(
            name: "CollaborationKitTests",
            dependencies: ["CollaborationKit"],
            path: "Tests/CollaborationKitTests"
        ),

        // ── AI Features Layer ──────────────────────────────
        .target(
            name: "AIFeatures",
            dependencies: ["CoreMediaPlus"],
            path: "Sources/AIFeatures"
        ),
        .testTarget(
            name: "AIFeaturesTests",
            dependencies: ["AIFeatures"],
            path: "Tests/AIFeaturesTests"
        ),

        // ── Interchange Layer ──────────────────────────────
        .target(
            name: "InterchangeKit",
            dependencies: ["CoreMediaPlus", "TimelineKit", "ProjectModel"],
            path: "Sources/InterchangeKit"
        ),
        .testTarget(
            name: "InterchangeKitTests",
            dependencies: ["InterchangeKit"],
            path: "Tests/InterchangeKitTests"
        ),

        // ── Public API Layer ─────────────────────────────
        .target(
            name: "SwiftEditorAPI",
            dependencies: [
                "CoreMediaPlus",
                "CommandBus",
                "ProjectModel",
                "TimelineKit",
                "EffectsEngine",
                "RenderEngine",
                "ViewerKit",
                "MediaManager",
                "AudioEngine",
                "PluginKit",
                "CollaborationKit",
                "AIFeatures",
                "InterchangeKit",
            ],
            path: "Sources/SwiftEditorAPI"
        ),
        .testTarget(
            name: "SwiftEditorAPITests",
            dependencies: ["SwiftEditorAPI"],
            path: "Tests/SwiftEditorAPITests"
        ),

        // ── macOS Application ──────────────────────────────
        .executableTarget(
            name: "SwiftEditorApp",
            dependencies: [
                "SwiftEditorAPI",
                "CoreMediaPlus",
                "ProjectModel",
                "TimelineKit",
                "ViewerKit",
                "RenderEngine",
                "MediaManager",
                "AudioEngine",
                "CommandBus",
                "EffectsEngine",
            ],
            path: "Sources/SwiftEditorApp",
            exclude: ["Resources"]
        ),

        // ── CLI Tool ────────────────────────────────────────
        .executableTarget(
            name: "SwiftEditorCLI",
            dependencies: [
                "SwiftEditorAPI",
                "CoreMediaPlus",
                "CommandBus",
                "TimelineKit",
                "ProjectModel",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwiftEditorCLI"
        ),
    ]
)
