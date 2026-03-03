import Foundation
import AVFoundation
import CoreMediaPlus

/// Imports media files and extracts metadata.
public final class AssetImporter: @unchecked Sendable {

    public init() {}

    /// Import media files and return metadata for each.
    public func importAssets(from urls: [URL]) async throws -> [ImportedAsset] {
        var results: [ImportedAsset] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let metadata = try await extractMetadata(from: asset, url: url)
            results.append(metadata)
        }
        return results
    }

    private func extractMetadata(from asset: AVURLAsset, url: URL) async throws -> ImportedAsset {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        var videoParams: VideoParams?
        var audioParams: AudioParams?

        for track in tracks {
            let mediaType = track.mediaType
            if mediaType == .video {
                let size = try await track.load(.naturalSize)
                videoParams = VideoParams(width: Int(size.width), height: Int(size.height))
            } else if mediaType == .audio {
                let desc = try await track.load(.formatDescriptions)
                if let first = desc.first {
                    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)
                    if let asbd = basic?.pointee {
                        audioParams = AudioParams(
                            sampleRate: Int(asbd.mSampleRate),
                            channelCount: Int(asbd.mChannelsPerFrame)
                        )
                    }
                }
            }
        }

        return ImportedAsset(
            id: UUID(),
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            duration: Rational(duration),
            videoParams: videoParams,
            audioParams: audioParams
        )
    }
}

/// Result of importing a media file.
public struct ImportedAsset: Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let duration: Rational
    public let videoParams: VideoParams?
    public let audioParams: AudioParams?
}
