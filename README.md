# SwiftEditor

An open-source research project exploring how to build a professional non-linear video editor (NLE) entirely in Swift. Think DaVinci Resolve — timeline editing, color grading, effects, audio mixing, export — built from the ground up as reusable SPM modules with a fully programmable API that enables **agentic video editing**.

> **Status:** Research & development. 187 Swift files, 30k+ lines, 270 tests passing. macOS 15+, Swift 6 strict concurrency.

## Why This Exists

There is no comprehensive open-source reference for building a professional video editor in Swift. This project fills that gap — 31 research documents covering every aspect of NLE construction, paired with a working implementation that proves the concepts.

Every line of code is written to answer: *"How would you actually build this?"*

## Three Core Ideas

### 1. Open-Source NLE Research

The `research/` directory contains 31 deep-dive documents covering:

| Topic | Files |
|---|---|
| Architecture & framework design | `00`, `11`, `27` |
| AVFoundation & Core Media | `01`, `19` |
| Metal rendering & shaders | `02`, `14`, `20` |
| Timeline UI implementation | `03`, `23` |
| Effects, transitions, compositing | `04`, `10` |
| Audio engine & multitrack | `05` |
| Export, codecs, delivery | `06`, `18` |
| UI/UX & panel system | `08` |
| Media management | `09` |
| Editing paradigm (16 operations) | `30` |
| AI/ML, collaboration, interchange | `17`, `22` |
| Distribution, security, testing | `21`, `25`, `28` |
| Competitive analysis | `07`, `12`, `13`, `15`, `26` |
| Emerging formats (spatial, 360) | `29` |

### 2. Reusable SPM Modules

SwiftEditor is not a monolith. It's 14 independent libraries and 2 executables, each usable on its own:

```
CoreMediaPlus       Rational time, TimeRange, VideoParams — the shared vocabulary
PluginKit           Protocol definitions for video/audio effects and generators
ProjectModel        Document model with Codable serialization and versioning
TimelineKit         Timeline editing model, undo/redo, snap, selection, 16 edit operations
EffectsEngine       Keyframes, CIFilter host, transitions, node-based compositing graph
RenderEngine        Metal compositor, texture pool, frame cache, background renderer
ViewerKit           Playback controller, transport, scrubbing, JKL shuttle
MediaManager        Import, proxy generation, thumbnails, media bin management
AudioEngine         AVAudioEngine mixing, metering, waveform generation
CommandBus          Actor-based command dispatcher, undo/redo, serialization, middleware
CollaborationKit    CRDT primitives (LWW registers, RGA sequences) for real-time collab
AIFeatures          Scene detection, object tracking, transcription, smart edit suggestions
InterchangeKit      FCPXML and EDL import/export
SwiftEditorAPI      Facade layer — 397 public methods exposing everything through one engine
```

Pick what you need. Building a timeline editor? Use `TimelineKit` + `CommandBus`. Need Metal compositing? Grab `RenderEngine` + `EffectsEngine`. Want the full stack? Import `SwiftEditorAPI`.

### 3. API-First — Built for Agentic Editing

This is the core architectural bet: **every operation in the editor is API-controllable**. The UI is a thin consumer of the same API that a script, CLI tool, test suite, or AI agent would use.

```swift
import SwiftEditorAPI

let engine = SwiftEditorEngine(projectName: "My Film")

// Create timeline structure
let videoTrack = try await engine.editing.addVideoTrack()
let audioTrack = try await engine.editing.addAudioTrack()

// Add clips
try await engine.editing.addClip(
    assetURL: footageURL,
    trackID: videoTrack.id,
    at: .zero,
    duration: Rational(seconds: 10)
)

// Edit operations — all 16 NLE operations available
try await engine.editing.splitClip(clipID: clipID, atTime: Rational(seconds: 5))
try await engine.editing.rippleDelete(clipID: secondHalf)
try await engine.editing.insertEdit(sourceURL: bRollURL, at: Rational(seconds: 3))

// Effects and color grading
try await engine.effects.addEffect(to: clipID, effectID: "colorCorrection")
try await engine.colorGrading.setLiftGammaGain(
    clipID: clipID, lift: SIMD3(0, 0, 0.1), gamma: .one, gain: .one
)
try await engine.colorGrading.loadLUT(clipID: clipID, url: lutFileURL)

// Audio mixing
try await engine.audioEffects.addEffect(to: audioTrack.id, type: .compressor)
try await engine.audio.setTrackVolume(trackID: audioTrack.id, volume: 0.8)

// Export
try await engine.export.exportTimeline(to: outputURL, preset: .h264_1080p)

// Undo everything
while engine.canUndo {
    try await engine.undo()
}
```

