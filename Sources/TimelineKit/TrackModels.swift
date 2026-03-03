import Foundation
import Observation
import CoreMediaPlus
import ProjectModel

/// Runtime model of a video track.
@Observable
public final class VideoTrackModel: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isMuted: Bool = false
    public var isLocked: Bool = false

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public init(from data: TrackData) {
        self.id = data.id
        self.name = data.name
        self.isMuted = data.isMuted
        self.isLocked = data.isLocked
    }
}

/// Runtime model of an audio track.
@Observable
public final class AudioTrackModel: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isMuted: Bool = false
    public var isLocked: Bool = false
    public var isSolo: Bool = false
    public var volume: Double = 1.0
    public var pan: Double = 0.0

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public init(from data: TrackData) {
        self.id = data.id
        self.name = data.name
        self.isMuted = data.isMuted
        self.isLocked = data.isLocked
    }
}
