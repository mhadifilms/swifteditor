# 09 - Media Management, Import & Asset Handling

## Table of Contents
1. [Media Browser / Bin Organization](#1-media-browser--bin-organization)
2. [AVAsset Metadata Extraction](#2-avasset-metadata-extraction)
3. [Thumbnail Generation & Caching](#3-thumbnail-generation--caching)
4. [Proxy Media Workflow](#4-proxy-media-workflow)
5. [Relinking Offline / Moved Media](#5-relinking-offline--moved-media)
6. [Supported Import Formats on macOS](#6-supported-import-formats-on-macos)
7. [Drag-and-Drop Import from Finder](#7-drag-and-drop-import-from-finder)
8. [Media Analysis](#8-media-analysis)
9. [Project File Format Design](#9-project-file-format-design)
10. [Auto-Save & Versioning](#10-auto-save--versioning)
11. [Undo/Redo Architecture](#11-undoredo-architecture)
12. [Smart Collections & Keyword Tagging](#12-smart-collections--keyword-tagging)
13. [Security-Scoped Bookmarks & Persistent File Access](#13-security-scoped-bookmarks--persistent-file-access)
14. [WWDC Sessions & References](#14-wwdc-sessions--references)

---

## 1. Media Browser / Bin Organization

### Professional NLE Bin Patterns

Professional NLEs (DaVinci Resolve, Premiere Pro, Final Cut Pro) universally use a hierarchical bin/folder system for organizing imported media. The core principles:

**Standard Folder Hierarchy (Numbered for Sort Order):**
```
00_Sequences       (timelines/edits)
10_Audio           (music, SFX, VO, field audio)
20_Footage         (camera A, camera B, day-based bins)
30_Graphics        (titles, lower thirds, logos)
40_Misc            (stills, documents, references)
```

Numbering forces alphabetical sort to match workflow order. This is a UX pattern we should adopt.

**Clip Labeling / Rating System:**
- Star ratings (1-5) for quality assessment
- Color labels for categorical tagging (e.g., red = interview, blue = B-roll)
- Favorites / Rejected flags for quick culling
- Keywords for searchable metadata

### Data Model for Our NLE

```swift
import Foundation

// MARK: - Media Bin (Folder) Model

struct MediaBin: Identifiable, Codable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var color: BinColor?
    var childBinIDs: [UUID]
    var clipIDs: [UUID]
    var isSmartCollection: Bool
    var smartFilter: SmartFilter?

    init(name: String, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.childBinIDs = []
        self.clipIDs = []
        self.isSmartCollection = false
    }
}

enum BinColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray
}

// MARK: - Media Clip Reference

struct MediaClipReference: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var filePath: String                // Original path
    var bookmarkData: Data?             // Security-scoped bookmark
    var mediaType: MediaType

    // Technical metadata
    var duration: Double                // seconds
    var videoResolution: CGSize?
    var frameRate: Double?
    var codec: String?
    var colorSpace: String?
    var bitDepth: Int?
    var audioChannels: Int?
    var audioSampleRate: Double?
    var fileSize: Int64

    // User metadata
    var rating: Int                     // 0-5
    var colorLabel: BinColor?
    var isFavorite: Bool
    var isRejected: Bool
    var keywords: Set<String>
    var notes: String

    // Proxy
    var proxyFilePath: String?
    var proxyBookmarkData: Data?
    var hasProxy: Bool { proxyFilePath != nil }

    // Thumbnails
    var thumbnailCacheKey: String       // key into thumbnail cache

    // State
    var isOffline: Bool
    var importDate: Date
    var lastAccessDate: Date
}

enum MediaType: String, Codable {
    case video
    case audio
    case image
    case sequence      // image sequence (EXR, DPX)
}
```

### Smart Collections

Smart collections are virtual bins whose contents are dynamically computed from filter criteria:

```swift
struct SmartFilter: Codable {
    var rules: [FilterRule]
    var matchType: MatchType         // all rules or any rule

    enum MatchType: String, Codable {
        case all    // AND
        case any    // OR
    }
}

struct FilterRule: Codable {
    var field: FilterField
    var comparison: Comparison
    var value: String

    enum FilterField: String, Codable {
        case keyword, rating, colorLabel, mediaType
        case codec, resolution, frameRate, duration
        case fileName, importDate, isFavorite
    }

    enum Comparison: String, Codable {
        case equals, notEquals
        case contains, notContains
        case greaterThan, lessThan
        case between
    }
}

// Evaluating a smart collection
extension SmartFilter {
    func matches(_ clip: MediaClipReference) -> Bool {
        switch matchType {
        case .all: return rules.allSatisfy { evaluate($0, against: clip) }
        case .any: return rules.contains { evaluate($0, against: clip) }
        }
    }

    private func evaluate(_ rule: FilterRule, against clip: MediaClipReference) -> Bool {
        switch rule.field {
        case .keyword:
            switch rule.comparison {
            case .contains:
                return clip.keywords.contains(rule.value)
            case .notContains:
                return !clip.keywords.contains(rule.value)
            default:
                return false
            }
        case .rating:
            guard let threshold = Int(rule.value) else { return false }
            switch rule.comparison {
            case .greaterThan: return clip.rating > threshold
            case .lessThan: return clip.rating < threshold
            case .equals: return clip.rating == threshold
            default: return false
            }
        case .mediaType:
            return clip.mediaType.rawValue == rule.value
        case .codec:
            return clip.codec?.lowercased().contains(rule.value.lowercased()) ?? false
        case .isFavorite:
            return clip.isFavorite == (rule.value == "true")
        default:
            return false
        }
    }
}
```

---

## 2. AVAsset Metadata Extraction

### Modern Async API (Swift Concurrency)

Since WWDC 2021, Apple deprecated the old `AVAsynchronousKeyValueLoading` protocol in favor of a type-safe `load()` method using Swift concurrency. This is the **only** recommended approach going forward.

```swift
import AVFoundation
import CoreMedia

// MARK: - Comprehensive Metadata Extraction

struct MediaMetadata {
    var duration: CMTime
    var videoResolution: CGSize?
    var frameRate: Double?
    var codec: String?
    var colorPrimaries: String?
    var transferFunction: String?
    var isHDR: Bool
    var bitDepth: Int?
    var audioChannelCount: Int?
    var audioSampleRate: Double?
    var creationDate: Date?
    var fileSize: Int64
}

actor MediaMetadataExtractor {

    /// Extract comprehensive metadata from a media file URL
    func extractMetadata(from url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)

        // Load properties concurrently using the modern async API
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        let creationDate = try await asset.load(.creationDate)
        let metadata = try await asset.load(.metadata)

        var resolution: CGSize?
        var frameRate: Double?
        var codec: String?
        var colorPrimaries: String?
        var transferFunction: String?
        var isHDR = false
        var bitDepth: Int?
        var audioChannelCount: Int?
        var audioSampleRate: Double?

        // Process video tracks
        let videoTracks = tracks.filter { $0.mediaType == .video }
        if let videoTrack = videoTracks.first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)

            // Apply transform to get correct orientation
            let transformedSize = naturalSize.applying(preferredTransform)
            resolution = CGSize(
                width: abs(transformedSize.width),
                height: abs(transformedSize.height)
            )
            frameRate = Double(nominalFrameRate)

            // Extract codec and color space from format descriptions
            if let formatDesc = formatDescriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                codec = fourCharCodeToString(mediaSubType)

                // Color space detection
                if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                    colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                    transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String

                    // HDR detection: PQ (HDR10/Dolby Vision) or HLG
                    if let tf = transferFunction {
                        isHDR = tf.contains("SMPTE_ST_2084") || // PQ / HDR10
                                tf.contains("ITU_R_2100_HLG")   // HLG
                    }

                    // Bit depth
                    if let depth = extensions[kCMFormatDescriptionExtension_Depth as String] as? Int {
                        bitDepth = depth
                    }
                }
            }
        }

        // Process audio tracks
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        if let audioTrack = audioTracks.first {
            let formatDescriptions = try await audioTrack.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                audioChannelCount = Int(asbd?.pointee.mChannelsPerFrame ?? 0)
                audioSampleRate = asbd?.pointee.mSampleRate
            }
        }

        // File size
        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        // Creation date from metadata
        let date: Date? = await {
            if let cdItem = creationDate {
                return try? await cdItem.load(.dateValue)
            }
            return nil
        }()

        return MediaMetadata(
            duration: duration,
            videoResolution: resolution,
            frameRate: frameRate,
            codec: codec,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            isHDR: isHDR,
            bitDepth: bitDepth,
            audioChannelCount: audioChannelCount,
            audioSampleRate: audioSampleRate,
            creationDate: date,
            fileSize: fileSize
        )
    }

    /// Convert FourCharCode to human-readable string
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
            CChar(truncatingIfNeeded: code & 0xFF),
            0
        ]
        return String(cString: bytes)
    }

    /// Map codec FourCharCode to readable name
    static func codecDisplayName(for fourCC: String) -> String {
        switch fourCC.trimmingCharacters(in: .whitespaces) {
        case "avc1", "avc2", "avc3": return "H.264"
        case "hvc1", "hev1": return "H.265 (HEVC)"
        case "ap4h": return "Apple ProRes 4444"
        case "ap4x": return "Apple ProRes 4444 XQ"
        case "apch": return "Apple ProRes 422 HQ"
        case "apcn": return "Apple ProRes 422"
        case "apcs": return "Apple ProRes 422 LT"
        case "apco": return "Apple ProRes 422 Proxy"
        case "aprh": return "Apple ProRes RAW HQ"
        case "aprn": return "Apple ProRes RAW"
        case "av01": return "AV1"
        case "mp4v": return "MPEG-4"
        case "jpeg": return "Photo JPEG"
        case "mjpg": return "Motion JPEG"
        case "png ": return "PNG"
        case "dvc ": return "DV (NTSC)"
        case "dvcp": return "DV (PAL)"
        case "dvh5", "dvh6": return "DVCPRO HD"
        default: return fourCC
        }
    }
}
```

### Common Metadata Keys

```swift
import AVFoundation

/// Extract common metadata (title, artist, album art, etc.)
func extractCommonMetadata(from asset: AVAsset) async throws -> [String: Any] {
    let metadata = try await asset.load(.commonMetadata)
    var result: [String: Any] = [:]

    for item in metadata {
        guard let commonKey = item.commonKey else { continue }

        switch commonKey {
        case .commonKeyTitle:
            result["title"] = try? await item.load(.stringValue)
        case .commonKeyCreationDate:
            result["creationDate"] = try? await item.load(.stringValue)
        case .commonKeyDescription:
            result["description"] = try? await item.load(.stringValue)
        case .commonKeyLocation:
            result["location"] = try? await item.load(.stringValue)
        case .commonKeyMake:
            result["cameraMake"] = try? await item.load(.stringValue)
        case .commonKeyModel:
            result["cameraModel"] = try? await item.load(.stringValue)
        case .commonKeySoftware:
            result["software"] = try? await item.load(.stringValue)
        case .commonKeyArtwork:
            result["artwork"] = try? await item.load(.dataValue)
        default:
            break
        }
    }

    return result
}
```

### MediaToolbox Notes

`MediaToolbox.framework` is largely a **private** Apple framework used internally by AVFoundation. It handles:
- Media format readers (plugin architecture for codec support)
- Audio tap processing (`MTAudioProcessingTap`)
- Internal format detection

For our NLE, we should use AVFoundation's public APIs rather than MediaToolbox directly. The one public API of note is `MTAudioProcessingTap` for real-time audio processing during playback (see the audio engine research document for details).

---

## 3. Thumbnail Generation & Caching

### AVAssetImageGenerator - Modern API

```swift
import AVFoundation
import AppKit

// MARK: - Thumbnail Generator

actor ThumbnailGenerator {

    /// Generate a single thumbnail at a specific time
    func generateThumbnail(
        for asset: AVAsset,
        at time: CMTime,
        maxSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> NSImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSize
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // Modern async API (iOS 16+ / macOS 13+)
        let (cgImage, _) = try await generator.image(at: time)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Generate multiple thumbnails for a filmstrip (timeline view)
    func generateFilmstrip(
        for asset: AVAsset,
        count: Int,
        maxSize: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [(CMTime, NSImage)] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0, count > 0 else { return [] }

        let interval = durationSeconds / Double(count)
        let times = (0..<count).map { i in
            CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSize
        generator.appliesPreferredTrackTransform = true
        // Allow tolerance for faster generation
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var results: [(CMTime, NSImage)] = []

        // Modern batch API (Swift concurrency)
        for await result in generator.images(for: times) {
            switch result {
            case .success(let requestedTime, let image, _):
                let nsImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                results.append((requestedTime, nsImage))
            case .failure(let requestedTime, let error):
                print("Failed to generate thumbnail at \(requestedTime): \(error)")
            }
        }

        return results
    }
}
```

### Two-Tier Thumbnail Cache

NLE timeline thumbnails require a two-tier caching strategy: fast in-memory cache for visible thumbnails and persistent disk cache for project continuity.

```swift
import AppKit
import CryptoKit

// MARK: - Thumbnail Cache

final class ThumbnailCache {

    // Tier 1: In-memory cache using NSCache (auto-evicts under memory pressure)
    private let memoryCache = NSCache<NSString, NSImage>()

    // Tier 2: Disk cache directory
    private let diskCacheURL: URL

    // Track pending generation to avoid duplicate work
    private var pendingRequests: Set<String> = []
    private let lock = NSLock()

    init(projectID: UUID) {
        // Store thumbnails in Application Support / project-specific folder
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.diskCacheURL = appSupport
            .appendingPathComponent("SwiftEditor")
            .appendingPathComponent("ThumbnailCache")
            .appendingPathComponent(projectID.uuidString)

        try? FileManager.default.createDirectory(
            at: diskCacheURL,
            withIntermediateDirectories: true
        )

        // Configure memory cache limits
        memoryCache.countLimit = 500          // max 500 thumbnails in memory
        memoryCache.totalCostLimit = 100_000_000  // ~100 MB
    }

    /// Generate a cache key from clip ID + time
    func cacheKey(clipID: UUID, time: CMTime) -> String {
        let timeStr = String(format: "%.3f", CMTimeGetSeconds(time))
        return "\(clipID.uuidString)_\(timeStr)"
    }

    /// Retrieve thumbnail (memory -> disk -> nil)
    func thumbnail(forKey key: String) -> NSImage? {
        // Check memory first
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        if let image = NSImage(contentsOf: fileURL) {
            // Promote back to memory cache
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }

        return nil
    }

    /// Store thumbnail in both tiers
    func store(_ image: NSImage, forKey key: String) {
        // Memory
        memoryCache.setObject(image, forKey: key as NSString)

        // Disk (JPEG for space efficiency)
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(
               using: .jpeg,
               properties: [.compressionFactor: 0.7]
           ) {
            try? jpegData.write(to: fileURL)
        }
    }

    /// Remove all cached thumbnails for a clip
    func invalidate(clipID: UUID) {
        // Remove from disk
        let prefix = clipID.uuidString
        if let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Clear entire cache (e.g., project deleted)
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(
            at: diskCacheURL,
            withIntermediateDirectories: true
        )
    }

    /// Get total disk cache size
    func diskCacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
}
```

### Filmstrip Generation Strategy for Timeline

For NLE timelines, thumbnails must be generated at varying densities depending on zoom level:

1. **Low density (zoomed out)**: 1 thumbnail per clip (poster frame)
2. **Medium density**: Thumbnails every few seconds (based on clip width in pixels)
3. **High density (zoomed in)**: Thumbnails at every visible frame boundary

```swift
// MARK: - Timeline Thumbnail Manager

@MainActor
class TimelineThumbnailManager: ObservableObject {

    private let generator = ThumbnailGenerator()
    private let cache: ThumbnailCache

    // Currently visible range for prioritized generation
    private var visibleTimeRange: CMTimeRange?

    // Background generation task (cancellable)
    private var generationTask: Task<Void, Never>?

    init(cache: ThumbnailCache) {
        self.cache = cache
    }

    /// Request thumbnails for a clip at specific times
    /// Returns immediately with cached thumbnails and fills gaps asynchronously
    func requestThumbnails(
        clipID: UUID,
        asset: AVAsset,
        times: [CMTime],
        maxSize: CGSize
    ) -> [CMTime: NSImage] {
        var results: [CMTime: NSImage] = [:]
        var missingTimes: [CMTime] = []

        // Serve from cache immediately
        for time in times {
            let key = cache.cacheKey(clipID: clipID, time: time)
            if let cached = cache.thumbnail(forKey: key) {
                results[time] = cached
            } else {
                missingTimes.append(time)
            }
        }

        // Generate missing thumbnails in background
        if !missingTimes.isEmpty {
            generationTask?.cancel()
            generationTask = Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }

                let gen = AVAssetImageGenerator(asset: asset)
                gen.maximumSize = maxSize
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
                gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

                for await result in gen.images(for: missingTimes) {
                    guard !Task.isCancelled else { break }

                    if case .success(_, let cgImage, _) = result {
                        let nsImage = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        )
                        let key = await self.cache.cacheKey(clipID: clipID, time: result.requestedTime)
                        await self.cache.store(nsImage, forKey: key)

                        // Notify UI to refresh
                        await MainActor.run {
                            self.objectWillChange.send()
                        }
                    }
                }
            }
        }

        return results
    }
}
```

---

## 4. Proxy Media Workflow

### Overview

Proxy workflows let editors work with lightweight copies of high-resolution footage for smooth playback, then switch to originals for export. Key concepts:

- **Proxy generation**: Transcode original to lower-resolution codec (e.g., ProRes Proxy, H.264 at 1/4 resolution)
- **Proxy/original toggle**: Switch between proxy and original for playback vs export
- **Metadata preservation**: Proxies must match original timecode, frame count, and aspect ratio

### Implementation

```swift
import AVFoundation

// MARK: - Proxy Generator

actor ProxyMediaGenerator {

    enum ProxyPreset {
        case quarterRes     // 1/4 original resolution, H.264
        case halfRes        // 1/2 original resolution, H.264
        case proResProxy    // Full resolution, ProRes Proxy (fast decode)

        var exportPreset: String {
            switch self {
            case .quarterRes: return AVAssetExportPresetLowQuality
            case .halfRes: return AVAssetExportPresetMediumQuality
            case .proResProxy: return AVAssetExportPresetAppleProRes422LPCM
            }
        }
    }

    /// Generate a proxy file for the given media
    func generateProxy(
        for sourceURL: URL,
        preset: ProxyPreset = .halfRes,
        outputDirectory: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Determine output filename
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDirectory
            .appendingPathComponent("\(baseName)_proxy")
            .appendingPathExtension("mov")

        // Check if preset is compatible
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset.exportPreset,
            with: asset,
            outputFileType: .mov
        ) else {
            throw ProxyError.incompatiblePreset
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset.exportPreset
        ) else {
            throw ProxyError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false

        // Monitor progress
        let progressTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let currentProgress = Double(exportSession.progress)
                progress(currentProgress)
            }
        }

        // Export
        await exportSession.export()
        progressTask.cancel()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? ProxyError.exportFailed
        }

        progress(1.0)
        return outputURL
    }

    enum ProxyError: Error {
        case incompatiblePreset
        case exportSessionCreationFailed
        case exportFailed
    }
}

// MARK: - Proxy Toggle Manager

class ProxyManager: ObservableObject {

    @Published var useProxy: Bool = false

    private var proxyDirectory: URL

    init(projectDirectory: URL) {
        self.proxyDirectory = projectDirectory.appendingPathComponent("Proxies")
        try? FileManager.default.createDirectory(
            at: proxyDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Get the appropriate URL for a clip based on proxy toggle
    func resolveMediaURL(for clip: MediaClipReference) -> URL {
        if useProxy, let proxyPath = clip.proxyFilePath {
            let proxyURL = URL(fileURLWithPath: proxyPath)
            if FileManager.default.fileExists(atPath: proxyURL.path) {
                return proxyURL
            }
        }
        // Fall back to original
        return URL(fileURLWithPath: clip.filePath)
    }

    /// Queue proxy generation for multiple clips
    func generateProxies(
        for clips: [MediaClipReference],
        preset: ProxyMediaGenerator.ProxyPreset = .halfRes,
        progress: @escaping (Int, Int, Double) -> Void  // (completed, total, currentItemProgress)
    ) async -> [UUID: URL] {
        let generator = ProxyMediaGenerator()
        var results: [UUID: URL] = [:]
        let total = clips.count

        for (index, clip) in clips.enumerated() {
            let sourceURL = URL(fileURLWithPath: clip.filePath)
            do {
                let proxyURL = try await generator.generateProxy(
                    for: sourceURL,
                    preset: preset,
                    outputDirectory: proxyDirectory,
                    progress: { itemProgress in
                        progress(index, total, itemProgress)
                    }
                )
                results[clip.id] = proxyURL
            } catch {
                print("Failed to generate proxy for \(clip.fileName): \(error)")
            }
        }

        return results
    }
}
```

### Proxy Workflow Design Principles

1. **Proxy naming convention**: `{originalName}_proxy.mov` stored in `{ProjectDir}/Proxies/`
2. **Resolution matching**: Proxy frame count and timecodes must exactly match the original
3. **Toggle is global**: When user switches to proxy mode, all clips switch simultaneously
4. **Export always uses originals**: Never export from proxy files
5. **Proxy status indicators**: Show proxy badge on clips in media pool when proxy is available
6. **Background generation**: Generate proxies in background, update clip references when done

---

## 5. Relinking Offline / Moved Media

### The Problem

Media files referenced by the project can become "offline" when:
- External drives are disconnected
- Files are moved or renamed
- Network volumes become unreachable
- Project is transferred to another machine

### Relink Strategy

```swift
import Foundation

// MARK: - Media Relinker

class MediaRelinker {

    enum RelinkResult {
        case found(URL)
        case notFound
        case ambiguous([URL])   // Multiple potential matches
    }

    /// Attempt to automatically relink offline clips
    func autoRelink(
        clips: [MediaClipReference],
        searchDirectories: [URL]
    ) async -> [UUID: RelinkResult] {
        var results: [UUID: RelinkResult] = [:]

        for clip in clips where clip.isOffline {
            let result = await findFile(
                originalPath: clip.filePath,
                fileName: clip.fileName,
                fileSize: clip.fileSize,
                in: searchDirectories
            )
            results[clip.id] = result
        }

        return results
    }

    /// Search for a specific file using multiple strategies
    private func findFile(
        originalPath: String,
        fileName: String,
        fileSize: Int64,
        in directories: [URL]
    ) async -> RelinkResult {

        // Strategy 1: Check if file still exists at original path
        if FileManager.default.fileExists(atPath: originalPath) {
            return .found(URL(fileURLWithPath: originalPath))
        }

        // Strategy 2: Try resolving security-scoped bookmark
        // (handled externally before calling this method)

        // Strategy 3: Search by filename + file size match in specified directories
        var candidates: [URL] = []

        for directory in directories {
            let found = searchDirectory(
                directory,
                fileName: fileName,
                fileSize: fileSize
            )
            candidates.append(contentsOf: found)
        }

        switch candidates.count {
        case 0: return .notFound
        case 1: return .found(candidates[0])
        default: return .ambiguous(candidates)
        }
    }

    /// Recursively search a directory for a file matching name and size
    private func searchDirectory(
        _ directory: URL,
        fileName: String,
        fileSize: Int64
    ) -> [URL] {
        var results: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ) else { continue }

            guard values.isRegularFile == true else { continue }

            if fileURL.lastPathComponent == fileName {
                // Also verify file size matches for confidence
                if let size = values.fileSize, Int64(size) == fileSize {
                    results.append(fileURL)
                }
            }
        }

        return results
    }

    /// Relink clips by changing the source folder (like DaVinci Resolve's "Change Source Folder")
    func relinkByFolderChange(
        clips: [MediaClipReference],
        oldBasePath: String,
        newBasePath: String
    ) -> [UUID: URL] {
        var results: [UUID: URL] = [:]

        for clip in clips {
            if clip.filePath.hasPrefix(oldBasePath) {
                let relativePath = String(clip.filePath.dropFirst(oldBasePath.count))
                let newPath = newBasePath + relativePath
                if FileManager.default.fileExists(atPath: newPath) {
                    results[clip.id] = URL(fileURLWithPath: newPath)
                }
            }
        }

        return results
    }
}
```

### Best Practices for Relink

1. **Store both absolute path and security-scoped bookmark** for each clip
2. **Store relative path from project file** as fallback
3. **File identity heuristic**: Match by filename + file size + duration (not just name)
4. **Relink dialog**: Show user offline clips, allow manual selection, offer auto-search
5. **Remember search locations**: Cache user-selected relink directories for future sessions
6. **Batch relink**: Support "Change Source Folder" that remaps path prefixes

---

## 6. Supported Import Formats on macOS

### Video Container Formats

| Container | Extension(s) | AVFoundation Support | Notes |
|-----------|-------------|---------------------|-------|
| QuickTime | .mov | Native | Apple's native container |
| MPEG-4 | .mp4, .m4v | Native | Most common |
| MPEG Transport Stream | .ts, .mts | Native | AVCHD camcorders |
| AVI | .avi | Partial | Limited codec support |
| MKV (Matroska) | .mkv | macOS 13+ | Added in Ventura |
| WebM | .webm | Limited | VP8/VP9 partial |

### Video Codecs

| Codec | FourCC | AVFoundation | Hardware Decode | Notes |
|-------|--------|-------------|-----------------|-------|
| H.264 / AVC | avc1 | Yes | Yes (all Macs) | Universal |
| H.265 / HEVC | hvc1, hev1 | Yes | Yes (2017+ Macs) | 50% better compression |
| Apple ProRes 422 | apcn | Yes | Yes (M1+) | Professional editing standard |
| Apple ProRes 422 HQ | apch | Yes | Yes (M1+) | Higher quality variant |
| Apple ProRes 422 LT | apcs | Yes | Yes (M1+) | Lightweight variant |
| Apple ProRes 422 Proxy | apco | Yes | Yes (M1+) | Lowest quality, offline editing |
| Apple ProRes 4444 | ap4h | Yes | Yes (M1+) | With alpha channel |
| Apple ProRes 4444 XQ | ap4x | Yes | Yes (M1+) | Highest quality ProRes |
| Apple ProRes RAW | aprn | Yes | Yes (M1+) | RAW sensor data |
| Apple ProRes RAW HQ | aprh | Yes | Yes (M1+) | Higher quality RAW |
| AV1 | av01 | macOS 13+ | Yes (M3+) | Open royalty-free |
| MPEG-4 Part 2 | mp4v | Yes | No | Legacy |
| Motion JPEG | mjpg | Yes | No | Some cameras |
| DV / DVCPRO | dvc, dvcp | Yes | No | Legacy tape formats |
| DVCPRO HD | dvh5, dvh6 | Yes | No | HD tape format |
| Photo JPEG | jpeg | Yes | No | Legacy |
| Apple Animation | rle | Yes | No | Lossless with alpha |

### Audio Formats

| Format | Extension(s) | Notes |
|--------|-------------|-------|
| AAC | .aac, .m4a | Most common lossy |
| Apple Lossless (ALAC) | .m4a, .caf | Lossless |
| WAV | .wav | Uncompressed PCM |
| AIFF | .aiff, .aif | Uncompressed PCM |
| MP3 | .mp3 | Lossy |
| FLAC | .flac | Open lossless |
| Opus | .opus | Modern efficient |
| AC-3 / E-AC-3 | .ac3, .eac3 | Dolby Digital |

### Image Formats (for stills/graphics)

| Format | Extension(s) | Notes |
|--------|-------------|-------|
| JPEG | .jpg, .jpeg | Universal |
| PNG | .png | Lossless with alpha |
| TIFF | .tif, .tiff | Professional |
| HEIF/HEIC | .heic, .heif | Apple modern |
| OpenEXR | .exr | HDR, VFX standard |
| DPX | .dpx | Film scanning |
| PSD | .psd | Photoshop (limited) |
| BMP | .bmp | Uncompressed |

### Checking Format Support at Runtime

```swift
import AVFoundation
import UniformTypeIdentifiers

/// Check which formats AVFoundation supports on this system
func logSupportedFormats() {
    // Supported media types for playback
    let supportedTypes = AVURLAsset.audiovisualTypes()
    print("Supported AV Types:")
    for type in supportedTypes {
        if let utType = UTType(type.rawValue) {
            print("  \(utType.identifier) - \(utType.localizedDescription ?? "unknown")")
        }
    }

    // Supported export presets
    print("\nSupported Export Presets:")
    for preset in AVAssetExportSession.allExportPresets() {
        print("  \(preset)")
    }
}

/// Check if a specific file can be imported
func canImport(url: URL) async -> Bool {
    let asset = AVURLAsset(url: url)
    do {
        let isPlayable = try await asset.load(.isPlayable)
        return isPlayable
    } catch {
        return false
    }
}
```

---

## 7. Drag-and-Drop Import from Finder

### SwiftUI Implementation

```swift
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Media Drop Target

struct MediaDropTarget: View {

    @EnvironmentObject var mediaLibrary: MediaLibrary
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            // Your media browser content
            MediaBrowserView()

            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .dropDestination(for: URL.self) { urls, location in
            return await handleDrop(urls: urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private func handleDrop(urls: [URL]) async -> Bool {
        let supportedTypes: Set<UTType> = [
            .movie, .video, .quickTimeMovie, .mpeg4Movie, .avi,
            .audio, .wav, .aiff, .mp3,
            .image, .jpeg, .png, .tiff, .heic
        ]

        var importedCount = 0

        for url in urls {
            // Verify the file type is supported
            guard let utType = UTType(filenameExtension: url.pathExtension),
                  supportedTypes.contains(where: { utType.conforms(to: $0) })
            else { continue }

            // Create security-scoped bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                await mediaLibrary.importFile(
                    url: url,
                    bookmarkData: bookmarkData
                )
                importedCount += 1
            } catch {
                print("Failed to create bookmark for \(url): \(error)")
            }
        }

        return importedCount > 0
    }
}

// MARK: - File Importer (Open Panel)

struct MediaImportButton: View {

    @EnvironmentObject var mediaLibrary: MediaLibrary
    @State private var showingImporter = false

    var body: some View {
        Button("Import Media") {
            showingImporter = true
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.movie, .video, .audio, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        // Must start security-scoped access for fileImporter URLs
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }

                        let bookmarkData = try? url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )

                        await mediaLibrary.importFile(
                            url: url,
                            bookmarkData: bookmarkData
                        )
                    }
                }
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
    }
}
```

### Media Library Import Pipeline

```swift
import AVFoundation

// MARK: - Media Library

@MainActor
class MediaLibrary: ObservableObject {

    @Published var clips: [MediaClipReference] = []
    @Published var bins: [MediaBin] = []
    @Published var importProgress: Double = 0

    private let metadataExtractor = MediaMetadataExtractor()

    /// Import a single file into the library
    func importFile(url: URL, bookmarkData: Data?) async {
        // Avoid duplicates
        guard !clips.contains(where: { $0.filePath == url.path }) else { return }

        do {
            let metadata = try await metadataExtractor.extractMetadata(from: url)

            let mediaType: MediaType
            if metadata.videoResolution != nil {
                mediaType = .video
            } else if metadata.audioChannelCount != nil {
                mediaType = .audio
            } else {
                mediaType = .image
            }

            let clip = MediaClipReference(
                id: UUID(),
                fileName: url.lastPathComponent,
                filePath: url.path,
                bookmarkData: bookmarkData,
                mediaType: mediaType,
                duration: CMTimeGetSeconds(metadata.duration),
                videoResolution: metadata.videoResolution,
                frameRate: metadata.frameRate,
                codec: metadata.codec,
                colorSpace: metadata.colorPrimaries,
                bitDepth: metadata.bitDepth,
                audioChannels: metadata.audioChannelCount,
                audioSampleRate: metadata.audioSampleRate,
                fileSize: metadata.fileSize,
                rating: 0,
                colorLabel: nil,
                isFavorite: false,
                isRejected: false,
                keywords: [],
                notes: "",
                proxyFilePath: nil,
                proxyBookmarkData: nil,
                thumbnailCacheKey: UUID().uuidString,
                isOffline: false,
                importDate: Date(),
                lastAccessDate: Date()
            )

            clips.append(clip)
        } catch {
            print("Failed to import \(url.lastPathComponent): \(error)")
        }
    }

    /// Batch import with progress tracking
    func importFiles(urls: [URL], bookmarkDatas: [URL: Data]) async {
        let total = urls.count
        for (index, url) in urls.enumerated() {
            await importFile(url: url, bookmarkData: bookmarkDatas[url])
            importProgress = Double(index + 1) / Double(total)
        }
        importProgress = 0 // reset
    }

    /// Check for offline clips on launch
    func validateMediaPaths() {
        for index in clips.indices {
            let exists = FileManager.default.fileExists(atPath: clips[index].filePath)
            clips[index].isOffline = !exists
        }
    }
}
```

---

## 8. Media Analysis

### Scene Detection (Cut Detection)

Scene detection compares consecutive frames to identify hard cuts and transitions:

```swift
import AVFoundation
import CoreImage

// MARK: - Scene Detector

actor SceneDetector {

    struct SceneChange {
        let time: CMTime
        let confidence: Double  // 0.0 - 1.0
        let type: ChangeType

        enum ChangeType {
            case hardCut
            case dissolve
            case fade
        }
    }

    /// Detect scene changes by comparing frame histograms
    func detectScenes(
        in asset: AVAsset,
        threshold: Double = 0.35,
        progress: @escaping (Double) -> Void
    ) async throws -> [SceneChange] {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            return []
        }
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160,    // Downscale for speed
            kCVPixelBufferHeightKey as String: 90
        ]

        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: outputSettings
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var sceneChanges: [SceneChange] = []
        var previousHistogram: [Float]?
        let durationSeconds = CMTimeGetSeconds(duration)

        // Sample every Nth frame for performance (e.g., every 3rd frame)
        let sampleInterval = max(1, Int(nominalFrameRate / 10))
        var frameIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            frameIndex += 1

            // Skip frames for performance
            guard frameIndex % sampleInterval == 0 else { continue }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let currentSeconds = CMTimeGetSeconds(presentationTime)
            progress(currentSeconds / durationSeconds)

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let histogram = computeHistogram(from: pixelBuffer)

            if let prev = previousHistogram {
                let difference = histogramDifference(prev, histogram)

                if difference > threshold {
                    let changeType: SceneChange.ChangeType
                    if difference > 0.7 {
                        changeType = .hardCut
                    } else if difference > 0.5 {
                        changeType = .dissolve
                    } else {
                        changeType = .fade
                    }

                    sceneChanges.append(SceneChange(
                        time: presentationTime,
                        confidence: min(1.0, difference),
                        type: changeType
                    ))
                }
            }

            previousHistogram = histogram
        }

        progress(1.0)
        return sceneChanges
    }

    /// Compute a color histogram for a pixel buffer
    private func computeHistogram(from pixelBuffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Array(repeating: 0, count: 768) // 256 * 3 channels
        }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        var histogram = Array(repeating: Float(0), count: 768)
        let totalPixels = Float(width * height)

        // Sample every 4th pixel for speed
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * 4
                let b = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let r = Int(buffer[offset + 2])

                histogram[r] += 1
                histogram[256 + g] += 1
                histogram[512 + b] += 1
            }
        }

        // Normalize
        let sampleCount = Float(width / 2) * Float(height / 2)
        for i in 0..<768 {
            histogram[i] /= sampleCount
        }

        return histogram
    }

    /// Compare two histograms using Chi-squared distance
    private func histogramDifference(_ a: [Float], _ b: [Float]) -> Double {
        var diff: Float = 0
        for i in 0..<min(a.count, b.count) {
            let sum = a[i] + b[i]
            if sum > 0 {
                diff += (a[i] - b[i]) * (a[i] - b[i]) / sum
            }
        }
        return Double(diff / Float(a.count))
    }
}
```

### Audio Level Analysis

```swift
import AVFoundation
import Accelerate

// MARK: - Audio Level Analyzer

actor AudioLevelAnalyzer {

    struct AudioLevelData {
        let time: Double           // seconds
        let peakLevel: Float       // 0.0 - 1.0
        let rmsLevel: Float        // 0.0 - 1.0
        let rmsDB: Float           // decibels (-inf to 0)
    }

    /// Analyze audio levels for waveform display
    func analyzeAudioLevels(
        url: URL,
        samplesPerSecond: Int = 30
    ) async throws -> [AudioLevelData] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(audioFile.length)

        let framesPerSample = AVAudioFrameCount(sampleRate / Double(samplesPerSecond))
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: framesPerSample
        )!

        var levels: [AudioLevelData] = []
        var currentFrame: AVAudioFramePosition = 0

        while currentFrame < audioFile.length {
            audioFile.framePosition = currentFrame
            let framesToRead = min(framesPerSample, totalFrames - AVAudioFrameCount(currentFrame))

            try audioFile.read(into: buffer, frameCount: framesToRead)

            guard let channelData = buffer.floatChannelData else { break }
            let frameCount = Int(buffer.frameLength)

            // Calculate peak and RMS for first channel
            var peak: Float = 0
            var rms: Float = 0

            vDSP_maxmgv(channelData[0], 1, &peak, vDSP_Length(frameCount))
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameCount))

            let timeInSeconds = Double(currentFrame) / sampleRate
            let rmsDB = 20 * log10(max(rms, 1e-10))

            levels.append(AudioLevelData(
                time: timeInSeconds,
                peakLevel: min(peak, 1.0),
                rmsLevel: min(rms, 1.0),
                rmsDB: rmsDB
            ))

            currentFrame += AVAudioFramePosition(framesPerSample)
        }

        return levels
    }

    /// Check if audio has clipping (levels exceeding 0 dBFS)
    func detectClipping(url: URL) async throws -> [(time: Double, duration: Double)] {
        let levels = try await analyzeAudioLevels(url: url, samplesPerSecond: 100)
        var clippingRegions: [(time: Double, duration: Double)] = []
        var clipStart: Double?

        for level in levels {
            if level.peakLevel >= 0.99 {
                if clipStart == nil {
                    clipStart = level.time
                }
            } else if let start = clipStart {
                clippingRegions.append((time: start, duration: level.time - start))
                clipStart = nil
            }
        }

        return clippingRegions
    }
}
```

---

## 9. Project File Format Design

### Format Comparison

| Format | Pros | Cons | Used By |
|--------|------|------|---------|
| **SQLite** | ACID transactions, incremental saves, concurrent access, SQL queries, extensible schema | Slightly more complex API than flat files | DaVinci Resolve, Lightroom, Photos.app |
| **JSON** | Human-readable, easy debugging, Codable support, diff-friendly | Must rewrite entire file on save, no partial updates, large files slow | Many web-based editors |
| **Custom Binary** | Maximum performance, smallest file size | Complex to implement, hard to debug, version migration nightmares | Premiere Pro (.prproj is gzipped XML), After Effects |
| **SQLite + JSON Blobs** | Best of both: relational structure with flexible JSON data | Slightly complex | **Recommended for our NLE** |

### Recommended: SQLite with JSON Blobs

```swift
import SQLite3
import Foundation

// MARK: - Project Database Schema

/*
 Schema Design for SwiftEditor Project File (.swproj)

 The project file is a SQLite database with the following tables:
*/

let projectSchema = """
-- Project metadata
CREATE TABLE IF NOT EXISTS project_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Media clips (source files)
CREATE TABLE IF NOT EXISTS media_clips (
    id TEXT PRIMARY KEY,                    -- UUID
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    bookmark_data BLOB,                     -- security-scoped bookmark
    media_type TEXT NOT NULL,               -- video/audio/image
    duration_seconds REAL,
    video_width INTEGER,
    video_height INTEGER,
    frame_rate REAL,
    codec TEXT,
    color_space TEXT,
    bit_depth INTEGER,
    audio_channels INTEGER,
    audio_sample_rate REAL,
    file_size INTEGER,
    rating INTEGER DEFAULT 0,
    color_label TEXT,
    is_favorite INTEGER DEFAULT 0,
    is_rejected INTEGER DEFAULT 0,
    keywords TEXT,                           -- JSON array of strings
    notes TEXT DEFAULT '',
    proxy_path TEXT,
    proxy_bookmark BLOB,
    is_offline INTEGER DEFAULT 0,
    import_date TEXT NOT NULL,               -- ISO 8601
    metadata_json TEXT                       -- extensible JSON blob
);

-- Media bins (folders)
CREATE TABLE IF NOT EXISTS media_bins (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    sort_order INTEGER DEFAULT 0,
    color TEXT,
    is_smart_collection INTEGER DEFAULT 0,
    smart_filter_json TEXT,                  -- SmartFilter as JSON
    FOREIGN KEY (parent_id) REFERENCES media_bins(id)
);

-- Bin-clip membership (many-to-many)
CREATE TABLE IF NOT EXISTS bin_clips (
    bin_id TEXT NOT NULL,
    clip_id TEXT NOT NULL,
    sort_order INTEGER DEFAULT 0,
    PRIMARY KEY (bin_id, clip_id),
    FOREIGN KEY (bin_id) REFERENCES media_bins(id),
    FOREIGN KEY (clip_id) REFERENCES media_clips(id)
);

-- Sequences (timelines)
CREATE TABLE IF NOT EXISTS sequences (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    frame_rate_num INTEGER NOT NULL,         -- numerator (e.g., 24000)
    frame_rate_den INTEGER NOT NULL,         -- denominator (e.g., 1001)
    audio_sample_rate REAL DEFAULT 48000,
    audio_channels INTEGER DEFAULT 2,
    created_date TEXT NOT NULL,
    modified_date TEXT NOT NULL,
    settings_json TEXT                       -- additional settings as JSON
);

-- Timeline tracks
CREATE TABLE IF NOT EXISTS tracks (
    id TEXT PRIMARY KEY,
    sequence_id TEXT NOT NULL,
    name TEXT NOT NULL,
    track_type TEXT NOT NULL,                -- video/audio
    track_index INTEGER NOT NULL,
    is_locked INTEGER DEFAULT 0,
    is_visible INTEGER DEFAULT 1,
    is_muted INTEGER DEFAULT 0,
    height INTEGER DEFAULT 60,               -- UI height in pixels
    FOREIGN KEY (sequence_id) REFERENCES sequences(id)
);

-- Timeline clips
CREATE TABLE IF NOT EXISTS timeline_clips (
    id TEXT PRIMARY KEY,
    track_id TEXT NOT NULL,
    media_clip_id TEXT,                      -- NULL for generated content (titles, etc.)
    timeline_start INTEGER NOT NULL,         -- frame number on timeline
    timeline_duration INTEGER NOT NULL,      -- duration in frames
    source_in INTEGER NOT NULL,              -- source clip in-point (frame)
    source_out INTEGER NOT NULL,             -- source clip out-point (frame)
    speed_ratio REAL DEFAULT 1.0,
    is_enabled INTEGER DEFAULT 1,
    effects_json TEXT,                       -- applied effects as JSON array
    transitions_json TEXT,                   -- transition data as JSON
    FOREIGN KEY (track_id) REFERENCES tracks(id),
    FOREIGN KEY (media_clip_id) REFERENCES media_clips(id)
);

-- Markers
CREATE TABLE IF NOT EXISTS markers (
    id TEXT PRIMARY KEY,
    sequence_id TEXT NOT NULL,
    time_position INTEGER NOT NULL,          -- frame number
    duration INTEGER DEFAULT 0,
    name TEXT NOT NULL,
    color TEXT DEFAULT 'blue',
    marker_type TEXT DEFAULT 'standard',     -- standard, todo, chapter
    notes TEXT DEFAULT '',
    FOREIGN KEY (sequence_id) REFERENCES sequences(id)
);

-- Undo history (for session-based undo)
CREATE TABLE IF NOT EXISTS undo_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action_type TEXT NOT NULL,
    description TEXT NOT NULL,
    undo_data TEXT NOT NULL,                 -- JSON: data needed to reverse
    redo_data TEXT NOT NULL,                 -- JSON: data needed to re-apply
    group_id INTEGER,                        -- for grouped operations
    timestamp TEXT NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_timeline_clips_track ON timeline_clips(track_id);
CREATE INDEX IF NOT EXISTS idx_tracks_sequence ON tracks(sequence_id);
CREATE INDEX IF NOT EXISTS idx_bin_clips_bin ON bin_clips(bin_id);
CREATE INDEX IF NOT EXISTS idx_bin_clips_clip ON bin_clips(clip_id);
CREATE INDEX IF NOT EXISTS idx_markers_sequence ON markers(sequence_id);
CREATE INDEX IF NOT EXISTS idx_media_clips_type ON media_clips(media_type);
CREATE INDEX IF NOT EXISTS idx_media_clips_rating ON media_clips(rating);
""";
```

### Project File Manager

```swift
import SQLite3
import Foundation

// MARK: - Project Database Manager

class ProjectDatabase {

    private var db: OpaquePointer?
    let fileURL: URL

    /// Open or create a project database
    init(at url: URL) throws {
        self.fileURL = url

        var dbPointer: OpaquePointer?
        let result = sqlite3_open(url.path, &dbPointer)
        guard result == SQLITE_OK, let database = dbPointer else {
            throw ProjectError.cannotOpenDatabase(
                String(cString: sqlite3_errmsg(dbPointer))
            )
        }
        self.db = database

        // Enable WAL mode for better concurrent read performance
        try execute("PRAGMA journal_mode=WAL")

        // Enable foreign keys
        try execute("PRAGMA foreign_keys=ON")

        // Create schema
        try execute(projectSchema)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Basic Operations

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw ProjectError.sqlError(message)
        }
    }

    /// Begin a transaction for batch operations
    func beginTransaction() throws { try execute("BEGIN TRANSACTION") }
    func commitTransaction() throws { try execute("COMMIT") }
    func rollbackTransaction() throws { try execute("ROLLBACK") }

    /// Execute a batch of operations atomically
    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try beginTransaction()
        do {
            let result = try body()
            try commitTransaction()
            return result
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    // MARK: - Project Info

    func setProjectInfo(key: String, value: String) throws {
        try execute("""
            INSERT OR REPLACE INTO project_info (key, value)
            VALUES ('\(key)', '\(value)')
        """)
    }

    func getProjectInfo(key: String) -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let sql = "SELECT value FROM project_info WHERE key = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    enum ProjectError: Error {
        case cannotOpenDatabase(String)
        case sqlError(String)
    }
}
```

### File Extension and UTI Registration

Register `.swproj` as a custom document type:

```xml
<!-- Info.plist excerpt -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>SwiftEditor Project</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>swproj</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.swifteditor.project</string>
        </array>
    </dict>
</array>

<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.swifteditor.project</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
        </array>
        <key>UTTypeDescription</key>
        <string>SwiftEditor Project</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>swproj</string>
            </array>
        </dict>
    </dict>
</array>
```

---

## 10. Auto-Save & Versioning

### macOS Versioning System

macOS has a built-in versioning system through NSDocument that:
- Saves versions automatically to `.DocumentRevisions-V100` database on each volume
- Uses APFS clone efficiency (versions share unchanged data blocks)
- Provides Time Machine-like "Browse All Versions" UI
- Works with the Revert To menu

However, since our project file is SQLite (not a simple flat file), we should implement our own versioning alongside NSDocument integration.

### Auto-Save Implementation

```swift
import Foundation
import Combine

// MARK: - Auto-Save Manager

class AutoSaveManager: ObservableObject {

    private let projectDB: ProjectDatabase
    private var autoSaveTimer: Timer?
    private var hasUnsavedChanges = false
    private var changeCount = 0

    // Configuration
    let autoSaveInterval: TimeInterval = 30.0    // seconds
    let maxVersions: Int = 50

    init(projectDB: ProjectDatabase) {
        self.projectDB = projectDB
        startAutoSaveTimer()
    }

    deinit {
        autoSaveTimer?.invalidate()
    }

    /// Mark that a change has occurred
    func markDirty() {
        hasUnsavedChanges = true
        changeCount += 1
    }

    /// Start the auto-save timer
    private func startAutoSaveTimer() {
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: autoSaveInterval,
            repeats: true
        ) { [weak self] _ in
            self?.autoSaveIfNeeded()
        }
    }

    /// Perform auto-save if there are unsaved changes
    func autoSaveIfNeeded() {
        guard hasUnsavedChanges else { return }

        Task {
            do {
                try await performAutoSave()
                hasUnsavedChanges = false
            } catch {
                print("Auto-save failed: \(error)")
            }
        }
    }

    /// Perform the auto-save operation
    private func performAutoSave() async throws {
        // SQLite WAL checkpoint - flushes WAL to main database
        try projectDB.execute("PRAGMA wal_checkpoint(PASSIVE)")

        // Save a version snapshot
        try saveVersionSnapshot()

        // Update last-saved timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try projectDB.setProjectInfo(key: "last_saved", value: timestamp)
    }

    /// Save a version snapshot (backup copy)
    private func saveVersionSnapshot() throws {
        let versionsDir = projectDB.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".versions")

        try FileManager.default.createDirectory(
            at: versionsDir,
            withIntermediateDirectories: true
        )

        // Create timestamped backup
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let versionFile = versionsDir.appendingPathComponent(
            "version_\(timestamp).swproj"
        )

        // Use SQLite's backup API for a consistent copy
        try backupDatabase(to: versionFile)

        // Prune old versions
        pruneVersions(in: versionsDir)
    }

    /// Use SQLite backup API for consistent database copy
    private func backupDatabase(to destination: URL) throws {
        var destDB: OpaquePointer?
        guard sqlite3_open(destination.path, &destDB) == SQLITE_OK else {
            throw AutoSaveError.backupFailed
        }
        defer { sqlite3_close(destDB) }

        // The backup API creates a consistent snapshot even while writes are happening
        guard let backup = sqlite3_backup_init(destDB, "main", projectDB.db, "main") else {
            throw AutoSaveError.backupFailed
        }

        sqlite3_backup_step(backup, -1)  // Copy all pages
        sqlite3_backup_finish(backup)
    }

    /// Keep only the most recent N versions
    private func pruneVersions(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = files
            .filter { $0.pathExtension == "swproj" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return dateA > dateB
            }

        // Remove excess versions
        if sorted.count > maxVersions {
            for file in sorted.suffix(from: maxVersions) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    enum AutoSaveError: Error {
        case backupFailed
    }
}
```

**Note**: `ProjectDatabase.db` would need to be exposed as an internal property or the backup method moved into `ProjectDatabase` for access to the raw SQLite pointer. This is a design sketch -- adjust visibility as needed.

---

## 11. Undo/Redo Architecture

### Approach Comparison

| Approach | How It Works | Pros | Cons |
|----------|-------------|------|------|
| **Command Pattern** | Store commands (do + undo closures) | Low memory, fine-grained | Complex to implement for every operation |
| **State Snapshot (Memento)** | Store entire state snapshots | Simple to implement | Memory-intensive for large projects |
| **Hybrid** | Commands for most ops, snapshots at intervals | Best of both worlds | Most complex |
| **Operational Transform** | Store diffs/patches | Good for collaboration | Overkill for single-user |

**Recommended: Command Pattern** with Apple's `UndoManager` integration.

### Command Pattern Implementation

```swift
import Foundation

// MARK: - Editing Command Protocol

protocol EditingCommand {
    var description: String { get }
    func execute(on project: ProjectState) throws
    func undo(on project: ProjectState) throws
}

// MARK: - Project State (the document model)

@MainActor
class ProjectState: ObservableObject {
    @Published var sequences: [Sequence] = []
    @Published var mediaClips: [MediaClipReference] = []
    @Published var mediaBins: [MediaBin] = []

    // UndoManager handles the undo/redo stack
    let undoManager = UndoManager()

    init() {
        // Optionally limit undo levels
        undoManager.levelsOfUndo = 100
    }

    /// Execute a command and register its undo
    func execute(_ command: EditingCommand) {
        do {
            try command.execute(on: self)

            undoManager.registerUndo(withTarget: self) { target in
                do {
                    try command.undo(on: target)

                    // Register redo (undo of the undo)
                    target.undoManager.registerUndo(withTarget: target) { innerTarget in
                        innerTarget.execute(command)
                    }
                    target.undoManager.setActionName(command.description)
                } catch {
                    print("Undo failed: \(error)")
                }
            }
            undoManager.setActionName(command.description)

        } catch {
            print("Command execution failed: \(error)")
        }
    }

    /// Execute a group of commands as a single undoable operation
    func executeGroup(named name: String, commands: [EditingCommand]) {
        undoManager.beginUndoGrouping()
        for command in commands {
            execute(command)
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName(name)
    }
}
```

### Concrete Command Examples

```swift
// MARK: - Timeline Editing Commands

/// Add a clip to the timeline
struct AddClipCommand: EditingCommand {
    let clipID: UUID
    let trackID: UUID
    let position: Int       // frame number
    let sourceIn: Int
    let sourceOut: Int
    let mediaClipID: UUID

    var description: String { "Add Clip" }

    func execute(on project: ProjectState) throws {
        // Find the track and add the clip
        guard let seqIndex = project.sequences.firstIndex(where: { seq in
            seq.tracks.contains { $0.id == trackID }
        }) else { throw CommandError.trackNotFound }

        guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
            $0.id == trackID
        }) else { throw CommandError.trackNotFound }

        let timelineClip = TimelineClip(
            id: clipID,
            mediaClipID: mediaClipID,
            timelineStart: position,
            timelineDuration: sourceOut - sourceIn,
            sourceIn: sourceIn,
            sourceOut: sourceOut
        )

        project.sequences[seqIndex].tracks[trackIndex].clips.append(timelineClip)
    }

    func undo(on project: ProjectState) throws {
        guard let seqIndex = project.sequences.firstIndex(where: { seq in
            seq.tracks.contains { $0.id == trackID }
        }) else { throw CommandError.trackNotFound }

        guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
            $0.id == trackID
        }) else { throw CommandError.trackNotFound }

        project.sequences[seqIndex].tracks[trackIndex].clips.removeAll {
            $0.id == clipID
        }
    }
}

/// Move a clip on the timeline (ripple or overwrite)
struct MoveClipCommand: EditingCommand {
    let clipID: UUID
    let sourceTrackID: UUID
    let destTrackID: UUID
    let oldPosition: Int
    let newPosition: Int

    var description: String { "Move Clip" }

    func execute(on project: ProjectState) throws {
        try moveClip(on: project, fromTrack: sourceTrackID, toTrack: destTrackID,
                      fromPosition: oldPosition, toPosition: newPosition)
    }

    func undo(on project: ProjectState) throws {
        try moveClip(on: project, fromTrack: destTrackID, toTrack: sourceTrackID,
                      fromPosition: newPosition, toPosition: oldPosition)
    }

    private func moveClip(on project: ProjectState,
                          fromTrack: UUID, toTrack: UUID,
                          fromPosition: Int, toPosition: Int) throws {
        // Remove from source track
        guard let sourceSeqIdx = project.sequences.firstIndex(where: { seq in
            seq.tracks.contains { $0.id == fromTrack }
        }) else { throw CommandError.trackNotFound }

        guard let sourceTrackIdx = project.sequences[sourceSeqIdx].tracks.firstIndex(where: {
            $0.id == fromTrack
        }) else { throw CommandError.trackNotFound }

        guard let clipIdx = project.sequences[sourceSeqIdx].tracks[sourceTrackIdx].clips.firstIndex(where: {
            $0.id == clipID
        }) else { throw CommandError.clipNotFound }

        var clip = project.sequences[sourceSeqIdx].tracks[sourceTrackIdx].clips.remove(at: clipIdx)
        clip.timelineStart = toPosition

        // Add to destination track
        guard let destTrackIdx = project.sequences[sourceSeqIdx].tracks.firstIndex(where: {
            $0.id == toTrack
        }) else { throw CommandError.trackNotFound }

        project.sequences[sourceSeqIdx].tracks[destTrackIdx].clips.append(clip)
    }
}

/// Trim a clip (change in/out points)
struct TrimClipCommand: EditingCommand {
    let clipID: UUID
    let trackID: UUID
    let oldSourceIn: Int
    let oldSourceOut: Int
    let oldTimelineStart: Int
    let oldTimelineDuration: Int
    let newSourceIn: Int
    let newSourceOut: Int
    let newTimelineStart: Int
    let newTimelineDuration: Int

    var description: String { "Trim Clip" }

    func execute(on project: ProjectState) throws {
        try applyTrim(on: project, sourceIn: newSourceIn, sourceOut: newSourceOut,
                       timelineStart: newTimelineStart, duration: newTimelineDuration)
    }

    func undo(on project: ProjectState) throws {
        try applyTrim(on: project, sourceIn: oldSourceIn, sourceOut: oldSourceOut,
                       timelineStart: oldTimelineStart, duration: oldTimelineDuration)
    }

    private func applyTrim(on project: ProjectState,
                           sourceIn: Int, sourceOut: Int,
                           timelineStart: Int, duration: Int) throws {
        guard let seqIndex = project.sequences.firstIndex(where: { seq in
            seq.tracks.contains { $0.id == trackID }
        }) else { throw CommandError.trackNotFound }

        guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
            $0.id == trackID
        }) else { throw CommandError.trackNotFound }

        guard let clipIndex = project.sequences[seqIndex].tracks[trackIndex].clips.firstIndex(where: {
            $0.id == clipID
        }) else { throw CommandError.clipNotFound }

        project.sequences[seqIndex].tracks[trackIndex].clips[clipIndex].sourceIn = sourceIn
        project.sequences[seqIndex].tracks[trackIndex].clips[clipIndex].sourceOut = sourceOut
        project.sequences[seqIndex].tracks[trackIndex].clips[clipIndex].timelineStart = timelineStart
        project.sequences[seqIndex].tracks[trackIndex].clips[clipIndex].timelineDuration = duration
    }
}

/// Delete clip(s) from timeline
struct DeleteClipsCommand: EditingCommand {
    let clipSnapshots: [(clip: TimelineClip, trackID: UUID)]

    var description: String {
        clipSnapshots.count == 1 ? "Delete Clip" : "Delete \(clipSnapshots.count) Clips"
    }

    func execute(on project: ProjectState) throws {
        for (clip, trackID) in clipSnapshots {
            guard let seqIndex = project.sequences.firstIndex(where: { seq in
                seq.tracks.contains { $0.id == trackID }
            }) else { continue }

            guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
                $0.id == trackID
            }) else { continue }

            project.sequences[seqIndex].tracks[trackIndex].clips.removeAll {
                $0.id == clip.id
            }
        }
    }

    func undo(on project: ProjectState) throws {
        for (clip, trackID) in clipSnapshots {
            guard let seqIndex = project.sequences.firstIndex(where: { seq in
                seq.tracks.contains { $0.id == trackID }
            }) else { continue }

            guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
                $0.id == trackID
            }) else { continue }

            project.sequences[seqIndex].tracks[trackIndex].clips.append(clip)
        }
    }
}

/// Apply or modify an effect on a clip
struct ApplyEffectCommand: EditingCommand {
    let clipID: UUID
    let trackID: UUID
    let effect: ClipEffect
    let previousEffects: [ClipEffect]  // snapshot of effects before change
    let newEffects: [ClipEffect]       // effects after change

    var description: String { "Apply \(effect.name)" }

    func execute(on project: ProjectState) throws {
        try setEffects(on: project, effects: newEffects)
    }

    func undo(on project: ProjectState) throws {
        try setEffects(on: project, effects: previousEffects)
    }

    private func setEffects(on project: ProjectState, effects: [ClipEffect]) throws {
        guard let seqIndex = project.sequences.firstIndex(where: { seq in
            seq.tracks.contains { $0.id == trackID }
        }) else { throw CommandError.trackNotFound }

        guard let trackIndex = project.sequences[seqIndex].tracks.firstIndex(where: {
            $0.id == trackID
        }) else { throw CommandError.trackNotFound }

        guard let clipIndex = project.sequences[seqIndex].tracks[trackIndex].clips.firstIndex(where: {
            $0.id == clipID
        }) else { throw CommandError.clipNotFound }

        project.sequences[seqIndex].tracks[trackIndex].clips[clipIndex].effects = effects
    }
}

// MARK: - Supporting Types

struct TimelineClip: Identifiable, Codable {
    let id: UUID
    var mediaClipID: UUID
    var timelineStart: Int       // frame
    var timelineDuration: Int    // frames
    var sourceIn: Int            // frame
    var sourceOut: Int           // frame
    var speed: Double = 1.0
    var isEnabled: Bool = true
    var effects: [ClipEffect] = []
}

struct ClipEffect: Codable {
    let id: UUID
    var name: String
    var type: String
    var parameters: [String: Double]
    var isEnabled: Bool
}

struct Track: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: TrackType
    var trackIndex: Int
    var clips: [TimelineClip]
    var isLocked: Bool
    var isVisible: Bool
    var isMuted: Bool

    enum TrackType: String, Codable {
        case video, audio
    }
}

struct Sequence: Identifiable, Codable {
    let id: UUID
    var name: String
    var width: Int
    var height: Int
    var frameRateNum: Int
    var frameRateDen: Int
    var tracks: [Track]
}

enum CommandError: Error {
    case trackNotFound
    case clipNotFound
    case sequenceNotFound
}
```

### UndoManager Integration with SwiftUI Menus

```swift
import SwiftUI

// MARK: - Undo/Redo Menu Integration

struct EditMenuCommands: Commands {
    @FocusedValue(\.projectState) var projectState

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo \(projectState?.undoManager.undoActionName ?? "")") {
                projectState?.undoManager.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(projectState?.undoManager.canUndo ?? false))

            Button("Redo \(projectState?.undoManager.redoActionName ?? "")") {
                projectState?.undoManager.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!(projectState?.undoManager.canRedo ?? false))
        }
    }
}

// FocusedValue for passing project state through environment
struct ProjectStateFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectState
}

extension FocusedValues {
    var projectState: ProjectState? {
        get { self[ProjectStateFocusedValueKey.self] }
        set { self[ProjectStateFocusedValueKey.self] = newValue }
    }
}
```

### Undo History Panel (like DaVinci Resolve)

```swift
// MARK: - Undo History View

struct UndoHistoryView: View {
    @ObservedObject var projectState: ProjectState
    @State private var historyEntries: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            List {
                ForEach(Array(historyEntries.enumerated()), id: \.offset) { index, entry in
                    Text(entry)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(index == 0 ? .primary : .secondary)
                }
            }
        }
        .frame(minWidth: 200, minHeight: 300)
    }
}
```

### Key Undo/Redo Design Principles for NLE

1. **Every user-visible change must be undoable**: Clip adds, deletes, moves, trims, effect changes, property edits
2. **Group related operations**: A ripple delete that moves subsequent clips should undo as one step
3. **Preserve selection state**: After undo, restore the selection the user had before the operation
4. **Clear redo on new action**: Standard behavior -- any new action after undo clears the redo stack
5. **Undo levels limit**: Default to 100 levels; make configurable in preferences
6. **Named actions**: Show descriptive names like "Move Clip", "Trim In Point", "Apply Color Correction"
7. **Disable undo during export**: Prevent undo while rendering is in progress
8. **Save undo state optionally**: Consider persisting undo history to project file for cross-session undo

---

## 12. Smart Collections & Keyword Tagging

### Keyword Management

```swift
// MARK: - Keyword Manager

@MainActor
class KeywordManager: ObservableObject {

    @Published var allKeywords: Set<String> = []

    /// Add keywords to a clip
    func addKeywords(_ keywords: Set<String>, to clip: inout MediaClipReference) {
        clip.keywords.formUnion(keywords)
        allKeywords.formUnion(keywords)
    }

    /// Remove keywords from a clip
    func removeKeywords(_ keywords: Set<String>, from clip: inout MediaClipReference) {
        clip.keywords.subtract(keywords)
        rebuildKeywordIndex()
    }

    /// Rebuild the global keyword set from all clips
    func rebuildKeywordIndex(from clips: [MediaClipReference]) {
        allKeywords = clips.reduce(into: Set<String>()) { result, clip in
            result.formUnion(clip.keywords)
        }
    }

    private func rebuildKeywordIndex() {
        // Would need reference to all clips
    }

    /// Suggest keywords based on partial input (autocomplete)
    func suggestKeywords(matching prefix: String) -> [String] {
        guard !prefix.isEmpty else { return Array(allKeywords.sorted()) }
        return allKeywords
            .filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
            .sorted()
    }
}
```

### Smart Collection Types (Inspired by FCP)

```
Default Smart Collections:
- All Video          (mediaType == .video)
- All Audio          (mediaType == .audio)
- Favorites          (isFavorite == true)
- Rejected           (isRejected == true)
- Unused             (not referenced by any timeline)
- 4K+                (videoWidth >= 3840)
- HDR                (colorSpace contains "BT.2020" AND transferFunction contains "PQ" or "HLG")
- ProRes             (codec starts with "ap")
- Recently Imported  (importDate within last 7 days)
```

---

## 13. Security-Scoped Bookmarks & Persistent File Access

### Why Bookmarks Are Essential

In a sandboxed macOS app, file access is lost when the app quits. Security-scoped bookmarks provide **persistent** file access across app launches.

### Implementation

```swift
import Foundation

// MARK: - Bookmark Manager

class BookmarkManager {

    /// Create a security-scoped bookmark for a URL
    static func createBookmark(for url: URL) throws -> Data {
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a bookmark back to a URL with access
    static func resolveBookmark(_ data: Data) throws -> (URL, Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Access a file using its bookmark, executing a closure with access
    static func withBookmarkAccess<T>(
        _ bookmarkData: Data,
        body: (URL) throws -> T
    ) throws -> T {
        let (url, isStale) = try resolveBookmark(bookmarkData)

        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if isStale {
            // Bookmark is stale -- caller should recreate it
            print("Warning: Bookmark for \(url) is stale and should be refreshed")
        }

        return try body(url)
    }

    /// Refresh a stale bookmark
    static func refreshBookmark(for url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        return try createBookmark(for: url)
    }

    enum BookmarkError: Error {
        case accessDenied
        case staleBookmark
    }
}
```

### Entitlements Required

```xml
<!-- SwiftEditor.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.files.bookmarks.document-scope</key>
<true/>
```

---

## 14. WWDC Sessions & References

### Essential WWDC Sessions

| Session | Year | Topic |
|---------|------|-------|
| **What's New in AVFoundation** | 2021 | Async property loading, Swift concurrency integration |
| **Create a More Responsive Media App** | 2022 | Performance optimization for media loading |
| **Edit and Play Back HDR Video with AVFoundation** | 2020 | HDR workflow, color space handling |
| **Decode ProRes with AVFoundation and VideoToolbox** | 2020 | ProRes decoding pipeline |
| **Editing Movies in AV Foundation** | 2015 | AVMutableMovie, non-destructive editing |
| **Working with HEIF and HEVC** | 2017 | HEVC codec support |
| **Direct Access to Video Encoding and Decoding** | 2014 | VideoToolbox, CMFormatDescription |
| **Editing Media with AV Foundation** | 2010 | AVComposition fundamentals |

### Key Apple Documentation URLs

- [AVAsset](https://developer.apple.com/documentation/avfoundation/avasset)
- [Loading Media Data Asynchronously](https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously)
- [Creating Images from a Video Asset](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset)
- [AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)
- [AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)
- [Export Presets](https://developer.apple.com/documentation/avfoundation/export-presets)
- [Retrieving Media Metadata](https://developer.apple.com/documentation/avfoundation/retrieving-media-metadata)
- [UndoManager](https://developer.apple.com/documentation/foundation/undomanager)
- [Enabling Security-Scoped Bookmarks](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [SQLite as an Application File Format](https://www.sqlite.org/appfileformat.html)

### Third-Party Libraries Worth Considering

| Library | Purpose | URL |
|---------|---------|-----|
| **MediaToolSwift** | Advanced media conversion/manipulation | github.com/starkdmi/MediaToolSwift |
| **AudioKit** | Audio analysis, waveform generation | github.com/AudioKit/AudioKit |
| **GRDB.swift** | Type-safe SQLite wrapper for Swift | github.com/groue/GRDB.swift |
| **SQLite.swift** | Another popular SQLite wrapper | github.com/stephencelis/SQLite.swift |

---

## Key Architectural Decisions Summary

1. **Project file format**: SQLite database (`.swproj`) with JSON blobs for extensible data
2. **Media references**: Store file path + security-scoped bookmark + relative path for maximum resilience
3. **Thumbnails**: Two-tier cache (NSCache in-memory + JPEG on disk), generated asynchronously with cancellation support
4. **Proxy workflow**: Generate to project-local `Proxies/` directory, global toggle, always export from originals
5. **Undo/redo**: Command pattern with Apple's UndoManager, 100-level default, grouped operations for compound edits
6. **Auto-save**: Timer-based (30s) with SQLite WAL checkpointing and periodic version snapshots
7. **Import**: Drag-and-drop + file importer, security-scoped bookmarks for sandbox persistence
8. **Metadata**: Async extraction using modern `AVAsset.load()` API, store in SQLite for fast queries
9. **Smart collections**: Dynamic filters evaluated against clip metadata, stored as JSON rules
10. **Relink**: Multi-strategy (bookmark -> original path -> filename+size search -> manual)
