import Foundation
import Observation
import EffectsEngine

/// Centralized store mapping clip IDs to their effect stacks.
/// Lives in SwiftEditorAPI to keep TimelineKit independent of EffectsEngine.
@Observable
public final class EffectStackStore: @unchecked Sendable {
    private var stacks: [UUID: EffectStack] = [:]

    public init() {}

    /// Get or create the effect stack for a clip.
    public func stack(for clipID: UUID) -> EffectStack {
        if let existing = stacks[clipID] {
            return existing
        }
        let newStack = EffectStack()
        stacks[clipID] = newStack
        return newStack
    }

    /// Check if a clip has any effects.
    public func hasEffects(for clipID: UUID) -> Bool {
        stacks[clipID]?.effects.isEmpty == false
    }

    /// Remove the effect stack for a clip (e.g., when clip is deleted).
    public func removeStack(for clipID: UUID) {
        stacks.removeValue(forKey: clipID)
    }

    /// All clip IDs that have effect stacks.
    public var clipIDs: Set<UUID> {
        Set(stacks.keys)
    }
}
