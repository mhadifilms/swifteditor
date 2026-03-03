import Foundation
import CoreMediaPlus
import CommandBus

// MARK: - Playback Commands

public struct PlayCommand: Command {
    public static let typeIdentifier = "playback.play"
    public var undoDescription: String { "Play" }
    public var isMutating: Bool { false }

    public init() {}
}

public struct PauseCommand: Command {
    public static let typeIdentifier = "playback.pause"
    public var undoDescription: String { "Pause" }
    public var isMutating: Bool { false }

    public init() {}
}

public struct StopCommand: Command {
    public static let typeIdentifier = "playback.stop"
    public var undoDescription: String { "Stop" }
    public var isMutating: Bool { false }

    public init() {}
}

public struct SeekCommand: Command {
    public static let typeIdentifier = "playback.seek"
    public let time: Rational
    public var undoDescription: String { "Seek" }
    public var isMutating: Bool { false }

    public init(time: Rational) {
        self.time = time
    }
}

public struct StepForwardCommand: Command {
    public static let typeIdentifier = "playback.stepForward"
    public let frames: Int
    public var undoDescription: String { "Step Forward" }
    public var isMutating: Bool { false }

    public init(frames: Int = 1) {
        self.frames = frames
    }
}

public struct StepBackwardCommand: Command {
    public static let typeIdentifier = "playback.stepBackward"
    public let frames: Int
    public var undoDescription: String { "Step Backward" }
    public var isMutating: Bool { false }

    public init(frames: Int = 1) {
        self.frames = frames
    }
}
