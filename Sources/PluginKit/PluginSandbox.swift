import Foundation
import CoreMediaPlus

// MARK: - Plugin Sandbox

/// Validates plugin capabilities and restricts access to host resources.
/// Acts as a gatekeeper between plugins and the host environment.
public struct PluginSandbox: Sendable {

    /// Errors raised when a plugin violates sandbox restrictions.
    public enum SandboxError: Error, Sendable {
        case missingCapability(PluginManifest.PluginCapability, plugin: String)
        case accessDenied(resource: String, plugin: String)
        case invalidManifest(reason: String, plugin: String)
        case hostVersionMismatch(required: String, current: String, plugin: String)
        case pathTraversal(path: String, plugin: String)
    }

    /// The current host version string for compatibility checks.
    public let hostVersion: String

    /// The set of capabilities the host is willing to grant.
    public let grantedCapabilities: Set<PluginManifest.PluginCapability>

    /// Allowed base directories plugins may read from.
    public let allowedReadPaths: [URL]

    /// Allowed base directories plugins may write to.
    public let allowedWritePaths: [URL]

    public init(
        hostVersion: String = "1.0.0",
        grantedCapabilities: Set<PluginManifest.PluginCapability> = Set(PluginManifest.PluginCapability.allCases),
        allowedReadPaths: [URL] = [],
        allowedWritePaths: [URL] = []
    ) {
        self.hostVersion = hostVersion
        self.grantedCapabilities = grantedCapabilities
        self.allowedReadPaths = allowedReadPaths
        self.allowedWritePaths = allowedWritePaths
    }

    // MARK: - Validation

    /// Validates a plugin manifest before the plugin is loaded.
    public func validate(manifest: PluginManifest) throws {
        // Check identifier is non-empty and uses reverse-DNS style
        guard !manifest.identifier.isEmpty else {
            throw SandboxError.invalidManifest(
                reason: "Plugin identifier must not be empty",
                plugin: manifest.identifier
            )
        }

        guard !manifest.name.isEmpty else {
            throw SandboxError.invalidManifest(
                reason: "Plugin name must not be empty",
                plugin: manifest.identifier
            )
        }

        // Check host version compatibility
        if !isVersionCompatible(required: manifest.minimumHostVersion, current: hostVersion) {
            throw SandboxError.hostVersionMismatch(
                required: manifest.minimumHostVersion,
                current: hostVersion,
                plugin: manifest.identifier
            )
        }

        // Verify all requested capabilities are granted
        for capability in manifest.capabilities {
            guard grantedCapabilities.contains(capability) else {
                throw SandboxError.missingCapability(capability, plugin: manifest.identifier)
            }
        }
    }

    /// Checks whether a plugin with the given manifest may use GPU acceleration.
    public func canUseGPU(manifest: PluginManifest) -> Bool {
        manifest.capabilities.contains(.gpuAccelerated) &&
        grantedCapabilities.contains(.gpuAccelerated)
    }

    // MARK: - Filesystem Access

    /// Validates that a plugin may read from the given path.
    public func validateReadAccess(to url: URL, plugin: String) throws {
        let resolved = url.standardizedFileURL
        try checkPathTraversal(resolved, plugin: plugin)

        guard allowedReadPaths.isEmpty || allowedReadPaths.contains(where: { base in
            resolved.path.hasPrefix(base.standardizedFileURL.path)
        }) else {
            throw SandboxError.accessDenied(resource: resolved.path, plugin: plugin)
        }
    }

    /// Validates that a plugin may write to the given path.
    public func validateWriteAccess(to url: URL, plugin: String) throws {
        let resolved = url.standardizedFileURL
        try checkPathTraversal(resolved, plugin: plugin)

        guard allowedWritePaths.isEmpty || allowedWritePaths.contains(where: { base in
            resolved.path.hasPrefix(base.standardizedFileURL.path)
        }) else {
            throw SandboxError.accessDenied(resource: resolved.path, plugin: plugin)
        }
    }

    // MARK: - Private

    private func checkPathTraversal(_ url: URL, plugin: String) throws {
        let path = url.path
        if path.contains("..") {
            throw SandboxError.pathTraversal(path: path, plugin: plugin)
        }
    }

    /// Simple semantic version comparison: returns true if current >= required.
    private func isVersionCompatible(required: String, current: String) -> Bool {
        let requiredParts = required.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(requiredParts.count, currentParts.count) {
            let req = i < requiredParts.count ? requiredParts[i] : 0
            let cur = i < currentParts.count ? currentParts[i] : 0
            if cur > req { return true }
            if cur < req { return false }
        }
        return true // equal
    }
}

// MARK: - PluginCapability + CaseIterable

extension PluginManifest.PluginCapability: CaseIterable {
    public static var allCases: [PluginManifest.PluginCapability] {
        [.gpuAccelerated, .realTimeCapable, .supportsHDR, .supportsMultiChannel, .keyframeable]
    }
}
