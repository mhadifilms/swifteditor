import Foundation
import Observation
import CoreMediaPlus
import ProjectModel

/// Type of marker on the timeline.
public enum MarkerType: String, Codable, Sendable {
    case standard   // Single frame
    case duration   // Range-based
    case chapter    // Chapter point for export
}

/// Runtime marker on the timeline.
public struct TimelineMarker: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var time: Rational
    public var duration: Rational?  // nil for standard/chapter markers
    public var markerType: MarkerType
    public var color: Marker.MarkerColor
    public var notes: String
    public var clipID: UUID?  // nil = timeline-level marker, non-nil = clip-level

    public init(
        id: UUID = UUID(),
        name: String = "",
        time: Rational,
        duration: Rational? = nil,
        markerType: MarkerType = .standard,
        color: Marker.MarkerColor = .blue,
        notes: String = "",
        clipID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.time = time
        self.duration = duration
        self.markerType = markerType
        self.color = color
        self.notes = notes
        self.clipID = clipID
    }
}

/// Manages markers on the timeline. Integrated with undo system.
@Observable
public final class MarkerManager: @unchecked Sendable {
    public private(set) var markers: [TimelineMarker] = []

    public init() {}

    /// All markers sorted by time.
    public var sortedMarkers: [TimelineMarker] {
        markers.sorted { $0.time < $1.time }
    }

    /// Markers of a specific type.
    public func markers(ofType type: MarkerType) -> [TimelineMarker] {
        markers.filter { $0.markerType == type }
    }

    /// Markers on a specific clip.
    public func markers(forClip clipID: UUID) -> [TimelineMarker] {
        markers.filter { $0.clipID == clipID }
    }

    /// Timeline-level markers only.
    public var timelineMarkers: [TimelineMarker] {
        markers.filter { $0.clipID == nil }
    }

    /// Find the next marker after a given time.
    public func nextMarker(after time: Rational) -> TimelineMarker? {
        sortedMarkers.first { $0.time > time }
    }

    /// Find the previous marker before a given time.
    public func previousMarker(before time: Rational) -> TimelineMarker? {
        sortedMarkers.last { $0.time < time }
    }

    // MARK: - Mutations (for use with TimelineModel undo system)

    public func addMarker(_ marker: TimelineMarker) {
        markers.append(marker)
    }

    public func removeMarker(id: UUID) -> TimelineMarker? {
        if let index = markers.firstIndex(where: { $0.id == id }) {
            return markers.remove(at: index)
        }
        return nil
    }

    public func updateMarker(id: UUID, name: String? = nil, color: Marker.MarkerColor? = nil,
                              notes: String? = nil, duration: Rational? = nil) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { markers[index].name = name }
        if let color = color { markers[index].color = color }
        if let notes = notes { markers[index].notes = notes }
        if let duration = duration {
            markers[index].duration = duration
            markers[index].markerType = .duration
        }
    }
}

// MARK: - Marker Operations on TimelineModel

extension TimelineModel {

    /// Add a marker to the timeline with undo support.
    @discardableResult
    public func requestAddMarker(
        name: String = "",
        at time: Rational,
        markerType: MarkerType = .standard,
        color: Marker.MarkerColor = .blue,
        notes: String = "",
        clipID: UUID? = nil,
        duration: Rational? = nil
    ) -> UUID {
        let marker = TimelineMarker(
            name: name, time: time, duration: duration,
            markerType: markerType, color: color, notes: notes, clipID: clipID
        )

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.markerManager.addMarker(marker)
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.markerManager.removeMarker(id: marker.id) != nil
        }

        guard redo() else { let _ = undo(); return marker.id }
        undoManager.record(undo: undo, redo: redo, description: "Add Marker")
        return marker.id
    }

    /// Remove a marker with undo support.
    @discardableResult
    public func requestRemoveMarker(id: UUID) -> Bool {
        guard let marker = markerManager.markers.first(where: { $0.id == id }) else { return false }
        let savedMarker = marker

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.markerManager.removeMarker(id: id) != nil
        }
        prependOperation(&undo) { [weak self] in
            self?.markerManager.addMarker(savedMarker)
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Remove Marker")
        return true
    }
}
