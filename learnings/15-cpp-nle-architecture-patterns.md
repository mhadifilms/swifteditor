# C++ NLE Architecture Patterns: Olive, MLT Framework, and Kdenlive

## Executive Summary

This document analyzes three battle-tested C++ NLE projects to extract architectural patterns that translate to Swift. **Olive Editor** provides the most modern architecture with a node-based compositing system, GPU-accelerated rendering, and a sophisticated caching layer. **MLT Framework** (used by Shotcut, Kdenlive, and others) defines the canonical Producer/Filter/Consumer pipeline for media processing. **Kdenlive** demonstrates production-grade MLT integration, dual-playlist track model for same-track transitions, lambda-based undo/redo composition, and a hierarchical effect stack.

---

## 1. Olive Editor -- Node-Based NLE Architecture

**Repository**: https://github.com/olive-editor/olive (~4,000 stars)
**Tech stack**: C++/Qt, OpenGL (renderer abstraction), OCIO color management
**Key insight**: Everything is a Node. The timeline, clips, effects, and even the viewer output are all nodes in a directed acyclic graph. This is the most flexible NLE architecture in open source.

### 1.1 Node System -- Core Architecture

Olive's central architectural decision: **every operation is a Node**.

```
Node (QObject) -- Abstract base class
├── Inputs: QVector<QString> input_ids_      // Named input ports
├── Outputs: implicit (single output)        // Any node can be connected as output
├── Connections: map<NodeInput, Node*>       // Input → connected output node
├── Keyframes: per-input keyframe tracks
├── Caches: FrameHashCache*, AudioPlaybackCache*, ThumbnailCache*
│
├── virtual Value() = 0     // Process inputs → output values
├── virtual id() = 0        // Unique string identifier
├── virtual Name() = 0      // Display name
├── virtual Category() = 0  // Menu category
│
├── Block : Node             // A time-occupying region on a track
│   ├── in_point_, out_point_: rational   // Position on timeline
│   ├── previous_, next_: Block*          // Linked list on track
│   ├── track_: Track*
│   │
│   ├── ClipBlock : Block    // Media clip on timeline
│   │   ├── media_in_: rational           // Source media offset
│   │   ├── speed_: double                // Playback speed
│   │   ├── reverse_: bool
│   │   ├── loop_mode_: LoopMode
│   │   ├── in_transition_, out_transition_: TransitionBlock*
│   │   ├── block_links_: QVector<Block*> // Linked A/V clips
│   │   └── kBufferIn: input port for connected source node
│   │
│   ├── GapBlock : Block     // Empty space on track
│   │
│   ├── TransitionBlock : Block  // Cross-fade between clips
│   │   ├── connected_out_block_, connected_in_block_: ClipBlock*
│   │   ├── CurveType: Linear/Exponential/Logarithmic
│   │   ├── ShaderJobEvent() -- GPU-based transition rendering
│   │   └── SampleJobEvent() -- Audio cross-fade
│   │
│   └── SubtitleBlock : Block
│
├── Track : Node             // A single timeline track
│   ├── blocks_: QVector<Block*>     // Ordered by time
│   ├── type_: kVideo/kAudio/kSubtitle
│   ├── track_height_: double
│   ├── muted_, locked_: bool
│   ├── Input array: blocks as input connections
│   └── Time transform: sequence_time → block-local time
│
├── ViewerOutput : Node      // The "output" node for a sequence
│   ├── Connected to video/audio track outputs
│   └── Drives playback and rendering
│
└── Effect Nodes (filters, generators, etc.)
    ├── Color: BrightnessNode, ContrastNode, GammaNode, etc.
    ├── Distort: TransformNode, CropNode, etc.
    ├── Generator: SolidNode, TextNode, etc.
    ├── Keying: ChromaKeyNode, etc.
    ├── Math: MathNode, MergeNode, etc.
    └── Time: TimeOffsetNode, etc.
```

**Swift translation**: A protocol-oriented `Node` base with associated `Input`/`Output` types would be natural. Swift's value semantics would require careful consideration for the node graph structure.

### 1.2 Node Value System

