// InterchangeKit — FCPXML Import
import Foundation
import CoreMediaPlus
import ProjectModel

// MARK: - Imported Model Types

/// Represents an imported FCPXML project before conversion to our internal model.
public struct ImportedProject: Sendable {
    public var name: String
    public var formatWidth: Int
    public var formatHeight: Int
    public var frameDuration: Rational
    public var tracks: [ImportedTrack]
    public var assets: [ImportedAsset]

    public init(name: String = "", formatWidth: Int = 1920, formatHeight: Int = 1080,
                frameDuration: Rational = Rational(1, 24),
                tracks: [ImportedTrack] = [], assets: [ImportedAsset] = []) {
        self.name = name
        self.formatWidth = formatWidth
        self.formatHeight = formatHeight
        self.frameDuration = frameDuration
        self.tracks = tracks
        self.assets = assets
    }
}

/// A track within an imported project.
public struct ImportedTrack: Sendable {
    public var name: String
    public var trackType: TrackType
    public var clips: [ImportedClip]

    public init(name: String = "", trackType: TrackType = .video, clips: [ImportedClip] = []) {
        self.name = name
        self.trackType = trackType
        self.clips = clips
    }
}

/// A clip within an imported track.
public struct ImportedClip: Sendable {
    public var assetRef: String
    public var name: String
    public var offset: Rational
    public var start: Rational
    public var duration: Rational
    public var lane: Int
    public var isEnabled: Bool
    public var isTransition: Bool
    public var transitionName: String?

    public init(assetRef: String = "", name: String = "",
                offset: Rational = .zero, start: Rational = .zero,
                duration: Rational = .zero, lane: Int = 0,
                isEnabled: Bool = true, isTransition: Bool = false,
                transitionName: String? = nil) {
        self.assetRef = assetRef
        self.name = name
        self.offset = offset
        self.start = start
        self.duration = duration
        self.lane = lane
        self.isEnabled = isEnabled
        self.isTransition = isTransition
        self.transitionName = transitionName
    }
}

/// An asset declared in the FCPXML resources.
public struct ImportedAsset: Sendable {
    public var id: String
    public var name: String
    public var src: String
    public var start: Rational
    public var duration: Rational
    public var hasVideo: Bool
    public var hasAudio: Bool

    public init(id: String = "", name: String = "", src: String = "",
                start: Rational = .zero, duration: Rational = .zero,
                hasVideo: Bool = true, hasAudio: Bool = true) {
        self.id = id
        self.name = name
        self.src = src
        self.start = start
        self.duration = duration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
    }
}

// MARK: - FCPXMLImporter

/// Parses FCPXML documents using Foundation's XMLParser.
public final class FCPXMLImporter: NSObject, XMLParserDelegate, @unchecked Sendable {

    private var result = ImportedProject()
    private var elementStack: [String] = []
    private var parseError: (any Error)?

    // Resource tracking
    private var formats: [String: (width: Int, height: Int, frameDuration: Rational)] = [:]
    private var assets: [ImportedAsset] = []

    // Track accumulation: lane -> clips
    private var spineClips: [ImportedClip] = []
    private var connectedClips: [Int: [ImportedClip]] = [:]

    // Current sequence format ref
    private var currentFormatRef: String = ""

    public override init() {
        super.init()
    }

    /// Parse FCPXML data and return an ImportedProject.
    public func parse(data: Data) throws -> ImportedProject {
        // Reset state
        result = ImportedProject()
        elementStack = []
        parseError = nil
        formats = [:]
        assets = []
        spineClips = []
        connectedClips = [:]
        currentFormatRef = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let error = parseError ?? parser.parserError {
            throw error
        }

        // Assemble tracks from accumulated clips
        assembleTracks()
        result.assets = assets

        return result
    }

