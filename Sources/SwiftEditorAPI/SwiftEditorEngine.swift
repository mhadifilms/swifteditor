@preconcurrency import AVFoundation
import Foundation
import Observation
import CoreMediaPlus
import CommandBus
import ProjectModel
import TimelineKit
import ViewerKit
import MediaManager
import AudioEngine
import RenderEngine
import EffectsEngine
import PluginKit
import CollaborationKit
import AIFeatures
import InterchangeKit

/// Top-level orchestrator for the SwiftEditor engine.
/// This is the single entry point for all consumers (UI, CLI, tests, scripts).
/// Every capability of the editor is exposed through typed facade APIs below.
@Observable
public final class SwiftEditorEngine: @unchecked Sendable {

    // MARK: - Domain Models

    public private(set) var project: Project
    public let timeline: TimelineModel
    public let transport: TransportController
    public let audioMixer: AudioMixer

    // MARK: - Command Infrastructure

    public let dispatcher: CommandDispatcher

    // MARK: - Core Facade APIs

    public let editing: EditingAPI
    public let playback: PlaybackAPI
    public let projectAPI: ProjectAPI
    public let media: MediaAPI
    public let audio: AudioAPI
    public let export: ExportAPI
    public let effects: EffectsAPI

    // MARK: - Timeline Facade APIs

    public let selection: SelectionAPI
    public let groups: GroupsAPI
    public let snap: SnapAPI
    public let tracks: TrackAPI
    public let compoundClips: CompoundClipAPI
    public let multicam: MulticamAPI
    public let subtitles: SubtitleAPI

    // MARK: - Effects & Visual Facade APIs

    public let transitions: TransitionAPI
    public let colorGrading: ColorGradingAPI
    public let nodeGraph: NodeGraphAPI
    public let titles: TitleAPI

    // MARK: - Audio & Viewer Facade APIs

    public let audioEffects: AudioEffectsAPI
    public let waveforms: WaveformAPI
    public let viewer: ViewerAPI

    // MARK: - External Module Facade APIs

    public let proxy: ProxyAPI
    public let interchange: InterchangeAPI
    public let aiFeatures: AIFeaturesAPI
    public let collaboration: CollaborationAPI
    public let plugins: PluginAPI
    public let renderConfig: RenderConfigAPI
    public let network: NetworkAPI

    // MARK: - Effect Management

    public let effectStacks: EffectStackStore

    // MARK: - Scope Analysis

    public let scopeDataProvider: ScopeDataProvider

    // MARK: - Internal Services

    private let projectBox: ProjectBox
    private let projectFileManager: ProjectFileManager
    private let assetImporter: AssetImporter
    private let thumbnailGenerator: ThumbnailGenerator
    private let compositionBuilder: CompositionBuilder
    private var importedAssets: [UUID: MediaManager.ImportedAsset] = [:]
    private var assetCache: [UUID: AVURLAsset] = [:]
    public private(set) var allImportedAssets: [MediaManager.ImportedAsset] = []

    // MARK: - Initialization

