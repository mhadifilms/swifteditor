import Foundation

/// Manages security-scoped bookmarks for sandbox support.
///
/// Allows the application to persist access to user-selected files across launches.
public final class SecurityBookmarks: @unchecked Sendable {

    private let lock = NSLock()
    private var bookmarks: [URL: Data] = [:]
    private var accessedURLs: Set<URL> = []

    public init() {}

    // MARK: - Bookmark Creation & Resolution

    /// Create a security-scoped bookmark for the given URL.
    public func createBookmark(for url: URL) throws -> Data {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        lock.lock()
        bookmarks[url] = data
        lock.unlock()
        return data
    }

    /// Resolve a previously created bookmark back to a URL.
    public func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            // Re-create the bookmark to refresh it
            let refreshed = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lock.lock()
            bookmarks[url] = refreshed
            lock.unlock()
        }
        return url
    }

    // MARK: - Access Management

    /// Begin accessing a security-scoped resource.
    @discardableResult
    public func startAccessing(_ url: URL) -> Bool {
        let success = url.startAccessingSecurityScopedResource()
        if success {
            lock.lock()
            accessedURLs.insert(url)
            lock.unlock()
        }
        return success
    }

    /// Stop accessing a security-scoped resource.
    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
        lock.lock()
        accessedURLs.remove(url)
        lock.unlock()
    }

    /// Stop accessing all currently accessed URLs.
    public func stopAccessingAll() {
        lock.lock()
        let urls = accessedURLs
        accessedURLs.removeAll()
        lock.unlock()
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Storage

    /// All stored bookmarks as a dictionary (for serialization).
    public var storedBookmarks: [URL: Data] {
        lock.lock()
        defer { lock.unlock() }
        return bookmarks
    }

    /// Restore bookmarks from previously serialized data.
    public func restoreBookmarks(_ stored: [URL: Data]) {
        lock.lock()
        bookmarks.merge(stored) { _, new in new }
        lock.unlock()
    }

    /// Remove the bookmark for a specific URL.
    public func removeBookmark(for url: URL) {
        lock.lock()
        bookmarks.removeValue(forKey: url)
        lock.unlock()
    }
}
