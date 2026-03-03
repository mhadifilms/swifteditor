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

/// Top-level orchestrator for the SwiftEditor engine.
/// This is the single entry point for all consumers (UI, CLI, tests, scripts).
@Observable
public final class SwiftEditorEngine: @unchecked Sendable {

    // MARK: - Domain Models

    public private(set) var project: Project
    public let timeline: TimelineModel
    public let transport: TransportController
    public let audioMixer: AudioMixer

    // MARK: - Command Infrastructure

    public let dispatcher: CommandDispatcher

    // MARK: - Facade APIs

    public let editing: EditingAPI
    public let playback: PlaybackAPI
    public let projectAPI: ProjectAPI
    public let media: MediaAPI
    public let audio: AudioAPI
    public let export: ExportAPI

    // MARK: - Internal Services

    private let projectFileManager: ProjectFileManager
    private let assetImporter: AssetImporter
    private let thumbnailGenerator: ThumbnailGenerator
    private let compositionBuilder: CompositionBuilder
    private var importedAssets: [UUID: ImportedAsset] = [:]
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

        // Create facade APIs
        self.editing = EditingAPI(dispatcher: dispatcher, timeline: timeline)
        self.playback = PlaybackAPI(dispatcher: dispatcher, transport: transport)
        self.projectAPI = ProjectAPI(dispatcher: dispatcher, fileManager: projectFileManager)
        self.media = MediaAPI(dispatcher: dispatcher, importer: assetImporter,
                              thumbnailGenerator: thumbnailGenerator)
        self.audio = AudioAPI(mixer: audioMixer)
        self.export = ExportAPI(dispatcher: dispatcher)

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
            projectProvider: { [weak self] in self?.project ?? Project(name: "Empty") }
        ))
        await dispatcher.register(LoadProjectHandler(
            projectFileManager: projectFileManager,
            onLoad: { [weak self] project in
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

        // Export handler
        await dispatcher.register(ExportHandler(
            compositionBuilder: compositionBuilder,
            timelineProvider: { [weak self] in self?.timeline ?? TimelineModel() },
            assetResolver: { [weak self] assetID in self?.assetCache[assetID] }
        ))

        // Add logging middleware
        await dispatcher.addMiddleware(LoggingMiddleware())
    }

    // MARK: - Convenience Methods

    /// Get an imported asset by ID
    public func importedAsset(by id: UUID) -> ImportedAsset? {
        importedAssets[id]
    }

    /// Get all imported assets
    public var allImportedAssets: [ImportedAsset] {
        Array(importedAssets.values)
    }
}