The command system is fully serializable — every operation round-trips through JSON, enabling command journaling, network replay, and scripted automation:

```swift
// Serialize any command to JSON
let json = try CommandSerializer.encode(command)

// Replay from a script
let restored = try CommandSerializer.decode(from: jsonData)
try await engine.dispatch(restored)
```

**What this enables:**
- AI agents that edit video programmatically
- Automated pipelines (batch processing, template-based editing)
- Remote control over network (built-in HTTP server)
- Comprehensive testing without UI interaction
- CLI tool (`SwiftEditorCLI`) with the same capabilities as the GUI

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Consumers                             │
│  SwiftUI App  │  CLI Tool  │  Tests  │  AI Agent  │ ... │
└───────────────┴────────────┴─────────┴────────────┴─────┘
                          │
                          ▼
              ┌──────────────────────┐
              │   SwiftEditorAPI     │   397 public methods
              │   SwiftEditorEngine  │   Single entry point
              └──────────┬───────────┘
                         │
              ┌──────────▼───────────┐
              │     CommandBus       │   Dispatch, undo/redo,
              │  CommandDispatcher   │   serialization, middleware
              └──────────┬───────────┘
                         │
        ┌────────┬───────┼───────┬────────┬─────────┐
        ▼        ▼       ▼       ▼        ▼         ▼
   Timeline  Render  Effects  Viewer   Audio    Media
     Kit     Engine  Engine    Kit     Engine   Manager
        │        │       │               │
        ▼        ▼       ▼               ▼
      Project  CoreMediaPlus          PluginKit
      Model     (shared types)
```

Every arrow goes through commands. The UI never talks to domain modules directly.

## Building

Requires **macOS 26** (Tahoe) with Xcode 26+ for Liquid Glass APIs. Builds and runs on macOS 15+ with graceful fallbacks.

```bash
# Build everything
swift build

# Run tests (270 tests, 44 suites)
swift test

# Build release
swift build -c release

# Run the CLI
swift run SwiftEditorCLI --help
```

## Project Structure

```
SwiftEditor/
├── Sources/
│   ├── CoreMediaPlus/          # Shared types (Rational, TimeRange, VideoParams)
│   ├── PluginKit/              # Plugin protocol definitions
│   ├── ProjectModel/           # Document model, serialization
│   ├── TimelineKit/            # Timeline editing, undo/redo, 16 edit ops
│   ├── EffectsEngine/          # Effects, keyframes, node graph
│   ├── RenderEngine/           # Metal compositor, texture pool
│   ├── ViewerKit/              # Playback, transport, scrubbing
│   ├── MediaManager/           # Import, proxies, thumbnails
│   ├── AudioEngine/            # AVAudioEngine mixing, metering
│   ├── CommandBus/             # Command dispatch, serialization
│   ├── CollaborationKit/       # CRDT types for real-time collab
│   ├── AIFeatures/             # Scene detection, tracking, transcription
│   ├── InterchangeKit/         # FCPXML/EDL import and export
│   ├── SwiftEditorAPI/         # Public facade (397 methods)
│   ├── SwiftEditorApp/         # macOS application (SwiftUI + AppKit)
│   └── SwiftEditorCLI/         # Command-line tool
├── Tests/                      # 270 tests across 44 suites
├── Examples/                   # Sample plugin project
├── research/                   # 31 deep-dive research documents
└── Package.swift
```

## Research Documents

The full research library is in `research/`. Start with:

- **`00-master-blueprint.md`** — Master synthesis with phases, risks, and performance targets
- **`11-architecture-framework-design.md`** — Module architecture, protocols, state management
- **`30-editing-paradigm-operations.md`** — All 16 NLE edit operations with behavioral specs
- **`02-metal-rendering-pipeline.md`** — Metal setup, shaders, triple buffering, HDR
- **`27-starter-code-scaffolding.md`** — Starter code, Package.swift, core type definitions

## License

MIT