```cpp
// NodeValue -- Type-safe value passing between nodes
class NodeValue {
    enum Type {
        kNone, kInt, kFloat, kRational, kBoolean, kColor, kMatrix, kText,
        kFont, kFile, kTexture, kSamples, kVec2, kVec3, kVec4, kBezier,
        kCombo, kVideoParams, kAudioParams, kSubtitleParams, kBinary
    };
    Type type_;
    QVariant data_;           // Actual value (type-erased)
    const Node* from_;        // Source node
    QString tag_;             // Optional tag for disambiguation
};

// NodeValueTable -- Stack-based value accumulation
// Values are pushed onto a stack as nodes process, and consumers
// pull values of specific types. This allows flexible routing.
class NodeValueTable {
    QVector<NodeValue> values_;

    NodeValue Get(Type type, const QString& tag);   // Find by type+tag
    NodeValue Take(Type type, const QString& tag);   // Find and remove
    void Push(const NodeValue& value);
    static NodeValueTable Merge(QList<NodeValueTable> tables);
};
```

**Key pattern**: The NodeValueTable is essentially a heterogeneous stack. When a node processes, it receives a table of accumulated values from upstream, picks what it needs, and pushes its results. This is much more flexible than fixed input/output types.

**Swift translation**: An enum with associated values would be cleaner:
```swift
enum NodeValue {
    case texture(TexturePtr)
    case samples(SampleBuffer)
    case float(Double)
    case color(Color)
    case matrix(Matrix4x4)
    // etc.
}
```

### 1.3 Graph Traversal and Rendering

```
NodeTraverser -- Base class for graph traversal
├── GenerateTable(node, timeRange) → NodeValueTable
│   1. For each input of the node:
│      a. If connected: recursively traverse connected output node
│      b. If keyframed: interpolate value at time
│      c. If static: use stored value
│   2. Call node.Value(inputValues, globals) → outputTable
│   3. Return outputTable
│
├── Protected virtual methods (overridden by RenderProcessor):
│   ├── ProcessVideoFootage()    // Decode video frame
│   ├── ProcessAudioFootage()    // Decode audio samples
│   ├── ProcessShader()          // Execute GPU shader
│   ├── ProcessColorTransform()  // OCIO color transform
│   ├── ProcessSamples()         // Audio DSP
│   ├── ProcessFrameGeneration() // Generate (solid, text, etc.)
│   └── ConvertToReferenceSpace() // Color space conversion
│
RenderProcessor : NodeTraverser -- Concrete renderer
├── Owns: Renderer*, DecoderCache*, ShaderCache*
├── Process(ticket, render_ctx, decoder_cache, shader_cache)
│   1. Traverse graph from output node
│   2. Resolve "jobs" into actual GPU operations
│   3. Return rendered frame/audio
└── Uses RenderTicket for async render coordination
```

**Key pattern**: The "job" abstraction. Node.Value() doesn't actually render -- it creates "jobs" (ShaderJob, FootageJob, SampleJob, etc.) that describe what needs to be done. The RenderProcessor then resolves these jobs into actual GPU/CPU operations. This separation allows:
- Graph traversal without requiring GPU context
- Caching at the job level (same job = same result)
- Different backends (OpenGL, Vulkan, software) resolving the same jobs

**Swift translation**: This maps to a two-phase approach: 1) Build a render plan (value types describing operations), 2) Execute the plan on the GPU.

### 1.4 Rendering and Caching

```
Renderer -- Abstract GPU rendering interface
├── Init() / Destroy()
├── CreateTexture(VideoParams) → TexturePtr
├── CreateNativeShader(ShaderCode) → QVariant
├── Blit(shader, ShaderJob, destination)  // Execute shader
├── BlitColorManaged(ColorTransformJob)   // OCIO transform
├── UploadToTexture() / DownloadFromTexture()
├── texture_cache_: list<CachedTexture>   // Texture pooling
└── color_cache_: map of compiled OCIO shaders

PreviewAutoCacher -- Background caching manager
├── Dynamically caches frames around playhead
├── Manages video + audio cache jobs separately
├── pending_video_jobs_ / pending_audio_jobs_
├── ForceCacheRange() for manual cache ranges
├── Uses ProjectCopier for thread-safe graph copy
└── Coordinates with RenderManager for async rendering

FrameHashCache : PlaybackCache
├── timebase_: rational
├── Validates time ranges as cached
├── Stores rendered frames to disk by timestamp
├── UUID-based cache paths per node
└── ThumbnailCache: FrameHashCache (10 FPS timebase)
```

**Key patterns for caching**:
1. **Frame hash caching**: Each frame's "hash" is determined by its node graph state. Same hash = same result = skip rendering.
2. **Disk-backed cache**: Rendered frames are persisted to disk, surviving between sessions.
3. **Background auto-caching**: PreviewAutoCacher anticipates what the user will view next and pre-renders in background threads.
4. **ProjectCopier**: The entire node graph is deep-copied for background rendering, avoiding thread contention with the UI.

### 1.5 Undo/Redo System

