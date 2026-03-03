import Foundation
import CoreMediaPlus
import CommandBus

// MARK: - Project Commands

public struct SaveProjectCommand: Command {
    public static let typeIdentifier = "project.save"
    public let url: URL
    public var undoDescription: String { "Save Project" }
    public var isMutating: Bool { false }

    public init(url: URL) {
        self.url = url
    }
}

public struct LoadProjectCommand: Command {
    public static let typeIdentifier = "project.load"
    public let url: URL
    public var undoDescription: String { "Load Project" }
    public var isMutating: Bool { true }

    public init(url: URL) {
        self.url = url
    }
}

public struct NewProjectCommand: Command {
    public static let typeIdentifier = "project.new"
    public let name: String
    public var undoDescription: String { "New Project" }
    public var isMutating: Bool { true }

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Media Commands

public struct ImportMediaCommand: Command {
    public static let typeIdentifier = "media.import"
    public let urls: [URL]
    public var undoDescription: String { "Import Media" }
    public var isMutating: Bool { true }

    public init(urls: [URL]) {
        self.urls = urls
    }
}

// MARK: - Export Commands

public struct ExportCommand: Command {
    public static let typeIdentifier = "export.start"
    public let outputURL: URL
    public let preset: ExportPreset
    public var undoDescription: String { "Export" }
    public var isMutating: Bool { false }

    public init(outputURL: URL, preset: ExportPreset) {
        self.outputURL = outputURL
        self.preset = preset
    }
}

public enum ExportPreset: String, Codable, Sendable {
    case h264_1080p
    case h264_4k
    case h265_1080p
    case h265_4k
    case prores422
    case prores4444
    case proresProxy
}
