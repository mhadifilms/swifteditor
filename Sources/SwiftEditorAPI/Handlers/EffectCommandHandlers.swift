import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit
import EffectsEngine

// MARK: - Effect Handlers

/// Handler for AddEffectCommand
public final class AddEffectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddEffectCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: AddEffectCommand) throws {}

    public func execute(_ command: AddEffectCommand) async throws -> (any Command)? {
        let effect = EffectInstance(pluginID: command.pluginID, name: command.effectName)
        effectStacks.stack(for: command.clipID).append(effect)
        return RemoveEffectCommand(clipID: command.clipID, effectID: effect.id)
    }
}

/// Handler for RemoveEffectCommand
public final class RemoveEffectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveEffectCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: RemoveEffectCommand) throws {}

    public func execute(_ command: RemoveEffectCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        guard let index = stack.effects.firstIndex(where: { $0.id == command.effectID }) else {
            throw CommandError.executionFailed("Effect not found on clip")
        }
        stack.remove(at: index)
        return nil
    }
}

/// Handler for SetEffectParameterCommand
public final class SetEffectParameterHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SetEffectParameterCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: SetEffectParameterCommand) throws {}

    public func execute(_ command: SetEffectParameterCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        guard let effect = stack.effects.first(where: { $0.id == command.effectID }) else {
            throw CommandError.executionFailed("Effect not found")
        }
        let oldValue = effect.parameters[command.parameterName]
        effect.parameters[command.parameterName] = command.value
        if let oldValue {
            return SetEffectParameterCommand(clipID: command.clipID, effectID: command.effectID,
                                              parameterName: command.parameterName, value: oldValue)
        }
        return nil
    }
}

/// Handler for ToggleEffectCommand
public final class ToggleEffectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = ToggleEffectCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: ToggleEffectCommand) throws {}

    public func execute(_ command: ToggleEffectCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        guard let effect = stack.effects.first(where: { $0.id == command.effectID }) else {
            throw CommandError.executionFailed("Effect not found")
        }
        let wasEnabled = effect.isEnabled
        effect.isEnabled = command.isEnabled
        return ToggleEffectCommand(clipID: command.clipID, effectID: command.effectID, isEnabled: wasEnabled)
    }
}

/// Handler for MoveEffectCommand
public final class MoveEffectHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = MoveEffectCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: MoveEffectCommand) throws {}

    public func execute(_ command: MoveEffectCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        stack.move(from: command.fromIndex, to: command.toIndex)
        return MoveEffectCommand(clipID: command.clipID, fromIndex: command.toIndex, toIndex: command.fromIndex)
    }
}

/// Handler for AddKeyframeCommand
public final class AddKeyframeHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddKeyframeCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: AddKeyframeCommand) throws {}

    public func execute(_ command: AddKeyframeCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        guard let effect = stack.effects.first(where: { $0.id == command.effectID }) else {
            throw CommandError.executionFailed("Effect not found")
        }

        if effect.keyframeTracks[command.parameterName] == nil {
            effect.keyframeTracks[command.parameterName] = KeyframeTrack()
        }
        let keyframe = KeyframeTrack.Keyframe(time: command.time, value: command.value)
        effect.keyframeTracks[command.parameterName]?.addKeyframe(keyframe)

        return RemoveKeyframeCommand(clipID: command.clipID, effectID: command.effectID,
                                      parameterName: command.parameterName, time: command.time)
    }
}

/// Handler for RemoveKeyframeCommand
public final class RemoveKeyframeHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveKeyframeCommand
    private let effectStacks: EffectStackStore

    public init(effectStacks: EffectStackStore) {
        self.effectStacks = effectStacks
    }

    public func validate(_ command: RemoveKeyframeCommand) throws {}

    public func execute(_ command: RemoveKeyframeCommand) async throws -> (any Command)? {
        let stack = effectStacks.stack(for: command.clipID)
        guard let effect = stack.effects.first(where: { $0.id == command.effectID }) else {
            throw CommandError.executionFailed("Effect not found")
        }
        effect.keyframeTracks[command.parameterName]?.removeKeyframe(at: command.time)
        return nil
    }
}

// MARK: - Advanced Editing Handlers

/// Handler for InsertEditCommand
public final class InsertEditHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = InsertEditCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: InsertEditCommand) throws {}

    public func execute(_ command: InsertEditCommand) async throws -> (any Command)? {
        guard timeline.requestInsertEdit(sourceAssetID: command.sourceAssetID, trackID: command.trackID,
                                          at: command.atTime, sourceIn: command.sourceIn,
                                          sourceOut: command.sourceOut) != nil else {
            throw CommandError.executionFailed("Insert edit failed")
        }
        return nil
    }
}

/// Handler for OverwriteEditCommand
public final class OverwriteEditHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = OverwriteEditCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: OverwriteEditCommand) throws {}

    public func execute(_ command: OverwriteEditCommand) async throws -> (any Command)? {
        guard timeline.requestOverwriteEdit(sourceAssetID: command.sourceAssetID, trackID: command.trackID,
                                             at: command.atTime, sourceIn: command.sourceIn,
                                             sourceOut: command.sourceOut) != nil else {
            throw CommandError.executionFailed("Overwrite edit failed")
        }
        return nil
    }
}

