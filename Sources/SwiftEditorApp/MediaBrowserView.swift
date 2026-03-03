import SwiftUI
import SwiftEditorAPI
import MediaManager
import CoreMediaPlus
import UniformTypeIdentifiers

// MARK: - Media Asset Transfer (Drag & Drop)

/// Lightweight transferable payload for dragging a media asset from the browser.
struct MediaAssetTransfer: Codable, Transferable, Sendable {
    let assetID: UUID
    /// Duration in seconds, for computing source out point on drop.
    let durationSeconds: Double
    /// Whether this asset has video content.
    let hasVideo: Bool
    /// Whether this asset has audio content.
    let hasAudio: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mediaAssetTransfer)
    }
}

extension UTType {
    static let mediaAssetTransfer = UTType(exportedAs: "com.swifteditor.mediaAssetTransfer")
}

/// Sidebar panel for browsing and importing media assets.
struct MediaBrowserView: View {
    let engine: SwiftEditorEngine

    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Media")
                    .font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
                .liquidGlassButton()
                .help("Import Media (Cmd+I)")
                .accessibilityLabel("Import Media")
                .accessibilityHint("Open a file picker to import media files into the project")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassSidebarHeader()

            Divider()

            // Asset list
            if engine.allImportedAssets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No Media Imported")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Drop files here or click + to import")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(engine.allImportedAssets) { asset in
                    MediaAssetRow(asset: asset)
                        .draggable(MediaAssetTransfer(
                            assetID: asset.id,
                            durationSeconds: asset.duration.seconds,
                            hasVideo: asset.videoParams != nil,
                            hasAudio: asset.audioParams != nil
                        ))
                }
                .listStyle(.sidebar)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .audio, .image],
            allowsMultipleSelection: true
        ) { result in
            Task {
                if case .success(let urls) = result {
                    _ = try? await engine.media.importMedia(urls: urls)
                }
            }
        }
    }
}

/// A single row in the media browser showing asset info.
struct MediaAssetRow: View {
    let asset: ImportedAsset

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let vp = asset.videoParams {
                        Text("\(vp.width)x\(vp.height)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name), \(mediaTypeLabel), \(formattedDuration)")
    }

    private var mediaTypeLabel: String {
        if asset.videoParams != nil && asset.audioParams != nil {
            return "video with audio"
        } else if asset.videoParams != nil {
            return "video only"
        } else if asset.audioParams != nil {
            return "audio only"
        } else {
            return "file"
        }
    }

    private var iconName: String {
        if asset.videoParams != nil && asset.audioParams != nil {
            return "film"
        } else if asset.videoParams != nil {
            return "video"
        } else if asset.audioParams != nil {
            return "waveform"
        } else {
            return "doc"
        }
    }

    private var formattedDuration: String {
        let total = asset.duration.seconds
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
