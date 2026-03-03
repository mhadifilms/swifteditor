import Testing
import Foundation
@testable import EffectsEngine
@testable import CoreMediaPlus

@Suite("KeyframeTrack Tests")
struct KeyframeTrackTests {

    @Test("Empty track returns nil")
    func emptyTrack() {
        let track = KeyframeTrack()
        #expect(track.value(at: Rational(0, 1)) == nil)
    }

    @Test("Single keyframe returns constant")
    func singleKeyframe() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(0, 1), value: .float(1.0), interpolation: .linear))
        #expect(track.value(at: Rational(0, 1)) == .float(1.0))
        #expect(track.value(at: Rational(100, 1)) == .float(1.0))
    }

    @Test("Linear interpolation between keyframes")
    func linearInterpolation() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(0, 1), value: .float(0.0), interpolation: .linear))
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(10, 1), value: .float(10.0), interpolation: .linear))

        if case .float(let val) = track.value(at: Rational(5, 1)) {
            #expect(abs(val - 5.0) < 0.01)
        } else {
            Issue.record("Expected float value")
        }
    }

    @Test("Hold interpolation")
    func holdInterpolation() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(0, 1), value: .float(0.0), interpolation: .hold))
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(10, 1), value: .float(10.0), interpolation: .linear))

        #expect(track.value(at: Rational(5, 1)) == .float(0.0))
    }

    @Test("Before first keyframe returns first value")
    func beforeFirst() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(10, 1), value: .float(5.0), interpolation: .linear))
        #expect(track.value(at: Rational(0, 1)) == .float(5.0))
    }

    @Test("After last keyframe returns last value")
    func afterLast() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(0, 1), value: .float(5.0), interpolation: .linear))
        #expect(track.value(at: Rational(100, 1)) == .float(5.0))
    }

    @Test("Add keyframe maintains sorted order")
    func sortedOrder() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(10, 1), value: .float(10.0)))
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(0, 1), value: .float(0.0)))
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(5, 1), value: .float(5.0)))

        #expect(track.keyframes.count == 3)
        #expect(track.keyframes[0].time == Rational(0, 1))
        #expect(track.keyframes[1].time == Rational(5, 1))
        #expect(track.keyframes[2].time == Rational(10, 1))
    }

    @Test("Replace keyframe at same time")
    func replaceKeyframe() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(5, 1), value: .float(1.0)))
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(5, 1), value: .float(2.0)))

        #expect(track.keyframes.count == 1)
        #expect(track.value(at: Rational(5, 1)) == .float(2.0))
    }

    @Test("Remove keyframe")
    func removeKeyframe() {
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(
            time: Rational(5, 1), value: .float(1.0)))
        #expect(track.keyframes.count == 1)

        track.removeKeyframe(at: Rational(5, 1))
        #expect(track.keyframes.count == 0)
    }
}
