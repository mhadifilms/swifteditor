import Foundation
import CoreMediaPlus

#if canImport(Metal)
import Metal
#endif

// MARK: - Plugin Host Service

/// Concrete implementation of PluginHost that provides Metal device access,
/// texture pool management, and structured logging for plugins.
public final class PluginHostService: PluginHost, @unchecked Sendable {
    #if canImport(Metal)
    /// The shared Metal device for GPU-accelerated plugins.
    public let device: MTLDevice?

    /// The command queue used for submitting GPU work.
    public let commandQueue: MTLCommandQueue?
    #endif

    /// Logging handler that plugins invoke through the host.
    private let logHandler: @Sendable (LogLevel, String, String) -> Void

    /// Parameter change handler for host-side observation.
    private let parameterHandler: @Sendable (String, ParameterValue, String) -> Void

    /// The texture pool for reusing Metal textures.
    public let texturePool: TexturePool

    #if canImport(Metal)
    public init(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        logHandler: @escaping @Sendable (LogLevel, String, String) -> Void = { level, message, plugin in
            #if DEBUG
            print("[\(plugin)] \(level): \(message)")
            #endif
        },
        parameterHandler: @escaping @Sendable (String, ParameterValue, String) -> Void = { _, _, _ in }
    ) {
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.logHandler = logHandler
        self.parameterHandler = parameterHandler
        self.texturePool = TexturePool(device: device)
    }
    #else
    public init(
        logHandler: @escaping @Sendable (LogLevel, String, String) -> Void = { level, message, plugin in
            #if DEBUG
            print("[\(plugin)] \(level): \(message)")
            #endif
        },
        parameterHandler: @escaping @Sendable (String, ParameterValue, String) -> Void = { _, _, _ in }
    ) {
        self.logHandler = logHandler
        self.parameterHandler = parameterHandler
        self.texturePool = TexturePool()
    }
    #endif

    // MARK: - PluginHost Protocol

    public func log(_ level: LogLevel, message: String, plugin: String) {
        logHandler(level, message, plugin)
    }

    public func parameterChanged(_ name: String, value: ParameterValue, plugin: String) {
        parameterHandler(name, value, plugin)
    }

    // MARK: - Command Buffer Helpers

    #if canImport(Metal)
    /// Creates a new command buffer from the shared command queue.
    public func makeCommandBuffer() -> MTLCommandBuffer? {
        commandQueue?.makeCommandBuffer()
    }
    #endif
}

// MARK: - Texture Pool

/// Manages a cache of reusable Metal textures to reduce allocation overhead.
public final class TexturePool: @unchecked Sendable {
    #if canImport(Metal)
    private let device: MTLDevice?
    private let lock = NSLock()
    private var pool: [TextureKey: [MTLTexture]] = [:]

    public init(device: MTLDevice?) {
        self.device = device
    }

    /// Checks out a texture with the given dimensions and format, reusing a cached one if available.
    public func checkout(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let key = TextureKey(width: width, height: height, pixelFormat: pixelFormat)
        lock.lock()
        defer { lock.unlock() }
        if var textures = pool[key], !textures.isEmpty {
            let texture = textures.removeLast()
            pool[key] = textures
            return texture
        }
        return createTexture(key: key)
    }

    /// Returns a texture to the pool for reuse.
    public func checkin(_ texture: MTLTexture) {
        let key = TextureKey(width: texture.width, height: texture.height, pixelFormat: texture.pixelFormat)
        lock.lock()
        defer { lock.unlock() }
        pool[key, default: []].append(texture)
    }

    /// Removes all cached textures.
    public func drain() {
        lock.lock()
        defer { lock.unlock() }
        pool.removeAll()
    }

    private func createTexture(key: TextureKey) -> MTLTexture? {
        guard let device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: key.pixelFormat,
            width: key.width,
            height: key.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }
    #else
    public init() {}
    #endif
}
