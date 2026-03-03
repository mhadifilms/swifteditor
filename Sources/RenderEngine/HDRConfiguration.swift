import Metal
import CoreGraphics

/// Describes the HDR pipeline configuration for rendering.
/// Determines color space, transfer function, pixel format, and EDR headroom.
public struct HDRConfiguration: Sendable, Hashable {

    // MARK: - Enums

    /// Working color space for the render pipeline.
    public enum ColorSpaceType: String, Sendable, Hashable, CaseIterable {
        case sRGB
        case displayP3
        case rec2020
    }

    /// Electro-optical transfer function describing how code values map to luminance.
    public enum TransferFunction: String, Sendable, Hashable, CaseIterable {
        /// Standard dynamic range (gamma ~2.2 / sRGB curve).
        case sdr
        /// Perceptual Quantizer (SMPTE ST 2084) for HDR10.
        case pq
        /// Hybrid Log-Gamma (ARIB STD-B67) for broadcast HDR.
        case hlg
    }

    // MARK: - Properties

    public let colorSpace: ColorSpaceType
    public let transferFunction: TransferFunction
    public let pixelFormat: MTLPixelFormat
    public let edrHeadroom: CGFloat

    /// Whether this configuration represents an HDR pipeline.
    public var isHDR: Bool {
        transferFunction != .sdr
    }

    // MARK: - Init

    public init(
        colorSpace: ColorSpaceType,
        transferFunction: TransferFunction,
        pixelFormat: MTLPixelFormat,
        edrHeadroom: CGFloat
    ) {
        self.colorSpace = colorSpace
        self.transferFunction = transferFunction
        self.pixelFormat = pixelFormat
        self.edrHeadroom = edrHeadroom
    }

    // MARK: - Factory Methods

    /// Standard SDR configuration: sRGB, gamma, 8-bit BGRA.
    public static func sdrDefault() -> HDRConfiguration {
        HDRConfiguration(
            colorSpace: .sRGB,
            transferFunction: .sdr,
            pixelFormat: .bgra8Unorm,
            edrHeadroom: 1.0
        )
    }

    /// HDR10 configuration: Rec.2020, PQ transfer function, 16-bit float.
    public static func hdrPQ(edrHeadroom: CGFloat = 4.0) -> HDRConfiguration {
        HDRConfiguration(
            colorSpace: .rec2020,
            transferFunction: .pq,
            pixelFormat: .rgba16Float,
            edrHeadroom: edrHeadroom
        )
    }

    /// HLG configuration: Rec.2020, Hybrid Log-Gamma, 16-bit float.
    public static func hdrHLG(edrHeadroom: CGFloat = 3.0) -> HDRConfiguration {
        HDRConfiguration(
            colorSpace: .rec2020,
            transferFunction: .hlg,
            pixelFormat: .rgba16Float,
            edrHeadroom: edrHeadroom
        )
    }

    // MARK: - Color Space Helpers

    /// Returns the appropriate CGColorSpace for this configuration.
    public var cgColorSpace: CGColorSpace? {
        switch (colorSpace, transferFunction) {
        case (.sRGB, .sdr):
            return CGColorSpace(name: CGColorSpace.sRGB)
        case (.displayP3, .sdr):
            return CGColorSpace(name: CGColorSpace.displayP3)
        case (.displayP3, _):
            return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        case (.rec2020, .pq):
            return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
        case (.rec2020, .hlg):
            return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
        case (.rec2020, .sdr):
            return CGColorSpace(name: CGColorSpace.itur_2020)
        case (.sRGB, _):
            return CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
    }
}
