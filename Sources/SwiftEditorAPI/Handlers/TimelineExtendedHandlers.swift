import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

// MARK: - Compound Clip Handlers

public final class CreateCompoundClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = CreateCompoundClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: CreateCompoundClipCommand) throws {
        guard !command.clipIDs.isEmpty else {
            throw CommandError.validationFailed("No clips specified for compound clip")
        }
    }

    public func execute(_ command: CreateCompoundClipCommand) async throws -> (any Command)? {
        guard let compoundID = timeline.requestCreateCompoundClip(clipIDs: command.clipIDs) else {
            throw CommandError.executionFailed("Failed to create compound clip")
        }
        // Undo is handled by TimelineKit's internal undo manager
        return nil
    }
}

public final class FlattenCompoundClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = FlattenCompoundClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: FlattenCompoundClipCommand) throws {
        guard timeline.compoundClips[command.compoundClipID] != nil else {
            throw CommandError.validationFailed("Compound clip not found: \(command.compoundClipID)")
        }
    }

    public func execute(_ command: FlattenCompoundClipCommand) async throws -> (any Command)? {
        guard timeline.requestFlattenCompoundClip(compoundClipID: command.compoundClipID) else {
            throw CommandError.executionFailed("Failed to flatten compound clip")
        }
        return nil
    }
}

// MARK: - Multicam Handlers

public final class CreateMulticamClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = CreateMulticamClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: CreateMulticamClipCommand) throws {
        guard !command.angleIDs.isEmpty else {
            throw CommandError.validationFailed("No angles specified for multicam clip")
        }
        guard command.duration > .zero else {
            throw CommandError.validationFailed("Duration must be positive")
        }
    }

    public func execute(_ command: CreateMulticamClipCommand) async throws -> (any Command)? {
        var angles: [MulticamAngle] = []
        for i in 0..<command.angleIDs.count {
            angles.append(MulticamAngle(
                id: command.angleIDs[i],
                name: command.angleNames[i],
                sourceAssetID: command.angleSourceAssetIDs[i],
                sourceIn: command.angleSourceIns[i],
                sourceOut: command.angleSourceOuts[i]
            ))
        }

        guard timeline.requestCreateMulticamClip(
            angles: angles,
            trackID: command.trackID,
            at: command.position,
            duration: command.duration
        ) != nil else {
            throw CommandError.executionFailed("Failed to create multicam clip")
        }
        return nil
    }
}

public final class SwitchAngleHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SwitchAngleCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: SwitchAngleCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found: \(command.clipID)")
        }
    }

    public func execute(_ command: SwitchAngleCommand) async throws -> (any Command)? {
        guard timeline.requestSwitchAngle(
            clipID: command.clipID,
            angleIndex: command.angleIndex,
            at: command.atTime
        ) else {
            throw CommandError.executionFailed("Failed to switch angle")
        }
        return nil
    }
}

// MARK: - Subtitle Handlers

public final class AddSubtitleTrackHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddSubtitleTrackCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AddSubtitleTrackCommand) throws {}

    public func execute(_ command: AddSubtitleTrackCommand) async throws -> (any Command)? {
        let trackID = timeline.requestAddSubtitleTrack(name: command.name)
        return RemoveSubtitleTrackCommand(trackID: trackID)
    }
}

public final class RemoveSubtitleTrackHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveSubtitleTrackCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RemoveSubtitleTrackCommand) throws {
        guard timeline.subtitleTracks.contains(where: { $0.id == command.trackID }) else {
            throw CommandError.validationFailed("Subtitle track not found: \(command.trackID)")
        }
    }

    public func execute(_ command: RemoveSubtitleTrackCommand) async throws -> (any Command)? {
        guard timeline.requestRemoveSubtitleTrack(trackID: command.trackID) else {
            throw CommandError.executionFailed("Failed to remove subtitle track")
        }
        return nil
    }
}

