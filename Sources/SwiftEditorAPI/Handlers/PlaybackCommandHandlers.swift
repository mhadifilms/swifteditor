import Foundation
import CoreMediaPlus
import CommandBus
import ViewerKit

/// Handler for PlayCommand
public final class PlayHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = PlayCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: PlayCommand) throws {}

    public func execute(_ command: PlayCommand) async throws -> (any Command)? {
        transport.play()
        return nil
    }
}

/// Handler for PauseCommand
public final class PauseHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = PauseCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: PauseCommand) throws {}

    public func execute(_ command: PauseCommand) async throws -> (any Command)? {
        transport.pause()
        return nil
    }
}

/// Handler for StopCommand
public final class StopHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = StopCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: StopCommand) throws {}

    public func execute(_ command: StopCommand) async throws -> (any Command)? {
        transport.stop()
        return nil
    }
}

/// Handler for SeekCommand
public final class SeekHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SeekCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: SeekCommand) throws {}

    public func execute(_ command: SeekCommand) async throws -> (any Command)? {
        await transport.seek(to: command.time)
        return nil
    }
}

/// Handler for StepForwardCommand
public final class StepForwardHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = StepForwardCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: StepForwardCommand) throws {}

    public func execute(_ command: StepForwardCommand) async throws -> (any Command)? {
        transport.stepForward(frames: command.frames)
        return nil
    }
}

/// Handler for StepBackwardCommand
public final class StepBackwardHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = StepBackwardCommand
    private let transport: TransportController

    public init(transport: TransportController) {
        self.transport = transport
    }

    public func validate(_ command: StepBackwardCommand) throws {}

    public func execute(_ command: StepBackwardCommand) async throws -> (any Command)? {
        transport.stepBackward(frames: command.frames)
        return nil
    }
}
