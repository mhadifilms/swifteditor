import Foundation

/// Smart relinking for media files that have been moved or renamed.
public final class MediaRelinker: Sendable {

    public init() {}

    /// Attempt to relink a single missing file by searching the given directories.
    ///
    /// Strategy:
    /// 1. Exact filename match in each search directory (recursive).
    /// 2. Fuzzy match: same stem with a different extension.
    ///
    /// - Parameters:
    ///   - missingURL: The original URL that is no longer accessible.
    ///   - searchDirectories: Directories to search for the file.
    /// - Returns: The new URL if found, or `nil`.
    public func relink(missingURL: URL, searchDirectories: [URL]) async -> URL? {
        let targetName = missingURL.lastPathComponent
        let targetStem = missingURL.deletingPathExtension().lastPathComponent

        let fm = FileManager.default

        for directory in searchDirectories {
            // Pass 1: exact filename match
            if let found = Self.findFile(
                named: targetName, in: directory, fileManager: fm
            ) {
                return found
            }

            // Pass 2: fuzzy match — same stem, any extension
            if let found = Self.findFileByStem(
                stem: targetStem, in: directory, fileManager: fm
            ) {
                return found
            }
        }

        return nil
    }

    /// Batch relink multiple missing files against a search directory.
    ///
    /// - Parameters:
    ///   - missingURLs: The original URLs that are offline.
    ///   - searchDirectory: The root directory to search within.
    /// - Returns: A mapping from original missing URL to newly found URL.
    public func relinkAll(
        missingURLs: [URL],
        searchDirectory: URL
    ) async -> [URL: URL] {
        var results: [URL: URL] = [:]
        for url in missingURLs {
            if let found = await relink(missingURL: url, searchDirectories: [searchDirectory]) {
                results[url] = found
            }
        }
        return results
    }

    // MARK: - Private

    /// Recursively search for a file with an exact name match.
    private static func findFile(
        named name: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == name {
                return fileURL
            }
        }
        return nil
    }

    /// Recursively search for a file with matching stem (ignoring extension).
    private static func findFileByStem(
        stem: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            if fileURL.deletingPathExtension().lastPathComponent == stem {
                return fileURL
            }
        }
        return nil
    }
}
