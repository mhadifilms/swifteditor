import CoreImage
import CoreMediaPlus
import Foundation

/// Ordered processing pipeline that applies a sequence of CIFilterEffects to an image.
/// Each effect's parameters are evaluated at the given time, supporting keyframe animation.
public final class EffectChain: @unchecked Sendable {

    /// An entry in the chain: a CIFilterEffect paired with its parameter state and keyframe tracks.
    public struct Entry: Sendable {
        public let effect: CIFilterEffect
        public var parameters: ParameterValues
        public var keyframeTracks: [String: KeyframeTrack]
        public var isEnabled: Bool

        public init(
            effect: CIFilterEffect,
            parameters: ParameterValues = ParameterValues(),
            keyframeTracks: [String: KeyframeTrack] = [:],
            isEnabled: Bool = true
        ) {
            self.effect = effect
            self.parameters = parameters
            self.keyframeTracks = keyframeTracks
            self.isEnabled = isEnabled
        }

        /// Evaluates parameter values at the given time, applying keyframe interpolation.
        public func evaluatedParameters(at time: Rational) -> ParameterValues {
            var result = parameters
            for (paramName, track) in keyframeTracks {
                if let interpolated = track.value(at: time) {
                    result[paramName] = interpolated
                }
            }
            return result
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public init(entries: [Entry]) {
        self.entries = entries
    }

    // MARK: - Mutation

    /// Appends an effect entry to the chain.
    public func append(_ entry: Entry) {
        entries.append(entry)
    }

    /// Removes the entry at the given index.
    public func remove(at index: Int) {
        entries.remove(at: index)
    }

    /// Moves an entry from one position to another.
    public func move(from source: Int, to destination: Int) {
        let entry = entries.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        entries.insert(entry, at: adjusted)
    }

    // MARK: - Processing

    /// Applies all enabled effects sequentially to the input image at the given time.
    public func process(image: CIImage, at time: Rational) -> CIImage {
        var current = image
        for entry in entries where entry.isEnabled {
            let params = entry.evaluatedParameters(at: time)
            current = entry.effect.apply(to: current, parameters: params)
        }
        return current
    }
}