```cpp
// Olive's UndoCommand -- Classic command pattern
class UndoCommand {
    virtual void redo() = 0;
    virtual void undo() = 0;
    virtual Project* GetRelevantProject() const = 0;
};

// MultiUndoCommand -- Composite command
class MultiUndoCommand : public UndoCommand {
    std::vector<UndoCommand*> children_;
    void redo() override { for (auto c : children_) c->redo(); }
    void undo() override { for (auto it = children_.rbegin(); ...) (*it)->undo(); }
};
```

Olive uses traditional Command pattern with explicit redo/undo method pairs. Each timeline operation (move, trim, split, etc.) has its own UndoCommand subclass.

### 1.6 Keyframe System

```cpp
class NodeKeyframe : public QObject {
    enum Type { kLinear, kHold, kBezier };  // Interpolation type
    rational time_;
    QVariant value_;
    Type type_;
    QPointF bezier_control_in_;    // Bezier handles
    QPointF bezier_control_out_;
    NodeKeyframe* previous_;       // Linked list
    NodeKeyframe* next_;
    int track_;                    // For multi-component values (x=0, y=1, z=2)
    int element_;                  // Array element index
};
```

**Key pattern**: Keyframes belong to a specific input parameter and track (component). Multi-dimensional values (Vec2, Vec3, Color) have separate keyframe tracks per component, allowing independent easing curves per channel.

### 1.7 Patterns to Adopt from Olive

1. **Everything-is-a-Node** -- Unified processing model
2. **NodeValueTable stack** -- Flexible heterogeneous value passing
3. **Job-based deferred rendering** -- Separate graph traversal from GPU execution
4. **Frame hash caching** -- Content-addressable render cache
5. **PreviewAutoCacher** -- Anticipatory background rendering
6. **Texture pooling in Renderer** -- Reuse GPU textures
7. **ProjectCopier for thread safety** -- Deep-copy graph for background rendering
8. **Rational time** -- Exact rational arithmetic avoids floating-point errors
9. **Per-component keyframe tracks** -- Independent easing per channel
10. **Block linked list on Track** -- O(1) neighbor access, O(n) time lookup

---

## 2. MLT Framework -- The Canonical Media Processing Pipeline

**Repository**: https://github.com/mltframework/mlt (~1,600 stars)
**Used by**: Shotcut, Kdenlive, Flowblade, OpenShot, and more
**Tech stack**: C (core framework), C++ (mlt++), modular plugin system
**Key insight**: MLT's Producer/Filter/Transition/Consumer pipeline is the industry-standard abstraction for open-source video editing backends.

### 2.1 Core Service Hierarchy

```
mlt_properties (property bag -- key/value store for all metadata)
└── mlt_service (base class for all processing units)
    ├── get_frame(self, frame_ptr, index)  // Virtual: produce a frame
    ├── Connections: producer(s) → service → consumer
    ├── Filters: attachable filter chain
    │
    ├── mlt_producer : mlt_service
    │   ├── get_frame()    // Produce video/audio frame
    │   ├── seek(position) // Seek to time position
    │   ├── set_in_and_out(in, out) // Set clip boundaries
    │   ├── speed: double  // Playback speed
    │   ├── length: int    // Total duration in frames
    │   ├── position: int  // Current playhead position
    │   │
    │   ├── mlt_playlist : mlt_producer
    │   │   ├── list: playlist_entry[]  // Ordered clip entries
    │   │   ├── count: int
    │   │   ├── Operations: append, insert, remove, move, split, join, mix
    │   │   ├── Blanks: explicit gap entries
    │   │   └── A playlist IS a producer (composable)
    │   │
    │   └── mlt_multitrack : mlt_producer
    │       ├── list: mlt_track[]       // Parallel tracks
    │       ├── count: int
    │       └── Produces frames from all tracks simultaneously
    │
    ├── mlt_filter : mlt_service
    │   ├── process(filter, frame) → frame  // Modify a frame
    │   ├── in/out: position range           // Active range
    │   └── Can be "attached" to any service
    │
    ├── mlt_transition : mlt_service
    │   ├── process(transition, a_frame, b_frame) → frame
    │   ├── a_track, b_track: int     // Track indices
    │   ├── in/out: position range    // Active range
    │   └── Operates on two frames from two tracks
    │
    ├── mlt_consumer : mlt_service
    │   ├── start() / stop()
    │   ├── is_stopped()
    │   ├── purge()              // Clear buffer
    │   ├── Threading: async render thread with frame buffering
    │   ├── real_time: int       // 1=async+drop, -1=async+nodrop, 0=sync
    │   └── Implementations: SDL (preview), avformat (export), XML (save)
    │
    └── mlt_tractor : mlt_producer
        ├── multitrack: mlt_multitrack  // The parallel tracks
        ├── field: mlt_field            // Transitions and filters
        └── Orchestrates multi-track composition
```

