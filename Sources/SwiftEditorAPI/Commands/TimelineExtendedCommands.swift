import Foundation
import CoreMediaPlus
import CommandBus

// MARK: - Compound Clip Commands

public struct CreateCompoundClipCommand: Command {
    public static let typeIdentifier = "timeline.createCompoundClip"
    public let clipIDs: Set<UUID>
    public var undoDescription: String { "Create Compound Clip" }
    public var isMutating: Bool { true }

    public init(clipIDs: Set<UUID>) {
        self.clipIDs = clipIDs
    }
}

public struct FlattenCompoundClipCommand: Command {
    public static let typeIdentifier = "timeline.flattenCompoundClip"
    public let compoundClipID: UUID
    public var undoDescription: String { "Flatten Compound Clip" }
    public var isMutating: Bool { true }

    public init(compoundClipID: UUID) {
        self.compoundClipID = compoundClipID
    }
}

// MARK: - Multicam Commands

public struct CreateMulticamClipCommand: Command {
    public static let typeIdentifier = "timeline.createMulticamClip"
    public let angleIDs: [UUID]
    public let angleNames: [String]
    public let angleSourceAssetIDs: [UUID]
    public let angleSourceIns: [Rational]
    public let angleSourceOuts: [Rational]
    public let trackID: UUID
    public let position: Rational
    public let duration: Rational
    public var undoDescription: String { "Create Multicam Clip" }
    public var isMutating: Bool { true }

    public init(angleIDs: [UUID], angleNames: [String], angleSourceAssetIDs: [UUID],
                angleSourceIns: [Rational], angleSourceOuts: [Rational],
                trackID: UUID, position: Rational, duration: Rational) {
        self.angleIDs = angleIDs
        self.angleNames = angleNames
        self.angleSourceAssetIDs = angleSourceAssetIDs
        self.angleSourceIns = angleSourceIns
        self.angleSourceOuts = angleSourceOuts
        self.trackID = trackID
        self.position = position
        self.duration = duration
    }
}

public struct SwitchAngleCommand: Command {
    public static let typeIdentifier = "timeline.switchAngle"
    public let clipID: UUID
    public let angleIndex: Int
    public let atTime: Rational?
    public var undoDescription: String { "Switch Angle" }
    public var isMutating: Bool { true }

    public init(clipID: UUID, angleIndex: Int, atTime: Rational? = nil) {
        self.clipID = clipID
        self.angleIndex = angleIndex
        self.atTime = atTime
    }
}

// MARK: - Subtitle Commands

public struct AddSubtitleTrackCommand: Command {
    public static let typeIdentifier = "subtitle.addTrack"
    public let name: String
    public var undoDescription: String { "Add Subtitle Track" }
    public var isMutating: Bool { true }

    public init(name: String) {
        self.name = name
    }
}

public struct RemoveSubtitleTrackCommand: Command {
    public static let typeIdentifier = "subtitle.removeTrack"
    public let trackID: UUID
    public var undoDescription: String { "Remove Subtitle Track" }
    public var isMutating: Bool { true }

    public init(trackID: UUID) {
        self.trackID = trackID
    }
}

public struct AddSubtitleCueCommand: Command {
    public static let typeIdentifier = "subtitle.addCue"
    public let trackID: UUID
    public let text: String
    public let startTime: Rational
    public let endTime: Rational
    // SubtitleStyle has tuple fields, so store individual style properties
    public let fontName: String
    public let fontSize: Double
    public let textColorR: Double
    public let textColorG: Double
    public let textColorB: Double
    public let textColorA: Double
    public let bgColorR: Double?
    public let bgColorG: Double?
    public let bgColorB: Double?
    public let bgColorA: Double?
    public let position: String
    public let alignment: String
    public let isBold: Bool
    public let isItalic: Bool
    public var undoDescription: String { "Add Subtitle" }
    public var isMutating: Bool { true }

    public init(trackID: UUID, text: String, startTime: Rational, endTime: Rational,
                fontName: String = "Helvetica Neue", fontSize: Double = 24,
                textColorR: Double = 1, textColorG: Double = 1, textColorB: Double = 1, textColorA: Double = 1,
                bgColorR: Double? = 0, bgColorG: Double? = 0, bgColorB: Double? = 0, bgColorA: Double? = 0.6,
                position: String = "bottom", alignment: String = "center",
                isBold: Bool = false, isItalic: Bool = false) {
        self.trackID = trackID
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColorR = textColorR
        self.textColorG = textColorG
        self.textColorB = textColorB
        self.textColorA = textColorA
        self.bgColorR = bgColorR
        self.bgColorG = bgColorG
        self.bgColorB = bgColorB
        self.bgColorA = bgColorA
        self.position = position
        self.alignment = alignment
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

public struct RemoveSubtitleCueCommand: Command {
    public static let typeIdentifier = "subtitle.removeCue"
    public let trackID: UUID
    public let cueID: UUID
    public var undoDescription: String { "Remove Subtitle" }
    public var isMutating: Bool { true }

    public init(trackID: UUID, cueID: UUID) {
        self.trackID = trackID
        self.cueID = cueID
    }
}

public struct UpdateSubtitleCueCommand: Command {
    public static let typeIdentifier = "subtitle.updateCue"
    public let trackID: UUID
    public let cueID: UUID
    public let text: String?
    public let startTime: Rational?
    public let endTime: Rational?
    // Optional style fields — nil means no change
    public let fontName: String?
    public let fontSize: Double?
    public let textColorR: Double?
    public let textColorG: Double?
    public let textColorB: Double?
    public let textColorA: Double?
    public let bgColorR: Double?
    public let bgColorG: Double?
    public let bgColorB: Double?
    public let bgColorA: Double?
    public let positionValue: String?
    public let alignmentValue: String?
    public let isBold: Bool?
    public let isItalic: Bool?
    public var undoDescription: String { "Update Subtitle" }
    public var isMutating: Bool { true }

    public init(trackID: UUID, cueID: UUID, text: String? = nil,
                startTime: Rational? = nil, endTime: Rational? = nil,
                fontName: String? = nil, fontSize: Double? = nil,
                textColorR: Double? = nil, textColorG: Double? = nil,
                textColorB: Double? = nil, textColorA: Double? = nil,
                bgColorR: Double? = nil, bgColorG: Double? = nil,
                bgColorB: Double? = nil, bgColorA: Double? = nil,
                positionValue: String? = nil, alignmentValue: String? = nil,
                isBold: Bool? = nil, isItalic: Bool? = nil) {
        self.trackID = trackID
        self.cueID = cueID
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColorR = textColorR
        self.textColorG = textColorG
        self.textColorB = textColorB
        self.textColorA = textColorA
        self.bgColorR = bgColorR
        self.bgColorG = bgColorG
        self.bgColorB = bgColorB
        self.bgColorA = bgColorA
        self.positionValue = positionValue
        self.alignmentValue = alignmentValue
        self.isBold = isBold
        self.isItalic = isItalic
    }
}
