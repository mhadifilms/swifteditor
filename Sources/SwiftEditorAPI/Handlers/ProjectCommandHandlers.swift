import Foundation
import CoreMediaPlus
import CommandBus
import ProjectModel
import MediaManager

/// Handler for SaveProjectCommand
public final class SaveProjectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SaveProjectCommand
    private let projectFileManager: ProjectFileManager
    private let projectProvider: @Sendable () -> Project

    public init(projectFileManager: ProjectFileManager, projectProvider: @escaping @Sendable () -> Project) {
        self.projectFileManager = projectFileManager
        self.projectProvider = projectProvider
    }

    public func validate(_ command: SaveProjectCommand) throws {}

    public func execute(_ command: SaveProjectCommand) async throws -> (any Command)? {
        let project = projectProvider()
        try projectFileManager.save(project, to: command.url)
        return nil
    }
}

/// Handler for LoadProjectCommand
public final class LoadProjectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = LoadProjectCommand
    private let projectFileManager: ProjectFileManager
    private let onLoad: @Sendable (Project) -> Void

    public init(projectFileManager: ProjectFileManager, onLoad: @escaping @Sendable (Project) -> Void) {
        self.projectFileManager = projectFileManager
        self.onLoad = onLoad
    }

    public func validate(_ command: LoadProjectCommand) throws {}

    public func execute(_ command: LoadProjectCommand) async throws -> (any Command)? {
        let project = try projectFileManager.load(from: command.url)
        onLoad(project)
        return nil
    }
}

/// Handler for ImportMediaCommand
public final class ImportMediaHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = ImportMediaCommand
    private let importer: AssetImporter
    private let onImport: @Sendable ([ImportedAsset]) -> Void

    public init(importer: AssetImporter, onImport: @escaping @Sendable ([ImportedAsset]) -> Void) {
        self.importer = importer
        self.onImport = onImport
    }

    public func validate(_ command: ImportMediaCommand) throws {
        guard !command.urls.isEmpty else {
            throw CommandError.validationFailed("No URLs provided")
        }
    }

    public func execute(_ command: ImportMediaCommand) async throws -> (any Command)? {
        let assets = try await importer.importAssets(from: command.urls)
        onImport(assets)
        return nil
    }
}