### 2.2 Frame-Pull Architecture

MLT uses a **pull-based** data flow, not push-based:

```
Consumer.start()
    │
    │ (render thread loop)
    ▼
Consumer pulls frame from connected Producer
    │
    │ mlt_service_get_frame(tractor)
    ▼
Tractor.get_frame()
    ├── Multitrack.get_frame(index=0) → frame_a from track 0
    ├── Multitrack.get_frame(index=1) → frame_b from track 1
    │   └── Each track's Playlist.get_frame() finds active clip at position
    │       └── Clip's Producer.get_frame() decodes media
    │
    ├── For each Transition in Field:
    │   └── transition.process(frame_a, frame_b) → composited frame
    │
    ├── For each Filter attached to service:
    │   └── filter.process(frame) → modified frame
    │
    └── Return final composited frame to Consumer

Consumer.consume(frame)
    └── Display/Encode/Save
```

**Key pattern**: Pull-based means the consumer controls timing. This naturally handles:
- Frame dropping (consumer skips if too slow)
- Seeking (producer repositions on demand)
- Variable speed playback (consumer adjusts pull rate)

**Swift translation**: This pull model maps well to AVFoundation's AVVideoCompositing protocol, where the system requests frames on demand via `startRequest()`.

### 2.3 Property System

Every MLT object is also a property bag (key-value store):

```c
// Properties are the universal data carrier in MLT
mlt_properties_set(props, "width", "1920");
mlt_properties_set_int(props, "height", 1080);
mlt_properties_set_double(props, "fps", 29.97);
mlt_properties_get_data(props, "audio_buffer", &size);

// Properties on a frame carry metadata through the pipeline:
// - "width", "height", "format" -- video params
// - "frequency", "channels" -- audio params
// - "aspect_ratio" -- pixel aspect
// - Custom properties set by filters (e.g., "movement" from motion tracker)
```

**Key pattern**: Using properties for metadata passing is extremely flexible. Any filter can annotate a frame with arbitrary data that downstream filters can read. This enables loose coupling between effects.

### 2.4 Playlist -- Single-Track Clip Sequence

```c
// A playlist is an ordered list of clips (producers) with gaps (blanks)
mlt_playlist playlist = mlt_playlist_new(profile);

// Add clips
mlt_playlist_append_io(playlist, clip1, in, out);  // Clip with in/out
mlt_playlist_blank(playlist, duration);              // Gap
mlt_playlist_append(playlist, clip2);                // Full clip

// Edit operations
mlt_playlist_split(playlist, clip_index, position);  // Split at position
mlt_playlist_join(playlist, clip_index, count, merge); // Join clips
mlt_playlist_move(playlist, from, to);               // Reorder
mlt_playlist_resize_clip(playlist, clip, in, out);   // Trim
mlt_playlist_mix(playlist, clip, length, transition); // Create crossfade
mlt_playlist_insert_at(playlist, position, producer, mode); // Insert at time
mlt_playlist_remove_region(playlist, position, length);     // Remove range
```

**Key pattern**: A Playlist IS a Producer. This composability means you can nest playlists, use a playlist as a clip inside another playlist, or use it as a track in a multitrack.

### 2.5 Tractor/Multitrack -- Multi-Track Composition

```
Tractor (orchestrator)
├── Multitrack (parallel container)
│   ├── Track 0: Playlist (V1) -- bottom video
│   ├── Track 1: Playlist (V2) -- overlay
│   ├── Track 2: Playlist (A1) -- audio
│   └── Track 3: Playlist (A2) -- audio
│
├── Field (transitions + track filters)
│   ├── Transition: composite (a_track=0, b_track=1, in=100, out=200)
│   ├── Transition: luma (a_track=0, b_track=1, in=500, out=550)
│   ├── Filter: volume (track=2)
│   └── Filter: brightness (track=0)
│
└── Consumer: SDL2 (preview) or avformat (export)
```

### 2.6 Plugin/Module System

```
MLT Modules (dynamically loaded .so/.dylib):
├── core: watermark, brightness, volume, rescale, resize, transition_composite, etc.
├── avformat: FFmpeg-based producer (decoder) and consumer (encoder)
├── sdl2: SDL2-based preview consumer
├── frei0r: Frei0r effect plugin host
├── ladspa: LADSPA audio plugin host
├── sox: SoX audio effects
├── movit: GPU-accelerated effects via OpenGL
├── qt: Qt-based text, image, color producers
├── xml: XML serialization (save/load)
├── jackrack: JACK audio routing
└── opencv: OpenCV-based effects (tracking, stabilization)
```

