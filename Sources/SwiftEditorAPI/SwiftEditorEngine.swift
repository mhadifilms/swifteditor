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
        self.network = NetworkAPI(
            dispatcher: dispatcher,
            timelineProvider: { tl },
            transportStateProvider: {
                NetworkTransportState(
                    currentTime: tp.currentTime.seconds,
                    isPlaying: tp.isPlaying
                )
            }
        )

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

    /// Get all imported assets
    public var allImportedAssets: [MediaManager.ImportedAsset] {
        Array(importedAssets.values)
    }

    /// Sync project changes from ProjectAPI back to the engine
    internal func syncProject() {
        self.project = projectBox.project
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
