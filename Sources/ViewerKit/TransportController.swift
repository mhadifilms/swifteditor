import Foundation
import AVFoundation
import Observation
import Combine
import CoreMediaPlus

/// Transport state enum.
public enum TransportState: Sendable {
    case stopped
    case playing
    case paused
    case shuttling(speed: Double)
    case scrubbing
}

/// Controls playback of the timeline composition.
@Observable
public final class TransportController: @unchecked Sendable {
    public private(set) var currentTime: Rational = .zero
    public private(set) var transportState: TransportState = .stopped

    public var isPlaying: Bool {
        if case .playing = transportState { return true }
        return false
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private let timeSubject = CurrentValueSubject<Rational, Never>(.zero)

    public var timePublisher: AnyPublisher<Rational, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    public init() {}

    public func setPlayer(_ player: AVPlayer) {
        self.player = player
        setupTimeObserver()
    }

    public func play() {
        player?.play()
        transportState = .playing
    }

    public func pause() {
        player?.pause()
        transportState = .paused
    }

    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        currentTime = .zero
        transportState = .stopped
        timeSubject.send(.zero)
    }

    public func seek(to time: Rational) async {
        let cmTime = time.cmTime
        await player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        timeSubject.send(time)
    }

    public func shuttle(speed: Double) {
        player?.rate = Float(speed)
        transportState = .shuttling(speed: speed)
    }

    public func stepForward(frames: Int = 1, frameRate: Rational = Rational(24, 1)) {
        let frameDuration = Rational(1, 1) / frameRate
        let newTime = currentTime + frameDuration * Rational(Int64(frames), 1)
        Task { await seek(to: newTime) }
    }

    public func stepBackward(frames: Int = 1, frameRate: Rational = Rational(24, 1)) {
        let frameDuration = Rational(1, 1) / frameRate
        let newTime = currentTime - frameDuration * Rational(Int64(frames), 1)
        let clamped = newTime < .zero ? .zero : newTime
        Task { await seek(to: clamped) }
    }

    private func setupTimeObserver() {
        if let existing = timeObserver {
            player?.removeTimeObserver(existing)
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60),
            queue: .main
        ) { [weak self] cmTime in
            guard let self else { return }
            let time = Rational(cmTime)
            self.currentTime = time
            self.timeSubject.send(time)
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}
