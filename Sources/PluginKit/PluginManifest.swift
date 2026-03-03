import Foundation

public struct PluginManifest: Codable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let author: String
    public let category: PluginCategory
    public let minimumHostVersion: String
    public let capabilities: Set<PluginCapability>

    public init(identifier: String, name: String, version: String, author: String,
                category: PluginCategory, minimumHostVersion: String,
                capabilities: Set<PluginCapability> = []) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.category = category
        self.minimumHostVersion = minimumHostVersion
        self.capabilities = capabilities
    }

    public enum PluginCategory: String, Codable, Sendable {
        case videoEffect, audioEffect, transition, generator, codec, exportFormat
    }

    public enum PluginCapability: String, Codable, Sendable {
        case gpuAccelerated, realTimeCapable, supportsHDR, supportsMultiChannel, keyframeable
    }
}
