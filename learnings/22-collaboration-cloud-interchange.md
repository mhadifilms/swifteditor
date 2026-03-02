# Collaboration, Cloud Workflows & Project Interchange for Professional NLE

## Table of Contents

1. [Real-Time Collaborative Editing (CRDT/OT for Timeline Ops)](#1-real-time-collaborative-editing)
2. [Cloud Rendering Architecture](#2-cloud-rendering-architecture)
3. [Project Interchange Formats — FCPXML Deep Dive](#3-project-interchange-formats--fcpxml-deep-dive)
4. [Project Interchange — AAF (Advanced Authoring Format)](#4-project-interchange--aaf)
5. [Project Interchange — OpenTimelineIO (Pixar/ASWF)](#5-project-interchange--opentimelineio)
6. [Project Interchange — EDL (CMX3600)](#6-project-interchange--edl-cmx3600)
7. [Version Control for NLE Projects](#7-version-control-for-nle-projects)
8. [Asset Management at Scale](#8-asset-management-at-scale)
9. [Review & Approval Workflows (Frame.io-Style)](#9-review--approval-workflows)
10. [Putting It All Together — Collaborative NLE Architecture](#10-putting-it-all-together)

---

## 1. Real-Time Collaborative Editing

### The Problem: Concurrent Timeline Edits

When multiple editors work on the same timeline simultaneously, their operations can conflict. For example:
- Editor A inserts a clip at position 5s while Editor B deletes the clip at position 3s
- Editor A trims a clip's out-point while Editor B applies an effect to the same clip
- Editor A moves a clip on track 1 while Editor B splits it

Traditional lock-based approaches (Avid's bin locking) prevent conflicts but limit collaboration. Modern approaches use CRDTs or OT to allow truly concurrent editing.

### CRDTs vs Operational Transformation

| Feature | CRDT | OT |
|---------|------|----|
| Server requirement | No (peer-to-peer possible) | Yes (central server) |
| Offline support | Excellent (merge on reconnect) | Weak (requires server) |
| Consistency guarantee | Eventual, automatic | Immediate with server |
| Complexity | Complex data structures | Complex transformation functions |
| Ordering | Happens-before partial order | Server-imposed total order |
| Latency | Low (local-first) | Medium (round-trip to server) |
| Used by | Figma, Apple Notes, Linear | Google Docs (original) |

**Recommendation for NLE**: CRDTs are the better fit because:
1. Local-first editing (no lag when editing)
2. Offline support (edit on plane, merge later)
3. No single point of failure
4. Natural fit for the timeline's list-like structure

### Modeling NLE Timeline Operations as CRDTs

The NLE timeline is fundamentally a **sequence of clips on tracks**. This maps well to sequence CRDTs (like RGA or Yjs's Y.Array):

```swift
import Foundation

// MARK: — Timeline CRDT Data Model

/// Unique identifier for each element, combining site ID and logical clock.
struct CRDTIdentifier: Codable, Hashable, Comparable {
    let siteID: UUID       // Which user/device created this
    let clock: UInt64      // Lamport timestamp at creation

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.clock != rhs.clock { return lhs.clock < rhs.clock }
        return lhs.siteID.uuidString < rhs.siteID.uuidString
    }
}

/// A single operation on the timeline CRDT.
enum TimelineOperation: Codable {
    // Clip operations
    case insertClip(id: CRDTIdentifier, afterID: CRDTIdentifier?, trackID: CRDTIdentifier, clip: ClipData)
    case deleteClip(id: CRDTIdentifier)
    case moveClip(id: CRDTIdentifier, afterID: CRDTIdentifier?, toTrackID: CRDTIdentifier)

    // Property operations (Last-Writer-Wins Register)
    case setClipProperty(clipID: CRDTIdentifier, key: String, value: PropertyValue, timestamp: UInt64)

    // Track operations
    case insertTrack(id: CRDTIdentifier, afterID: CRDTIdentifier?, kind: TrackKind)
    case deleteTrack(id: CRDTIdentifier)

    // Time operations
    case trimClipStart(clipID: CRDTIdentifier, newInPoint: RationalTime, timestamp: UInt64)
    case trimClipEnd(clipID: CRDTIdentifier, newOutPoint: RationalTime, timestamp: UInt64)
}

/// Serializable clip data (the content of a clip, not its position).
struct ClipData: Codable {
    let assetID: String
    let sourceIn: RationalTime
    let sourceOut: RationalTime
    let speed: Double
    let effects: [EffectData]
}

struct RationalTime: Codable {
    let value: Int64
    let timescale: Int32
}

struct EffectData: Codable {
    let effectID: String
    let parameters: [String: Double]
}

enum PropertyValue: Codable {
    case double(Double)
    case string(String)
    case bool(Bool)
    case color(r: Double, g: Double, b: Double, a: Double)
}

enum TrackKind: Codable {
    case video
    case audio
    case subtitle
}
```

### RGA-Based Sequence CRDT for Track Clips

The Replicated Growable Array (RGA) is ideal for the ordered list of clips on a track:

```swift
/// RGA (Replicated Growable Array) node for the clip sequence on a track.
/// Each node has a unique ID and a reference to the node it was inserted after.
final class RGANode<T: Codable>: Codable {
    let id: CRDTIdentifier
    let afterID: CRDTIdentifier?  // Which node this was inserted after (nil = head)
    var value: T?                  // nil = tombstoned (deleted)
    var isDeleted: Bool

    init(id: CRDTIdentifier, afterID: CRDTIdentifier?, value: T) {
        self.id = id
        self.afterID = afterID
        self.value = value
        self.isDeleted = false
    }
}

/// An RGA sequence representing the clips on a single track.
/// Supports concurrent inserts and deletes without conflicts.
final class RGASequence<T: Codable> {
    private var nodes: [CRDTIdentifier: RGANode<T>] = [:]
    private var head: CRDTIdentifier?  // First node
    private var ordering: [CRDTIdentifier] = []  // Sorted order cache

    /// Insert a new element after a given position.
    /// If two users insert after the same element concurrently,
    /// the one with the higher (siteID, clock) wins and goes first.
    func insert(id: CRDTIdentifier, afterID: CRDTIdentifier?, value: T) {
        let node = RGANode(id: id, afterID: afterID, value: value)
        nodes[id] = node

        // Find insertion index
        if let afterID = afterID, let afterIndex = ordering.firstIndex(of: afterID) {
            // Insert after the referenced node, but before any concurrent
            // inserts with lower priority
            var insertIndex = afterIndex + 1
            while insertIndex < ordering.count {
                let existingID = ordering[insertIndex]
                guard let existing = nodes[existingID] else { break }
                // If existing node was also inserted after the same node,
                // compare by ID to determine priority (higher ID wins)
                if existing.afterID == afterID && existingID > id {
                    insertIndex += 1
                } else {
                    break
                }
            }
            ordering.insert(id, at: insertIndex)
        } else {
            // Insert at head — same priority logic applies
            var insertIndex = 0
            while insertIndex < ordering.count {
                let existingID = ordering[insertIndex]
                guard let existing = nodes[existingID] else { break }
                if existing.afterID == nil && existingID > id {
                    insertIndex += 1
                } else {
                    break
                }
            }
            ordering.insert(id, at: insertIndex)
        }
    }

    /// Delete an element (tombstone — don't remove, mark as deleted).
    func delete(id: CRDTIdentifier) {
        nodes[id]?.isDeleted = true
        nodes[id]?.value = nil
    }

    /// Get the live (non-tombstoned) elements in order.
    var liveElements: [(id: CRDTIdentifier, value: T)] {
        ordering.compactMap { id in
            guard let node = nodes[id], !node.isDeleted, let value = node.value else { return nil }
            return (id, value)
        }
    }

    /// Merge operations from a remote peer.
    func merge(operations: [TimelineOperation]) {
        for op in operations {
            switch op {
            case .insertClip(let id, let afterID, _, let clip):
                insert(id: id, afterID: afterID, value: clip as! T)
            case .deleteClip(let id):
                delete(id: id)
            default:
                break
            }
        }
    }
}
```

### Using Automerge for Swift-Native CRDT

[Automerge-Swift](https://github.com/automerge/automerge-swift) provides production-ready CRDTs with native Swift bindings:

```swift
import Automerge

/// NLE project document using Automerge CRDT.
final class CollaborativeProject {
    private var document: Document

    init() {
        document = Document()
    }

    /// Initialize from sync'd data.
    init(data: Data) throws {
        document = try Document(data)
    }

    // MARK: — Timeline Structure

    /// Create the initial timeline structure in the document.
    func initializeTimeline() throws {
        // Root object
        let root = document.root

        // Tracks list (Automerge List — sequence CRDT)
        try document.put(obj: root, key: "tracks", value: .List)

        // Project metadata (Automerge Map — LWW register per key)
        try document.put(obj: root, key: "metadata", value: .Map)
        let metadata = try document.get(obj: root, key: "metadata")!
        try document.put(obj: metadata, key: "name", value: .String("Untitled"))
        try document.put(obj: metadata, key: "frameRate", value: .F64(24.0))
        try document.put(obj: metadata, key: "width", value: .Int(1920))
        try document.put(obj: metadata, key: "height", value: .Int(1080))
    }

    /// Add a track to the timeline.
    func addTrack(name: String, kind: String) throws -> ObjId {
        let root = document.root
        let tracks = try document.get(obj: root, key: "tracks")!
        let trackCount = try document.length(obj: tracks)

        // Insert a new map at the end of the tracks list
        try document.insert(obj: tracks, index: trackCount, value: .Map)
        let track = try document.get(obj: tracks, index: trackCount)!

        try document.put(obj: track, key: "name", value: .String(name))
        try document.put(obj: track, key: "kind", value: .String(kind))
        try document.put(obj: track, key: "clips", value: .List)

        return track
    }

    /// Insert a clip on a track at a given index.
    func insertClip(
        onTrack trackObj: ObjId,
        atIndex index: UInt64,
        assetID: String,
        sourceIn: Double,
        sourceOut: Double
    ) throws {
        let clips = try document.get(obj: trackObj, key: "clips")!
        try document.insert(obj: clips, index: index, value: .Map)
        let clip = try document.get(obj: clips, index: index)!

        try document.put(obj: clip, key: "assetID", value: .String(assetID))
        try document.put(obj: clip, key: "sourceIn", value: .F64(sourceIn))
        try document.put(obj: clip, key: "sourceOut", value: .F64(sourceOut))
        try document.put(obj: clip, key: "speed", value: .F64(1.0))
        try document.put(obj: clip, key: "effects", value: .List)
    }

    /// Update a clip property (LWW — last writer wins).
    func updateClipProperty(
        clip clipObj: ObjId,
        key: String,
        value: Automerge.Value
    ) throws {
        try document.put(obj: clipObj, key: key, value: value)
    }

    // MARK: — Sync

    /// Generate sync message to send to a peer.
    func generateSyncMessage(for state: inout SyncState) -> Data? {
        return document.generateSyncMessage(state: &state)
    }

    /// Receive sync message from a peer.
    func receiveSyncMessage(_ data: Data, state: inout SyncState) throws {
        try document.receiveSyncMessage(state: &state, message: data)
    }

    /// Export document as binary data for storage.
    func save() -> Data {
        return document.save()
    }

    /// Get changes since a given set of heads (for undo/history).
    func changesSince(_ heads: [ChangeHash]) -> [Change] {
        return document.getChanges(since: heads)
    }
}
```

### Network Sync Layer

```swift
import Foundation
import Network

/// WebSocket-based sync transport for collaborative editing.
final class CollaborativeSyncManager {
    private let project: CollaborativeProject
    private var syncStates: [UUID: SyncState] = [:]  // Per-peer sync state
    private var webSocket: URLSessionWebSocketTask?
    private let peerID = UUID()

    // Presence tracking
    struct PeerPresence: Codable {
        let peerID: UUID
        let displayName: String
        let color: String       // Assigned cursor color
        let playheadTime: Double
        let selectedClipIDs: [String]
        let isOnline: Bool
    }

    var onPeersUpdated: (([PeerPresence]) -> Void)?
    var onRemoteChange: (() -> Void)?

    init(project: CollaborativeProject) {
        self.project = project
    }

    /// Connect to the collaboration server.
    func connect(to url: URL) {
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessages()
        sendSyncMessage()
    }

    /// Send local changes to all peers.
    func syncLocalChanges() {
        sendSyncMessage()
    }

    /// Broadcast presence (playhead position, selection, etc.)
    func broadcastPresence(playheadTime: Double, selectedClipIDs: [String]) {
        let presence = PeerPresence(
            peerID: peerID,
            displayName: NSFullUserName(),
            color: "#FF6B6B",
            playheadTime: playheadTime,
            selectedClipIDs: selectedClipIDs,
            isOnline: true
        )

        guard let data = try? JSONEncoder().encode(presence) else { return }

        let message = SyncMessage(
            type: .presence,
            senderID: peerID,
            payload: data
        )
        sendMessage(message)
    }

    // MARK: — Private

    private func sendSyncMessage() {
        // Generate Automerge sync messages for each known peer
        // In practice, the server relays messages to the right peers
        var state = syncStates[UUID()] ?? SyncState()
        if let message = project.generateSyncMessage(for: &state) {
            let syncMsg = SyncMessage(
                type: .automergeSync,
                senderID: peerID,
                payload: message
            )
            sendMessage(syncMsg)
            syncStates[UUID()] = state
        }
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleIncomingMessage(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleIncomingMessage(data)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages() // Continue listening
            case .failure(let error):
                print("WebSocket error: \(error)")
                // Reconnect logic here
            }
        }
    }

    private func handleIncomingMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }

        switch message.type {
        case .automergeSync:
            var state = syncStates[message.senderID] ?? SyncState()
            try? project.receiveSyncMessage(message.payload, state: &state)
            syncStates[message.senderID] = state
            DispatchQueue.main.async { self.onRemoteChange?() }

        case .presence:
            if let presence = try? JSONDecoder().decode(PeerPresence.self, from: message.payload) {
                // Update peer presence display
                DispatchQueue.main.async {
                    // Merge presence into peers list
                }
            }
        }
    }

    private func sendMessage(_ message: SyncMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        webSocket?.send(.data(data)) { error in
            if let error { print("Send error: \(error)") }
        }
    }
}

struct SyncMessage: Codable {
    enum MessageType: String, Codable {
        case automergeSync
        case presence
    }
    let type: MessageType
    let senderID: UUID
    let payload: Data
}
```

### Conflict Resolution Strategies for NLE-Specific Operations

| Operation Conflict | Resolution Strategy |
|-------------------|---------------------|
| Two users insert clip at same position | RGA ordering by (clock, siteID) — deterministic |
| One user deletes clip another is editing | Delete wins; edits are silently discarded (tombstoned) |
| Two users trim same clip to different lengths | LWW (Last Writer Wins) on the trim property |
| One user moves clip, another splits it | Move resolves first, then split applies to moved clip |
| Two users change same effect parameter | LWW per parameter key |
| Two users add transitions at same cut | Both transitions appear; user must manually resolve |

---

## 2. Cloud Rendering Architecture

### Architecture Overview

A cloud rendering system for an NLE offloads export/render jobs to remote GPU-equipped servers:

```
┌──────────────────┐         ┌─────────────────────────┐
│   NLE Desktop    │         │     Cloud Services       │
│  (macOS Client)  │         │                          │
│                  │  HTTPS  │  ┌─────────────────┐     │
│  ┌────────────┐  │────────▶│  │  API Gateway    │     │
│  │ Submit Job │  │         │  │  (REST/gRPC)    │     │
│  └────────────┘  │         │  └────────┬────────┘     │
│                  │         │           │               │
│  ┌────────────┐  │         │  ┌────────▼────────┐     │
│  │  Monitor   │◀─│─ WSS ──│  │  Job Orchestrator│     │
│  │  Progress  │  │         │  │  (Coordinator)   │     │
│  └────────────┘  │         │  └────────┬────────┘     │
│                  │         │           │               │
│  ┌────────────┐  │         │  ┌────────▼────────┐     │
│  │  Download  │◀─│── CDN ─│  │  Render Farm     │     │
│  │  Result    │  │         │  │  (GPU Workers)   │     │
│  └────────────┘  │         │  └─────────────────┘     │
└──────────────────┘         └─────────────────────────┘
```

### Job Submission and Segmented Rendering

```swift
import Foundation

/// Represents a cloud render job with segmented parallel processing.
struct RenderJob: Codable {
    let jobID: UUID
    let projectData: Data         // Serialized project (OTIO or FCPXML)
    let outputSettings: OutputSettings
    let segments: [RenderSegment]  // Parallel render segments
    let assetManifest: [AssetReference]  // Media files needed

    struct OutputSettings: Codable {
        let codec: String          // "prores_4444", "h265", etc.
        let width: Int
        let height: Int
        let frameRate: Double
        let colorSpace: String     // "rec709", "rec2020", "aces"
        let bitDepth: Int
        let audioCodec: String
        let audioSampleRate: Int
    }

    struct RenderSegment: Codable {
        let segmentID: UUID
        let timeRange: TimeRange   // Which part of the timeline
        let priority: Int          // 0 = highest
        let estimatedFrames: Int

        struct TimeRange: Codable {
            let startSeconds: Double
            let durationSeconds: Double
        }
    }

    struct AssetReference: Codable {
        let assetID: String
        let storageURL: URL        // Cloud storage URL (S3, GCS, etc.)
        let checksum: String       // For integrity verification
        let sizeBytes: Int64
    }
}

/// Client-side job manager for cloud rendering.
final class CloudRenderManager {
    private let apiBaseURL: URL
    private let session = URLSession.shared

    init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    /// Submit a render job, segmenting the timeline for parallel processing.
    func submitJob(
        projectData: Data,
        totalDuration: Double,
        outputSettings: RenderJob.OutputSettings,
        assetManifest: [RenderJob.AssetReference]
    ) async throws -> RenderJob {
        // Segment the timeline into chunks for parallel rendering.
        // Each segment can be rendered independently on a different GPU worker.
        // Typically segment at GOP boundaries or scene cuts for optimal quality.
        let segmentDuration: Double = 10.0  // 10-second segments
        var segments: [RenderJob.RenderSegment] = []
        var offset: Double = 0

        while offset < totalDuration {
            let duration = min(segmentDuration, totalDuration - offset)
            let segment = RenderJob.RenderSegment(
                segmentID: UUID(),
                timeRange: .init(startSeconds: offset, durationSeconds: duration),
                priority: 0,
                estimatedFrames: Int(duration * outputSettings.frameRate)
            )
            segments.append(segment)
            offset += duration
        }

        let job = RenderJob(
            jobID: UUID(),
            projectData: projectData,
            outputSettings: outputSettings,
            segments: segments,
            assetManifest: assetManifest
        )

        // Upload job to cloud
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("/api/v1/jobs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(job)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw CloudRenderError.submissionFailed
        }

        return try JSONDecoder().decode(RenderJob.self, from: data)
    }

    /// Monitor job progress via WebSocket.
    func monitorProgress(
        jobID: UUID,
        onProgress: @escaping (JobProgress) -> Void
    ) -> URLSessionWebSocketTask {
        let wsURL = apiBaseURL
            .appendingPathComponent("/ws/jobs/\(jobID.uuidString)/progress")
        let task = session.webSocketTask(with: wsURL)
        task.resume()

        func receive() {
            task.receive { result in
                if case .success(.data(let data)) = result,
                   let progress = try? JSONDecoder().decode(JobProgress.self, from: data) {
                    DispatchQueue.main.async { onProgress(progress) }
                    receive()
                }
            }
        }
        receive()
        return task
    }

    struct JobProgress: Codable {
        let jobID: UUID
        let state: JobState
        let completedSegments: Int
        let totalSegments: Int
        let currentFPS: Double        // Frames per second rendering speed
        let estimatedTimeRemaining: Double  // Seconds
        let segmentStatuses: [SegmentStatus]

        enum JobState: String, Codable {
            case queued, rendering, concatenating, uploading, completed, failed
        }

        struct SegmentStatus: Codable {
            let segmentID: UUID
            let state: SegmentState
            let progress: Double  // 0.0 to 1.0
            let workerID: String?

            enum SegmentState: String, Codable {
                case pending, rendering, completed, failed
            }
        }
    }

    enum CloudRenderError: Error {
        case submissionFailed
        case assetUploadFailed
        case renderFailed(String)
    }
}
```

### Server-Side Worker Architecture (Conceptual)

```swift
/// Conceptual server-side render worker.
/// Each worker pulls segments from the job queue and renders them.
final class RenderWorker {
    let workerID: String
    let gpuCapability: GPUInfo

    struct GPUInfo {
        let name: String      // "Apple M4 Ultra", "NVIDIA A100", etc.
        let vramGB: Int
        let metalSupport: Bool
    }

    /// Worker main loop: pull jobs, render, upload results.
    func startProcessing(jobQueue: JobQueue) async {
        while true {
            // 1. Pull next segment from the distributed queue
            guard let assignment = await jobQueue.dequeue(workerID: workerID) else {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1s
                continue
            }

            // 2. Download required assets from cloud storage
            // 3. Deserialize the project (OTIO/FCPXML)
            // 4. Build AVComposition for the segment's time range
            // 5. Render using AVAssetExportSession or AVAssetWriter
            // 6. Upload rendered segment to cloud storage
            // 7. Report completion to orchestrator

            await jobQueue.reportComplete(
                segmentID: assignment.segmentID,
                outputURL: assignment.outputURL,
                workerID: workerID
            )
        }
    }
}

protocol JobQueue {
    func dequeue(workerID: String) async -> SegmentAssignment?
    func reportComplete(segmentID: UUID, outputURL: URL, workerID: String) async
}

struct SegmentAssignment {
    let segmentID: UUID
    let jobID: UUID
    let timeRange: RenderJob.RenderSegment.TimeRange
    let projectData: Data
    let assetURLs: [String: URL]
    var outputURL: URL
}
```

---

## 3. Project Interchange Formats — FCPXML Deep Dive

### FCPXML Overview

FCPXML (Final Cut Pro XML) is Apple's interchange format for Final Cut Pro. It describes the complete edit as an XML document: assets, sequences, clips, transitions, effects, and metadata.

**Key differences from traditional track-based formats:**
- **No tracks** — uses a "magnetic timeline" model with a primary storyline (spine)
- **Hierarchical** — clips can contain other clips (compound clips, multicam clips)
- **Rational time** — all times expressed as rational fractions (e.g., "12/25s" not "0.48s")
- **Referenced resources** — media files are declared as `<asset>` elements and referenced by ID

### FCPXML Document Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="1.11">
    <!-- Resources: all assets, formats, effects -->
    <resources>
        <format id="r1" name="FFVideoFormat1080p2398"
                frameDuration="1001/24000s" width="1920" height="1080"/>
        <asset id="r2" name="Interview_A" src="file:///Media/Interview_A.mov"
               start="0s" duration="3600/24s" hasVideo="1" hasAudio="1">
            <media-rep kind="original-media"
                       src="file:///Media/Interview_A.mov"/>
        </asset>
        <asset id="r3" name="BRoll_01" src="file:///Media/BRoll_01.mov"
               start="0s" duration="1200/24s" hasVideo="1" hasAudio="1"/>
        <effect id="r4" name="Cross Dissolve" uid=".../Cross Dissolve"/>
    </resources>

    <!-- Library > Event > Project > Sequence -->
    <library>
        <event name="My Event">
            <project name="My Edit" uid="...">
                <sequence format="r1" duration="2400/24s"
                          tcStart="0s" tcFormat="NDF">

                    <!-- The spine is the primary storyline -->
                    <spine>
                        <!-- Simple clip -->
                        <asset-clip ref="r2" name="Interview_A"
                                    offset="0s" start="100/24s"
                                    duration="600/24s">
                            <!-- Nested audio configuration -->
                            <audio-channel-source srcCh="1, 2"
                                                  role="dialogue"/>
                        </asset-clip>

                        <!-- Transition between clips -->
                        <transition name="Cross Dissolve"
                                    offset="600/24s" duration="48/24s">
                            <filter-video ref="r4"/>
                        </transition>

                        <!-- Second clip with connected clip -->
                        <asset-clip ref="r3" name="BRoll_01"
                                    offset="624/24s" start="0s"
                                    duration="1200/24s">
                            <!-- Connected clip (B-roll overlay) -->
                            <asset-clip ref="r3" lane="1"
                                        offset="100/24s"
                                        start="200/24s"
                                        duration="300/24s"/>
                        </asset-clip>

                        <!-- Gap (empty space) -->
                        <gap offset="1824/24s" duration="576/24s"/>
                    </spine>
                </sequence>
            </project>
        </event>
    </library>
</fcpxml>
```

### Key FCPXML Elements

| Element | Description |
|---------|-------------|
| `<fcpxml>` | Root; `version` attribute specifies DTD version |
| `<resources>` | Container for `<format>`, `<asset>`, `<effect>`, `<media>` |
| `<format>` | Frame size, rate, codec info |
| `<asset>` | Source media file reference with duration, tracks |
| `<library>` | Top-level container (maps to FCP library) |
| `<event>` | Organizational unit (maps to FCP event) |
| `<project>` | A single edit/sequence |
| `<sequence>` | The timeline with format, duration, timecode settings |
| `<spine>` | Primary storyline — ordered list of clips |
| `<asset-clip>` | A clip referencing an `<asset>` |
| `<clip>` | A clip with explicitly specified media (older style) |
| `<gap>` | Empty space in the timeline |
| `<transition>` | Visual transition between adjacent clips |
| `<mc-clip>` | Multicam clip (contains multiple angles) |
| `<sync-clip>` | Synchronized clip (audio+video from different sources) |
| `<compound-clip>` | Nested sequence (compound clip) |
| `<audition>` | Alternative clips (auditions) |
| `<title>` | Generator/title clip |

### FCPXML Time Model

All times in FCPXML are rational numbers expressed as strings:

```swift
import CoreMedia

/// Parse an FCPXML time string to CMTime.
/// FCPXML format: "numerator/denominators" or "Xs" (where X is seconds).
func parseFCPXMLTime(_ string: String) -> CMTime {
    // Remove trailing "s"
    let cleaned = string.hasSuffix("s")
        ? String(string.dropLast())
        : string

    if cleaned.contains("/") {
        // Rational format: "1001/24000"
        let parts = cleaned.split(separator: "/")
        guard parts.count == 2,
              let numerator = Int64(parts[0]),
              let denominator = Int32(parts[1]) else {
            return .invalid
        }
        return CMTime(value: numerator, timescale: denominator)
    } else {
        // Decimal seconds: "10.5"
        guard let seconds = Double(cleaned) else { return .invalid }
        return CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
    }
}

/// Convert CMTime to FCPXML time string.
func cmTimeToFCPXML(_ time: CMTime) -> String {
    return "\(time.value)/\(time.timescale)s"
}
```

### Swift FCPXML Parser

```swift
import Foundation
import CoreMedia

/// Parses FCPXML documents into a structured timeline model.
final class FCPXMLParser: NSObject, XMLParserDelegate {

    // Parsed results
    struct FCPXMLDocument {
        var resources: [String: Resource] = [:]  // Keyed by id
        var projects: [Project] = []
    }

    struct Resource {
        let id: String
        let name: String
        let src: URL?
        let duration: CMTime?
        let formatID: String?
        let hasVideo: Bool
        let hasAudio: Bool
    }

    struct Format {
        let id: String
        let name: String
        let frameDuration: CMTime
        let width: Int
        let height: Int
    }

    struct Project {
        let name: String
        let sequence: Sequence
    }

    struct Sequence {
        let formatRef: String
        let duration: CMTime
        let tcStart: CMTime
        let spine: [TimelineElement]
    }

    enum TimelineElement {
        case assetClip(AssetClip)
        case gap(Gap)
        case transition(Transition)
        case compoundClip(CompoundClip)
        case mcClip(MultiCamClip)
    }

    struct AssetClip {
        let ref: String         // Resource ID
        let name: String
        let offset: CMTime      // Position in timeline
        let start: CMTime       // In-point in source
        let duration: CMTime    // Duration on timeline
        let lane: Int           // 0 = primary storyline, >0 = connected
        var connectedClips: [TimelineElement]  // B-roll, titles, etc.
        var audioChannels: [AudioChannelSource]
        var videoFilters: [String]
        var audioFilters: [String]
    }

    struct Gap {
        let offset: CMTime
        let duration: CMTime
    }

    struct Transition {
        let name: String
        let offset: CMTime
        let duration: CMTime
        let effectRef: String?
    }

    struct CompoundClip {
        let name: String
        let offset: CMTime
        let duration: CMTime
        let spine: [TimelineElement]
    }

    struct MultiCamClip {
        let name: String
        let offset: CMTime
        let duration: CMTime
        let angles: [Angle]
        let activeVideoAngle: Int
        let activeAudioAngle: Int

        struct Angle {
            let name: String
            let clips: [AssetClip]
        }
    }

    struct AudioChannelSource {
        let srcChannels: String
        let role: String
    }

    // MARK: — Parsing

    private var document = FCPXMLDocument()
    private var elementStack: [String] = []
    private var currentAttributes: [String: String] = [:]

    func parse(data: Data) throws -> FCPXMLDocument {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error = parser.parserError {
            throw error
        }
        return document
    }

    // XMLParserDelegate methods would go here...
    // (Full implementation would handle each element type)

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        elementStack.append(elementName)
        currentAttributes = attributeDict

        switch elementName {
        case "asset":
            let resource = Resource(
                id: attributeDict["id"] ?? "",
                name: attributeDict["name"] ?? "",
                src: attributeDict["src"].flatMap { URL(string: $0) },
                duration: attributeDict["duration"].map { parseFCPXMLTime($0) },
                formatID: attributeDict["format"],
                hasVideo: attributeDict["hasVideo"] == "1",
                hasAudio: attributeDict["hasAudio"] == "1"
            )
            document.resources[resource.id] = resource

        case "asset-clip":
            // Parse clip attributes and push onto current context
            break

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        elementStack.removeLast()
    }
}
```

### FCPXML Export (Writing)

```swift
import Foundation
import CoreMedia

/// Generates FCPXML from an internal timeline model.
final class FCPXMLWriter {

    struct ExportSettings {
        let fcpxmlVersion: String  // "1.11"
        let formatID: String
        let frameDuration: CMTime
        let width: Int
        let height: Int
    }

    func generateFCPXML(
        projectName: String,
        clips: [(assetURL: URL, inPoint: CMTime, outPoint: CMTime, timelineOffset: CMTime)],
        settings: ExportSettings
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="\(settings.fcpxmlVersion)">
            <resources>
                <format id="r1" name="FFVideoFormat"
                        frameDuration="\(cmTimeToFCPXML(settings.frameDuration))"
                        width="\(settings.width)" height="\(settings.height)"/>
        """

        // Declare assets
        for (index, clip) in clips.enumerated() {
            let duration = CMTimeSubtract(clip.outPoint, clip.inPoint)
            xml += """

                    <asset id="r\(index + 2)" name="\(clip.assetURL.lastPathComponent)"
                           src="\(clip.assetURL.absoluteString)"
                           start="0s" duration="\(cmTimeToFCPXML(duration))"
                           hasVideo="1" hasAudio="1"/>
            """
        }

        xml += """

            </resources>
            <library>
                <event name="Export">
                    <project name="\(escapeXML(projectName))">
                        <sequence format="r1"
                                  duration="\(cmTimeToFCPXML(totalDuration(clips)))"
                                  tcStart="0s" tcFormat="NDF">
                            <spine>
        """

        // Write clips
        for (index, clip) in clips.enumerated() {
            let duration = CMTimeSubtract(clip.outPoint, clip.inPoint)
            xml += """

                                <asset-clip ref="r\(index + 2)"
                                            name="\(clip.assetURL.lastPathComponent)"
                                            offset="\(cmTimeToFCPXML(clip.timelineOffset))"
                                            start="\(cmTimeToFCPXML(clip.inPoint))"
                                            duration="\(cmTimeToFCPXML(duration))"/>
            """
        }

        xml += """

                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """

        return xml
    }

    private func totalDuration(
        _ clips: [(assetURL: URL, inPoint: CMTime, outPoint: CMTime, timelineOffset: CMTime)]
    ) -> CMTime {
        guard let last = clips.last else { return .zero }
        let dur = CMTimeSubtract(last.outPoint, last.inPoint)
        return CMTimeAdd(last.timelineOffset, dur)
    }

    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
```

---

## 4. Project Interchange — AAF

### AAF Overview

AAF (Advanced Authoring Format) is an industry-standard binary container format for exchanging project metadata and optionally media essence between NLEs, particularly Avid Media Composer, Adobe Premiere Pro, and Pro Tools.

**What AAF preserves:**
- Multi-track timeline with in/out points
- Timecodes (source and record)
- Volume automation, pan, fades
- Transitions (dissolves, wipes)
- Markers and comments
- Basic effects metadata
- Audio routing and channel assignments

**What AAF typically loses:**
- Complex effects (GPU-specific shaders)
- Nested sequences (sometimes)
- Third-party plugin parameters
- Color grading data
- Some metadata fields

### AAF vs FCPXML vs OTIO vs EDL

| Feature | AAF | FCPXML | OTIO | EDL (CMX3600) |
|---------|-----|--------|------|---------------|
| Binary/Text | Binary (structured storage) | XML text | JSON text | Plain text |
| Embeds media | Optional | No | No | No |
| Multi-track | Yes | Yes (magnetic) | Yes | Single track |
| Transitions | Yes | Yes | Yes | Limited |
| Effects | Basic | FCP-specific | Metadata only | No |
| Audio routing | Detailed | Detailed (roles) | Basic | 4 channels max |
| Timecode | Full support | Full support | Full support | Full support |
| Speed changes | Yes | Yes | Yes | No |
| Max events | Unlimited | Unlimited | Unlimited | 999 |
| NLE support | Avid, Premiere, Pro Tools | Final Cut Pro | Growing | Universal |
| Swift library | No native | XMLParser | OTIO-Swift | Easy to parse |

### Implementing AAF Read in Swift

AAF is a Microsoft Structured Storage (COM) binary format. Reading it natively in Swift requires either a C library or the open-source OpenAAF/libmxf:

```swift
/// Strategy for AAF support: use OpenTimelineIO's AAF adapter as a bridge.
/// OTIO has a Python-based AAF adapter that can convert AAF → OTIO JSON,
/// which Swift can then parse natively.
///
/// Workflow:
/// 1. User imports .aaf file
/// 2. Shell out to a bundled Python/OTIO tool: `otiocat input.aaf -o output.otio`
/// 3. Parse the resulting .otio JSON file in Swift
/// 4. Map OTIO data model to internal timeline model

/// Alternatively, use the pymxf or pyaaf2 Python libraries in a helper process.

final class AAFImporter {
    /// Convert AAF to OTIO JSON using bundled OTIO command-line tool.
    func importAAF(at url: URL) async throws -> Data {
        let otioPath = Bundle.main.path(
            forResource: "otioconvert",
            ofType: nil,
            inDirectory: "Tools"
        ) ?? "/usr/local/bin/otioconvert"

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("otio")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: otioPath)
        process.arguments = ["-i", url.path, "-o", outputURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AAFError.conversionFailed
        }

        return try Data(contentsOf: outputURL)
    }

    enum AAFError: Error {
        case conversionFailed
        case unsupportedVersion
    }
}
```

---

## 5. Project Interchange — OpenTimelineIO

### OTIO Data Model

OpenTimelineIO (OTIO) is developed by Pixar (now under ASWF) as a universal interchange format. Its data model closely mirrors how NLEs think about timelines:

```
Timeline
  └── Stack (tracks container)
       ├── Track (V1 - Video)
       │    ├── Clip (references media)
       │    ├── Gap (empty space)
       │    ├── Transition (between clips)
       │    └── Clip
       ├── Track (V2 - Video overlay)
       │    └── Clip
       ├── Track (A1 - Audio)
       │    ├── Clip
       │    └── Gap
       └── Track (A2 - Audio)
            └── Clip
```

### OTIO-AVFoundation Swift Bridge

The [OpenTimelineIO-AVFoundation](https://github.com/OpenTimelineIO/OpenTimelineIO-AVFoundation) Swift package provides direct conversion between OTIO and AVFoundation objects:

```swift
import OpenTimelineIO
import OpenTimelineIO_AVFoundation  // The bridge package
import AVFoundation

/// Import and export timelines using OpenTimelineIO with AVFoundation bridge.
final class OTIOInterchange {

    // MARK: — Import: OTIO → AVFoundation

    /// Load an OTIO file and convert to AVComposition for playback.
    func importTimeline(from url: URL) throws -> (
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix
    ) {
        // 1. Read the OTIO file
        let timeline = try Timeline.fromJSON(url: url)

        // 2. Convert to AVFoundation using the bridge
        // The bridge handles:
        //   - RationalTime → CMTime conversion (with precision preservation)
        //   - TimeRange → CMTimeRange conversion
        //   - Track → AVMutableCompositionTrack mapping
        //   - Clip → insertTimeRange calls
        //   - Transition → AVVideoCompositionInstruction
        let composition = try timeline.toAVComposition()
        let videoComposition = try timeline.toAVVideoComposition()
        let audioMix = try timeline.toAVAudioMix()

        return (composition, videoComposition, audioMix)
    }

    // MARK: — Export: Internal Model → OTIO

    /// Convert internal timeline model to OTIO for interchange.
    func exportToOTIO(
        tracks: [InternalTrack],
        projectName: String,
        frameRate: Double
    ) throws -> Data {
        // Build OTIO timeline
        let timeline = Timeline(name: projectName)
        let stack = Stack(name: "tracks")

        for track in tracks {
            let otioTrack = Track(
                name: track.name,
                kind: track.isVideo ? .video : .audio
            )

            for clip in track.clips {
                if clip.isGap {
                    let gap = Gap(
                        sourceRange: TimeRange(
                            startTime: RationalTime(value: 0, rate: frameRate),
                            duration: RationalTime(
                                value: clip.duration,
                                rate: frameRate
                            )
                        )
                    )
                    try otioTrack.append(child: gap)
                } else {
                    let mediaRef = ExternalReference(
                        targetURL: clip.assetURL?.absoluteString,
                        availableRange: TimeRange(
                            startTime: RationalTime(value: 0, rate: frameRate),
                            duration: RationalTime(
                                value: clip.sourceDuration,
                                rate: frameRate
                            )
                        )
                    )

                    let otioClip = Clip(
                        name: clip.name,
                        mediaReference: mediaRef,
                        sourceRange: TimeRange(
                            startTime: RationalTime(
                                value: clip.sourceIn,
                                rate: frameRate
                            ),
                            duration: RationalTime(
                                value: clip.duration,
                                rate: frameRate
                            )
                        )
                    )

                    // Add effects as metadata
                    for effect in clip.effects {
                        let otioEffect = LinearTimeWarp() // or other effect type
                        otioEffect.name = effect.name
                        otioEffect.metadata["parameters"] = effect.parameters
                        try otioClip.effects.append(otioEffect)
                    }

                    try otioTrack.append(child: otioClip)
                }
            }

            try stack.append(child: otioTrack)
        }

        timeline.tracks = stack

        // Serialize to JSON
        return try timeline.toJSON()
    }

    // MARK: — Format Conversion via OTIO

    /// Convert between formats using OTIO as the intermediate representation.
    func convert(from inputURL: URL, to outputURL: URL) throws {
        // OTIO's adapter system handles format detection and conversion
        // Supported: .otio, .fcpxml, .aaf, .edl, .ale, .cdl, .rv, .otioz
        let timeline = try Timeline.fromJSON(url: inputURL)
        try timeline.toJSON(url: outputURL)
    }
}

// Internal model types (for the example above)
struct InternalTrack {
    let name: String
    let isVideo: Bool
    let clips: [InternalClip]
}

struct InternalClip {
    let name: String
    let isGap: Bool
    let assetURL: URL?
    let sourceIn: Double     // In seconds
    let sourceDuration: Double
    let duration: Double     // On timeline
    let effects: [InternalEffect]
}

struct InternalEffect {
    let name: String
    let parameters: [String: Any]
}
```

### RationalTime ↔ CMTime Precision

The bridge carefully handles the precision mismatch:

```swift
import CoreMedia

/// OTIO RationalTime uses Double for value and rate.
/// CMTime uses Int64 value and Int32 timescale.
/// The bridge scales the double to preserve maximum precision.

extension RationalTime {
    /// Convert to CMTime with maximum precision.
    func toCMTime() -> CMTime {
        // Find the best integer representation
        // If rate is 24.0 and value is 10.0, result is CMTime(10, 24)
        // If rate is 29.97 (actually 30000/1001), need higher precision

        let rate = self.rate
        let value = self.value

        // Check for common NTSC rates that need 1001-based timescales
        if isNTSCRate(rate) {
            let timescale: Int32
            if rate < 30 { timescale = 30000 }      // 29.97
            else if rate < 60 { timescale = 60000 }  // 59.94
            else { timescale = Int32(rate * 1000) }

            let cmValue = Int64(value * Double(timescale) / rate)
            return CMTime(value: cmValue, timescale: timescale)
        }

        // For integer rates, use directly
        if rate == rate.rounded() {
            return CMTime(value: Int64(value), timescale: Int32(rate))
        }

        // General case: scale up to preserve precision
        let scaleFactor = 1000.0
        let timescale = Int32(rate * scaleFactor)
        let cmValue = Int64(value * scaleFactor)
        return CMTime(value: cmValue, timescale: timescale)
    }

    private func isNTSCRate(_ rate: Double) -> Bool {
        let ntscRates = [23.976, 29.97, 47.952, 59.94]
        return ntscRates.contains { abs(rate - $0) < 0.01 }
    }
}

extension CMTime {
    /// Convert to OTIO RationalTime.
    func toRationalTime() -> RationalTime {
        return RationalTime(
            value: Double(self.value),
            rate: Double(self.timescale)
        )
    }
}
```

---

## 6. Project Interchange — EDL (CMX3600)

### EDL Format

EDL (Edit Decision List) is the oldest and simplest interchange format. Limited but universally supported:

```
TITLE: MY_EDIT
FCM: NON-DROP FRAME

001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
002  REEL_02  V     C        00:05:00:00 00:05:05:00 01:00:10:00 01:00:15:00
003  REEL_02  V     D    024 00:05:05:00 00:05:15:00 01:00:14:00 01:00:25:00
* FROM CLIP NAME: Interview_B.mov
004  REEL_03  VA1A2 C        00:00:30:00 00:01:00:00 01:00:25:00 01:00:55:00
```

Format: `EVENT# REEL TRACK TYPE DURATION SRC_IN SRC_OUT REC_IN REC_OUT`

### Swift EDL Parser

```swift
import Foundation
import CoreMedia

/// Parses CMX3600 EDL files into structured edit events.
final class EDLParser {

    struct EDLDocument {
        var title: String = ""
        var frameCountMode: FrameCountMode = .nonDropFrame
        var events: [EditEvent] = []
    }

    enum FrameCountMode {
        case dropFrame
        case nonDropFrame
    }

    struct EditEvent {
        let eventNumber: Int
        let reelName: String
        let trackType: TrackType
        let editType: EditType
        let transitionDuration: Int?  // Frames, for dissolves/wipes
        let sourceIn: Timecode
        let sourceOut: Timecode
        let recordIn: Timecode
        let recordOut: Timecode
        var clipName: String?         // From * FROM CLIP NAME comment
        var comments: [String] = []
    }

    enum TrackType {
        case videoOnly          // V
        case audioOnly(Int)     // A1, A2, etc.
        case videoAndAudio      // B, VA1, VA1A2, etc.
    }

    enum EditType {
        case cut                // C
        case dissolve           // D
        case wipe(Int)          // W001, W002, etc.
    }

    struct Timecode {
        let hours: Int
        let minutes: Int
        let seconds: Int
        let frames: Int

        /// Convert to CMTime at a given frame rate.
        func toCMTime(fps: Double, dropFrame: Bool = false) -> CMTime {
            var totalFrames = frames
            totalFrames += seconds * Int(fps.rounded())
            totalFrames += minutes * 60 * Int(fps.rounded())
            totalFrames += hours * 3600 * Int(fps.rounded())

            if dropFrame && fps > 29 && fps < 30 {
                // Drop frame compensation:
                // Drop 2 frames every minute except every 10th minute
                let totalMinutes = hours * 60 + minutes
                let dropFrames = 2 * (totalMinutes - totalMinutes / 10)
                totalFrames -= dropFrames
            }

            // Use native frame rate timescale
            if fps > 29 && fps < 30 {
                // 29.97fps → timescale 30000, value per frame = 1001
                return CMTime(
                    value: CMTimeValue(totalFrames) * 1001,
                    timescale: 30000
                )
            } else {
                return CMTime(
                    value: CMTimeValue(totalFrames),
                    timescale: CMTimeScale(fps)
                )
            }
        }

        /// Parse "HH:MM:SS:FF" or "HH;MM;SS;FF" (drop frame uses semicolons)
        static func parse(_ string: String) -> Timecode? {
            let separators = CharacterSet(charactersIn: ":;")
            let parts = string.components(separatedBy: separators)
            guard parts.count == 4,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]),
                  let s = Int(parts[2]),
                  let f = Int(parts[3]) else { return nil }
            return Timecode(hours: h, minutes: m, seconds: s, frames: f)
        }
    }

    // MARK: — Parsing

    func parse(text: String) throws -> EDLDocument {
        var document = EDLDocument()
        let lines = text.components(separatedBy: .newlines)
        var currentEvent: EditEvent?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Title
            if trimmed.hasPrefix("TITLE:") {
                document.title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Frame count mode
            if trimmed.hasPrefix("FCM:") {
                let mode = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                document.frameCountMode = mode.contains("DROP") && !mode.contains("NON")
                    ? .dropFrame : .nonDropFrame
                continue
            }

            // Comment lines (clip names, etc.)
            if trimmed.hasPrefix("*") {
                let comment = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                if comment.hasPrefix("FROM CLIP NAME:") {
                    let clipName = String(comment.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                    if var event = currentEvent {
                        event.clipName = clipName
                        if let lastIndex = document.events.indices.last {
                            document.events[lastIndex].clipName = clipName
                        }
                    }
                }
                continue
            }

            // Event line
            if let event = parseEventLine(trimmed) {
                document.events.append(event)
                currentEvent = event
            }
        }

        return document
    }

    private func parseEventLine(_ line: String) -> EditEvent? {
        // Split by whitespace, respecting the fixed-width format
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8 else { return nil }

        guard let eventNum = Int(parts[0]) else { return nil }

        let reel = parts[1]
        let trackStr = parts[2]
        let editStr = parts[3]

        // Parse track type
        let trackType: TrackType
        if trackStr == "V" {
            trackType = .videoOnly
        } else if trackStr.hasPrefix("A") {
            let channelNum = Int(trackStr.dropFirst()) ?? 1
            trackType = .audioOnly(channelNum)
        } else {
            trackType = .videoAndAudio
        }

        // Parse edit type
        let editType: EditType
        var transitionDuration: Int?
        if editStr == "C" {
            editType = .cut
        } else if editStr == "D" {
            editType = .dissolve
            if parts.count > 4, let dur = Int(parts[4]) {
                transitionDuration = dur
            }
        } else if editStr.hasPrefix("W") {
            let wipeNum = Int(editStr.dropFirst()) ?? 0
            editType = .wipe(wipeNum)
        } else {
            editType = .cut
        }

        // Parse timecodes (last 4 fields are always TC)
        let tcStartIndex = parts.count - 4
        guard let srcIn = Timecode.parse(parts[tcStartIndex]),
              let srcOut = Timecode.parse(parts[tcStartIndex + 1]),
              let recIn = Timecode.parse(parts[tcStartIndex + 2]),
              let recOut = Timecode.parse(parts[tcStartIndex + 3]) else {
            return nil
        }

        return EditEvent(
            eventNumber: eventNum,
            reelName: reel,
            trackType: trackType,
            editType: editType,
            transitionDuration: transitionDuration,
            sourceIn: srcIn,
            sourceOut: srcOut,
            recordIn: recIn,
            recordOut: recOut
        )
    }
}
```

### EDL Export

```swift
/// Generates a CMX3600 EDL from internal timeline data.
final class EDLWriter {

    func generateEDL(
        title: String,
        events: [EDLParser.EditEvent],
        dropFrame: Bool = false
    ) -> String {
        var lines: [String] = []

        lines.append("TITLE: \(title)")
        lines.append("FCM: \(dropFrame ? "DROP FRAME" : "NON-DROP FRAME")")
        lines.append("")

        for event in events {
            let eventNum = String(format: "%03d", event.eventNumber)
            let reel = event.reelName.padding(toLength: 8, withPad: " ", startingAt: 0)

            let track: String
            switch event.trackType {
            case .videoOnly: track = "V    "
            case .audioOnly(let ch): track = "A\(ch)   "
            case .videoAndAudio: track = "VA1A2"
            }

            let edit: String
            switch event.editType {
            case .cut: edit = "C   "
            case .dissolve: edit = "D   "
            case .wipe(let n): edit = "W\(String(format: "%03d", n))"
            }

            let duration = event.transitionDuration.map { String(format: " %03d", $0) } ?? "    "

            let sep = dropFrame ? ";" : ":"
            func formatTC(_ tc: EDLParser.Timecode) -> String {
                return String(format: "%02d\(sep)%02d\(sep)%02d\(sep)%02d",
                              tc.hours, tc.minutes, tc.seconds, tc.frames)
            }

            let line = "\(eventNum)  \(reel) \(track) \(edit)\(duration) " +
                       "\(formatTC(event.sourceIn)) \(formatTC(event.sourceOut)) " +
                       "\(formatTC(event.recordIn)) \(formatTC(event.recordOut))"
            lines.append(line)

            if let clipName = event.clipName {
                lines.append("* FROM CLIP NAME: \(clipName)")
            }

            for comment in event.comments {
                lines.append("* \(comment)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
```

---

## 7. Version Control for NLE Projects

### Challenges Unique to Video Projects

- **Project files** are relatively small (KB-MB) but change frequently
- **Media files** are enormous (GB-TB) and rarely change after import
- **Binary formats** (AAF, proprietary project files) don't diff well
- **Many editors** may work on different sequences within one project

### Strategy: Separate Project Data from Media

```swift
/// Version control strategy for NLE projects.
///
/// Principle: Track project metadata in Git, manage media separately.
///
/// Repository structure:
/// ├── .git/                          # Git tracks project files only
/// ├── .gitattributes                 # LFS rules for proxies
/// ├── project.otio                   # Timeline data (JSON, diffs well)
/// ├── project.fcpxml                 # FCP interchange (XML, diffs well)
/// ├── metadata/
/// │   ├── clips.json                 # Clip metadata, notes, tags
/// │   ├── markers.json               # Timeline markers
/// │   └── color-decisions.json       # CDL/LUT references
/// ├── proxies/                       # Git LFS tracks proxy media
/// │   ├── clip_001_proxy.mov
/// │   └── clip_002_proxy.mov
/// ├── exports/                       # Ignored in git
/// └── media/                         # NOT in git — symlink to shared storage
///     ├── clip_001.mxf
///     └── clip_002.mov

/// .gitattributes:
/// proxies/**/*.mov filter=lfs diff=lfs merge=lfs -text
/// proxies/**/*.mp4 filter=lfs diff=lfs merge=lfs -text

/// .gitignore:
/// media/
/// exports/
/// *.autosave
/// .DS_Store
```

### Project Snapshot and History

```swift
import Foundation

/// Manages project version history with semantic snapshots.
final class ProjectVersionManager {

    struct ProjectSnapshot: Codable {
        let id: UUID
        let timestamp: Date
        let author: String
        let message: String        // "Rough cut - Act 1"
        let timelineHash: String   // SHA256 of timeline data
        let markerCount: Int
        let clipCount: Int
        let duration: Double       // Total timeline duration in seconds
    }

    private let projectDirectory: URL
    private let snapshotsFile: URL

    init(projectDirectory: URL) {
        self.projectDirectory = projectDirectory
        self.snapshotsFile = projectDirectory.appendingPathComponent("snapshots.json")
    }

    /// Create a named snapshot (like a git tag with context).
    func createSnapshot(
        message: String,
        author: String,
        timelineData: Data
    ) throws -> ProjectSnapshot {
        let snapshot = ProjectSnapshot(
            id: UUID(),
            timestamp: Date(),
            author: author,
            message: message,
            timelineHash: timelineData.sha256Hash,
            markerCount: 0,  // Would be calculated from timeline
            clipCount: 0,
            duration: 0
        )

        // Save the timeline state for this snapshot
        let snapshotDir = projectDirectory
            .appendingPathComponent(".history")
            .appendingPathComponent(snapshot.id.uuidString)
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        try timelineData.write(to: snapshotDir.appendingPathComponent("timeline.otio"))

        // Append to snapshots manifest
        var snapshots = loadSnapshots()
        snapshots.append(snapshot)
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: snapshotsFile)

        return snapshot
    }

    /// List all snapshots (version history).
    func loadSnapshots() -> [ProjectSnapshot] {
        guard let data = try? Data(contentsOf: snapshotsFile),
              let snapshots = try? JSONDecoder().decode([ProjectSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    /// Restore a previous snapshot.
    func restore(snapshot: ProjectSnapshot) throws -> Data {
        let snapshotDir = projectDirectory
            .appendingPathComponent(".history")
            .appendingPathComponent(snapshot.id.uuidString)
        return try Data(contentsOf: snapshotDir.appendingPathComponent("timeline.otio"))
    }

    /// Compare two snapshots (for diff view).
    func diff(from older: ProjectSnapshot, to newer: ProjectSnapshot) throws -> ProjectDiff {
        let olderData = try restore(snapshot: older)
        let newerData = try restore(snapshot: newer)

        // Parse both timelines and compute structural diff
        // (Clips added, removed, moved, trimmed, effects changed, etc.)
        return ProjectDiff(
            addedClips: [],
            removedClips: [],
            modifiedClips: [],
            addedTracks: 0,
            removedTracks: 0,
            durationChange: 0
        )
    }

    struct ProjectDiff {
        let addedClips: [String]
        let removedClips: [String]
        let modifiedClips: [String]
        let addedTracks: Int
        let removedTracks: Int
        let durationChange: Double  // seconds
    }
}

extension Data {
    var sha256Hash: String {
        // Use CryptoKit or CC_SHA256
        return ""  // Implementation omitted for brevity
    }
}
```

### Git Integration

```swift
import Foundation

/// Git operations for project version control.
final class GitProjectManager {
    private let repoPath: URL

    init(repoPath: URL) {
        self.repoPath = repoPath
    }

    /// Initialize a new project repository.
    func initializeRepository() throws {
        try runGit(["init"])

        // Set up .gitattributes for LFS
        let gitattributes = """
        proxies/**/*.mov filter=lfs diff=lfs merge=lfs -text
        proxies/**/*.mp4 filter=lfs diff=lfs merge=lfs -text
        proxies/**/*.mxf filter=lfs diff=lfs merge=lfs -text
        *.otio diff
        *.fcpxml diff
        """
        try gitattributes.write(
            to: repoPath.appendingPathComponent(".gitattributes"),
            atomically: true,
            encoding: .utf8
        )

        // Set up .gitignore
        let gitignore = """
        media/
        exports/
        render_cache/
        *.autosave
        .DS_Store
        """
        try gitignore.write(
            to: repoPath.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        try runGit(["lfs", "install"])
        try runGit(["lfs", "track", "proxies/**/*.mov"])
        try runGit(["add", "."])
        try runGit(["commit", "-m", "Initialize NLE project"])
    }

    /// Commit current project state.
    func commit(message: String) throws {
        try runGit(["add", "project.otio", "project.fcpxml", "metadata/"])
        try runGit(["commit", "-m", message])
    }

    /// Create a named branch for an edit variant.
    func createBranch(_ name: String) throws {
        try runGit(["checkout", "-b", name])
    }

    /// List branches (edit variants).
    func branches() throws -> [String] {
        let output = try runGit(["branch", "--list"])
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repoPath

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

---

## 8. Asset Management at Scale

### Media Asset Management (MAM) Architecture

```swift
import Foundation
import CryptoKit

/// Central media asset catalog for a collaborative NLE.
final class MediaAssetManager {

    struct ManagedAsset: Codable {
        let id: UUID
        let originalFilename: String
        let contentHash: String          // SHA256 of file content
        let fileSize: Int64
        let codec: String
        let duration: Double
        let frameRate: Double
        let width: Int
        let height: Int
        let audioChannels: Int
        let audioSampleRate: Int
        let colorSpace: String
        let importDate: Date
        let tags: [String]
        let metadata: [String: String]   // Custom metadata fields

        // Storage locations
        var originalPath: URL?           // Original media (local or network)
        var proxyPath: URL?              // Proxy media for editing
        var thumbnailPath: URL?          // Filmstrip thumbnails
        var waveformPath: URL?           // Pre-rendered audio waveform
    }

    private var catalog: [UUID: ManagedAsset] = [:]
    private let storageRoot: URL
    private let catalogFile: URL

    init(storageRoot: URL) {
        self.storageRoot = storageRoot
        self.catalogFile = storageRoot.appendingPathComponent("catalog.json")
        loadCatalog()
    }

    // MARK: — Import

    /// Import a media file into the asset management system.
    func importAsset(
        from sourceURL: URL,
        tags: [String] = [],
        copyToManagedStorage: Bool = true
    ) async throws -> ManagedAsset {
        // 1. Compute content hash for deduplication
        let hash = try await computeHash(of: sourceURL)

        // Check for duplicates
        if let existing = catalog.values.first(where: { $0.contentHash == hash }) {
            return existing
        }

        // 2. Probe media metadata using AVAsset
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first

        let width = videoTrack != nil ? Int(try await videoTrack!.load(.naturalSize).width) : 0
        let height = videoTrack != nil ? Int(try await videoTrack!.load(.naturalSize).height) : 0
        let fps = videoTrack != nil ? Double(try await videoTrack!.load(.nominalFrameRate)) : 0

        // 3. Create managed asset record
        let id = UUID()
        var managedAsset = ManagedAsset(
            id: id,
            originalFilename: sourceURL.lastPathComponent,
            contentHash: hash,
            fileSize: try FileManager.default.attributesOfItem(
                atPath: sourceURL.path
            )[.size] as? Int64 ?? 0,
            codec: "unknown",  // Would probe from format descriptions
            duration: CMTimeGetSeconds(duration),
            frameRate: fps,
            width: width,
            height: height,
            audioChannels: 2,
            audioSampleRate: 48000,
            colorSpace: "rec709",
            importDate: Date(),
            tags: tags,
            metadata: [:]
        )

        // 4. Copy to managed storage (or reference in-place)
        if copyToManagedStorage {
            let destDir = storageRoot
                .appendingPathComponent("originals")
                .appendingPathComponent(id.uuidString)
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            managedAsset.originalPath = destURL
        } else {
            managedAsset.originalPath = sourceURL
        }

        // 5. Save to catalog
        catalog[id] = managedAsset
        saveCatalog()

        return managedAsset
    }

    // MARK: — Proxy Generation

    /// Generate a low-resolution proxy for editing performance.
    func generateProxy(
        for assetID: UUID,
        width: Int = 1280,
        codec: String = "prores_proxy"
    ) async throws -> URL {
        guard let asset = catalog[assetID],
              let originalPath = asset.originalPath else {
            throw AssetError.notFound
        }

        let proxyDir = storageRoot
            .appendingPathComponent("proxies")
            .appendingPathComponent(assetID.uuidString)
        try FileManager.default.createDirectory(at: proxyDir, withIntermediateDirectories: true)
        let proxyURL = proxyDir.appendingPathComponent("proxy.mov")

        // Use AVAssetExportSession for proxy generation
        let avAsset = AVURLAsset(url: originalPath)
        guard let session = AVAssetExportSession(
            asset: avAsset,
            presetName: AVAssetExportPreset1280x720
        ) else {
            throw AssetError.proxyGenerationFailed
        }

        session.outputURL = proxyURL
        session.outputFileType = .mov
        await session.export()

        if session.status == .completed {
            catalog[assetID]?.proxyPath = proxyURL
            saveCatalog()
            return proxyURL
        } else {
            throw AssetError.proxyGenerationFailed
        }
    }

    // MARK: — Search

    /// Search assets by tags, filename, metadata.
    func search(query: String, tags: [String] = []) -> [ManagedAsset] {
        return catalog.values.filter { asset in
            let matchesQuery = query.isEmpty ||
                asset.originalFilename.localizedCaseInsensitiveContains(query) ||
                asset.metadata.values.contains { $0.localizedCaseInsensitiveContains(query) }

            let matchesTags = tags.isEmpty ||
                tags.allSatisfy { asset.tags.contains($0) }

            return matchesQuery && matchesTags
        }
    }

    // MARK: — Storage

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogFile),
              let loaded = try? JSONDecoder().decode([UUID: ManagedAsset].self, from: data) else {
            return
        }
        catalog = loaded
    }

    private func saveCatalog() {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: catalogFile)
    }

    private func computeHash(of url: URL) async throws -> String {
        // Stream the file through SHA256 to avoid loading entire file into memory
        let handle = try FileHandle(forReadingFrom: url)
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024) // 1MB chunks
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        handle.closeFile()
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum AssetError: Error {
        case notFound
        case proxyGenerationFailed
        case duplicateAsset
    }
}
```

### Shared Storage Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Shared Storage                      │
│                                                      │
│  ┌──────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │   Original    │  │   Proxies   │  │  Exports   │ │
│  │  Media (SAN)  │  │   (NAS)     │  │  (Cloud)   │ │
│  │  NFS/SMB      │  │  SMB        │  │  S3/GCS    │ │
│  └──────┬───────┘  └──────┬──────┘  └─────┬──────┘ │
│         │                  │                │        │
│         └─────────┬────────┘                │        │
│                   │                         │        │
│         ┌─────────▼─────────┐               │        │
│         │  Asset Catalog DB │◀──────────────┘        │
│         │  (PostgreSQL)     │                         │
│         └─────────┬─────────┘                         │
│                   │                                   │
└───────────────────┼───────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
   ┌────▼───┐  ┌───▼────┐  ┌──▼─────┐
   │ Editor │  │ Editor │  │ Review │
   │   A    │  │   B    │  │  App   │
   └────────┘  └────────┘  └────────┘
```

### Network Storage Protocol Comparison for NLE

| Protocol | Bandwidth | Latency | Multi-user | Best For |
|----------|-----------|---------|------------|----------|
| NFS v4.1 | High | Low | Good (pNFS) | Linux/Mac environments |
| SMB 3.x | High | Medium | Good | Windows+Mac mixed |
| Avid NEXIS | Optimized | Very Low | Excellent | Avid-centric workflows |
| EditShare EFS | Optimized | Low | Excellent | Multi-NLE workflows |
| AFP | Medium | Medium | Poor (deprecated) | Legacy Mac |
| Thunderbolt DAS | Highest | Lowest | Single user | Solo editor |

---

## 9. Review & Approval Workflows

### Frame.io-Style Review System Architecture

```swift
import Foundation

/// Review and approval system with timecoded comments and annotations.
final class ReviewSystem {

    // MARK: — Data Model

    struct ReviewSession: Codable {
        let id: UUID
        let projectID: UUID
        let name: String           // "Director's Review - Rough Cut 3"
        let createdAt: Date
        let createdBy: String
        var status: SessionStatus
        var mediaURL: URL          // Review media (usually H.264 proxy)
        var comments: [ReviewComment]
        var approvalStatus: ApprovalStatus

        enum SessionStatus: String, Codable {
            case active, archived, expired
        }

        enum ApprovalStatus: String, Codable {
            case pending, approved, changesRequested, rejected
        }
    }

    struct ReviewComment: Codable, Identifiable {
        let id: UUID
        let author: String
        let authorAvatar: URL?
        let timestamp: Date
        let timecodeIn: Double      // Seconds — start of comment range
        let timecodeOut: Double?    // Seconds — end of range (nil = single frame)
        let text: String
        var annotation: Annotation? // Drawing overlay
        var replies: [ReviewComment]
        var isResolved: Bool

        struct Annotation: Codable {
            let frameTimecode: Double
            let drawings: [Drawing]
            let snapshotURL: URL?   // Screenshot of the frame

            struct Drawing: Codable {
                let type: DrawingType
                let points: [[Double]] // [[x, y], [x, y], ...]
                let color: String      // Hex color
                let strokeWidth: Double

                enum DrawingType: String, Codable {
                    case freehand, arrow, rectangle, circle, line
                }
            }
        }
    }

    // MARK: — Comment Management

    private var sessions: [UUID: ReviewSession] = [:]

    /// Create a new review session for a specific export.
    func createSession(
        projectID: UUID,
        name: String,
        mediaURL: URL,
        createdBy: String
    ) -> ReviewSession {
        let session = ReviewSession(
            id: UUID(),
            projectID: projectID,
            name: name,
            createdAt: Date(),
            createdBy: createdBy,
            status: .active,
            mediaURL: mediaURL,
            comments: [],
            approvalStatus: .pending
        )
        sessions[session.id] = session
        return session
    }

    /// Add a timecoded comment to a review session.
    func addComment(
        to sessionID: UUID,
        author: String,
        timecodeIn: Double,
        timecodeOut: Double?,
        text: String,
        annotation: ReviewComment.Annotation? = nil
    ) -> ReviewComment? {
        guard var session = sessions[sessionID] else { return nil }

        let comment = ReviewComment(
            id: UUID(),
            author: author,
            authorAvatar: nil,
            timestamp: Date(),
            timecodeIn: timecodeIn,
            timecodeOut: timecodeOut,
            text: text,
            annotation: annotation,
            replies: [],
            isResolved: false
        )

        session.comments.append(comment)
        sessions[sessionID] = session

        // Notify via WebSocket to all session viewers
        broadcastCommentAdded(sessionID: sessionID, comment: comment)

        return comment
    }

    /// Convert review comments to NLE markers for import.
    func exportAsMarkers(sessionID: UUID) -> [TimelineMarker] {
        guard let session = sessions[sessionID] else { return [] }

        return session.comments.map { comment in
            TimelineMarker(
                name: "\(comment.author): \(comment.text.prefix(50))",
                time: comment.timecodeIn,
                duration: comment.timecodeOut.map { $0 - comment.timecodeIn },
                color: comment.isResolved ? .green : .red,
                note: comment.text
            )
        }
    }

    /// Convert review comments to FCPXML markers for FCP import.
    func exportAsFCPXMLMarkers(sessionID: UUID) -> String {
        guard let session = sessions[sessionID] else { return "" }

        var markers = ""
        for comment in session.comments {
            let time = cmTimeToFCPXML(CMTimeMakeWithSeconds(comment.timecodeIn, preferredTimescale: 600))
            let duration: String
            if let out = comment.timecodeOut {
                duration = cmTimeToFCPXML(CMTimeMakeWithSeconds(
                    out - comment.timecodeIn, preferredTimescale: 600
                ))
            } else {
                duration = "1/24s"
            }

            markers += """
                <marker start="\(time)" duration="\(duration)"
                        value="\(escapeXML(comment.text))"/>
            """
        }
        return markers
    }

    struct TimelineMarker {
        let name: String
        let time: Double
        let duration: Double?
        let color: MarkerColor
        let note: String

        enum MarkerColor {
            case red, green, blue, yellow, purple
        }
    }

    // MARK: — Helpers

    private func broadcastCommentAdded(sessionID: UUID, comment: ReviewComment) {
        // WebSocket broadcast to all connected viewers
    }

    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

### Review Link Sharing

```swift
/// Generates secure, time-limited review links.
final class ReviewLinkManager {

    struct ReviewLink: Codable {
        let token: String        // Unique URL-safe token
        let sessionID: UUID
        let expiresAt: Date
        let permissions: Permissions
        let password: String?    // Optional password protection

        struct Permissions: Codable {
            let canComment: Bool
            let canAnnotate: Bool
            let canApprove: Bool
            let canDownload: Bool
        }
    }

    /// Generate a shareable review link.
    func createLink(
        for sessionID: UUID,
        expiresIn: TimeInterval = 7 * 24 * 3600, // 7 days default
        permissions: ReviewLink.Permissions,
        password: String? = nil
    ) -> ReviewLink {
        let token = generateSecureToken()
        return ReviewLink(
            token: token,
            sessionID: sessionID,
            expiresAt: Date().addingTimeInterval(expiresIn),
            permissions: permissions,
            password: password
        )
    }

    /// URL format: https://review.app.com/r/{token}
    func reviewURL(for link: ReviewLink, baseURL: URL) -> URL {
        return baseURL.appendingPathComponent("r").appendingPathComponent(link.token)
    }

    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

---

## 10. Putting It All Together

### Collaborative NLE Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     NLE Desktop App (macOS)                  │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Timeline     │  │  Viewer      │  │  Inspector       │  │
│  │  (SwiftUI)   │  │  (Metal)     │  │  (SwiftUI)       │  │
│  └──────┬───────┘  └──────────────┘  └──────────────────┘  │
│         │                                                    │
│  ┌──────▼────────────────────────────────────────────────┐  │
│  │              Automerge CRDT Document                    │  │
│  │  (Tracks, Clips, Effects, Markers, Metadata)           │  │
│  └──────┬──────────────────────┬──────────────────────┘  │
│         │                      │                          │
│  ┌──────▼──────┐   ┌──────────▼──────────┐               │
│  │  Local Git   │   │  WebSocket Sync     │               │
│  │  (Snapshots) │   │  (Real-time collab) │               │
│  └─────────────┘   └──────────┬──────────┘               │
│                                │                          │
│  ┌─────────────────────────────▼────────────────────────┐ │
│  │              Import/Export Engine                      │ │
│  │  OTIO ↔ FCPXML ↔ AAF ↔ EDL ↔ Internal Model         │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              Asset Management                         │ │
│  │  Local Storage ↔ Network (NFS/SMB) ↔ Cloud (S3)     │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────────────────────┬───────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
     ┌────────▼──┐  ┌─────▼────┐  ┌───▼──────────┐
     │ Collab     │  │  Cloud   │  │  Review      │
     │ Server     │  │  Render  │  │  Portal      │
     │ (WebSocket)│  │  Farm    │  │  (Web App)   │
     └───────────┘  └──────────┘  └──────────────┘
```

### Format Interchange Decision Matrix

| Scenario | Recommended Format | Why |
|----------|-------------------|-----|
| FCP ↔ Our NLE | FCPXML | Native FCP format, lossless |
| Avid ↔ Our NLE | AAF (via OTIO) | Industry standard for Avid |
| Color grading → DaVinci | OTIO or FCPXML | DaVinci supports both |
| Audio post → Pro Tools | AAF | Industry standard for audio |
| Simple conform list | EDL (CMX3600) | Universal, simple |
| Internal project save | OTIO JSON | Clean, diffable, extensible |
| Collaborative sync | Automerge binary | CRDT-native, mergeable |
| Archive/long-term storage | OTIO + sidecar metadata | Future-proof, open standard |
| Web review → NLE markers | Custom JSON → FCPXML markers | Round-trip comments to NLE |

### Key Libraries and Dependencies

| Library | Purpose | Language | Integration |
|---------|---------|----------|-------------|
| [automerge-swift](https://github.com/automerge/automerge-swift) | CRDT for collaborative editing | Swift | Swift Package |
| [OpenTimelineIO](https://github.com/AcademySoftwareFoundation/OpenTimelineIO) | Timeline interchange | C++/Python | C bindings or helper process |
| [OpenTimelineIO-AVFoundation](https://github.com/OpenTimelineIO/OpenTimelineIO-AVFoundation) | OTIO ↔ AVFoundation bridge | Swift | Swift Package |
| Foundation XMLParser | FCPXML parsing | Swift | Built-in |
| Git / libgit2 | Version control | C | Swift wrapper |
| Git LFS | Large file storage | Go | CLI tool |
| CryptoKit | File hashing (dedup) | Swift | Built-in |