    public init(projectName: String = "Untitled") {
        let project = Project(name: projectName)
        self.project = project
        self.timeline = TimelineModel()
        self.transport = TransportController()
        self.audioMixer = AudioMixer()
        self.dispatcher = CommandDispatcher()
        self.projectFileManager = ProjectFileManager()
        self.assetImporter = AssetImporter()
        self.thumbnailGenerator = ThumbnailGenerator()
        self.compositionBuilder = CompositionBuilder()

        // Create effect stack store
        self.effectStacks = EffectStackStore()

        // Create scope data provider for video scopes
        self.scopeDataProvider = ScopeDataProvider(configuration: ScopeConfiguration(
            outputWidth: 512,
            outputHeight: 256,
            brightness: 1.2,
            showGraticule: true,
            vectorscopeSize: 256
        ))

        // ── Core Facade APIs ──────────────────────────
        self.editing = EditingAPI(dispatcher: dispatcher, timeline: timeline)
        self.playback = PlaybackAPI(dispatcher: dispatcher, transport: transport)
        // ProjectAPI needs project access — use a box to break the init cycle
        let projectBox = ProjectBox(project: project)
        self.projectBox = projectBox
        self.projectAPI = ProjectAPI(
            dispatcher: dispatcher, fileManager: projectFileManager,
            projectProvider: { projectBox.project },
            projectMutator: { projectBox.project = $0 }
        )
        self.media = MediaAPI(dispatcher: dispatcher, importer: assetImporter,
                              thumbnailGenerator: thumbnailGenerator)
        self.audio = AudioAPI(mixer: audioMixer)
        self.export = ExportAPI(dispatcher: dispatcher)
        self.effects = EffectsAPI(dispatcher: dispatcher, effectStacks: effectStacks)

        // ── Timeline Facade APIs ──────────────────────
        self.selection = SelectionAPI(timeline: timeline)
        self.groups = GroupsAPI(timeline: timeline)
        self.snap = SnapAPI(timeline: timeline)
        self.tracks = TrackAPI(timeline: timeline)
        self.compoundClips = CompoundClipAPI(dispatcher: dispatcher, timeline: timeline)
        self.multicam = MulticamAPI(dispatcher: dispatcher, timeline: timeline)
        self.subtitles = SubtitleAPI(dispatcher: dispatcher, timeline: timeline)

        // ── Effects & Visual Facade APIs ──────────────
        let transitionStore = TransitionStore()
        self.transitions = TransitionAPI(dispatcher: dispatcher, store: transitionStore)
        let colorGradingStore = ColorGradingStore()
        self.colorGrading = ColorGradingAPI(store: colorGradingStore)
        self.nodeGraph = NodeGraphAPI()
        self.titles = TitleAPI()

        // ── Audio & Viewer Facade APIs ────────────────
        self.audioEffects = AudioEffectsAPI()
        self.waveforms = WaveformAPI()
        self.viewer = ViewerAPI(
            inOutModel: InOutPointModel(),
            shuttle: JKLShuttleController(transport: transport),
            sourceViewer: SourceViewerState(),
            transport: transport
        )

        // ── External Module Facade APIs ───────────────
        self.proxy = ProxyAPI()
        self.interchange = InterchangeAPI(timeline: timeline)
        self.aiFeatures = AIFeaturesAPI()
        self.collaboration = CollaborationAPI(timeline: timeline)
        self.plugins = PluginAPI()
        self.renderConfig = RenderConfigAPI()
        // Capture timeline and transport directly to avoid self-before-init issue
        let tl = timeline
        let tp = transport
        let mediaAPI = media
        let engineRef = EngineRef()
        let stacks = effectStacks
        self.network = NetworkAPI(
            dispatcher: dispatcher,
            timelineProvider: { tl },
            transportStateProvider: {
                NetworkTransportState(
                    currentTime: tp.currentTime.seconds,
                    isPlaying: tp.isPlaying
                )
            },
            importHandler: { @Sendable urls in
                let imported = try await mediaAPI.importAssetsDirectly(from: urls)
                await MainActor.run { engineRef.engine?.registerImportedAssets(imported) }
                return imported.map { ["id": $0.id.uuidString, "name": $0.name, "url": $0.url.path] }
            },
            rebuildHandler: { @Sendable in
                await engineRef.engine?.rebuildPlaybackComposition()
            },
            effectsHandler: { @Sendable action in
                switch action {
                case .add(let clipID, let effectName):
                    let effect = EffectInstance(pluginID: "com.apple.coreimage", name: effectName)
                    await MainActor.run { stacks.stack(for: clipID).append(effect) }
                    return ["success": true, "effectID": effect.id.uuidString, "effectName": effectName]
                case .setParameter(let clipID, let effectIndex, let parameterName, let value):
                    let stack = await MainActor.run { stacks.stack(for: clipID) }
                    guard effectIndex < stack.effects.count else {
                        throw CommandError.executionFailed("Effect index \(effectIndex) out of range")
                    }
                    let effect = stack.effects[effectIndex]
                    await MainActor.run { effect.parameters[parameterName] = .float(value) }
                    return ["success": true, "effectID": effect.id.uuidString]
                case .addKeyframe(let clipID, let effectIndex, let parameterName, let time, let value):
                    let stack = await MainActor.run { stacks.stack(for: clipID) }
                    guard effectIndex < stack.effects.count else {
                        throw CommandError.executionFailed("Effect index \(effectIndex) out of range")
                    }
                    let effect = stack.effects[effectIndex]
                    let keyframe = KeyframeTrack.Keyframe(time: time, value: .float(value))
                    await MainActor.run {
                        if effect.keyframeTracks[parameterName] == nil {
                            effect.keyframeTracks[parameterName] = KeyframeTrack()
                        }
                        effect.keyframeTracks[parameterName]?.addKeyframe(keyframe)
                    }
                    return ["success": true, "effectID": effect.id.uuidString]
                }
            }
        )

        // Now all stored properties are initialized — set up self-referencing callbacks
        engineRef.engine = self

        // Wire proxy URL resolver into the composition builder
        let proxyManager = proxy.manager
        compositionBuilder.urlResolver = { @Sendable url in
            await proxyManager.resolveURL(url)
        }

        // Load initial sequence
        if let firstSequence = project.sequences.first {
            timeline.load(from: firstSequence)
        }

        // Register command handlers
        Task { await registerHandlers() }

        // Register command types for serialization (needed by network API)
        registerCommandTypes()
    }

