import Foundation
import CoreMediaPlus

/// Codec identifier for comparing source and output formats.
public enum VideoCodec: String, Sendable, Hashable {
    case h264
    case hevc
    case prores422
    case prores4444
    case proresProxy
    case av1
    case unknown
}

/// Describes a segment of the timeline that may be eligible for smart rendering
/// (pass-through without re-encoding).
public struct ExportSegment: Sendable {
    public enum RenderMode: Sendable {
        /// Segment can be copied directly from source without re-encoding.
        case passthrough
        /// Segment must be decoded, composited, and re-encoded.
        case reencode(reason: String)
    }

    public let timeRange: TimeRange
    public let clipID: UUID
    public let sourceCodec: VideoCodec
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let renderMode: RenderMode

    public var isPassthrough: Bool {
        if case .passthrough = renderMode { return true }
        return false
    }
}

/// Output format specification for smart render analysis.
public struct ExportFormat: Sendable {
    public let codec: VideoCodec
    public let width: Int
    public let height: Int
    public let frameRate: Rational

    public init(codec: VideoCodec, width: Int, height: Int, frameRate: Rational) {
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

/// Describes a source clip's media properties for smart render analysis.
public struct SourceClipInfo: Sendable {
    public let clipID: UUID
    public let timeRange: TimeRange
    public let codec: VideoCodec
    public let width: Int
    public let height: Int
    public let hasEffects: Bool
    public let hasTransform: Bool
    public let opacity: Double
    public let blendMode: BlendMode
    /// Whether this clip overlaps with other clips on different tracks.
    public let isComposited: Bool

    public init(
        clipID: UUID,
        timeRange: TimeRange,
        codec: VideoCodec,
        width: Int,
        height: Int,
        hasEffects: Bool = false,
        hasTransform: Bool = false,
        opacity: Double = 1.0,
        blendMode: BlendMode = .normal,
        isComposited: Bool = false
    ) {
        self.clipID = clipID
        self.timeRange = timeRange
        self.codec = codec
        self.width = width
        self.height = height
        self.hasEffects = hasEffects
        self.hasTransform = hasTransform
        self.opacity = opacity
        self.blendMode = blendMode
        self.isComposited = isComposited
    }
}

/// Analyzes timeline segments to identify which can be passed through during export
/// without re-encoding. Segments are eligible for passthrough when:
/// - Source codec matches the output codec
/// - Source resolution matches the output resolution
/// - No effects are applied to the clip
/// - No transform (scale/rotation/translation) is applied
/// - The clip is not composited with other clips
/// - Opacity is 1.0 and blend mode is normal
public struct SmartRenderer: Sendable {

    public init() {}

    /// Analyze a list of source clips against the target export format and return
    /// a list of export segments with their determined render mode.
    public func analyze(
        clips: [SourceClipInfo],
        outputFormat: ExportFormat
    ) -> [ExportSegment] {
        clips.map { clip in
            let renderMode = determineRenderMode(for: clip, outputFormat: outputFormat)
            return ExportSegment(
                timeRange: clip.timeRange,
                clipID: clip.clipID,
                sourceCodec: clip.codec,
                sourceWidth: clip.width,
                sourceHeight: clip.height,
                renderMode: renderMode
            )
        }
    }

    /// Compute a summary of how much of the timeline can be passed through.
    public func passthroughRatio(segments: [ExportSegment]) -> Double {
        guard !segments.isEmpty else { return 0 }
        var passthroughDuration: Double = 0
        var totalDuration: Double = 0
        for segment in segments {
            let dur = segment.timeRange.duration.seconds
            totalDuration += dur
            if segment.isPassthrough {
                passthroughDuration += dur
            }
        }
        guard totalDuration > 0 else { return 0 }
        return passthroughDuration / totalDuration
    }

    // MARK: - Private

    private func determineRenderMode(
        for clip: SourceClipInfo,
        outputFormat: ExportFormat
    ) -> ExportSegment.RenderMode {
        if clip.hasEffects {
            return .reencode(reason: "clip has effects applied")
        }
        if clip.hasTransform {
            return .reencode(reason: "clip has spatial transform")
        }
        if clip.opacity < 1.0 {
            return .reencode(reason: "clip opacity is not 1.0")
        }
        if clip.blendMode != .normal {
            return .reencode(reason: "clip uses non-normal blend mode")
        }
        if clip.isComposited {
            return .reencode(reason: "clip is composited with other layers")
        }
        if clip.codec != outputFormat.codec {
            return .reencode(reason: "codec mismatch: \(clip.codec.rawValue) vs \(outputFormat.codec.rawValue)")
        }
        if clip.width != outputFormat.width || clip.height != outputFormat.height {
            return .reencode(reason: "resolution mismatch: \(clip.width)x\(clip.height) vs \(outputFormat.width)x\(outputFormat.height)")
        }
        return .passthrough
    }
}
