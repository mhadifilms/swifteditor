import Foundation

/// Video format parameters used throughout the pipeline.
public struct VideoParams: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var pixelFormat: PixelFormat
    public var colorSpace: ColorSpace

    public init(
        width: Int,
        height: Int,
        pixelFormat: PixelFormat = .bgra8Unorm,
        colorSpace: ColorSpace = .rec709
    ) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.colorSpace = colorSpace
    }

    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    public enum PixelFormat: String, Codable, Sendable {
        case bgra8Unorm
        case rgba16Float
        case bgr10a2Unorm
        case yuv420BiPlanar8
        case yuv420BiPlanar10
    }
}
