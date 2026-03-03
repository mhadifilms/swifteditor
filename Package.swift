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
            ],
            path: "Sources/SwiftEditorApp"
        ),
    ]
)
