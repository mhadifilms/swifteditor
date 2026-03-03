import Metal
import CoreGraphics

// MARK: - MTLTextureDescriptor HDR Helpers

extension MTLTextureDescriptor {

    /// Create a texture descriptor suitable for HDR rendering (rgba16Float).
    /// - Parameters:
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    ///   - usage: Texture usage flags.
    /// - Returns: A configured MTLTextureDescriptor with .rgba16Float format.
    public static func hdrDescriptor(
        width: Int,
        height: Int,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private
        return descriptor
    }

    /// Create a texture descriptor matching a given HDR configuration.
    /// - Parameters:
    ///   - width: Texture width in pixels.
    ///   - height: Texture height in pixels.
    ///   - configuration: The HDR configuration determining pixel format.
    ///   - usage: Texture usage flags.
    /// - Returns: A configured MTLTextureDescriptor.
    public static func descriptor(
        width: Int,
        height: Int,
        configuration: HDRConfiguration,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: configuration.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private
        return descriptor
    }
}

// MARK: - CGColorSpace HDR Helpers

extension CGColorSpace {

    /// Rec. 2020 color space (ITU-R BT.2020).
    public static var rec2020: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.itur_2020)
    }

    /// Rec. 2100 PQ (Perceptual Quantizer) color space for HDR10.
    public static var rec2100PQ: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.itur_2100_PQ)
    }

    /// Rec. 2100 HLG (Hybrid Log-Gamma) color space for broadcast HDR.
    public static var rec2100HLG: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.itur_2100_HLG)
    }

    /// Display P3 with PQ transfer function (extended linear for EDR rendering).
    public static var displayP3Linear: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    }

    /// Extended linear sRGB (suitable for EDR rendering in sRGB gamut).
    public static var sRGBLinear: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    }

    /// Determine if this color space uses a wide gamut (P3 or wider).
    public var isWideGamut: Bool {
        guard let name = self.name else { return false }
        let wideGamutNames: Set<CFString> = [
            CGColorSpace.displayP3,
            CGColorSpace.extendedLinearDisplayP3,
            CGColorSpace.itur_2020,
            CGColorSpace.itur_2100_PQ,
            CGColorSpace.itur_2100_HLG,
        ]
        return wideGamutNames.contains(name)
    }
}
