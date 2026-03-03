import Foundation

/// Middleware that tracks and reports command execution time.
/// Uses os_clock for high-resolution timing within each method call.
public final class PerformanceMiddleware: CommandMiddleware, @unchecked Sendable {
    /// Threshold in seconds; commands taking longer will be logged as warnings
    private let warningThreshold: TimeInterval
    private let storage = TimingStorage()

    public init(warningThreshold: TimeInterval = 0.1) {
        self.warningThreshold = warningThreshold
    }

    public func beforeExecute(_ command: any Command) async -> Bool {
        let key = type(of: command).typeIdentifier
        await storage.recordStart(key: key, time: CFAbsoluteTimeGetCurrent())
        return true
    }

    public func afterExecute(_ command: any Command, result: CommandResult) async {
        let key = type(of: command).typeIdentifier
        let endTime = CFAbsoluteTimeGetCurrent()

        guard let startTime = await storage.popStart(key: key) else { return }

        let elapsed = endTime - startTime

        if elapsed > warningThreshold {
            print("[Performance] WARNING: \(key) took \(String(format: "%.3f", elapsed))s (threshold: \(String(format: "%.3f", warningThreshold))s)")
        } else {
            print("[Performance] \(key) completed in \(String(format: "%.3f", elapsed))s")
        }
    }
}

/// Actor-isolated storage for timing data
private actor TimingStorage {
    private var startTimes: [String: CFAbsoluteTime] = [:]

    func recordStart(key: String, time: CFAbsoluteTime) {
        startTimes[key] = time
    }

    func popStart(key: String) -> CFAbsoluteTime? {
        startTimes.removeValue(forKey: key)
    }
}
