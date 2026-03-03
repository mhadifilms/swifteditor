import Foundation
import CoreMediaPlus
import CommandBus

// MARK: - Effect Commands

public struct AddEffectCommand: Command {
    public static let typeIdentifier = "effects.addEffect"
    public let clipID: UUID
    public let pluginID: String
    public let effectName: String
    public var undoDescription: String { "Add Effect" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, pluginID: String, effectName: String) {
        self.clipID = clipID
        self.pluginID = pluginID
        self.effectName = effectName
    }
}

public struct RemoveEffectCommand: Command {
    public static let typeIdentifier = "effects.removeEffect"
    public let clipID: UUID
    public let effectID: UUID
    public var undoDescription: String { "Remove Effect" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, effectID: UUID) {
        self.clipID = clipID
        self.effectID = effectID
    }
}

public struct SetEffectParameterCommand: Command {
    public static let typeIdentifier = "effects.setParameter"
    public let clipID: UUID
    public let effectID: UUID
    public let parameterName: String
    public let value: ParameterValue
    public var undoDescription: String { "Set Effect Parameter" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, effectID: UUID, parameterName: String, value: ParameterValue) {
        self.clipID = clipID
        self.effectID = effectID
        self.parameterName = parameterName
        self.value = value
    }
}

public struct ToggleEffectCommand: Command {
    public static let typeIdentifier = "effects.toggleEffect"
    public let clipID: UUID
    public let effectID: UUID
    public let isEnabled: Bool
    public var undoDescription: String { "Toggle Effect" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, effectID: UUID, isEnabled: Bool) {
        self.clipID = clipID
        self.effectID = effectID
        self.isEnabled = isEnabled
    }
}

public struct MoveEffectCommand: Command {
    public static let typeIdentifier = "effects.moveEffect"
    public let clipID: UUID
    public let fromIndex: Int
    public let toIndex: Int
    public var undoDescription: String { "Reorder Effect" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, fromIndex: Int, toIndex: Int) {
        self.clipID = clipID
        self.fromIndex = fromIndex
        self.toIndex = toIndex
    }
}

public struct AddKeyframeCommand: Command {
    public static let typeIdentifier = "effects.addKeyframe"
    public let clipID: UUID
    public let effectID: UUID
    public let parameterName: String
    public let time: Rational
    public let value: ParameterValue
    public var undoDescription: String { "Add Keyframe" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, effectID: UUID, parameterName: String,
                time: Rational, value: ParameterValue) {
        self.clipID = clipID
        self.effectID = effectID
        self.parameterName = parameterName
        self.time = time
        self.value = value
    }
}

public struct RemoveKeyframeCommand: Command {
    public static let typeIdentifier = "effects.removeKeyframe"
    public let clipID: UUID
    public let effectID: UUID
    public let parameterName: String
    public let time: Rational
    public var undoDescription: String { "Remove Keyframe" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, effectID: UUID, parameterName: String, time: Rational) {
        self.clipID = clipID
        self.effectID = effectID
        self.parameterName = parameterName
        self.time = time
    }
}

// MARK: - Transition Commands

public struct AddTransitionCommand: Command {
    public static let typeIdentifier = "effects.addTransition"
    public let clipAID: UUID
    public let clipBID: UUID
    public let transitionType: String  // Serializable type identifier
    public let duration: Rational
    public var undoDescription: String { "Add Transition" }
    public var isMutating: Bool { true }

    public init(clipAID: UUID, clipBID: UUID, transitionType: String, duration: Rational) {
        self.clipAID = clipAID
        self.clipBID = clipBID
        self.transitionType = transitionType
        self.duration = duration
    }
}

public struct RemoveTransitionCommand: Command {
    public static let typeIdentifier = "effects.removeTransition"
    public let transitionID: UUID
    public var undoDescription: String { "Remove Transition" }
    public var isMutating: Bool { true }

    public init(transitionID: UUID) {
        self.transitionID = transitionID
    }
}

// MARK: - Advanced Editing Commands (Phase 2)

public struct RippleDeleteCommand: Command {
    public static let typeIdentifier = "editing.rippleDelete"
    public let clipID: UUID
    public var undoDescription: String { "Ripple Delete" }
    public var isMutating: Bool { true }