**Key pattern**: MLT discovers plugins at runtime via a module registry. Each module registers its producers, filters, transitions, and consumers. This enables:
- Third-party effect plugins
- Optional dependency on heavy frameworks (FFmpeg, OpenCV)
- Build-time configuration of which modules to include

### 2.7 Patterns to Adopt from MLT

1. **Pull-based frame delivery** -- Consumer controls timing, natural for playback
2. **Service is-a PropertyBag** -- Universal metadata system
3. **Playlist IS a Producer** -- Composable containers
4. **Tractor/Multitrack/Field** -- Clean separation of tracks, transitions, and orchestration
5. **Filter attachment** -- Any service can have a chain of filters
6. **Module/plugin system** -- Dynamic effect discovery and registration
7. **Transition with track indices** -- Transitions reference source/destination by track number
8. **Blank entries** -- Explicit gaps in playlists simplify time calculations
9. **Cut/parent system** -- A "cut" references a parent producer with different in/out points (non-destructive)
10. **XML serialization** -- Standard save format understood by multiple editors

---

## 3. Kdenlive -- Production-Grade MLT Integration

**Repository**: https://github.com/KDE/kdenlive (~3,000 stars)
**Tech stack**: C++/Qt/KDE Frameworks, MLT for backend
**Key insight**: Kdenlive demonstrates how to build a full-featured NLE GUI on top of MLT, with sophisticated undo/redo, dual-playlist tracks for same-track transitions, and a hierarchical effect stack.

### 3.1 Timeline Model Architecture

```
TimelineModel : QAbstractItemModel
├── Implements Qt Model/View for QML timeline UI
├── m_tractor: Mlt::Tractor (the MLT backend)
├── m_allTracks: map<int, shared_ptr<TrackModel>>  // id → track
├── m_allClips: map<int, shared_ptr<ClipModel>>     // id → clip
├── m_allCompositions: map<int, shared_ptr<CompositionModel>>
├── m_groups: shared_ptr<GroupsModel>   // Clip grouping
├── m_snaps: shared_ptr<SnapModel>      // Snap points
├── m_subtitleModel: shared_ptr<SubtitleModel>
│
├── Request methods (entry points for all modifications):
│   ├── requestClipMove(clipId, trackId, position, ...)
│   ├── requestClipResize(clipId, size, right, ...)
│   ├── requestClipSplit(clipId, position)
│   ├── requestTrackInsertion(position, id, audioTrack)
│   ├── requestGroupMove(groupId, delta_track, delta_pos)
│   └── ... (all return bool indicating success)
│
└── Two-level QAbstractItemModel:
    ├── Top level rows: Tracks
    └── Second level rows: Clips within track (by id order)
        ├── Rich role system (50+ roles): StartRole, DurationRole,
        │   SpeedRole, FadeInRole, EffectsEnabledRole, etc.
        └── Provides data to QML timeline view
```

### 3.2 Lambda-Based Undo/Redo (Kdenlive's Key Innovation)

```cpp
// undohelper.hpp
using Fun = std::function<bool(void)>;

// Every modification constructs undo/redo lambdas
// PUSH_LAMBDA appends an operation to a lambda chain:
#define PUSH_LAMBDA(operation, lambda) \
    lambda = [lambda, operation]() { \
        bool v = lambda(); \
        return v && operation(); \
    };

// Usage pattern -- composing operations:
bool TimelineModel::requestClipMove(int clipId, int trackId, int position, ...) {
    Fun undo = []() { return true; };  // Identity
    Fun redo = []() { return true; };  // Identity

    // Step 1: Remove from old track
    PUSH_LAMBDA(removeClipLambda, redo);
    PUSH_FRONT_LAMBDA(insertClipLambda, undo);  // Undo inserts back

    // Step 2: Insert into new track
    PUSH_LAMBDA(insertClipLambda, redo);
    PUSH_FRONT_LAMBDA(removeClipLambda, undo);  // Undo removes

    // Step 3: Update group positions (if grouped)
    // ... more PUSH_LAMBDA calls

    // Execute redo
    bool result = redo();
    if (!result) {
        undo();  // Rollback on failure
        return false;
    }

    // Push to QUndoStack
    pCore->pushUndo(undo, redo, i18n("Move clip"));
    return true;
}

// FunctionalUndoCommand wraps lambdas for QUndoStack:
class FunctionalUndoCommand : public QUndoCommand {
    Fun m_undo, m_redo;
    bool m_undone;
    void undo() override { m_undone = true; m_undo(); }
    void redo() override { if (m_undone) m_redo(); }  // Skip first redo
};
```

