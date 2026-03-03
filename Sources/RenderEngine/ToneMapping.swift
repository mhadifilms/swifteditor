import Foundation
import CoreImage

/// Tone mapping method used when converting HDR content to a target range.
public enum ToneMappingMethod: String, Sendable, Hashable, CaseIterable {
    /// Reinhard global operator: simple and fast.
    case reinhard
    /// ACES filmic curve: cinematic highlight rolloff.
    case aces
    /// Hable (Uncharted 2) filmic curve: good shadow detail preservation.
    case hable
}

/// Static utility methods for HDR-to-SDR and transfer function conversions.
/// All operations work on normalized linear-light values unless stated otherwise.
public struct ToneMapper: Sendable {

    private init() {}

    // MARK: - PQ (SMPTE ST 2084)

    /// PQ EOTF constants (SMPTE ST 2084).
    private static let pqM1: Double = 0.1593017578125       // 2610 / 16384
    private static let pqM2: Double = 78.84375              // 2523 / 4096 * 128
    private static let pqC1: Double = 0.8359375             // 3424 / 4096
    private static let pqC2: Double = 18.8515625            // 2413 / 4096 * 32
    private static let pqC3: Double = 18.6875               // 2392 / 4096 * 32

    /// Convert a PQ-encoded value (0...1) to linear luminance in nits (0...10000).
    public static func pqToLinear(_ pq: Double) -> Double {
        let np = pow(pq, 1.0 / pqM2)
        let numerator = max(np - pqC1, 0.0)
        let denominator = pqC2 - pqC3 * np
        guard denominator > 0 else { return 0 }
        return pow(numerator / denominator, 1.0 / pqM1) * 10000.0
    }

    /// Convert a linear luminance value in nits (0...10000) to PQ-encoded (0...1).
    public static func linearToPQ(_ nits: Double) -> Double {
        let y = max(nits, 0) / 10000.0
        let ym1 = pow(y, pqM1)
        let numerator = pqC1 + pqC2 * ym1
        let denominator = 1.0 + pqC3 * ym1
        return pow(numerator / denominator, pqM2)
    }

    // MARK: - HLG (ARIB STD-B67)

    /// HLG OETF constants.
    private static let hlgA: Double = 0.17883277
    private static let hlgB: Double = 1.0 - 4.0 * 0.17883277
    private static let hlgC: Double = 0.5 - 0.17883277 * log(4.0 * 0.17883277)

    /// Convert an HLG-encoded signal (0...1) to relative scene linear light (0...1).
    public static func hlgToLinear(_ hlg: Double) -> Double {
        if hlg <= 0.5 {
            return (hlg * hlg) / 3.0
        } else {
            return (exp((hlg - hlgC) / hlgA) + hlgB) / 12.0
        }
    }

    /// Convert a relative scene linear light value (0...1) to HLG-encoded signal (0...1).
    public static func linearToHLG(_ linear: Double) -> Double {
        let e = max(linear, 0)
        if e <= 1.0 / 12.0 {
            return sqrt(3.0 * e)
        } else {
            return hlgA * log(12.0 * e - hlgB) + hlgC
        }
    }

    // MARK: - Tone Mapping Operators

    /// Apply tone mapping to convert an HDR linear value to a displayable range.
    /// - Parameters:
    ///   - input: Linear-light luminance (may exceed 1.0 for HDR).
    ///   - method: The tone mapping operator to use.
    ///   - maxOutput: Maximum output value (e.g. EDR headroom).
    /// - Returns: Tone-mapped value clamped to 0...maxOutput.
    public static func hdrToSDR(input: Double, method: ToneMappingMethod,
                                maxOutput: Double = 1.0) -> Double {
        let mapped: Double
        switch method {
        case .reinhard:
            mapped = input / (1.0 + input)
        case .aces:
            mapped = acesFilmic(input)
        case .hable:
            mapped = hableFilmic(input)
        }
        return min(max(mapped * maxOutput, 0), maxOutput)
    }

    /// Apply tone mapping per-component to an RGB triple.
    public static func hdrToSDR(r: Double, g: Double, b: Double,
                                method: ToneMappingMethod,
                                maxOutput: Double = 1.0) -> (r: Double, g: Double, b: Double) {
        (r: hdrToSDR(input: r, method: method, maxOutput: maxOutput),
         g: hdrToSDR(input: g, method: method, maxOutput: maxOutput),
         b: hdrToSDR(input: b, method: method, maxOutput: maxOutput))
    }

    // MARK: - Private Curves

    /// ACES filmic tone mapping (approximation by Krzysztof Narkowicz).
    private static func acesFilmic(_ x: Double) -> Double {
        let a = 2.51
        let b = 0.03
        let c = 2.43
        let d = 0.59
        let e = 0.14
        let numerator = x * (a * x + b)
        let denominator = x * (c * x + d) + e
        return min(max(numerator / denominator, 0), 1)
    }

    /// Hable (Uncharted 2) filmic curve.
    private static func hableFilmic(_ x: Double) -> Double {
        let mapped = hablePartial(x)
        let whiteScale = 1.0 / hablePartial(11.2)
        return mapped * whiteScale
    }

    private static func hablePartial(_ x: Double) -> Double {
        let a = 0.15
        let b = 0.50
        let c = 0.10
        let d = 0.20
        let e = 0.02
        let f = 0.30
        return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f
    }
}
