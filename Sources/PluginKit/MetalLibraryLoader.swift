import Foundation

#if canImport(Metal)
import Metal

// MARK: - Metal Library Loader

/// Loads `.metallib` files from plugin bundles and compiles shader functions.
public final class MetalLibraryLoader: @unchecked Sendable {
    private let device: MTLDevice
    private let lock = NSLock()
    private var loadedLibraries: [String: MTLLibrary] = [:]
    private var compiledPipelines: [String: MTLComputePipelineState] = [:]

    public enum LoaderError: Error, Sendable {
        case deviceUnavailable
        case libraryNotFound(path: String)
        case libraryLoadFailed(underlying: String)
        case functionNotFound(name: String, library: String)
        case pipelineCreationFailed(function: String, underlying: String)
    }

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Library Loading

    /// Loads a `.metallib` file from disk and caches it by identifier.
    @discardableResult
    public func loadLibrary(from url: URL, identifier: String) throws -> MTLLibrary {
        lock.lock()
        if let cached = loadedLibraries[identifier] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoaderError.libraryNotFound(path: url.path)
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(URL: url)
        } catch {
            throw LoaderError.libraryLoadFailed(underlying: error.localizedDescription)
        }

        lock.lock()
        loadedLibraries[identifier] = library
        lock.unlock()

        return library
    }

    /// Loads a `.metallib` from a plugin bundle by scanning for the first `.metallib` resource.
    @discardableResult
    public func loadLibrary(fromBundle bundle: Bundle, identifier: String) throws -> MTLLibrary {
        lock.lock()
        if let cached = loadedLibraries[identifier] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = bundle.url(forResource: nil, withExtension: "metallib") else {
            throw LoaderError.libraryNotFound(path: bundle.bundlePath)
        }

        return try loadLibrary(from: url, identifier: identifier)
    }

    /// Compiles Metal source code at runtime and caches the resulting library.
    @discardableResult
    public func compileSource(_ source: String, identifier: String) throws -> MTLLibrary {
        lock.lock()
        if let cached = loadedLibraries[identifier] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let options = MTLCompileOptions()
        options.mathMode = .fast

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: options)
        } catch {
            throw LoaderError.libraryLoadFailed(underlying: error.localizedDescription)
        }

        lock.lock()
        loadedLibraries[identifier] = library
        lock.unlock()

        return library
    }

    // MARK: - Function & Pipeline Access

    /// Retrieves a named function from a previously loaded library.
    public func function(named name: String, inLibrary identifier: String) throws -> MTLFunction {
        lock.lock()
        guard let library = loadedLibraries[identifier] else {
            lock.unlock()
            throw LoaderError.libraryNotFound(path: identifier)
        }
        lock.unlock()

        guard let function = library.makeFunction(name: name) else {
            throw LoaderError.functionNotFound(name: name, library: identifier)
        }
        return function
    }

    /// Creates (or retrieves cached) a compute pipeline state for the given function.
    public func computePipeline(functionName: String, inLibrary identifier: String) throws -> MTLComputePipelineState {
        let cacheKey = "\(identifier)/\(functionName)"

        lock.lock()
        if let cached = compiledPipelines[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let fn = try function(named: functionName, inLibrary: identifier)

        let pipeline: MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(function: fn)
        } catch {
            throw LoaderError.pipelineCreationFailed(function: functionName, underlying: error.localizedDescription)
        }

        lock.lock()
        compiledPipelines[cacheKey] = pipeline
        lock.unlock()

        return pipeline
    }

    // MARK: - Cache Management

    /// Returns the identifiers of all loaded libraries.
    public func loadedLibraryIdentifiers() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadedLibraries.keys)
    }

    /// Removes a specific library and its associated pipelines from cache.
    public func unloadLibrary(identifier: String) {
        lock.lock()
        loadedLibraries.removeValue(forKey: identifier)
        let keysToRemove = compiledPipelines.keys.filter { $0.hasPrefix("\(identifier)/") }
        for key in keysToRemove {
            compiledPipelines.removeValue(forKey: key)
        }
        lock.unlock()
    }

    /// Removes all loaded libraries and compiled pipelines from cache.
    public func unloadAll() {
        lock.lock()
        loadedLibraries.removeAll()
        compiledPipelines.removeAll()
        lock.unlock()
    }
}
#endif
