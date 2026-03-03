import Foundation
import Combine
import CoreMediaPlus

/// Events emitted by the timeline model for cross-module communication.
public enum TimelineEvent: Sendable {
    case clipAdded(clipID: UUID, trackID: UUID)
    case clipRemoved(clipID: UUID, trackID: UUID)
    case clipMoved(clipID: UUID, toTrack: UUID, at: Rational)
    case clipResized(clipID: UUID)
    case clipSplit(clipID: UUID, newClipID: UUID, at: Rational)
    case trackAdded(trackID: UUID, type: TrackType, at: Int)
    case trackRemoved(trackID: UUID)
    case effectChanged(clipID: UUID)
    case playheadMoved(time: Rational)
    case selectionChanged
    case undoPerformed(description: String)
    case redoPerformed(description: String)
}

/// Combine-based event bus for timeline events.
public final class TimelineEventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<TimelineEvent, Never>()

    public init() {}

    public var publisher: AnyPublisher<TimelineEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public func send(_ event: TimelineEvent) {
        subject.send(event)
    }

    public var clipEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter {
            switch $0 {
            case .clipAdded, .clipRemoved, .clipMoved, .clipResized, .clipSplit: return true
            default: return false
            }
        }.eraseToAnyPublisher()
    }

    public var effectEvents: AnyPublisher<TimelineEvent, Never> {
        publisher.filter {
            if case .effectChanged = $0 { return true }
            return false
        }.eraseToAnyPublisher()
    }
}