    private func registerCommandTypes() {
        let registry = CommandRegistry.shared
        // Editing commands
        registry.register(AddClipCommand.self)
        registry.register(MoveClipCommand.self)
        registry.register(TrimClipCommand.self)
        registry.register(SplitClipCommand.self)
        registry.register(DeleteClipCommand.self)
        registry.register(AddTrackCommand.self)
        registry.register(RemoveTrackCommand.self)
        registry.register(InsertEditCommand.self)
        registry.register(OverwriteEditCommand.self)
        registry.register(RippleDeleteCommand.self)
        registry.register(RippleTrimCommand.self)
        registry.register(RollTrimCommand.self)
        registry.register(SlipCommand.self)
        registry.register(SlideCommand.self)
        registry.register(BladeAllCommand.self)
        registry.register(SpeedChangeCommand.self)
        registry.register(AppendAtEndCommand.self)
        registry.register(PlaceOnTopCommand.self)
        registry.register(RippleOverwriteCommand.self)
        registry.register(FitToFillCommand.self)
        registry.register(ReplaceEditCommand.self)
        // Marker commands
        registry.register(AddMarkerCommand.self)
        registry.register(RemoveMarkerCommand.self)
        // Effect commands
        registry.register(AddEffectCommand.self)
        registry.register(RemoveEffectCommand.self)
        registry.register(SetEffectParameterCommand.self)
        registry.register(ToggleEffectCommand.self)
        registry.register(MoveEffectCommand.self)
        registry.register(AddKeyframeCommand.self)
        registry.register(RemoveKeyframeCommand.self)
        // Transition commands
        registry.register(AddTransitionCommand.self)
        registry.register(RemoveTransitionCommand.self)
        // Playback commands
        registry.register(PlayCommand.self)
        registry.register(PauseCommand.self)
        registry.register(StopCommand.self)
        registry.register(SeekCommand.self)
        registry.register(StepForwardCommand.self)
        registry.register(StepBackwardCommand.self)
        // Timeline extended commands
        registry.register(CreateCompoundClipCommand.self)
        registry.register(FlattenCompoundClipCommand.self)
        registry.register(CreateMulticamClipCommand.self)
        registry.register(SwitchAngleCommand.self)
        // Subtitle commands
        registry.register(AddSubtitleTrackCommand.self)
        registry.register(RemoveSubtitleTrackCommand.self)
        registry.register(AddSubtitleCueCommand.self)
        registry.register(RemoveSubtitleCueCommand.self)
        registry.register(UpdateSubtitleCueCommand.self)
        // Project commands
        registry.register(SaveProjectCommand.self)
        registry.register(LoadProjectCommand.self)
        registry.register(ExportCommand.self)
    }

    // MARK: - Handler Registration