/// Handler for RippleDeleteCommand
public final class RippleDeleteHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RippleDeleteCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RippleDeleteCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found")
        }
    }

    public func execute(_ command: RippleDeleteCommand) async throws -> (any Command)? {
        guard timeline.requestRippleDelete(clipID: command.clipID) else {
            throw CommandError.executionFailed("Ripple delete failed")
        }
        return nil
    }
}

/// Handler for RippleTrimCommand
public final class RippleTrimHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RippleTrimCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RippleTrimCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found")
        }
    }

    public func execute(_ command: RippleTrimCommand) async throws -> (any Command)? {
        guard timeline.requestRippleTrim(clipID: command.clipID, edge: command.edge,
                                          to: command.toTime) else {
            throw CommandError.executionFailed("Ripple trim failed")
        }
        return nil
    }
}

/// Handler for RollTrimCommand
public final class RollTrimHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RollTrimCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RollTrimCommand) throws {}

    public func execute(_ command: RollTrimCommand) async throws -> (any Command)? {
        guard timeline.requestRollTrim(leftClipID: command.leftClipID, rightClipID: command.rightClipID,
                                        to: command.toTime) else {
            throw CommandError.executionFailed("Roll trim failed")
        }
        return nil
    }
}

/// Handler for SlipCommand
public final class SlipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SlipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: SlipCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found")
        }
    }

    public func execute(_ command: SlipCommand) async throws -> (any Command)? {
        guard timeline.requestSlip(clipID: command.clipID, by: command.offset) else {
            throw CommandError.executionFailed("Slip failed")
        }
        return nil
    }
}

/// Handler for SlideCommand
public final class SlideHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SlideCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: SlideCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found")
        }
    }

    public func execute(_ command: SlideCommand) async throws -> (any Command)? {
        guard timeline.requestSlide(clipID: command.clipID, by: command.offset,
                                     leftNeighborID: command.leftNeighborID,
                                     rightNeighborID: command.rightNeighborID) else {
            throw CommandError.executionFailed("Slide failed")
        }
        return nil
    }
}

/// Handler for BladeAllCommand
public final class BladeAllHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = BladeAllCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: BladeAllCommand) throws {}

    public func execute(_ command: BladeAllCommand) async throws -> (any Command)? {
        guard timeline.requestBladeAll(at: command.atTime) else {
            throw CommandError.executionFailed("Blade all failed")
        }
        return nil
    }
}

/// Handler for SpeedChangeCommand
public final class SpeedChangeHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SpeedChangeCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: SpeedChangeCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found")
        }
        guard command.newSpeed > 0 else {
            throw CommandError.validationFailed("Speed must be positive")
        }
    }

    public func execute(_ command: SpeedChangeCommand) async throws -> (any Command)? {
        let oldSpeed = timeline.clip(by: command.clipID)?.speed ?? 1.0
        guard timeline.requestSpeedChange(clipID: command.clipID, newSpeed: command.newSpeed) else {
            throw CommandError.executionFailed("Speed change failed")
        }
        return SpeedChangeCommand(clipID: command.clipID, newSpeed: oldSpeed)
    }
}

/// Handler for AppendAtEndCommand
public final class AppendAtEndHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AppendAtEndCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AppendAtEndCommand) throws {}

    public func execute(_ command: AppendAtEndCommand) async throws -> (any Command)? {
        guard timeline.requestAppendAtEnd(sourceAssetID: command.sourceAssetID, trackID: command.trackID,
                                           sourceIn: command.sourceIn, sourceOut: command.sourceOut) != nil else {
            throw CommandError.executionFailed("Append at end failed")
        }
        return nil
    }
}

/// Handler for PlaceOnTopCommand
public final class PlaceOnTopHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = PlaceOnTopCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: PlaceOnTopCommand) throws {}

    public func execute(_ command: PlaceOnTopCommand) async throws -> (any Command)? {
        guard timeline.requestPlaceOnTop(sourceAssetID: command.sourceAssetID,
                                          at: command.position, sourceIn: command.sourceIn,
                                          sourceOut: command.sourceOut) != nil else {
            throw CommandError.executionFailed("Place on top failed")
        }
        return nil
    }
}

// MARK: - Marker Handlers

/// Handler for AddMarkerCommand
public final class AddMarkerHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddMarkerCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AddMarkerCommand) throws {}

    public func execute(_ command: AddMarkerCommand) async throws -> (any Command)? {
        let markerID = timeline.requestAddMarker(name: command.name, at: command.atTime)
        return RemoveMarkerCommand(markerID: markerID)
    }
}

/// Handler for RemoveMarkerCommand
public final class RemoveMarkerHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveMarkerCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RemoveMarkerCommand) throws {}

    public func execute(_ command: RemoveMarkerCommand) async throws -> (any Command)? {
        guard timeline.requestRemoveMarker(id: command.markerID) else {
            throw CommandError.executionFailed("Remove marker failed")
        }
        return nil
    }
}
