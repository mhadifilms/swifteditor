import SwiftUI
import UniformTypeIdentifiers

/// FileDocument wrapper for opening and saving projects via SwiftUI's document-based app infrastructure.
public struct ProjectDocument: FileDocument {
    public var project: Project

    public static var readableContentTypes: [UTType] {
        [.init(exportedAs: "com.swifteditor.project")]
    }

    public init(project: Project = Project()) {
        self.project = project
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.project = try decoder.decode(Project.self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
