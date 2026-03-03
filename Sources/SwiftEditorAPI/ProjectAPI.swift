import Foundation
import CoreMediaPlus
import CommandBus
import ProjectModel

/// Facade for project management operations.
public final class ProjectAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let fileManager: ProjectFileManager

    public init(dispatcher: CommandDispatcher, fileManager: ProjectFileManager) {
        self.dispatcher = dispatcher
        self.fileManager = fileManager
    }

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
}
