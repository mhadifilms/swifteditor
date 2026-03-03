// CollaborationKit — Bridge between CRDT operations and live TimelineModel
import Foundation
import Combine
import CoreMediaPlus
import TimelineKit

/// Bridges a local TimelineModel with a collaborative SyncSession.
///
/// - Observes local edits via TimelineEventBus and converts them to
///   TimelineOperations, sending them through the SyncSession.
/// - Receives remote OperationEnvelopes from the SyncSession and applies
///   them to the local TimelineModel.
/// - Maintains a bidirectional mapping between local UUIDs and CRDTIdentifiers.
public final class CollaborationBridge: @unchecked Sendable {

    // MARK: - State

    private let timeline: TimelineModel
    private let session: SyncSession
    private var cancellables = Set<AnyCancellable>()

    /// The local site ID, cached from the session to avoid async access.
    private var localSiteID: UUID?

    /// Maps local UUID (clip/track) -> CRDTIdentifier
    private var localToCRDT: [UUID: CRDTIdentifier] = [:]
    /// Maps CRDTIdentifier -> local UUID
    private var crdtToLocal: [CRDTIdentifier: UUID] = [:]

    /// When true, events from the TimelineModel are suppressed to avoid
    /// re-broadcasting operations that originated from a remote peer.
    private var isApplyingRemote = false

    /// Tracks which clip IDs were just added remotely so we skip them
    /// in the event handler.
    private var remoteAddedClipIDs: Set<UUID> = []

    public init(timeline: TimelineModel, session: SyncSession) {
        self.timeline = timeline
        self.session = session
    }

    // MARK: - Lifecycle

    /// Start the bridge: subscribe to local events and remote operations.
    public func start() async {
        // Cache the site ID for synchronous access
        self.localSiteID = await session.siteID

        // Register existing tracks/clips so we have CRDT IDs for them
        await registerExistingState()

        // Subscribe to local timeline events
        timeline.events.publisher
            .sink { [weak self] event in
                guard let self, !self.isApplyingRemote else { return }
                Task { await self.handleLocalEvent(event) }
            }
            .store(in: &cancellables)

        // Subscribe to remote operations from the sync session
        await session.setOnRemoteOperation { [weak self] envelope in
            guard let self else { return }
            Task { @MainActor in
                self.applyRemoteOperation(envelope)
            }
        }
    }

    /// Stop the bridge and clean up subscriptions.
    public func stop() {
        cancellables.removeAll()
    }

    // MARK: - ID Mapping

    /// Register a local UUID <-> CRDTIdentifier mapping.
    public func register(localID: UUID, crdtID: CRDTIdentifier) {
        localToCRDT[localID] = crdtID
        crdtToLocal[crdtID] = localID
    }

    /// Look up the CRDT identifier for a local UUID.
    public func crdtID(for localID: UUID) -> CRDTIdentifier? {
        localToCRDT[localID]
    }

    /// Look up the local UUID for a CRDT identifier.
    public func localID(for crdtID: CRDTIdentifier) -> UUID? {
        crdtToLocal[crdtID]
    }

    // MARK: - Register Existing State

    /// Assigns CRDT identifiers to all existing tracks and clips so they
    /// can be referenced in subsequent collaborative operations.
    private func registerExistingState() async {
        for track in timeline.videoTracks {
            let crdtID = await session.nextIdentifier()
            register(localID: track.id, crdtID: crdtID)
            for clip in timeline.clipsOnTrack(track.id) {
                let clipCRDT = await session.nextIdentifier()
                register(localID: clip.id, crdtID: clipCRDT)
            }
        }
        for track in timeline.audioTracks {
            let crdtID = await session.nextIdentifier()
            register(localID: track.id, crdtID: crdtID)
            for clip in timeline.clipsOnTrack(track.id) {
                let clipCRDT = await session.nextIdentifier()
                register(localID: clip.id, crdtID: clipCRDT)
            }
        }
    }

