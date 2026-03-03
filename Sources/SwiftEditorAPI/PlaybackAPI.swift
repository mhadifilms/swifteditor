@preconcurrency import AVFoundation
import Foundation
import Combine
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

    // MARK: - Playback Commands

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

    // MARK: - Transport State

    /// Current playhead position
    public var currentTime: Rational { transport.currentTime }

    /// Whether playback is currently active
    public var isPlaying: Bool { transport.isPlaying }

    /// The current transport state (stopped/playing/paused/shuttling/scrubbing)
    public var transportState: TransportState { transport.transportState }

    /// Combine publisher that emits the current time
    public var timePublisher: AnyPublisher<Rational, Never> {
        transport.timePublisher
    }

    // MARK: - Direct Transport Control

    /// Shuttle at a specific speed (positive = forward, negative = reverse)
    public func shuttle(speed: Double) {
        transport.shuttle(speed: speed)
    }

    /// Set the AVPlayer instance for playback
    public func setPlayer(_ player: AVPlayer) {
        transport.setPlayer(player)
    }
}
