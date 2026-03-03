import CoreMediaPlus
import Foundation

/// Identifies which output of tracking data to read.
public enum TrackingOutput: String, Sendable, Codable, Hashable {
    /// Center X of the tracked bounding box (normalized 0...1).
    case positionX
    /// Center Y of the tracked bounding box (normalized 0...1).
    case positionY
    /// Width of the tracked bounding box (normalized 0...1).
    case scaleX
    /// Height of the tracked bounding box (normalized 0...1).
    case scaleY
    /// Tracker confidence (0...1).
    case confidence
}

/// Maps a single tracking output to an effect parameter with optional scaling.
public struct TrackingLink: Sendable, Codable, Equatable {
    /// Which tracking output to read.
    public var source: TrackingOutput
    /// Name of the effect parameter to drive.
    public var targetParameter: String
    /// Multiplier applied to the tracking value before assignment.
    public var scale: Double
    /// Offset added after scaling.
    public var offset: Double

    public init(
        source: TrackingOutput,
        targetParameter: String,
        scale: Double = 1.0,
        offset: Double = 0.0
    ) {
        self.source = source
        self.targetParameter = targetParameter
        self.scale = scale
        self.offset = offset
    }
}

/// An effect whose parameters are partially driven by motion tracking data.
///
/// At evaluation time, the linked effect computes tracking-derived values
/// and merges them with any static/keyframed parameters.
public struct LinkedEffect: Sendable {
    /// The underlying effect instance.
    public var effectPluginID: String
    /// Static parameter values (can be overridden by tracking links).
    public var baseParameters: [String: ParameterValue]
    /// The tracking data source.
    public var trackingData: TrackingData
    /// Mappings from tracking outputs to effect parameters.
    public var links: [TrackingLink]

    public init(
        effectPluginID: String,
        baseParameters: [String: ParameterValue] = [:],
        trackingData: TrackingData,
        links: [TrackingLink]
    ) {
        self.effectPluginID = effectPluginID
        self.baseParameters = baseParameters
        self.trackingData = trackingData
        self.links = links
    }

    /// Evaluates all tracking links at the given time and returns the merged parameter values.
    ///
    /// Base parameters are used as defaults. Any parameter targeted by a tracking link
    /// is overwritten with the tracking-derived value (scaled and offset).
    public func evaluateAt(time: Rational) -> [String: ParameterValue] {
        var result = baseParameters

        let position = trackingData.positionAt(time: time)
        let scale = trackingData.scaleAt(time: time)
        let confidence = trackingData.confidenceAt(time: time)

        for link in links {
            let rawValue: Double
            switch link.source {
            case .positionX:
                rawValue = position.x
            case .positionY:
                rawValue = position.y
            case .scaleX:
                rawValue = scale.width
            case .scaleY:
                rawValue = scale.height
            case .confidence:
                rawValue = Double(confidence)
            }

            let finalValue = rawValue * link.scale + link.offset
            result[link.targetParameter] = .float(finalValue)
        }

        return result
    }
}