**Key pattern**: Operations are composed by chaining lambdas. If any step fails, the accumulated undo lambda rolls back everything done so far. This is:
- **Self-healing**: No corruption from partial operations
- **Composable**: Complex operations built from simple ones
- **Automatic**: Undo/redo generated as a side effect of doing the operation

**Swift translation**: This maps perfectly to Swift closures:
```swift
typealias Fun = () -> Bool

func requestClipMove(clipId: Int, ...) -> Bool {
    var undo: Fun = { true }
    var redo: Fun = { true }

    // Compose operations
    let oldRedo = redo
    redo = { oldRedo() && removeClip() }

    let oldUndo = undo
    undo = { insertClipBack() && oldUndo() }

    // Execute and record
    guard redo() else { undo(); return false }
    undoStack.push(undo: undo, redo: redo)
    return true
}
```

### 3.3 Dual-Playlist Track Model

```
TrackModel
├── m_track: unique_ptr<Mlt::Tractor>  // Track-level tractor
├── Two internal playlists (for same-track transitions):
│   ├── Playlist A (index 0)
│   └── Playlist B (index 1)
│
│ Normal state: all clips in Playlist A
│
│ Same-track transition (mix):
│ Playlist A: [clip1                    ][blank  ][clip3...]
│ Playlist B: [blank         ][clip2_overlap     ][blank...]
│ Mix:         ←────transition──→
│
│ The overlapping region uses an MLT transition between playlists
│
├── m_allClips: unordered_map<int, shared_ptr<ClipModel>>
├── m_compostions: map<int, shared_ptr<CompositionModel>>  // Transitions
├── m_mixList: map<int, MixInfo>  // Same-track transition data
│
├── MixInfo:
│   ├── firstClipId, secondClipId
│   ├── firstClipInOut, secondClipInOut: pair<int,int>
│   └── mixOffset: int  // Distance from first clip out to cut
│
└── Methods:
    ├── requestClipMix()    -- Create same-track transition
    ├── deleteMix()         -- Remove transition
    ├── switchPlaylist()    -- Move clip between A/B playlists
    └── syncronizeMixes()   -- Validate playlist consistency
```

**Key pattern**: Same-track transitions (crossfades between adjacent clips on the same track) are implemented by using TWO MLT playlists per track. The overlapping clip segments are split across the two playlists, and an MLT transition composites them. This is the standard technique used by professional editors.

### 3.4 Effect Stack Model

```
EffectStackModel : AbstractTreeModel
├── Hierarchical effect stack (effects can be grouped)
├── m_service: weak_ptr<Mlt::Service>  // The MLT object we plant effects on
├── ownerId: ObjectId                   // Clip/Track that owns this stack
│
├── Operations:
│   ├── appendEffect(effectId)         // Add effect at bottom
│   ├── removeEffect(index)            // Remove by index
│   ├── moveEffect(destRow, item)      // Reorder
│   ├── setEffectStackEnabled(bool)    // Global enable/disable
│   ├── adjustFadeLength(duration, fromStart) // Adjust fade effects
│   └── importEffects(sourceStack)     // Copy from another stack
│
├── EffectItemModel : AbstractEffectItem + AssetParameterModel
│   ├── Wraps Mlt::Filter
│   ├── plant(service) / unplant(service)  // Add/remove from MLT
│   ├── Parameters exposed via AssetParameterModel
│   ├── Keyframes via KeyframeModelList
│   ├── Built-in effects (hidden transform, etc.)
│   └── Grouped effects via EffectGroupModel
│
└── AssetParameterModel
    ├── Reads effect parameters from XML metadata
    ├── Provides model for parameter editing UI
    └── Keyframe support per parameter
```

### 3.5 Groups Model

```
GroupsModel
├── Manages clip grouping (linked clips move together)
├── m_downLinks: map<int, set<int>>  // parent → children
├── m_upLink: map<int, int>          // child → parent
│
├── Operations:
│   ├── groupItems(ids) → groupId
│   ├── ungroupItem(id)
│   ├── getDirectChildren(groupId) → set<int>
│   ├── getRootId(id) → int  // Find top-level group
│   └── getLeaves(groupId) → set<int>  // All clips in group
│
└── Used by TimelineModel for group moves, splits, etc.
```

### 3.6 Snap Model

