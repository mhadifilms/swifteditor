import Testing
import Foundation
@testable import ViewerKit
@testable import CoreMediaPlus

@Suite("Transport Controller Tests")
struct TransportTests {

    @Test("Initial state is stopped with zero time")
    func initialState() {
        let transport = TransportController()
        #expect(transport.currentTime == .zero)
        #expect(!transport.isPlaying)
        if case .stopped = transport.transportState {} else {
            Issue.record("Expected stopped state")
        }
    }

    @Test("Play sets playing state")
    func playState() {
        let transport = TransportController()
        transport.play()
        #expect(transport.isPlaying)
    }

    @Test("Pause sets paused state")
    func pauseState() {
        let transport = TransportController()
        transport.play()
        transport.pause()
        #expect(!transport.isPlaying)
        if case .paused = transport.transportState {} else {
            Issue.record("Expected paused state")
        }
    }

    @Test("Stop resets time to zero")
    func stopResetsTime() {
        let transport = TransportController()
        transport.play()
        transport.stop()
        #expect(transport.currentTime == .zero)
        #expect(!transport.isPlaying)
    }

    @Test("Seek updates current time")
    func seekUpdatesTime() async {
        let transport = TransportController()
        let target = Rational(10, 1)
        await transport.seek(to: target)
        #expect(transport.currentTime == target)
    }

    @Test("Seek to zero works")
    func seekToZero() async {
        let transport = TransportController()
        await transport.seek(to: Rational(5, 1))
        await transport.seek(to: .zero)
        #expect(transport.currentTime == .zero)
    }

    @Test("Step forward advances by one frame")
    func stepForward() async throws {
        let transport = TransportController()
        // Step at 24fps: 1/24 seconds forward
        transport.stepForward(frames: 1, frameRate: Rational(24, 1))
        // Give the internal Task a moment to execute
        try await Task.sleep(for: .milliseconds(50))
        let expected = Rational(1, 1) / Rational(24, 1)
        #expect(transport.currentTime == expected)
    }

    @Test("Step backward clamps to zero")
    func stepBackwardClampsToZero() async throws {
        let transport = TransportController()
        // Stepping backward from 0 should stay at 0
        transport.stepBackward(frames: 1, frameRate: Rational(24, 1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(transport.currentTime == .zero)
    }

    @Test("Shuttle sets shuttling state")
    func shuttleState() {
        let transport = TransportController()
        transport.shuttle(speed: 2.0)
        if case .shuttling(let speed) = transport.transportState {
            #expect(speed == 2.0)
        } else {
            Issue.record("Expected shuttling state")
        }
    }

    @Test("Shuttle with negative speed for reverse")
    func reverseShuttle() {
        let transport = TransportController()
        transport.shuttle(speed: -4.0)
        if case .shuttling(let speed) = transport.transportState {
            #expect(speed == -4.0)
        } else {
            Issue.record("Expected shuttling state for reverse")
        }
    }

    @Test("Time publisher emits on seek")
    func timePublisherEmitsOnSeek() async throws {
        let transport = TransportController()
        var receivedTimes: [Rational] = []

        let cancellable = transport.timePublisher.sink { time in
            receivedTimes.append(time)
        }
        defer { cancellable.cancel() }

        await transport.seek(to: Rational(5, 1))
        // Publisher should have emitted
        #expect(receivedTimes.contains(Rational(5, 1)))
    }
}

@Suite("JKL Shuttle Controller Tests")
struct JKLShuttleTests {

    @Test("Initial speed is zero")
    func initialSpeed() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        #expect(shuttle.currentSpeed == 0)
    }

    @Test("Press L starts forward shuttle")
    func pressLStartsForward() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressL()
        #expect(shuttle.currentSpeed == 1.0)
    }

    @Test("Press L twice increases speed")
    func pressLTwice() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressL()
        shuttle.pressL()
        #expect(shuttle.currentSpeed == 2.0)
    }

    @Test("Press J starts reverse shuttle")
    func pressJStartsReverse() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressJ()
        #expect(shuttle.currentSpeed == -1.0)
    }

    @Test("Press J twice increases reverse speed")
    func pressJTwice() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressJ()
        shuttle.pressJ()
        #expect(shuttle.currentSpeed == -2.0)
    }

    @Test("Press K stops shuttle")
    func pressKStops() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressL()
        shuttle.pressL()
        shuttle.pressK()
        #expect(shuttle.currentSpeed == 0)
    }

    @Test("Press L when reversing switches to forward")
    func pressLFromReverse() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressJ()  // -1x
        shuttle.pressJ()  // -2x
        shuttle.pressL()  // Should switch to +1x
        #expect(shuttle.currentSpeed == 1.0)
    }

    @Test("Press J when going forward switches to reverse")
    func pressJFromForward() {
        let transport = TransportController()
        let shuttle = JKLShuttleController(transport: transport)
        shuttle.pressL()  // +1x
        shuttle.pressL()  // +2x
        shuttle.pressJ()  // Should switch to -1x
        #expect(shuttle.currentSpeed == -1.0)
    }
}

@Suite("InOutPoint Model Tests")
struct InOutPointTests {

    @Test("Initial state has no points set")
    func initialState() {
        let model = InOutPointModel()
        #expect(model.inPoint == nil)
        #expect(model.outPoint == nil)
        #expect(model.markedDuration == nil)
    }

    @Test("Set and get in/out points")
    func setInOutPoints() {
        let model = InOutPointModel()
        model.setIn(Rational(5, 1))
        model.setOut(Rational(15, 1))
        #expect(model.inPoint == Rational(5, 1))
        #expect(model.outPoint == Rational(15, 1))
    }

    @Test("Marked duration calculation")
    func markedDuration() {
        let model = InOutPointModel()
        model.setIn(Rational(5, 1))
        model.setOut(Rational(15, 1))
        #expect(model.markedDuration == Rational(10, 1))
    }

    @Test("Contains checks time within range")
    func containsCheck() {
        let model = InOutPointModel()
        model.setIn(Rational(5, 1))
        model.setOut(Rational(15, 1))
        #expect(model.contains(Rational(10, 1)))
        #expect(model.contains(Rational(5, 1)))   // Inclusive of in
        #expect(!model.contains(Rational(15, 1)))  // Exclusive of out
        #expect(!model.contains(Rational(3, 1)))   // Before in
        #expect(!model.contains(Rational(20, 1)))  // After out
    }

    @Test("Clear in point")
    func clearIn() {
        let model = InOutPointModel()
        model.setIn(Rational(5, 1))
        model.clearIn()
        #expect(model.inPoint == nil)
    }

    @Test("Clear both points")
    func clearBoth() {
        let model = InOutPointModel()
        model.setIn(Rational(5, 1))
        model.setOut(Rational(15, 1))
        model.clearBoth()
        #expect(model.inPoint == nil)
        #expect(model.outPoint == nil)
    }
}
