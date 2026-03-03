import CoreMedia
import Foundation

/// Exact rational time representation wrapping CMTime.
/// Eliminates floating-point accumulation errors in timeline arithmetic.
/// Timescale 600 is the default (LCM of 24, 25, 30, 60 fps).
public struct Rational: Sendable, Hashable, Comparable, Codable {
    public let numerator: Int64
    public let denominator: Int64

    public static let zero = Rational(0, 1)
    public static let invalid = Rational(0, 0)

    public init(_ numerator: Int64, _ denominator: Int64) {
        if denominator == 0 {
            self.numerator = 0
            self.denominator = 0
            return
        }
        let g = Self.gcd(Swift.abs(numerator), Swift.abs(denominator))
        let sign: Int64 = denominator < 0 ? -1 : 1
        self.numerator = sign * numerator / g
        self.denominator = sign * denominator / g
    }

    public init(_ cmTime: CMTime) {
        guard cmTime.isValid, !cmTime.isIndefinite else {
            self = .invalid
            return
        }
        self.init(cmTime.value, Int64(cmTime.timescale))
    }

    public init(seconds: Double, preferredTimescale: Int32 = 600) {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
        self.init(cmTime)
    }

    public var isValid: Bool { denominator != 0 }

    public var cmTime: CMTime {
        guard isValid else { return .invalid }
        return CMTime(value: numerator, timescale: CMTimeScale(denominator))
    }

    public var seconds: Double {
        guard denominator != 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    public func frameNumber(at frameRate: Rational) -> Int64 {
        let product = self * frameRate
        guard product.denominator != 0 else { return 0 }
        return product.numerator / product.denominator
    }

    // MARK: - Arithmetic

    public static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(
            lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    public static func / (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    public var abs: Rational {
        Rational(Swift.abs(numerator), denominator)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let num = try container.decode(Int64.self)
        let den = try container.decode(Int64.self)
        self.init(num, den)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(numerator)
        try container.encode(denominator)
    }

    // MARK: - Private

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        b == 0 ? a : gcd(b, a % b)
    }
}

extension Rational: CustomStringConvertible {
    public var description: String {
        guard isValid else { return "invalid" }
        return "\(numerator)/\(denominator)"
    }
}
