import Foundation

/// Handles save, load, and autosave operations for `.nleproj` directory bundles.
///
/// Bundle layout:
/// ```
/// MyProject.nleproj/
///   project.json          -- main project data
///   autosave.json         -- autosave snapshot (if present)
/// ```
public final class ProjectFileManager: @unchecked Sendable {
    private static let projectFileName = "project.json"
    private static let autosaveFileName = "autosave.json"

    public init() {}

    /// Saves the project as a JSON file inside a `.nleproj` directory bundle.
    public func save(_ project: Project, to url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let data = try Self.encode(project)
        let fileURL = url.appendingPathComponent(Self.projectFileName)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads a project from a `.nleproj` directory bundle.
    public func load(from url: URL) throws -> Project {
        let fileURL = url.appendingPathComponent(Self.projectFileName)
        let data = try Data(contentsOf: fileURL)
        return try Self.decode(data)
    }

    /// Writes an autosave snapshot alongside the main project file.
    public func autosave(_ project: Project, to url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let data = try Self.encode(project)
        let fileURL = url.appendingPathComponent(Self.autosaveFileName)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Private

    private static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    private static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Project.self, from: data)
    }
}
