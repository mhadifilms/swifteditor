import Foundation
import PluginKit
import CoreMediaPlus

// MARK: - Plugin Bundle

/// The plugin bundle entry point. This is the principal class discovered by PluginRegistry
/// when loading the plugin from a .plugin bundle directory.
///
/// ## How It Works
///
/// 1. The host app scans a plugins directory for `.plugin` bundles.
/// 2. Each bundle's principal class must conform to `PluginBundle`.
/// 3. The host calls `createProcessingNode()` to get the effect instance.
/// 4. The effect is registered in `PluginRegistry` and becomes available in the UI.
///
public struct SepiaEffectBundle: PluginBundle {
    public init() {}

    public var manifest: PluginManifest {
        PluginManifest(
            identifier: "com.example.sepiaEffect",
            name: "Sepia Tone",
            version: "1.0.0",
            author: "SwiftEditor Examples",
            category: .videoEffect,
            minimumHostVersion: "1.0.0",
            capabilities: [.realTimeCapable, .keyframeable]
        )
    }

    public func createProcessingNode() -> any ProcessingNode {
        SepiaEffect()
    }
}