```
SnapModel
├── m_snaps: map<int, int>  // position → reference_count
│
├── addPoint(position)      // Add snap target
├── removePoint(position)   // Remove snap target
├── getClosestPoint(position) → int  // Find nearest snap
│
└── Snap sources: clip edges, playhead, markers, guides
```

### 3.7 Proxy Workflow

Kdenlive supports a proxy workflow where lower-resolution versions of media files are used during editing for better performance:

- **Bin clip level**: Each bin clip can have an associated proxy file
- **Automatic generation**: Proxies are generated in background using MLT consumers
- **Seamless switching**: Timeline model tracks whether clips use proxies via `IsProxyRole`
- **Export uses originals**: When rendering, proxies are swapped back to original media
- **Per-project settings**: Proxy dimensions, codec, and auto-generation rules

### 3.8 Patterns to Adopt from Kdenlive

1. **Lambda-based undo/redo composition** -- PUSH_LAMBDA pattern for automatic undo
2. **Dual-playlist per track** -- Enables same-track transitions
3. **Hierarchical effect stack** -- TreeModel for grouped/nested effects
4. **Request pattern** -- All modifications go through `requestXxx()` methods that validate and compose
5. **QAbstractItemModel for timeline** -- Efficient Qt Model/View for large timelines
6. **Groups model** -- Separate concern for clip grouping
7. **Snap model** -- Reference-counted snap points
8. **Proxy workflow** -- Transparent low-res editing with full-res export
9. **MixInfo struct** -- Clean data model for same-track transitions
10. **ObjectId ownership** -- Effect stacks know their owner (clip/track) for targeting

---

## 4. Cross-Project Comparison

### 4.1 Core Architecture Philosophy

| Aspect | Olive | MLT | Kdenlive |
|--------|-------|-----|----------|
| Core model | Node graph (DAG) | Service pipeline (pull) | MLT + Qt Model/View |
| Data flow | Push-based traversal | Pull-based (consumer drives) | MLT pull + request pattern |
| Extensibility | Node subclasses | Dynamic modules (.so) | MLT modules + asset metadata |
| Time representation | `rational` (exact) | `mlt_position` (int frames) | Frames (int) via MLT |
| Threading | Background ProjectCopier | Consumer render thread | MLT threads + Qt signals |
| GPU rendering | Abstract Renderer (OpenGL) | movit module (optional) | MLT (CPU default) |

### 4.2 Timeline Model

| Aspect | Olive | MLT | Kdenlive |
|--------|-------|-----|----------|
| Track | Node with Block array | Playlist (sequential) | Dual-playlist Tractor |
| Clip | ClipBlock node | Producer (or cut) | ClipModel wrapping Mlt::Producer |
| Gap | GapBlock node | Blank entry in playlist | Blank in MLT playlist |
| Transition | TransitionBlock node | mlt_transition on field | CompositionModel + MixInfo |
| Multi-track | Node connections | Multitrack + Tractor | MLT Tractor via TimelineModel |
| Same-track trans. | TransitionBlock between clips | playlist.mix() | Dual-playlist technique |

### 4.3 Undo/Redo

| Aspect | Olive | MLT | Kdenlive |
|--------|-------|-----|----------|
| Pattern | Command pattern (classes) | N/A (framework only) | Lambda composition |
| Granularity | Per-operation commands | N/A | Per-operation lambdas |
| Composition | MultiUndoCommand | N/A | PUSH_LAMBDA chaining |
| Failure handling | Manual | N/A | Automatic rollback |

### 4.4 Effect System

| Aspect | Olive | MLT | Kdenlive |
|--------|-------|-----|----------|
| Effect model | Node in graph | Filter attached to service | EffectItemModel wrapping Mlt::Filter |
| Parameters | Node inputs | Properties | AssetParameterModel |
| Keyframes | NodeKeyframe linked list | Properties + animation API | KeyframeModelList |
| Ordering | Node graph topology | Filter chain order | EffectStackModel tree |
| GPU effects | ShaderJob via Renderer | movit module | Via MLT (CPU or movit) |

---

## 5. Synthesis: Patterns for Our Swift NLE

### 5.1 Highest-Value Patterns to Adopt

**From Olive:**
- **Rational time arithmetic** -- Prevents floating-point errors in timeline calculations
- **Job-based rendering** -- Separate graph traversal from GPU execution
- **Frame hash caching** -- Content-addressable render cache for instant previews
- **Background auto-caching** -- Anticipatory rendering around playhead
- **Texture pooling** -- Reuse Metal textures to reduce allocation overhead
- **Node value types** -- Typed values flowing through processing graph

