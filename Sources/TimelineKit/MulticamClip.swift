import Foundation
import Observation
import CoreMediaPlus

/// Represents a single angle (camera source) in a multicam clip.
public struct MulticamAngle: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let sourceAssetID: UUID
    public var sourceIn: Rational
    public var sourceOut: Rational

    public init(
        id: UUID = UUID(),
        name: String,
        sourceAssetID: UUID,
        sourceIn: Rational,
        sourceOut: Rational
    ) {
        self.id = id
        self.name = name
        self.sourceAssetID = sourceAssetID
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }
}

/// A multicam clip contains multiple synchronized angle sources.
/// The active angle determines which source is rendered.
@Observable
public final class MulticamClipModel: @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var angles: [MulticamAngle]
    public var activeAngleIndex: Int

    /// Angle switching events: (timelineTime, angleIndex)
    /// Sorted by time. Each entry means "from this time forward, use this angle."
    public var angleSwitches: [(time: Rational, angleIndex: Int)]

    public init(
        id: UUID = UUID(),
        name: String = "Multicam",
        angles: [MulticamAngle] = [],
        activeAngleIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.angles = angles
        self.activeAngleIndex = activeAngleIndex
        self.angleSwitches = []
    }

    /// Get the active angle at a given time within the multicam clip.
    public func angleIndex(at time: Rational) -> Int {
        // Find the last switch at or before this time
        var result = activeAngleIndex
        for sw in angleSwitches {
            if sw.time <= time {
                result = sw.angleIndex
            } else {
                break
            }
        }
        return min(result, angles.count - 1)
    }

    /// Get the active angle source at a given time.
    public func activeAngle(at time: Rational) -> MulticamAngle? {
        let idx = angleIndex(at: time)
        guard idx >= 0, idx < angles.count else { return nil }
        return angles[idx]
    }

    /// Add an angle switch point.
    public func addSwitch(at time: Rational, angleIndex: Int) {
        // Remove existing switch at same time
        angleSwitches.removeAll { $0.time == time }
        angleSwitches.append((time: time, angleIndex: angleIndex))
        angleSwitches.sort { $0.time < $1.time }
    }

    /// Remove an angle switch point.
    public func removeSwitch(at time: Rational) {
        angleSwitches.removeAll { $0.time == time }
    }
}

// MARK: - Multicam Operations on TimelineModel

extension TimelineModel {

    /// Registry of multicam clips associated with this timeline.
    nonisolated(unsafe) private static var _multicamClips: [ObjectIdentifier: [UUID: MulticamClipModel]] = [:]

    public var multicamClips: [UUID: MulticamClipModel] {
        get { Self._multicamClips[ObjectIdentifier(self)] ?? [:] }
        set { Self._multicamClips[ObjectIdentifier(self)] = newValue }
    }

    /// Create a multicam clip from multiple sources.
    @discardableResult
    public func requestCreateMulticamClip(
        angles: [MulticamAngle],
        trackID: UUID,
        at position: Rational,
        duration: Rational
    ) -> UUID? {
        guard !angles.isEmpty, duration > .zero else { return nil }

        let multicamID = UUID()
        let multicam = MulticamClipModel(id: multicamID, name: "Multicam", angles: angles)

        let clipID = UUID()
        let clip = ClipModel(
            id: clipID,
            sourceAssetID: multicamID, // Use multicam ID as source
            trackID: trackID,
            startTime: position,
            sourceIn: .zero,
            sourceOut: duration
        )

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.allClips[clipID] = clip
            self?.multicamClips[multicamID] = multicam
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: clipID)
            self?.multicamClips.removeValue(forKey: multicamID)
            return true
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Create Multicam Clip")
        recalculateDuration()
        events.send(.clipAdded(clipID: clipID, trackID: trackID))
        return multicamID
    }

    /// Switch the active angle of a multicam clip at a given time.
    @discardableResult
    public func requestSwitchAngle(clipID: UUID, angleIndex: Int, at time: Rational? = nil) -> Bool {
        guard let clip = allClips[clipID],
              let multicam = multicamClips[clip.sourceAssetID],
              angleIndex >= 0, angleIndex < multicam.angles.count else { return false }

        let oldIndex = multicam.activeAngleIndex

        if let switchTime = time {
            // Add a switch point at a specific time
            let oldSwitches = multicam.angleSwitches

            var undo: UndoAction = { true }
            var redo: UndoAction = { true }

            appendOperation(&redo) { [weak multicam] in
                multicam?.addSwitch(at: switchTime, angleIndex: angleIndex)
                return true
            }
            prependOperation(&undo) { [weak multicam] in
                multicam?.angleSwitches = oldSwitches
                return true
            }

            guard redo() else { let _ = undo(); return false }
            undoManager.record(undo: undo, redo: redo, description: "Switch Angle")
        } else {
            // Set the default active angle
            var undo: UndoAction = { true }
            var redo: UndoAction = { true }

            appendOperation(&redo) { [weak multicam] in
                multicam?.activeAngleIndex = angleIndex
                return true
            }
            prependOperation(&undo) { [weak multicam] in
                multicam?.activeAngleIndex = oldIndex
                return true
            }

            guard redo() else { let _ = undo(); return false }
            undoManager.record(undo: undo, redo: redo, description: "Switch Angle")
        }

        return true
    }

    /// Check if a clip is a multicam clip.
    public func isMulticamClip(_ clipID: UUID) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        return multicamClips[clip.sourceAssetID] != nil
    }

    /// Get the multicam model for a clip.
    public func multicamModel(for clipID: UUID) -> MulticamClipModel? {
        guard let clip = allClips[clipID] else { return nil }
        return multicamClips[clip.sourceAssetID]
    }
}
