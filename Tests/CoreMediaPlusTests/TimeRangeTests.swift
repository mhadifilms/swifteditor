import Testing
@testable import CoreMediaPlus

@Suite("TimeRange Tests")
struct TimeRangeTests {

    @Test("Basic creation")
    func creation() {
        let range = TimeRange(start: Rational(1, 1), duration: Rational(2, 1))
        #expect(range.start == Rational(1, 1))
        #expect(range.duration == Rational(2, 1))
        #expect(range.end == Rational(3, 1))
    }

    @Test("Creation from start and end")
    func creationFromStartEnd() {
        let range = TimeRange(start: Rational(1, 1), end: Rational(4, 1))
        #expect(range.duration == Rational(3, 1))
    }

    @Test("Contains time")
    func contains() {
        let range = TimeRange(start: Rational(1, 1), duration: Rational(2, 1))
        #expect(range.contains(Rational(1, 1)))   // start
        #expect(range.contains(Rational(2, 1)))   // middle
        #expect(!range.contains(Rational(3, 1)))  // end (exclusive)
        #expect(!range.contains(Rational(0, 1)))  // before
    }

    @Test("Overlaps")
    func overlaps() {
        let a = TimeRange(start: Rational(0, 1), duration: Rational(3, 1))
        let b = TimeRange(start: Rational(2, 1), duration: Rational(3, 1))
        let c = TimeRange(start: Rational(3, 1), duration: Rational(1, 1))
        #expect(a.overlaps(b))
        #expect(!a.overlaps(c))
    }

    @Test("Intersection")
    func intersection() {
        let a = TimeRange(start: Rational(0, 1), duration: Rational(3, 1))
        let b = TimeRange(start: Rational(2, 1), duration: Rational(3, 1))
        let intersection = a.intersection(b)
        #expect(intersection != nil)
        #expect(intersection?.start == Rational(2, 1))
        #expect(intersection?.end == Rational(3, 1))
    }

    @Test("No intersection")
    func noIntersection() {
        let a = TimeRange(start: Rational(0, 1), duration: Rational(1, 1))
        let b = TimeRange(start: Rational(2, 1), duration: Rational(1, 1))
        #expect(a.intersection(b) == nil)
    }

    @Test("Union")
    func union() {
        let a = TimeRange(start: Rational(0, 1), duration: Rational(2, 1))
        let b = TimeRange(start: Rational(3, 1), duration: Rational(2, 1))
        let union = a.union(b)
        #expect(union.start == Rational(0, 1))
        #expect(union.end == Rational(5, 1))
    }
}
