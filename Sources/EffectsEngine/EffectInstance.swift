import CoreMediaPlus
import Foundation
import Observation

/// Runtime instance of an effect with parameter state and keyframe tracks.
@Observable
public final class EffectInstance: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let pluginID: String
    public let name: String
    public var isEnabled: Bool = true
    public var parameters: ParameterValues
    public var keyframeTracks: [String: KeyframeTrack] = [:]

    public init(
        id: UUID = UUID(),
        pluginID: String,
        name: String,
        defaults: [String: ParameterValue] = [:]
    ) {
        self.id = id
        self.pluginID = pluginID
        self.name = name
        self.parameters = ParameterValues(defaults)
    }

    /// Returns the effective parameter values at the given time.
    /// For parameters with keyframe tracks, the interpolated keyframe value is used.
    /// For parameters without keyframe tracks, the static parameter value is used.
    public func currentValues(at time: Rational) -> ParameterValues {
        var result = parameters
        for (parameterName, track) in keyframeTracks {
            if let interpolated = track.value(at: time) {
                result[parameterName] = interpolated
            }
        }
        return result
    }
}
