import Foundation
import Observation
import CoreMediaPlus

/// A single subtitle cue on the subtitle track.
public struct SubtitleCue: Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var startTime: Rational
    public var endTime: Rational
    public var style: SubtitleStyle

    public var duration: Rational { endTime - startTime }

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: Rational,
        endTime: Rational,
        style: SubtitleStyle = .default
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.style = style
    }
}

/// Styling for subtitle cues.
public struct SubtitleStyle: Sendable {
    public var fontName: String
    public var fontSize: CGFloat
    public var textColor: (r: Double, g: Double, b: Double, a: Double)
    public var backgroundColor: (r: Double, g: Double, b: Double, a: Double)?
    public var position: SubtitlePosition
    public var alignment: SubtitleAlignment
    public var isBold: Bool
    public var isItalic: Bool

    public static let `default` = SubtitleStyle(
        fontName: "Helvetica Neue",
        fontSize: 24,
        textColor: (1, 1, 1, 1),
        backgroundColor: (0, 0, 0, 0.6),
        position: .bottom,
        alignment: .center,
        isBold: false,
        isItalic: false
    )

    public init(
        fontName: String = "Helvetica Neue",
        fontSize: CGFloat = 24,
        textColor: (r: Double, g: Double, b: Double, a: Double) = (1, 1, 1, 1),
        backgroundColor: (r: Double, g: Double, b: Double, a: Double)? = (0, 0, 0, 0.6),
        position: SubtitlePosition = .bottom,
        alignment: SubtitleAlignment = .center,
        isBold: Bool = false,
        isItalic: Bool = false
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.position = position
        self.alignment = alignment
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

public enum SubtitlePosition: String, Sendable {
    case top
    case center
    case bottom
}

public enum SubtitleAlignment: String, Sendable {
    case left
    case center
    case right
}

/// Runtime model of a subtitle track.
@Observable
public final class SubtitleTrackModel: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isMuted: Bool = false
    public var isLocked: Bool = false
    public private(set) var cues: [SubtitleCue] = []

    public init(id: UUID = UUID(), name: String = "Subtitles") {
        self.id = id
        self.name = name
    }

    /// Cues sorted by start time.
    public var sortedCues: [SubtitleCue] {
        cues.sorted { $0.startTime < $1.startTime }
    }

    /// Get the active cue at a given time.
    public func cue(at time: Rational) -> SubtitleCue? {
        cues.first { time >= $0.startTime && time < $0.endTime }
    }

    // MARK: - Mutations

    public func addCue(_ cue: SubtitleCue) {
        cues.append(cue)
    }

    public func removeCue(id: UUID) -> SubtitleCue? {
        if let index = cues.firstIndex(where: { $0.id == id }) {
            return cues.remove(at: index)
        }
        return nil
    }

    public func updateCue(id: UUID, text: String? = nil, startTime: Rational? = nil,
                           endTime: Rational? = nil, style: SubtitleStyle? = nil) {
        guard let index = cues.firstIndex(where: { $0.id == id }) else { return }
        if let text { cues[index].text = text }
        if let startTime { cues[index].startTime = startTime }
        if let endTime { cues[index].endTime = endTime }
        if let style { cues[index].style = style }
    }
}

// MARK: - Subtitle Operations on TimelineModel

extension TimelineModel {

    /// Storage for subtitle tracks.
    nonisolated(unsafe) private static var _subtitleTracks: [ObjectIdentifier: [SubtitleTrackModel]] = [:]

    public var subtitleTracks: [SubtitleTrackModel] {
        get { Self._subtitleTracks[ObjectIdentifier(self)] ?? [] }
        set { Self._subtitleTracks[ObjectIdentifier(self)] = newValue }
    }

    /// Add a subtitle track.
    @discardableResult
    public func requestAddSubtitleTrack(name: String = "Subtitles") -> UUID {
        let trackID = UUID()
        let track = SubtitleTrackModel(id: trackID, name: name)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.subtitleTracks.append(track)
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.subtitleTracks.removeAll { $0.id == trackID }
            return true
        }

        guard redo() else { let _ = undo(); return trackID }
        undoManager.record(undo: undo, redo: redo, description: "Add Subtitle Track")
        return trackID
    }

    /// Remove a subtitle track.
    @discardableResult
    public func requestRemoveSubtitleTrack(trackID: UUID) -> Bool {
        guard let index = subtitleTracks.firstIndex(where: { $0.id == trackID }) else { return false }
        let track = subtitleTracks[index]
        let savedCues = track.cues

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.subtitleTracks.removeAll { $0.id == trackID }
            return true
        }
        prependOperation(&undo) { [weak self] in
            let restored = SubtitleTrackModel(id: trackID, name: track.name)
            for cue in savedCues {
                restored.addCue(cue)
            }
            self?.subtitleTracks.insert(restored, at: min(index, self?.subtitleTracks.count ?? 0))
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Remove Subtitle Track")
        return true
    }

    /// Add a subtitle cue to a track.
    @discardableResult
    public func requestAddSubtitleCue(
        trackID: UUID, text: String,
        startTime: Rational, endTime: Rational,
        style: SubtitleStyle = .default
    ) -> UUID? {
        guard let track = subtitleTracks.first(where: { $0.id == trackID }) else { return nil }

        let cue = SubtitleCue(text: text, startTime: startTime, endTime: endTime, style: style)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak track] in
            track?.addCue(cue)
            return true
        }
        prependOperation(&undo) { [weak track] in
            track?.removeCue(id: cue.id) != nil
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Add Subtitle")
        return cue.id
    }

    /// Remove a subtitle cue.
    @discardableResult
    public func requestRemoveSubtitleCue(trackID: UUID, cueID: UUID) -> Bool {
        guard let track = subtitleTracks.first(where: { $0.id == trackID }),
              let cue = track.cues.first(where: { $0.id == cueID }) else { return false }

        let savedCue = cue

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak track] in
            track?.removeCue(id: cueID) != nil
        }
        prependOperation(&undo) { [weak track] in
            track?.addCue(savedCue)
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Remove Subtitle")
        return true
    }
}
