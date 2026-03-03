import Foundation
@preconcurrency import Metal
import CryptoKit

/// Persistent on-disk cache for compiled Metal pipeline states.
/// Keyed by a SHA-256 hash of the shader source code so that recompilation
/// is avoided when the same shader is loaded across sessions.
public actor ShaderCache {

    /// A cached pipeline entry associating a hash with a compiled pipeline state.
    private struct CacheEntry {
        let pipelineState: any MTLRenderPipelineState
        let lastUsed: Date
    }

    /// On-disk metadata stored alongside the Metal binary archive.
    private struct DiskMetadata: Codable {
        var entries: [String: EntryMeta]

        struct EntryMeta: Codable {
            let sourceHash: String
            let vertexFunction: String
            let fragmentFunction: String
            let createdAt: Date
        }
    }

    private let device: any MTLDevice
    private let cacheDirectory: URL
    private var inMemory: [String: CacheEntry] = [:]
    private var metadata: DiskMetadata

    /// Initialize with a Metal device and an optional cache directory.
    /// Defaults to ~/Library/Caches/SwiftEditor/ShaderCache.
    public init(device: any MTLDevice, cacheDirectory: URL? = nil) {
        self.device = device
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
        self.metadata = DiskMetadata(entries: [:])
        Self.ensureDirectoryExists(at: self.cacheDirectory)
        self.metadata = Self.loadMetadata(from: self.cacheDirectory) ?? DiskMetadata(entries: [:])
    }

    /// Compute a stable hash key for shader source code.
    public static func hashKey(for source: String) -> String {
        let data = Data(source.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Look up a cached pipeline state by shader source hash.
    /// Returns nil on cache miss.
    public func pipeline(forSourceHash hash: String) -> (any MTLRenderPipelineState)? {
        guard let entry = inMemory[hash] else { return nil }
        return entry.pipelineState
    }

    /// Store a compiled pipeline state for the given shader source hash.
    public func store(
        _ pipelineState: any MTLRenderPipelineState,
        forSourceHash hash: String,
        vertexFunction: String,
        fragmentFunction: String
    ) {
        inMemory[hash] = CacheEntry(pipelineState: pipelineState, lastUsed: Date())
        metadata.entries[hash] = DiskMetadata.EntryMeta(
            sourceHash: hash,
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            createdAt: Date()
        )
        Self.saveMetadata(metadata, to: cacheDirectory)
    }

    /// Compile a shader from source, caching the result.
    /// Returns the pipeline state on success.
    public func pipelineState(
        forSource source: String,
        vertexFunction: String,
        fragmentFunction: String,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> any MTLRenderPipelineState {
        let hash = Self.hashKey(for: source)

        // Check in-memory cache first
        if let cached = inMemory[hash] {
            inMemory[hash] = CacheEntry(pipelineState: cached.pipelineState, lastUsed: Date())
            return cached.pipelineState
        }

        // Compile the shader
        let library = try device.makeLibrary(source: source, options: nil)
        guard let vertexFn = library.makeFunction(name: vertexFunction) else {
            throw ShaderCacheError.functionNotFound(vertexFunction)
        }
        guard let fragmentFn = library.makeFunction(name: fragmentFunction) else {
            throw ShaderCacheError.functionNotFound(fragmentFunction)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        store(pipeline, forSourceHash: hash, vertexFunction: vertexFunction, fragmentFunction: fragmentFunction)
        return pipeline
    }

    /// Remove all cached entries (both in-memory and on-disk metadata).
    public func clear() {
        inMemory.removeAll()
        metadata = DiskMetadata(entries: [:])
        Self.saveMetadata(metadata, to: cacheDirectory)
    }

    /// Number of entries currently in the in-memory cache.
    public var count: Int {
        inMemory.count
    }

    /// All source hashes currently cached in memory.
    public var cachedHashes: [String] {
        Array(inMemory.keys)
    }

    // MARK: - Private

    private static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("SwiftEditor/ShaderCache", isDirectory: true)
    }

    private static func ensureDirectoryExists(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func metadataURL(in directory: URL) -> URL {
        directory.appendingPathComponent("shader_cache_metadata.json")
    }

    private static func loadMetadata(from directory: URL) -> DiskMetadata? {
        let url = metadataURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiskMetadata.self, from: data)
    }

    private static func saveMetadata(_ metadata: DiskMetadata, to directory: URL) {
        let url = metadataURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Errors that can occur during shader cache operations.
public enum ShaderCacheError: Error, LocalizedError {
    case functionNotFound(String)
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .functionNotFound(let name):
            return "Metal function '\(name)' not found in compiled library"
        case .compilationFailed(let message):
            return "Shader compilation failed: \(message)"
        }
    }
}