    private func registerHandlers() async {
        // Editing handlers
        await dispatcher.register(AddClipHandler(timeline: timeline))
        await dispatcher.register(MoveClipHandler(timeline: timeline))
        await dispatcher.register(TrimClipHandler(timeline: timeline))
        await dispatcher.register(SplitClipHandler(timeline: timeline))
        await dispatcher.register(DeleteClipHandler(timeline: timeline))
        await dispatcher.register(AddTrackHandler(timeline: timeline))
        await dispatcher.register(RemoveTrackHandler(timeline: timeline))

        // Playback handlers
        await dispatcher.register(PlayHandler(transport: transport))
        await dispatcher.register(PauseHandler(transport: transport))
        await dispatcher.register(StopHandler(transport: transport))
        await dispatcher.register(SeekHandler(transport: transport))
        await dispatcher.register(StepForwardHandler(transport: transport))
        await dispatcher.register(StepBackwardHandler(transport: transport))

        // Project handlers
        await dispatcher.register(SaveProjectHandler(
            projectFileManager: projectFileManager,
            projectProvider: { [weak self] in self?.projectBox.project ?? Project(name: "Empty") }
        ))
        await dispatcher.register(LoadProjectHandler(
            projectFileManager: projectFileManager,
            onLoad: { [weak self] project in
                self?.projectBox.project = project
                self?.project = project
                if let seq = project.sequences.first {
                    self?.timeline.load(from: seq)
                }
            }
        ))

        // Media handlers
        await dispatcher.register(ImportMediaHandler(
            importer: assetImporter,
            onImport: { [weak self] assets in
                for asset in assets {
                    self?.importedAssets[asset.id] = asset
                    self?.assetCache[asset.id] = AVURLAsset(url: asset.url)
                }
                self?.didUpdateImportedAssets()
            }
        ))

        // Export handler — wire progress reporting through ExportAPI
        let stacks = effectStacks
        let exportAPI = self.export
        await dispatcher.register(ExportHandler(
            compositionBuilder: compositionBuilder,
            timelineProvider: { [weak self] in self?.timeline ?? TimelineModel() },
            assetResolver: { [weak self] assetID in self?.assetCache[assetID] },
            effectStackResolver: { clipID in
                stacks.hasEffects(for: clipID) ? stacks.stack(for: clipID) : nil
            },
            onProgress: { @Sendable progress in
                exportAPI.reportProgress(progress)
            }
        ))

        // Advanced editing handlers
        await dispatcher.register(InsertEditHandler(timeline: timeline))
        await dispatcher.register(OverwriteEditHandler(timeline: timeline))
        await dispatcher.register(RippleDeleteHandler(timeline: timeline))
        await dispatcher.register(RippleTrimHandler(timeline: timeline))
        await dispatcher.register(RollTrimHandler(timeline: timeline))
        await dispatcher.register(SlipHandler(timeline: timeline))
        await dispatcher.register(SlideHandler(timeline: timeline))
        await dispatcher.register(BladeAllHandler(timeline: timeline))
        await dispatcher.register(SpeedChangeHandler(timeline: timeline))
        await dispatcher.register(AppendAtEndHandler(timeline: timeline))
        await dispatcher.register(PlaceOnTopHandler(timeline: timeline))
        await dispatcher.register(RippleOverwriteHandler(timeline: timeline))
        await dispatcher.register(FitToFillHandler(timeline: timeline))
        await dispatcher.register(ReplaceEditHandler(timeline: timeline))

        // Marker handlers
        await dispatcher.register(AddMarkerHandler(timeline: timeline))
        await dispatcher.register(RemoveMarkerHandler(timeline: timeline))

        // Effect handlers
        await dispatcher.register(AddEffectHandler(effectStacks: effectStacks))
        await dispatcher.register(RemoveEffectHandler(effectStacks: effectStacks))
        await dispatcher.register(SetEffectParameterHandler(effectStacks: effectStacks))
        await dispatcher.register(ToggleEffectHandler(effectStacks: effectStacks))
        await dispatcher.register(MoveEffectHandler(effectStacks: effectStacks))
        await dispatcher.register(AddKeyframeHandler(effectStacks: effectStacks))
        await dispatcher.register(RemoveKeyframeHandler(effectStacks: effectStacks))

        // Transition handlers
        await dispatcher.register(AddTransitionHandler(store: transitions.store))
        await dispatcher.register(RemoveTransitionHandler(store: transitions.store))

        // Timeline extended handlers (compound clips, multicam, subtitles)
        await dispatcher.register(CreateCompoundClipHandler(timeline: timeline))
        await dispatcher.register(FlattenCompoundClipHandler(timeline: timeline))
        await dispatcher.register(CreateMulticamClipHandler(timeline: timeline))
        await dispatcher.register(SwitchAngleHandler(timeline: timeline))
        await dispatcher.register(AddSubtitleTrackHandler(timeline: timeline))
        await dispatcher.register(RemoveSubtitleTrackHandler(timeline: timeline))
        await dispatcher.register(AddSubtitleCueHandler(timeline: timeline))
        await dispatcher.register(RemoveSubtitleCueHandler(timeline: timeline))
        await dispatcher.register(UpdateSubtitleCueHandler(timeline: timeline))

        // Add logging middleware
        await dispatcher.addMiddleware(LoggingMiddleware())
    }

