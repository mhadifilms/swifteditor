import Foundation

/// Triple buffer for smooth producer/consumer handoff.
/// Three slots rotate through roles: one being written, one ready for display,
/// and one currently being displayed. Thread-safe via DispatchSemaphore.
public final class TripleBuffer<T>: @unchecked Sendable {

    private var buffers: [T]
    private var writeIndex: Int = 0
    private var readyIndex: Int = 1
    private var displayIndex: Int = 2
    private let lock = NSLock()
    private let writeSemaphore: DispatchSemaphore
    private let readSemaphore: DispatchSemaphore
    private var hasReady = false

    /// Initialize with three pre-allocated buffer values.
    public init(_ a: T, _ b: T, _ c: T) {
        buffers = [a, b, c]
        writeSemaphore = DispatchSemaphore(value: 1)
        readSemaphore = DispatchSemaphore(value: 0)
    }

    /// Begin writing to the write buffer. Returns the buffer to write into.
    /// Blocks if the previous write has not been consumed.
    public func beginWrite() -> T {
        writeSemaphore.wait()
        lock.lock()
        let index = writeIndex
        lock.unlock()
        return buffers[index]
    }

    /// Finish writing. The written buffer becomes the new "ready" buffer.
    public func endWrite() {
        lock.lock()
        // Swap write and ready indices
        let oldReady = readyIndex
        readyIndex = writeIndex
        writeIndex = oldReady
        hasReady = true
        lock.unlock()

        writeSemaphore.signal()
        readSemaphore.signal()
    }

    /// Begin reading the most recently completed buffer for display.
    /// Returns nil if no buffer is ready.
    public func beginRead() -> T? {
        // Non-blocking check: if no frame is ready, return nil
        guard readSemaphore.wait(timeout: .now()) == .success else {
            return nil
        }

        lock.lock()
        guard hasReady else {
            lock.unlock()
            return nil
        }
        // Swap ready and display indices
        let oldDisplay = displayIndex
        displayIndex = readyIndex
        readyIndex = oldDisplay
        hasReady = false
        let index = displayIndex
        lock.unlock()

        return buffers[index]
    }

    /// Finish reading/displaying the current buffer.
    public func endRead() {
        // No-op for the basic triple buffer pattern; the display buffer
        // remains valid until the next beginRead swaps it.
    }
}
