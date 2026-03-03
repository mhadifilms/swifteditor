import Foundation
import CoreMediaPlus

/// Thread-safe registry that manages plugin discovery and lookup.
public actor PluginRegistry {
    private var videoEffects: [String: any VideoEffect] = [:]
    private var transitions: [String: any VideoTransition] = [:]
    private var generators: [String: any VideoGenerator] = [:]
    private var audioEffects: [String: any AudioEffect] = [:]
    private var codecs: [String: any CodecPlugin] = [:]
    private var exportFormats: [String: any ExportFormatPlugin] = [:]

    public init() {}

    // MARK: - Registration

    public func register(videoEffect: any VideoEffect) {
        videoEffects[videoEffect.identifier] = videoEffect
    }

    public func register(transition: any VideoTransition) {
        transitions[transition.identifier] = transition
    }

    public func register(generator: any VideoGenerator) {
        generators[generator.identifier] = generator
    }

    public func register(audioEffect: any AudioEffect) {
        audioEffects[audioEffect.identifier] = audioEffect
    }

    public func register(codec: any CodecPlugin) {
        codecs[codec.identifier] = codec
    }

    public func register(exportFormat: any ExportFormatPlugin) {
        exportFormats[exportFormat.identifier] = exportFormat
    }

    // MARK: - Lookup

    public func videoEffect(for identifier: String) -> (any VideoEffect)? {
        videoEffects[identifier]
    }

    public func transition(for identifier: String) -> (any VideoTransition)? {
        transitions[identifier]
    }

    public func generator(for identifier: String) -> (any VideoGenerator)? {
        generators[identifier]
    }

    public func audioEffect(for identifier: String) -> (any AudioEffect)? {
        audioEffects[identifier]
    }

    public func codec(for identifier: String) -> (any CodecPlugin)? {
        codecs[identifier]
    }

    public func exportFormat(for identifier: String) -> (any ExportFormatPlugin)? {
        exportFormats[identifier]
    }

    // MARK: - All Items

    public func allVideoEffects() -> [any VideoEffect] {
        Array(videoEffects.values)
    }

    public func allTransitions() -> [any VideoTransition] {
        Array(transitions.values)
    }

    public func allGenerators() -> [any VideoGenerator] {
        Array(generators.values)
    }

    public func allAudioEffects() -> [any AudioEffect] {
        Array(audioEffects.values)
    }

    // MARK: - Plugin Discovery

    /// Discovers and loads plugin bundles from a directory.
    /// Scans for `.plugin` bundles that contain a `PluginBundle` conforming principal class.
    public func loadPlugins(from directory: URL) throws {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents {
            guard url.pathExtension == "plugin" else { continue }

            guard let bundle = Bundle(url: url), bundle.load() else {
                continue
            }

            guard let principalClass = bundle.principalClass as? any PluginBundle.Type else {
                continue
            }

            let plugin = principalClass.init()
            let node = plugin.createProcessingNode()

            switch plugin.manifest.category {
            case .videoEffect:
                if let effect = node as? any VideoEffect {
                    register(videoEffect: effect)
                }
            case .audioEffect:
                if let effect = node as? any AudioEffect {
                    register(audioEffect: effect)
                }
            case .transition:
                if let transition = node as? any VideoTransition {
                    register(transition: transition)
                }
            case .generator:
                if let generator = node as? any VideoGenerator {
                    register(generator: generator)
                }
            case .codec:
                if let codec = node as? any CodecPlugin {
                    register(codec: codec)
                }
            case .exportFormat:
                if let format = node as? any ExportFormatPlugin {
                    register(exportFormat: format)
                }
            }
        }
    }

    // MARK: - Removal

    public func removeVideoEffect(for identifier: String) {
        videoEffects.removeValue(forKey: identifier)
    }

    public func removeTransition(for identifier: String) {
        transitions.removeValue(forKey: identifier)
    }

    public func removeGenerator(for identifier: String) {
        generators.removeValue(forKey: identifier)
    }

    public func removeAudioEffect(for identifier: String) {
        audioEffects.removeValue(forKey: identifier)
    }
}