    // MARK: - Local Event Handling

    /// Convert a local timeline event into a CRDT TimelineOperation and
    /// send it through the sync session.
    private func handleLocalEvent(_ event: TimelineEvent) async {
        switch event {
        case .clipAdded(let clipID, let trackID):
            // Skip if this was a remote add
            if remoteAddedClipIDs.remove(clipID) != nil { return }

            guard let clip = timeline.clip(by: clipID) else { return }

            let clipCRDT = await session.nextIdentifier()
            register(localID: clipID, crdtID: clipCRDT)

            let trackCRDT = localToCRDT[trackID]
                ?? CRDTIdentifier(siteID: UUID(), clock: 0)

            // Find the preceding clip on this track to use as anchor
            let clipsOnTrack = timeline.clipsOnTrack(trackID)
            let afterCRDT: CRDTIdentifier?
            if let clipIndex = clipsOnTrack.firstIndex(where: { $0.id == clipID }),
               clipIndex > 0 {
                afterCRDT = localToCRDT[clipsOnTrack[clipIndex - 1].id]
            } else {
                afterCRDT = nil
            }

            let payload = ClipPayload(
                assetID: clip.sourceAssetID,
                sourceIn: clip.sourceIn,
                sourceOut: clip.sourceOut,
                speed: clip.speed
            )

            let op = TimelineOperation.insertClip(
                id: clipCRDT,
                afterID: afterCRDT,
                trackID: trackCRDT,
                clip: payload
            )
            await session.send(operation: op)

        case .clipRemoved(let clipID, _):
            guard let clipCRDT = localToCRDT[clipID] else { return }
            let op = TimelineOperation.deleteClip(id: clipCRDT)
            await session.send(operation: op)

        case .clipMoved(let clipID, let toTrack, _):
            guard let clipCRDT = localToCRDT[clipID],
                  let trackCRDT = localToCRDT[toTrack] else { return }

            // Find anchor on destination track
            let clipsOnTrack = timeline.clipsOnTrack(toTrack)
            let afterCRDT: CRDTIdentifier?
            if let clipIndex = clipsOnTrack.firstIndex(where: { $0.id == clipID }),
               clipIndex > 0 {
                afterCRDT = localToCRDT[clipsOnTrack[clipIndex - 1].id]
            } else {
                afterCRDT = nil
            }

            let op = TimelineOperation.moveClip(
                id: clipCRDT,
                afterID: afterCRDT,
                toTrackID: trackCRDT
            )
            await session.send(operation: op)

        case .clipResized(let clipID):
            guard let clip = timeline.clip(by: clipID),
                  let clipCRDT = localToCRDT[clipID] else { return }
            let timestamp = await session.nextIdentifier()

            let opIn = TimelineOperation.trimClipStart(
                clipID: clipCRDT,
                newInPoint: clip.sourceIn,
                timestamp: timestamp
            )
            let opOut = TimelineOperation.trimClipEnd(
                clipID: clipCRDT,
                newOutPoint: clip.sourceOut,
                timestamp: timestamp
            )
            await session.send(operation: opIn)
            await session.send(operation: opOut)

        case .trackAdded(let trackID, let type, _):
            let trackCRDT = await session.nextIdentifier()
            register(localID: trackID, crdtID: trackCRDT)

            let kind: TrackKind = switch type {
            case .video: .video
            case .audio: .audio
            case .subtitle: .subtitle
            }

            let op = TimelineOperation.insertTrack(
                id: trackCRDT,
                afterID: nil,
                kind: kind
            )
            await session.send(operation: op)

        case .trackRemoved(let trackID):
            guard let trackCRDT = localToCRDT[trackID] else { return }
            let op = TimelineOperation.deleteTrack(id: trackCRDT)
            await session.send(operation: op)

        case .clipSplit, .effectChanged, .playheadMoved,
             .selectionChanged, .undoPerformed, .redoPerformed:
            // These events don't have direct CRDT operation mappings
            break
        }
    }

