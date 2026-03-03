import CoreMediaPlus
import Foundation

/// Enhanced asset management that wraps AssetImporter and tracks proxy state per asset.
public actor MediaAssetManager {

    // MARK: - Types

    /// Internal record for a managed asset.
    private struct ManagedAsset {
        let imported: ImportedAsset
        var proxyURL: URL?
        var useProxy: Bool
    }

    // MARK: - State

    private let importer = AssetImporter()
    private var assets: [UUID: ManagedAsset] = [:]
    private var _globalProxyMode: Bool = false

    public init() {}

    // MARK: - Import

    /// Import assets and begin tracking them.
    public func importAssets(from urls: [URL]) async throws -> [ImportedAsset] {
        let imported = try await importer.importAssets(from: urls)
        for asset in imported {
            assets[asset.id] = ManagedAsset(imported: asset, proxyURL: nil, useProxy: false)
        }
        return imported
    }

    // MARK: - Proxy Management

    /// Register a proxy URL for a given asset.
    public func setProxyURL(_ url: URL, for assetID: UUID) {
        assets[assetID]?.proxyURL = url
    }

    /// Switch a specific asset to use its proxy.
    public func useProxy(_ assetID: UUID) {
        assets[assetID]?.useProxy = true
    }

    /// Switch a specific asset to use the original file.
    public func useOriginal(_ assetID: UUID) {
        assets[assetID]?.useProxy = false
    }

    /// The globally active URL for a given asset (respects global and per-asset proxy toggle).
    public func activeURL(for assetID: UUID) -> URL? {
        guard let managed = assets[assetID] else { return nil }
        let wantProxy = _globalProxyMode || managed.useProxy
        if wantProxy, let proxyURL = managed.proxyURL {
            return proxyURL
        }
        return managed.imported.url
    }

    /// Toggle global proxy mode on or off. When enabled, all assets with proxies serve proxies.
    public var globalProxyMode: Bool {
        get { _globalProxyMode }
        set { _globalProxyMode = newValue }
    }

    // MARK: - Queries

    /// All managed asset IDs.
    public var allAssetIDs: [UUID] {
        Array(assets.keys)
    }

    /// Retrieve the original imported metadata for an asset.
    public func importedAsset(for assetID: UUID) -> ImportedAsset? {
        assets[assetID]?.imported
    }

    /// Whether a proxy is available for the given asset.
    public func hasProxy(for assetID: UUID) -> Bool {
        assets[assetID]?.proxyURL != nil
    }

    /// Remove an asset from management.
    public func removeAsset(_ assetID: UUID) {
        assets.removeValue(forKey: assetID)
    }
}
