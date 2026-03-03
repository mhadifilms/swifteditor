import Foundation
import CoreMediaPlus

/// Pre-renders and caches frames around the playhead position on a background queue.
/// Monitors the playhead and automatically renders frames ahead and behind,
/// cancelling stale work when the playhead jumps significantly.
public actor BackgroundRenderer {

    private let cache: FrameCache
    private let framesAhead: Int
    private let framesBehind: Int
    private let frameDuration: Rational

    private var currentPlayhead: Rational = .zero
    private var isRunning = false
    private var currentTask: Task<Void, Never>?

    /// Callback invoked for each frame that needs rendering.
    /// Implementations should render the frame and return the result for caching.
    public var renderFrame: (@Sendable (Rational) async -> FrameCache.CachedFrame?)?

    /// Callback that returns the FrameHash for a given composition time.
    public var frameHashForTime: (@Sendable (Rational) -> FrameHash)?

    public init(
        cache: FrameCache,
        frameDuration: Rational = Rational(1, 30),
        framesAhead: Int = 30,
        framesBehind: Int = 10
    ) {
        self.cache = cache
        self.frameDuration = frameDuration
        self.framesAhead = framesAhead
        self.framesBehind = framesBehind
    }

    /// Set the render frame callback.
    public func setRenderFrame(_ callback: @escaping @Sendable (Rational) async -> FrameCache.CachedFrame?) {
        self.renderFrame = callback
    }

    /// Set the frame hash callback.
    public func setFrameHashForTime(_ callback: @escaping @Sendable (Rational) -> FrameHash) {
        self.frameHashForTime = callback
    }

    /// Begin background pre-rendering.
    public func start() {
        isRunning = true
        schedulePrerender()
    }

    /// Stop background pre-rendering and cancel in-flight work.
    public func stop() {
        isRunning = false
        currentTask?.cancel()
        currentTask = nil
    }

    /// Update the playhead position. If the playhead has moved significantly,
    /// in-flight work is cancelled and new pre-render work is scheduled.
    public func updatePlayheadPosition(_ time: Rational) {
        let delta = (time - currentPlayhead).abs
        currentPlayhead = time

        // If the playhead jumped more than a few frames, cancel and reschedule
        let threshold = frameDuration * Rational(3, 1)
        if delta > threshold {
            currentTask?.cancel()
            currentTask = nil
        }

        if isRunning {
            schedulePrerender()
        }
    }

    // MARK: - Private

    private func schedulePrerender() {
        guard currentTask == nil else { return }

        let playhead = currentPlayhead
        let ahead = framesAhead
        let behind = framesBehind
        let duration = frameDuration
        let cache = self.cache
        let renderFrame = self.renderFrame
        let frameHashForTime = self.frameHashForTime

        currentTask = Task.detached(priority: .utility) { [weak self] in
            // Build list of times to pre-render: behind first, then ahead
            var times: [Rational] = []
            for i in (-behind)...ahead {
                let time = playhead + duration * Rational(Int64(i), 1)
                guard time >= .zero else { continue }
                times.append(time)
            }

            for time in times {
                guard !Task.isCancelled else { break }

                // Check if already cached
                if let hashFn = frameHashForTime {
                    let hash = hashFn(time)
                    if await cache.hit(for: hash) != nil {
                        continue
                    }

                    // Render the frame
                    if let render = renderFrame,
                       let frame = await render(time) {
                        await cache.store(frame, for: hash)
                    }
                }
            }

            // Clear the task reference when done
            await self?.clearCurrentTask()
        }
    }

    private func clearCurrentTask() {
        currentTask = nil
    }
}
