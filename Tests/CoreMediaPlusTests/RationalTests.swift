import Testing
import CoreMedia
@testable import CoreMediaPlus

@Suite("Rational Tests")
struct RationalTests {

    @Test("Basic creation and normalization")
    func creation() {
        let r = Rational(2, 4)
        #expect(r.numerator == 1)
        #expect(r.denominator == 2)
    }

    @Test("Zero initialization")
    func zero() {
        #expect(Rational.zero.numerator == 0)
        #expect(Rational.zero.denominator == 1)
        #expect(Rational.zero.seconds == 0)
    }

    @Test("Invalid rational")
    func invalid() {
        let r = Rational.invalid
        #expect(!r.isValid)
        #expect(r.denominator == 0)
    }

    @Test("Addition")
    func addition() {
        let a = Rational(1, 4)
        let b = Rational(1, 4)
        let result = a + b
        #expect(result == Rational(1, 2))
    }

    @Test("Subtraction")
    func subtraction() {
        let a = Rational(3, 4)
        let b = Rational(1, 4)
        let result = a - b
        #expect(result == Rational(1, 2))
    }

    @Test("Multiplication")
    func multiplication() {
        let a = Rational(2, 3)
        let b = Rational(3, 4)
        let result = a * b
        #expect(result == Rational(1, 2))
    }

    @Test("Division")
    func division() {
        let a = Rational(1, 2)
        let b = Rational(1, 4)
        let result = a / b
        #expect(result == Rational(2, 1))
    }

    @Test("Comparison")
    func comparison() {
        let a = Rational(1, 3)
        let b = Rational(1, 2)
        #expect(a < b)
        #expect(!(b < a))
        #expect(a == a)
    }

    @Test("Seconds conversion")
    func seconds() {
        let r = Rational(seconds: 1.5)
        #expect(abs(r.seconds - 1.5) < 0.001)
    }

    @Test("CMTime round-trip")
    func cmTimeRoundTrip() {
        let original = Rational(600, 600)
        let cmTime = original.cmTime
        let restored = Rational(cmTime)
        #expect(restored == original)
    }

    @Test("Frame number calculation")
    func frameNumber() {
        let time = Rational(48, 24)  // 2 seconds
        let frameRate = Rational(24, 1)
        let frame = time.frameNumber(at: frameRate)
        #expect(frame == 48)
    }

    @Test("Absolute value")
    func absoluteValue() {
        let r = Rational(-3, 4)
        #expect(r.abs == Rational(3, 4))
    }

    @Test("Negative denominator normalization")
    func negativeDenominator() {
        let r = Rational(1, -2)
        #expect(r.numerator == -1)
        #expect(r.denominator == 2)
    }
}