    public init(clipID: UUID) {
        self.clipID = clipID
    }
}

public struct RippleTrimCommand: Command {
    public static let typeIdentifier = "editing.rippleTrim"
    public let clipID: UUID
    public let edge: TrimEdge
    public let toTime: Rational
    public var undoDescription: String { "Ripple Trim" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, edge: TrimEdge, toTime: Rational) {
        self.clipID = clipID
        self.edge = edge
        self.toTime = toTime
    }
}

public struct RollTrimCommand: Command {
    public static let typeIdentifier = "editing.rollTrim"
    public let leftClipID: UUID
    public let rightClipID: UUID
    public let toTime: Rational
    public var undoDescription: String { "Roll Trim" }
    public var isMutating: Bool { true }

    public init(leftClipID: UUID, rightClipID: UUID, toTime: Rational) {
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.toTime = toTime
    }
}

public struct SlipCommand: Command {
    public static let typeIdentifier = "editing.slip"
    public let clipID: UUID
    public let offset: Rational
    public var undoDescription: String { "Slip" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, offset: Rational) {
        self.clipID = clipID
        self.offset = offset
    }
}

public struct SlideCommand: Command {
    public static let typeIdentifier = "editing.slide"
    public let clipID: UUID
    public let offset: Rational
    public let leftNeighborID: UUID?
    public let rightNeighborID: UUID?
    public var undoDescription: String { "Slide" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, offset: Rational, leftNeighborID: UUID?, rightNeighborID: UUID?) {
        self.clipID = clipID
        self.offset = offset
        self.leftNeighborID = leftNeighborID
        self.rightNeighborID = rightNeighborID
    }
}

public struct BladeAllCommand: Command {
    public static let typeIdentifier = "editing.bladeAll"
    public let atTime: Rational
    public var undoDescription: String { "Blade All" }
    public var isMutating: Bool { true }

    public init(atTime: Rational) {
        self.atTime = atTime
    }
}

public struct SpeedChangeCommand: Command {
    public static let typeIdentifier = "editing.speedChange"
    public let clipID: UUID
    public let newSpeed: Double
    public var undoDescription: String { "Speed Change" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, newSpeed: Double) {
        self.clipID = clipID
        self.newSpeed = newSpeed
    }
}

public struct AppendAtEndCommand: Command {
    public static let typeIdentifier = "editing.appendAtEnd"
    public let sourceAssetID: UUID
    public let trackID: UUID
    public let sourceIn: Rational
    public let sourceOut: Rational
    public var undoDescription: String { "Append at End" }
    public var isMutating: Bool { true }

    public init(sourceAssetID: UUID, trackID: UUID, sourceIn: Rational, sourceOut: Rational) {
        self.sourceAssetID = sourceAssetID
        self.trackID = trackID
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

public struct PlaceOnTopCommand: Command {
    public static let typeIdentifier = "editing.placeOnTop"
    public let sourceAssetID: UUID
    public let position: Rational
    public let sourceIn: Rational
    public let sourceOut: Rational
    public var undoDescription: String { "Place on Top" }
    public var isMutating: Bool { true }

    public init(sourceAssetID: UUID, position: Rational, sourceIn: Rational, sourceOut: Rational) {
        self.sourceAssetID = sourceAssetID
        self.position = position
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

// MARK: - Marker Commands

public struct AddMarkerCommand: Command {
    public static let typeIdentifier = "editing.addMarker"
    public let name: String
    public let atTime: Rational
    public let color: String  // Serializable color name
    public var undoDescription: String { "Add Marker" }
    public var isMutating: Bool { true }

    public init(name: String, atTime: Rational, color: String = "blue") {
        self.name = name
        self.atTime = atTime
        self.color = color
    }
}

public struct RemoveMarkerCommand: Command {
    public static let typeIdentifier = "editing.removeMarker"
    public let markerID: UUID
    public var undoDescription: String { "Remove Marker" }
    public var isMutating: Bool { true }

    public init(markerID: UUID) {
        self.markerID = markerID
    }
}