    // MARK: - Remote Operation Application

    /// Apply a remote operation to the local timeline.
    /// Sets `isApplyingRemote` to prevent re-broadcasting the change.
    private func applyRemoteOperation(_ envelope: OperationEnvelope) {
        // Don't apply our own operations
        guard envelope.senderID != localSiteID else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        switch envelope.operation {
        case .insertClip(let id, _, let trackCRDT, let payload):
            guard let trackID = crdtToLocal[trackCRDT] else { return }

            // Calculate the insert position — append at end for now
            let position = timeline.clipsOnTrack(trackID).last.map {
                $0.startTime + $0.duration
            } ?? .zero

            let clipID = timeline.requestAddClip(
                sourceAssetID: payload.assetID,
                trackID: trackID,
                at: position,
                sourceIn: payload.sourceIn,
                sourceOut: payload.sourceOut
            )
            if let clipID {
                remoteAddedClipIDs.insert(clipID)
                register(localID: clipID, crdtID: id)
            }

        case .deleteClip(let id):
            guard let localClipID = crdtToLocal[id] else { return }
            timeline.requestClipDelete(clipID: localClipID)

        case .moveClip(let id, _, let toTrackCRDT):
            guard let localClipID = crdtToLocal[id],
                  let toTrackID = crdtToLocal[toTrackCRDT] else { return }

            let position = timeline.clipsOnTrack(toTrackID).last.map {
                $0.startTime + $0.duration
            } ?? .zero

            timeline.requestClipMove(clipID: localClipID, toTrackID: toTrackID, at: position)

        case .setClipProperty(let clipCRDT, let key, let value, _):
            guard let localClipID = crdtToLocal[clipCRDT],
                  let clip = timeline.clip(by: localClipID) else { return }
            switch key {
            case "speed":
                if case .double(let v) = value { clip.speed = v }
            case "isEnabled":
                if case .bool(let v) = value { clip.isEnabled = v }
            default:
                break
            }

        case .trimClipStart(let clipCRDT, let newInPoint, _):
            guard let localClipID = crdtToLocal[clipCRDT],
                  let clip = timeline.clip(by: localClipID) else { return }
            let delta = newInPoint - clip.sourceIn
            let newStart = clip.startTime + delta
            timeline.requestClipResize(clipID: localClipID, edge: .leading, to: newStart)

        case .trimClipEnd(let clipCRDT, let newOutPoint, _):
            guard let localClipID = crdtToLocal[clipCRDT],
                  let clip = timeline.clip(by: localClipID) else { return }
            let newEnd = clip.startTime + (newOutPoint - clip.sourceIn)
            timeline.requestClipResize(clipID: localClipID, edge: .trailing, to: newEnd)

        case .insertTrack(let id, _, let kind):
            let type: TrackType = switch kind {
            case .video: .video
            case .audio: .audio
            case .subtitle: .subtitle
            }

            if type == .subtitle {
                let trackID = timeline.requestAddSubtitleTrack()
                register(localID: trackID, crdtID: id)
            } else {
                let trackCount = type == .video
                    ? timeline.videoTracks.count
                    : timeline.audioTracks.count
                if let trackID = timeline.requestTrackInsert(at: trackCount, type: type) {
                    register(localID: trackID, crdtID: id)
                }
            }

        case .deleteTrack(let id):
            guard let localTrackID = crdtToLocal[id] else { return }
            timeline.requestTrackRemove(trackID: localTrackID)
        }
    }
}

// MARK: - SyncSession Callback Helper

extension SyncSession {
    /// Sets the remote operation callback.
    func setOnRemoteOperation(_ handler: (@Sendable (OperationEnvelope) -> Void)?) {
        self.onRemoteOperation = handler
    }
}
