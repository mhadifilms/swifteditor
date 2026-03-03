import Foundation
import CoreMediaPlus
import CommandBus
import ViewerKit

/// Facade for playback operations.
public final class PlaybackAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let transport: TransportController

    public init(dispatcher: CommandDispatcher, transport: TransportController) {
        self.dispatcher = dispatcher
        self.transport = transport
    }

    @discardableResult
    public func play() async throws -> CommandResult {
        try await dispatcher.dispatch(PlayCommand())
    }

    @discardableResult
    public func pause() async throws -> CommandResult {
        try await dispatcher.dispatch(PauseCommand())
    }

    @discardableResult
    public func stop() async throws -> CommandResult {
        try await dispatcher.dispatch(StopCommand())
    }

    @discardableResult
    public func seek(to time: Rational) async throws -> CommandResult {
        try await dispatcher.dispatch(SeekCommand(time: time))
    }

    @discardableResult
    public func stepForward(frames: Int = 1) async throws -> CommandResult {
        try await dispatcher.dispatch(StepForwardCommand(frames: frames))
    }

    @discardableResult
    public func stepBackward(frames: Int = 1) async throws -> CommandResult {
        try await dispatcher.dispatch(StepBackwardCommand(frames: frames))
    }

    /// Direct access to current transport state
    public var currentTime: Rational { transport.currentTime }
    public var isPlaying: Bool { transport.isPlaying }
    public var transportState: TransportState { transport.transportState }
}