    /// Convenience: parse from a string.
    public func parse(string: String) throws -> ImportedProject {
        guard let data = string.data(using: .utf8) else {
            throw FCPXMLImportError.invalidData
        }
        return try parse(data: data)
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attr: [String: String] = [:]
    ) {
        elementStack.append(elementName)

        switch elementName {
        case "format":
            let id = attr["id"] ?? ""
            let width = Int(attr["width"] ?? "0") ?? 0
            let height = Int(attr["height"] ?? "0") ?? 0
            let frameDur = parseFCPXMLTime(attr["frameDuration"] ?? "1/24s")
            formats[id] = (width, height, frameDur)

        case "asset":
            let asset = ImportedAsset(
                id: attr["id"] ?? "",
                name: attr["name"] ?? "",
                src: attr["src"] ?? "",
                start: parseFCPXMLTime(attr["start"] ?? "0s"),
                duration: parseFCPXMLTime(attr["duration"] ?? "0s"),
                hasVideo: attr["hasVideo"] == "1",
                hasAudio: attr["hasAudio"] == "1"
            )
            assets.append(asset)

        case "project":
            result.name = attr["name"] ?? ""

        case "sequence":
            currentFormatRef = attr["format"] ?? ""
            if let fmt = formats[currentFormatRef] {
                result.formatWidth = fmt.width
                result.formatHeight = fmt.height
                result.frameDuration = fmt.frameDuration
            }

        case "asset-clip", "clip":
            let lane = Int(attr["lane"] ?? "0") ?? 0
            let clip = ImportedClip(
                assetRef: attr["ref"] ?? "",
                name: attr["name"] ?? "",
                offset: parseFCPXMLTime(attr["offset"] ?? "0s"),
                start: parseFCPXMLTime(attr["start"] ?? "0s"),
                duration: parseFCPXMLTime(attr["duration"] ?? "0s"),
                lane: lane,
                isEnabled: attr["enabled"] != "0"
            )
            if lane == 0 && isInSpine() {
                spineClips.append(clip)
            } else {
                connectedClips[lane, default: []].append(clip)
            }

        case "transition":
            let clip = ImportedClip(
                name: attr["name"] ?? "Transition",
                offset: parseFCPXMLTime(attr["offset"] ?? "0s"),
                duration: parseFCPXMLTime(attr["duration"] ?? "0s"),
                isTransition: true,
                transitionName: attr["name"]
            )
            spineClips.append(clip)

        case "gap":
            // Gaps are represented as clips with no asset ref
            let clip = ImportedClip(
                name: "Gap",
                offset: parseFCPXMLTime(attr["offset"] ?? "0s"),
                duration: parseFCPXMLTime(attr["duration"] ?? "0s")
            )
            spineClips.append(clip)

        default:
            break
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred error: any Error) {
        parseError = error
    }

    // MARK: - Private

    private func isInSpine() -> Bool {
        elementStack.contains("spine")
    }

    private func assembleTracks() {
        // Primary video track from spine (non-transition, non-gap clips)
        let videoClips = spineClips.filter {
            !$0.isTransition && !$0.assetRef.isEmpty
        }
        if !videoClips.isEmpty {
            var track = ImportedTrack(name: "V1", trackType: .video, clips: videoClips)
            // Include transitions as well for completeness
            let transitions = spineClips.filter { $0.isTransition }
            track.clips.append(contentsOf: transitions)
            track.clips.sort { $0.offset < $1.offset }
            result.tracks.append(track)
        }

        // Connected clips by lane
        let sortedLanes = connectedClips.keys.sorted()
        for lane in sortedLanes {
            guard let clips = connectedClips[lane], !clips.isEmpty else { continue }
            let trackType: TrackType = lane > 0 ? .video : .audio
            let prefix = lane > 0 ? "V" : "A"
            let trackNum = lane > 0 ? lane + 1 : -lane
            let track = ImportedTrack(
                name: "\(prefix)\(trackNum)",
                trackType: trackType,
                clips: clips.sorted { $0.offset < $1.offset }
            )
            result.tracks.append(track)
        }
    }
}

/// Errors from FCPXML import.
public enum FCPXMLImportError: Error, Sendable {
    case invalidData
    case parsingFailed(String)
}

// MARK: - Conversion to ProjectModel

extension ImportedProject {
    /// Convert the imported FCPXML data to a ProjectModel.Project.
    public func toProject() -> Project {
        var projectTracks: [TrackData] = []

        for importedTrack in tracks {
            var trackData = TrackData(
                name: importedTrack.name,
                trackType: importedTrack.trackType
            )

            for clip in importedTrack.clips where !clip.isTransition && !clip.assetRef.isEmpty {
                // Map asset ref to a UUID (deterministic from the ref string)
                let assetID = deterministicUUID(from: clip.assetRef)
                let clipData = ClipData(
                    sourceAssetID: assetID,
                    startTime: clip.offset,
                    sourceIn: clip.start,
                    sourceOut: clip.start + clip.duration,
                    isEnabled: clip.isEnabled
                )
                trackData.clips.append(clipData)
            }

            if !trackData.clips.isEmpty {
                projectTracks.append(trackData)
            }
        }

        let frameRate: Rational
        if frameDuration.isValid && frameDuration != .zero {
            frameRate = Rational(1, 1) / frameDuration
        } else {
            frameRate = Rational(24, 1)
        }

        let settings = ProjectSettings(
            videoParams: VideoParams(width: formatWidth, height: formatHeight),
            audioParams: AudioParams(),
            frameRate: frameRate
        )

        let sequence = ProjectModel.Sequence(
            name: name.isEmpty ? "Imported" : name,
            tracks: projectTracks
        )

        return Project(
            name: name.isEmpty ? "Imported" : name,
            settings: settings,
            sequences: [sequence]
        )
    }

    private func deterministicUUID(from string: String) -> UUID {
        // Create a deterministic UUID from a string by hashing it
        let bytes = Array(string.utf8)
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        for (i, byte) in bytes.enumerated() {
            hash[i % 16] ^= byte
        }
        // Set version 4 and variant bits for valid UUID format
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
        return uuid
    }
}
