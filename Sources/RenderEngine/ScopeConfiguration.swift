import Foundation
import CoreGraphics

/// Configuration for video scope rendering.
public struct ScopeConfiguration: Sendable {

    /// The type of video scope to render.
    public enum ScopeType: String, CaseIterable, Sendable {
        case histogram
        case waveform
        case rgbParade
        case vectorscope
    }

    /// Output texture dimensions.
    public var outputWidth: Int
    public var outputHeight: Int

    /// Brightness/gain multiplier for scope visualization (1.0 = default).
    public var brightness: Float

    /// Whether to draw graticule overlay lines.
    public var showGraticule: Bool

    /// Parade layout: number of columns used per channel in the accumulation buffer.
    public var paradeColumnCount: Int

    /// Vectorscope internal resolution (square grid, e.g. 256x256).
    public var vectorscopeSize: Int

    /// Whether to draw the Rec.709 skin tone line on the vectorscope.
    public var showSkinToneLine: Bool

    public init(
        outputWidth: Int = 256,
        outputHeight: Int = 256,
        brightness: Float = 1.0,
        showGraticule: Bool = true,
        paradeColumnCount: Int = 256,
        vectorscopeSize: Int = 256,
        showSkinToneLine: Bool = false
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.brightness = brightness
        self.showGraticule = showGraticule
        self.paradeColumnCount = paradeColumnCount
        self.vectorscopeSize = vectorscopeSize
        self.showSkinToneLine = showSkinToneLine
    }
}