public final class AddSubtitleCueHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddSubtitleCueCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AddSubtitleCueCommand) throws {
        guard timeline.subtitleTracks.contains(where: { $0.id == command.trackID }) else {
            throw CommandError.validationFailed("Subtitle track not found: \(command.trackID)")
        }
    }

    public func execute(_ command: AddSubtitleCueCommand) async throws -> (any Command)? {
        let bgColor: (r: Double, g: Double, b: Double, a: Double)?
        if let r = command.bgColorR, let g = command.bgColorG,
           let b = command.bgColorB, let a = command.bgColorA {
            bgColor = (r, g, b, a)
        } else {
            bgColor = nil
        }

        let style = SubtitleStyle(
            fontName: command.fontName,
            fontSize: CGFloat(command.fontSize),
            textColor: (command.textColorR, command.textColorG, command.textColorB, command.textColorA),
            backgroundColor: bgColor,
            position: SubtitlePosition(rawValue: command.position) ?? .bottom,
            alignment: SubtitleAlignment(rawValue: command.alignment) ?? .center,
            isBold: command.isBold,
            isItalic: command.isItalic
        )

        guard let cueID = timeline.requestAddSubtitleCue(
            trackID: command.trackID,
            text: command.text,
            startTime: command.startTime,
            endTime: command.endTime,
            style: style
        ) else {
            throw CommandError.executionFailed("Failed to add subtitle cue")
        }

        return RemoveSubtitleCueCommand(trackID: command.trackID, cueID: cueID)
    }
}

public final class RemoveSubtitleCueHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveSubtitleCueCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RemoveSubtitleCueCommand) throws {
        guard timeline.subtitleTracks.contains(where: { $0.id == command.trackID }) else {
            throw CommandError.validationFailed("Subtitle track not found: \(command.trackID)")
        }
    }

    public func execute(_ command: RemoveSubtitleCueCommand) async throws -> (any Command)? {
        guard timeline.requestRemoveSubtitleCue(trackID: command.trackID, cueID: command.cueID) else {
            throw CommandError.executionFailed("Failed to remove subtitle cue")
        }
        return nil
    }
}

public final class UpdateSubtitleCueHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = UpdateSubtitleCueCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: UpdateSubtitleCueCommand) throws {
        guard let track = timeline.subtitleTracks.first(where: { $0.id == command.trackID }) else {
            throw CommandError.validationFailed("Subtitle track not found: \(command.trackID)")
        }
        guard track.cues.contains(where: { $0.id == command.cueID }) else {
            throw CommandError.validationFailed("Subtitle cue not found: \(command.cueID)")
        }
    }

    public func execute(_ command: UpdateSubtitleCueCommand) async throws -> (any Command)? {
        guard let track = timeline.subtitleTracks.first(where: { $0.id == command.trackID }) else {
            throw CommandError.executionFailed("Subtitle track not found")
        }

        // Build style if any style fields provided
        var style: SubtitleStyle?
        if command.fontName != nil || command.fontSize != nil ||
           command.textColorR != nil || command.positionValue != nil ||
           command.alignmentValue != nil || command.isBold != nil || command.isItalic != nil {

            // Get current cue to use as base for style merge
            if let currentCue = track.cues.first(where: { $0.id == command.cueID }) {
                let currentStyle = currentCue.style
                let bgColor: (r: Double, g: Double, b: Double, a: Double)?
                if let r = command.bgColorR, let g = command.bgColorG,
                   let b = command.bgColorB, let a = command.bgColorA {
                    bgColor = (r, g, b, a)
                } else {
                    bgColor = currentStyle.backgroundColor
                }

                style = SubtitleStyle(
                    fontName: command.fontName ?? currentStyle.fontName,
                    fontSize: CGFloat(command.fontSize ?? Double(currentStyle.fontSize)),
                    textColor: (
                        command.textColorR ?? currentStyle.textColor.r,
                        command.textColorG ?? currentStyle.textColor.g,
                        command.textColorB ?? currentStyle.textColor.b,
                        command.textColorA ?? currentStyle.textColor.a
                    ),
                    backgroundColor: bgColor,
                    position: command.positionValue.flatMap { SubtitlePosition(rawValue: $0) } ?? currentStyle.position,
                    alignment: command.alignmentValue.flatMap { SubtitleAlignment(rawValue: $0) } ?? currentStyle.alignment,
                    isBold: command.isBold ?? currentStyle.isBold,
                    isItalic: command.isItalic ?? currentStyle.isItalic
                )
            }
        }

        track.updateCue(
            id: command.cueID,
            text: command.text,
            startTime: command.startTime,
            endTime: command.endTime,
            style: style
        )

        return nil
    }
}
