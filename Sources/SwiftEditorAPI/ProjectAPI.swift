import Foundation
import CoreMediaPlus
import CommandBus
import ProjectModel

/// Facade for project management operations.
public final class ProjectAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let fileManager: ProjectFileManager
    private let projectProvider: @Sendable () -> Project
    private let projectMutator: @Sendable (Project) -> Void

    public init(dispatcher: CommandDispatcher, fileManager: ProjectFileManager,
                projectProvider: @escaping @Sendable () -> Project,
                projectMutator: @escaping @Sendable (Project) -> Void) {
        self.dispatcher = dispatcher
        self.fileManager = fileManager
        self.projectProvider = projectProvider
        self.projectMutator = projectMutator
    }

    // MARK: - File Operations

    @discardableResult
    public func newProject(name: String) async throws -> CommandResult {
        try await dispatcher.dispatch(NewProjectCommand(name: name))
    }

    @discardableResult
    public func save(to url: URL) async throws -> CommandResult {
        try await dispatcher.dispatch(SaveProjectCommand(url: url))
    }

    @discardableResult
    public func load(from url: URL) async throws -> CommandResult {
        try await dispatcher.dispatch(LoadProjectCommand(url: url))
    }

    // MARK: - Project Properties

    /// The current project
    public var project: Project { projectProvider() }

    /// The project name
    public var name: String { projectProvider().name }

    /// The project ID
    public var id: UUID { projectProvider().id }

    /// When the project was created
    public var createdAt: Date { projectProvider().createdAt }

    /// When the project was last modified
    public var modifiedAt: Date { projectProvider().modifiedAt }

    /// The project version
    public var version: Int { projectProvider().version }

    // MARK: - Project Settings

    /// The project settings (video params, audio params, frame rate)
    public var settings: ProjectSettings { projectProvider().settings }

    /// Update the project settings
    public func updateSettings(_ settings: ProjectSettings) {
        var p = projectProvider()
        p.settings = settings
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// The project frame rate
    public var frameRate: Rational { projectProvider().settings.frameRate }

    /// The project video params
    public var videoParams: VideoParams { projectProvider().settings.videoParams }

    /// The project audio params
    public var audioParams: AudioParams { projectProvider().settings.audioParams }

    // MARK: - Sequences

    /// All sequences in the project
    public var sequences: [ProjectModel.Sequence] { projectProvider().sequences }

    /// Add a new sequence to the project
    @discardableResult
    public func addSequence(name: String = "Sequence") -> ProjectModel.Sequence {
        var p = projectProvider()
        let seq = ProjectModel.Sequence(name: name)
        p.sequences.append(seq)
        p.modifiedAt = Date()
        projectMutator(p)
        return seq
    }

    /// Remove a sequence by ID
    public func removeSequence(id: UUID) {
        var p = projectProvider()
        p.sequences.removeAll { $0.id == id }
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Rename a sequence
    public func renameSequence(id: UUID, name: String) {
        var p = projectProvider()
        if let index = p.sequences.firstIndex(where: { $0.id == id }) {
            p.sequences[index].name = name
            p.modifiedAt = Date()
            projectMutator(p)
        }
    }

    // MARK: - Metadata

    /// The project metadata
    public var metadata: ProjectMetadata { projectProvider().metadata }

    /// Update project metadata
    public func updateMetadata(_ metadata: ProjectMetadata) {
        var p = projectProvider()
        p.metadata = metadata
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Set the project author
    public func setAuthor(_ author: String) {
        var p = projectProvider()
        p.metadata.author = author
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Set the project description
    public func setDescription(_ description: String) {
        var p = projectProvider()
        p.metadata.description = description
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Add a tag to the project
    public func addTag(_ tag: String) {
        var p = projectProvider()
        if !p.metadata.tags.contains(tag) {
            p.metadata.tags.append(tag)
            p.modifiedAt = Date()
            projectMutator(p)
        }
    }

    /// Remove a tag from the project
    public func removeTag(_ tag: String) {
        var p = projectProvider()
        p.metadata.tags.removeAll { $0 == tag }
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Set a custom metadata field
    public func setCustomField(key: String, value: String) {
        var p = projectProvider()
        p.metadata.customFields[key] = value
        p.modifiedAt = Date()
        projectMutator(p)
    }

    /// Remove a custom metadata field
    public func removeCustomField(key: String) {
        var p = projectProvider()
        p.metadata.customFields.removeValue(forKey: key)
        p.modifiedAt = Date()
        projectMutator(p)
    }

    // MARK: - Media Bin

    /// The project media bin
    public var mediaBin: MediaBinModel { projectProvider().bin }

    /// Rename the project
    public func rename(_ newName: String) {
        var p = projectProvider()
        p.name = newName
        p.modifiedAt = Date()
        projectMutator(p)
    }
}
