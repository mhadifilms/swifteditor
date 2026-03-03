import CoreMediaPlus
import Foundation
import Observation
import PluginKit

/// Ordered list of effects applied to a clip.
@Observable
public final class EffectStack: @unchecked Sendable {
    public private(set) var effects: [EffectInstance] = []
    public var isEnabled: Bool = true

    public init() {}

    /// Appends an effect to the end of the stack.
    public func append(_ effect: EffectInstance) {
        effects.append(effect)
    }

    /// Removes the effect at the given index.
    public func remove(at index: Int) {
        effects.remove(at: index)
    }

    /// Moves an effect from one position to another in the stack.
    public func move(from source: Int, to destination: Int) {
        let effect = effects.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        effects.insert(effect, at: adjustedDestination)
    }

    /// Returns the effects that are currently active (stack enabled and individual effect enabled).
    public var activeEffects: [EffectInstance] {
        guard isEnabled else { return [] }
        return effects.filter(\.isEnabled)
    }
}
