import Foundation
import PluginKit

#if canImport(Metal)
import Metal
#endif

/// Facade for plugin discovery, registration, and management.
public final class PluginAPI: @unchecked Sendable {
    /// The underlying plugin registry actor.
    public let registry: PluginRegistry

    public init() {
        self.registry = PluginRegistry()
    }

    public init(registry: PluginRegistry) {
        self.registry = registry
    }

    // MARK: - Registration

    /// Register a video effect plugin.
    public func registerVideoEffect(_ effect: any VideoEffect) async {
        await registry.register(videoEffect: effect)
    }

    /// Register a transition plugin.
    public func registerTransition(_ transition: any VideoTransition) async {
        await registry.register(transition: transition)
    }

    /// Register a generator plugin.
    public func registerGenerator(_ generator: any VideoGenerator) async {
        await registry.register(generator: generator)
    }

    /// Register an audio effect plugin.
    public func registerAudioEffect(_ effect: any AudioEffect) async {
        await registry.register(audioEffect: effect)
    }

    // MARK: - Discovery

    /// Discover and load plugin bundles from a directory.
    public func discover(in directory: URL) async throws {
        try await registry.loadPlugins(from: directory)
    }

    // MARK: - Lookup

    /// Get all registered video effects.
    public func allVideoEffects() async -> [any VideoEffect] {
        await registry.allVideoEffects()
    }

    /// Get all registered transitions.
    public func allTransitions() async -> [any VideoTransition] {
        await registry.allTransitions()
    }

    /// Get all registered generators.
    public func allGenerators() async -> [any VideoGenerator] {
        await registry.allGenerators()
    }

    /// Get all registered audio effects.
    public func allAudioEffects() async -> [any AudioEffect] {
        await registry.allAudioEffects()
    }

    /// Look up a video effect by identifier.
    public func videoEffect(for identifier: String) async -> (any VideoEffect)? {
        await registry.videoEffect(for: identifier)
    }

    /// Look up a transition by identifier.
    public func transition(for identifier: String) async -> (any VideoTransition)? {
        await registry.transition(for: identifier)
    }

    /// Look up a generator by identifier.
    public func generator(for identifier: String) async -> (any VideoGenerator)? {
        await registry.generator(for: identifier)
    }

    /// Look up an audio effect by identifier.
    public func audioEffect(for identifier: String) async -> (any AudioEffect)? {
        await registry.audioEffect(for: identifier)
    }

    // MARK: - Removal

    /// Unregister a video effect by identifier.
    public func removeVideoEffect(for identifier: String) async {
        await registry.removeVideoEffect(for: identifier)
    }

    /// Unregister a transition by identifier.
    public func removeTransition(for identifier: String) async {
        await registry.removeTransition(for: identifier)
    }

    /// Unregister a generator by identifier.
    public func removeGenerator(for identifier: String) async {
        await registry.removeGenerator(for: identifier)
    }

    /// Unregister an audio effect by identifier.
    public func removeAudioEffect(for identifier: String) async {
        await registry.removeAudioEffect(for: identifier)
    }

    // MARK: - Metal Library Loading

    #if canImport(Metal)
    /// Load a Metal library from a .metallib file for plugin GPU effects.
    public func loadMetalLibrary(at url: URL, identifier: String, device: MTLDevice) throws {
        let loader = MetalLibraryLoader(device: device)
        try loader.loadLibrary(from: url, identifier: identifier)
    }
    #endif
}
