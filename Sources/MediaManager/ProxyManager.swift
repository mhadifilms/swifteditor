import Foundation
import CoreMediaPlus

/// Status of a proxy for a given asset.
public enum ProxyClipStatus: Sendable {
    case original
    case proxy
    case generating
}

/// Manages the mapping between original media URLs and their proxy counterparts.
/// Used by the render pipeline to swap between original and proxy media on the fly.
public actor ProxyManager {

    private var proxyMappings: [URL: URL] = [:]
    private var generatingSet: Set<URL> = []
    private var _useProxy: Bool = false

    public init() {}

    /// Whether the pipeline should resolve URLs through proxy mappings.
    public var useProxy: Bool {
        get { _useProxy }
    }

    /// Toggle proxy mode on or off.
    public func setUseProxy(_ enabled: Bool) {
        _useProxy = enabled
    }

    /// Register a proxy URL for a given original URL.
    public func registerProxy(original: URL, proxy: URL) {
        proxyMappings[original] = proxy
        generatingSet.remove(original)
    }

    /// Mark an original URL as currently generating a proxy.
    public func markGenerating(original: URL) {
        generatingSet.insert(original)
    }

    /// Remove the proxy mapping for a given original URL.
    public func removeProxy(original: URL) {
        proxyMappings.removeValue(forKey: original)
        generatingSet.remove(original)
    }

    /// Resolve a URL: returns the proxy URL if proxy mode is on and a proxy exists,
    /// otherwise returns the original URL.
    public func resolveURL(_ original: URL) -> URL {
        guard _useProxy, let proxy = proxyMappings[original] else {
            return original
        }
        return proxy
    }

    /// Get the status of a specific asset URL.
    public func status(for original: URL) -> ProxyClipStatus {
        if generatingSet.contains(original) {
            return .generating
        }
        if proxyMappings[original] != nil {
            return _useProxy ? .proxy : .original
        }
        return .original
    }

    /// Get all registered proxy mappings.
    public var allMappings: [URL: URL] {
        proxyMappings
    }

    /// Whether a proxy file exists for the given original URL.
    public func hasProxy(for original: URL) -> Bool {
        proxyMappings[original] != nil
    }

    /// Clear all proxy mappings.
    public func clearAll() {
        proxyMappings.removeAll()
        generatingSet.removeAll()
    }
}
