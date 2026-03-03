import Foundation
import CoreMediaPlus
import CommandBus
import EffectsEngine

/// Facade for effects operations.
/// All operations create Command structs and dispatch through CommandBus.
public final class EffectsAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    public let effectStacks: EffectStackStore

    public init(dispatcher: CommandDispatcher, effectStacks: EffectStackStore) {
        self.dispatcher = dispatcher
        self.effectStacks = effectStacks
    }

    /// Add an effect to a clip's effect stack.
    @discardableResult
    public func addEffect(clipID: UUID, pluginID: String, name: String) async throws -> CommandResult {
        let command = AddEffectCommand(clipID: clipID, pluginID: pluginID, effectName: name)
        return try await dispatcher.dispatch(command)
    }

    /// Remove an effect from a clip.
    @discardableResult
    public func removeEffect(clipID: UUID, effectID: UUID) async throws -> CommandResult {
        let command = RemoveEffectCommand(clipID: clipID, effectID: effectID)
        return try await dispatcher.dispatch(command)
    }

    /// Set an effect parameter value.
    @discardableResult
    public func setParameter(clipID: UUID, effectID: UUID,
                              parameterName: String, value: ParameterValue) async throws -> CommandResult {
        let command = SetEffectParameterCommand(clipID: clipID, effectID: effectID,
                                                 parameterName: parameterName, value: value)
        return try await dispatcher.dispatch(command)
    }

    /// Toggle an effect on/off.
    @discardableResult
    public func toggleEffect(clipID: UUID, effectID: UUID, isEnabled: Bool) async throws -> CommandResult {
        let command = ToggleEffectCommand(clipID: clipID, effectID: effectID, isEnabled: isEnabled)
        return try await dispatcher.dispatch(command)
    }

    /// Reorder an effect in the stack.
    @discardableResult
    public func moveEffect(clipID: UUID, fromIndex: Int, toIndex: Int) async throws -> CommandResult {
        let command = MoveEffectCommand(clipID: clipID, fromIndex: fromIndex, toIndex: toIndex)
        return try await dispatcher.dispatch(command)
    }

    /// Add a keyframe to an effect parameter.
    @discardableResult
    public func addKeyframe(clipID: UUID, effectID: UUID, parameterName: String,
                             time: Rational, value: ParameterValue) async throws -> CommandResult {
        let command = AddKeyframeCommand(clipID: clipID, effectID: effectID,
                                          parameterName: parameterName, time: time, value: value)
        return try await dispatcher.dispatch(command)
    }

    /// Remove a keyframe from an effect parameter.
    @discardableResult
    public func removeKeyframe(clipID: UUID, effectID: UUID,
                                parameterName: String, time: Rational) async throws -> CommandResult {
        let command = RemoveKeyframeCommand(clipID: clipID, effectID: effectID,
                                             parameterName: parameterName, time: time)
        return try await dispatcher.dispatch(command)
    }

    /// Set or clear a speed ramp curve on a clip.
    @discardableResult
    public func setSpeedRamp(clipID: UUID, curve: TimeRemapCurve?) async throws -> CommandResult {
        let command = SetSpeedRampCommand(clipID: clipID, curve: curve)
        return try await dispatcher.dispatch(command)
    }

    /// Get the effect stack for a clip (read-only access).
    public func effects(for clipID: UUID) -> EffectStack {
        effectStacks.stack(for: clipID)
    }

    /// List built-in effects.
    public var builtInEffects: [BuiltInEffectDescriptor] {
        BuiltInEffects.all
    }

    /// Get built-in effects in a category.
    public func builtInEffects(in category: BuiltInEffectCategory) -> [BuiltInEffectDescriptor] {
        BuiltInEffects.descriptors(in: category)
    }
}
