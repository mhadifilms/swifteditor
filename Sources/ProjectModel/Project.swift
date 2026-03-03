import CoreMediaPlus
import Foundation

// MARK: - Project

/// Top-level project container for a non-linear editing session.
public struct Project: Codable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var settings: ProjectSettings
    public var sequences: [Sequence]
    public var bin: MediaBinModel
    public var metadata: ProjectMetadata

    public init(
        version: Int = Project.currentVersion,
        id: UUID = UUID(),
        name: String = "Untitled",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        settings: ProjectSettings = .defaultHD,
        sequences: [Sequence] = [],
        bin: MediaBinModel = MediaBinModel(),
        metadata: ProjectMetadata = ProjectMetadata()
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.settings = settings
        self.sequences = sequences
        self.bin = bin
        self.metadata = metadata
    }
}

// MARK: - ProjectSettings

/// Global settings that apply to the entire project.
public struct ProjectSettings: Codable, Sendable, Hashable {
    public var videoParams: VideoParams
    public var audioParams: AudioParams
    public var frameRate: Rational

    public init(
        videoParams: VideoParams,
        audioParams: AudioParams,
        frameRate: Rational
    ) {
        self.videoParams = videoParams
        self.audioParams = audioParams
        self.frameRate = frameRate
    }

    /// 1920x1080, Rec709, 24 fps, 48kHz stereo.
    public static let defaultHD = ProjectSettings(
        videoParams: VideoParams(width: 1920, height: 1080, colorSpace: .rec709),
        audioParams: AudioParams(),
        frameRate: Rational(24, 1)
    )

    /// 3840x2160, Rec709, 24 fps, 48kHz stereo.
    public static let default4K = ProjectSettings(
        videoParams: VideoParams(width: 3840, height: 2160, colorSpace: .rec709),
        audioParams: AudioParams(),
        frameRate: Rational(24, 1)
    )
}

// MARK: - Sequence

/// An ordered timeline of tracks within a project.
public struct Sequence: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var tracks: [TrackData]
    public var markers: [Marker]

    public init(
        id: UUID = UUID(),
        name: String = "Sequence 1",
        tracks: [TrackData] = [],
        markers: [Marker] = []
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.markers = markers
    }
}

// MARK: - TrackData

/// A single track containing an ordered list of clips.
public struct TrackData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var trackType: TrackType
    public var clips: [ClipData]
    public var isMuted: Bool
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        trackType: TrackType = .video,
        clips: [ClipData] = [],
        isMuted: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.clips = clips
        self.isMuted = isMuted
        self.isLocked = isLocked
    }
}

// MARK: - ClipData

/// A single clip placed on the timeline.
public struct ClipData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sourceAssetID: UUID
    public var startTime: Rational
    public var sourceIn: Rational
    public var sourceOut: Rational
    public var speed: Rational
    public var isEnabled: Bool
    public var effects: [EffectData]
    public var volume: Double
    public var opacity: Double
    public var position: SIMD2<Double>
    public var scale: SIMD2<Double>
    public var rotation: Double

    /// The duration of this clip on the timeline, accounting for speed.
    public var duration: Rational {
        guard speed.isValid, speed != .zero else { return sourceOut - sourceIn }
        return (sourceOut - sourceIn) / speed
    }

    public init(
        id: UUID = UUID(),
        sourceAssetID: UUID,
        startTime: Rational = .zero,
        sourceIn: Rational = .zero,
        sourceOut: Rational = .zero,
        speed: Rational = Rational(1, 1),
        isEnabled: Bool = true,
        effects: [EffectData] = [],
        volume: Double = 1.0,
        opacity: Double = 1.0,
        position: SIMD2<Double> = .zero,
        scale: SIMD2<Double> = SIMD2(1.0, 1.0),
        rotation: Double = 0.0
    ) {
        self.id = id
        self.sourceAssetID = sourceAssetID
        self.startTime = startTime
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.speed = speed
        self.isEnabled = isEnabled
        self.effects = effects
        self.volume = volume
        self.opacity = opacity
        self.position = position
        self.scale = scale
        self.rotation = rotation
    }
}

// MARK: - EffectData

/// Serializable representation of an applied effect.
public struct EffectData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var effectID: String
    public var name: String
    public var isEnabled: Bool
    public var parameters: [String: ParameterValue]
    public var keyframes: [String: [KeyframeData]]

    public init(
        id: UUID = UUID(),
        effectID: String,
        name: String,
        isEnabled: Bool = true,
        parameters: [String: ParameterValue] = [:],
        keyframes: [String: [KeyframeData]] = [:]
    ) {
        self.id = id
        self.effectID = effectID
        self.name = name
        self.isEnabled = isEnabled
        self.parameters = parameters
        self.keyframes = keyframes
    }
}

// MARK: - KeyframeData

/// A single keyframe value at a point in time.
public struct KeyframeData: Codable, Sendable {
    public var time: Rational
    public var value: ParameterValue
    public var interpolation: InterpolationType

    public init(
        time: Rational,
        value: ParameterValue,
        interpolation: InterpolationType = .linear
    ) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }

    public enum InterpolationType: String, Codable, Sendable {
        case linear
        case hold
        case bezier
    }
}

// MARK: - Marker

/// A labelled marker on the timeline.
public struct Marker: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var time: Rational
    public var color: MarkerColor
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        time: Rational = .zero,
        color: MarkerColor = .blue,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.time = time
        self.color = color
        self.notes = notes
    }

    public enum MarkerColor: String, Codable, Sendable {
        case red
        case orange
        case yellow
        case green
        case blue
        case purple
        case pink
    }
}

// MARK: - MediaBinModel

/// Recursive folder structure holding references to imported media assets.
public struct MediaBinModel: Codable, Sendable {
    public var name: String
    public var items: [BinItemData]
    public var subfolders: [MediaBinModel]

    public init(
        name: String = "Media",
        items: [BinItemData] = [],
        subfolders: [MediaBinModel] = []
    ) {
        self.name = name
        self.items = items
        self.subfolders = subfolders
    }
}

// MARK: - BinItemData

/// Metadata for a single asset imported into the media bin.
public struct BinItemData: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var relativePath: String
    public var originalPath: String
    public var proxyPath: String?
    public var duration: Rational?
    public var videoParams: VideoParams?
    public var audioParams: AudioParams?
    public var importDate: Date

    public init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        originalPath: String,
        proxyPath: String? = nil,
        duration: Rational? = nil,
        videoParams: VideoParams? = nil,
        audioParams: AudioParams? = nil,
        importDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.originalPath = originalPath
        self.proxyPath = proxyPath
        self.duration = duration
        self.videoParams = videoParams
        self.audioParams = audioParams
        self.importDate = importDate
    }
}

// MARK: - ProjectMetadata

/// Free-form metadata attached to a project.
public struct ProjectMetadata: Codable, Sendable {
    public var author: String
    public var description: String
    public var tags: [String]
    public var customFields: [String: String]

    public init(
        author: String = "",
        description: String = "",
        tags: [String] = [],
        customFields: [String: String] = [:]
    ) {
        self.author = author
        self.description = description
        self.tags = tags
        self.customFields = customFields
    }
}