    // MARK: - Convenience Methods

    /// Get an imported asset by ID
    public func importedAsset(by id: UUID) -> MediaManager.ImportedAsset? {
        importedAssets[id]
    }

    /// Register externally-imported assets (e.g. from drag-and-drop).
    public func registerImportedAssets(_ assets: [MediaManager.ImportedAsset]) {
        for asset in assets {
            importedAssets[asset.id] = asset
            assetCache[asset.id] = AVURLAsset(url: asset.url)
        }
        didUpdateImportedAssets()
    }

    /// Sync the stored allImportedAssets array from the internal dict.
    private func didUpdateImportedAssets() {
        allImportedAssets = Array(importedAssets.values)
    }

    /// Sync project changes from ProjectAPI back to the engine
    internal func syncProject() {
        self.project = projectBox.project
    }

    // MARK: - Playback Composition

    /// Rebuild the AVPlayer composition from the current timeline and asset cache,
    /// then set it on the transport controller so the viewer can display frames.
    @MainActor
    public func rebuildPlaybackComposition() async {
        let videoTrackData = timeline.videoTracks.map { track in
            CompositionBuilder.TrackBuildData(
                trackID: track.id,
                clips: timeline.clipsOnTrack(track.id).map { clip in
                    CompositionBuilder.ClipBuildData(
                        clipID: clip.id,
                        asset: assetCache[clip.sourceAssetID],
                        startTime: clip.startTime,
                        sourceIn: clip.sourceIn,
                        sourceOut: clip.sourceOut,
                        effectStack: effectStacks.hasEffects(for: clip.id) ? effectStacks.stack(for: clip.id) : nil
                    )
                }
            )
        }

        let audioTrackData = timeline.audioTracks.map { track in
            CompositionBuilder.TrackBuildData(
                trackID: track.id,
                clips: timeline.clipsOnTrack(track.id).map { clip in
                    CompositionBuilder.ClipBuildData(
                        clipID: clip.id,
                        asset: assetCache[clip.sourceAssetID],
                        startTime: clip.startTime,
                        sourceIn: clip.sourceIn,
                        sourceOut: clip.sourceOut
                    )
                }
            )
        }

        // Only rebuild if there are clips with resolved assets
        let hasVideoClips = videoTrackData.flatMap(\.clips).contains { $0.asset != nil }
        let hasAudioClips = audioTrackData.flatMap(\.clips).contains { $0.asset != nil }
        guard hasVideoClips || hasAudioClips else { return }

        do {
            let playerItem = try await compositionBuilder.buildPlayerItem(
                videoTracks: videoTrackData,
                audioTracks: audioTrackData,
                renderSize: CGSize(width: 1920, height: 1080),
                frameDuration: CMTime(value: 1, timescale: 24)
            )
            let player = AVPlayer(playerItem: playerItem)
            transport.setPlayer(player)
        } catch {
            print("[SwiftEditorEngine] Failed to build playback composition: \(error)")
        }
    }
}

// MARK: - ProjectBox (breaks init cycle for closure capture)

/// Mutable box that allows closures to read/write the project
/// without capturing `self` during init.
final class ProjectBox: @unchecked Sendable {
    var project: Project

    init(project: Project = Project()) {
        self.project = project
    }
}

// MARK: - EngineRef (breaks init cycle for Sendable closures)

/// Weak reference box allowing @Sendable closures created during init
/// to call back into the engine after initialization completes.
private final class EngineRef: @unchecked Sendable {
    weak var engine: SwiftEditorEngine?
}