**From MLT:**
- **Pull-based frame delivery** -- Aligns with AVFoundation's AVVideoCompositing
- **Playlist-is-a-Producer** -- Composable timeline containers
- **Filter attachment chain** -- Any clip/track can have ordered effect list
- **Property bag metadata** -- Loose coupling between processing stages
- **Module/plugin discovery** -- Dynamic effect registration

**From Kdenlive:**
- **Lambda-based undo/redo** -- The most elegant undo system in any open-source NLE
- **Dual-playlist tracks** -- Essential for same-track transitions
- **Request pattern** -- Single entry point for all modifications with validation
- **QAbstractItemModel** -- Maps to SwiftUI's identifiable/observable patterns
- **Groups and snaps** -- Separate models for cross-cutting concerns
- **Proxy workflow** -- Critical for professional video editing

### 5.2 Recommended Architecture Combining All Three

```
Swift NLE Architecture (informed by C++ NLEs):
═══════════════════════════════════════════════

┌─ SwiftUI / AppKit Layer ─────────────────────────────────┐
│  Timeline view backed by TimelineModel (observable)       │
│  Node graph editor view (like Olive's)                    │
│  Inspector with EffectStackModel binding                  │
└────────────┬─────────────────────────────────────────────┘
             │
┌─ Edit Model Layer (Kdenlive patterns) ───────────────────┐
│  TimelineModel: ObservableObject                          │
│  ├── request*() methods (single entry point)              │
│  ├── Lambda undo/redo composition                         │
│  ├── GroupsModel for clip grouping                        │
│  └── SnapModel for snap points                            │
│                                                           │
│  TrackModel with dual-playlist for same-track transitions │
│  ClipModel with EffectStackModel                          │
│  Rational time arithmetic throughout                      │
└────────────┬─────────────────────────────────────────────┘
             │
┌─ Composition Engine (Olive + Cabbage patterns) ──────────┐
│  Node-based processing graph                              │
│  NodeValue typed value system                             │
│  Job-based deferred rendering                             │
│  NodeTraverser → RenderProcessor                          │
│  Pull-based frame delivery (AVVideoCompositing)           │
└────────────┬─────────────────────────────────────────────┘
             │
┌─ Render Layer (Olive + GPUImage3 patterns) ──────────────┐
│  Abstract Renderer protocol                               │
│  Metal implementation with texture pooling                 │
│  Frame hash caching (disk-backed)                         │
│  PreviewAutoCacher for background rendering               │
│  Project deep-copy for thread-safe background render      │
│  ShaderJob execution via Metal compute/render pipeline    │
└────────────┬─────────────────────────────────────────────┘
             │
┌─ Plugin System (MLT patterns) ───────────────────────────┐
│  Effect registry with dynamic discovery                   │
│  Filter protocol: process(frame, time) → frame            │
│  Transition protocol: process(a, b, progress) → frame     │
│  Generator protocol: generate(time, size) → frame         │
│  Property-bag metadata passing through pipeline           │
└───────────────────────────────────────────────────────────┘
```

### 5.3 Critical Implementation Details

**Rational time (from Olive)**:
```swift
struct Rational: Comparable, Hashable {
    let numerator: Int64
    let denominator: Int64
    // Exact arithmetic -- no floating point errors
    // Essential for frame-accurate editing
}
```

**Lambda undo/redo (from Kdenlive)**:
```swift
typealias UndoAction = () -> Bool

func requestClipMove(_ clipId: Int, to trackId: Int, at position: Rational) -> Bool {
    var undo: UndoAction = { true }
    var redo: UndoAction = { true }

    // Each step appends to undo/redo chains
    guard appendRemoveFromOldTrack(&undo, &redo, clipId) else { return false }
    guard appendInsertToNewTrack(&undo, &redo, clipId, trackId, position) else {
        undo()  // Automatic rollback
        return false
    }

    guard redo() else { undo(); return false }
    undoManager.record(undo: undo, redo: redo, description: "Move Clip")
    return true
}
```

**Job-based rendering (from Olive)**:
```swift
// Phase 1: Traverse graph, collect jobs
enum RenderJob {
    case decodeVideo(asset: AVAsset, time: Rational)
    case decodeAudio(asset: AVAsset, range: TimeRange)
    case shader(code: ShaderCode, inputs: [String: Any])
    case colorTransform(source: ColorSpace, dest: ColorSpace)
    case composite(layers: [TextureRef], blendModes: [BlendMode])
}

// Phase 2: Execute jobs on Metal
protocol RenderExecutor {
    func execute(_ job: RenderJob) async throws -> RenderResult
}
```
