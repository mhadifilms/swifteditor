@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import Metal
import CoreMediaPlus
import EffectsEngine

/// Custom AVVideoCompositing implementation using Metal-backed CIContext.
/// Reads CompositorInstruction per-frame to composite layers with effects and transitions.
public final class MetalCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    public var sourcePixelBufferAttributes: [String: any Sendable]? {
        let pixelFormat = hdrConfig.isHDR ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        return [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        let pixelFormat = hdrConfig.isHDR ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        return [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var supportsHDRSourceFrames: Bool { true }
    public var supportsWideColorSourceFrames: Bool { true }

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let ciContext: CIContext
    private let transitionRenderer: TransitionRenderer
    private let renderQueue = DispatchQueue(label: "com.swifteditor.compositor",
                                            qos: .userInteractive)
    private var isCancelled = false

    /// HDR configuration controlling color space and pixel format.
    public var hdrConfig: HDRConfiguration = .sdrDefault()

    override public init() {
        let renderDevice = MetalRenderingDevice.shared
        self.device = renderDevice.device
        self.commandQueue = renderDevice.commandQueue
        self.ciContext = CIContext(mtlDevice: renderDevice.device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            .outputPremultiplied: true,
        ])
        self.transitionRenderer = TransitionRenderer()
        super.init()
    }

    /// Initialize with an explicit HDR configuration.
    public init(hdrConfiguration: HDRConfiguration) {
        let renderDevice = MetalRenderingDevice.shared
        self.device = renderDevice.device
        self.commandQueue = renderDevice.commandQueue
        self.hdrConfig = hdrConfiguration
        let colorSpace = hdrConfiguration.cgColorSpace ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        self.ciContext = CIContext(mtlDevice: renderDevice.device, options: [
            .workingColorSpace: colorSpace,
            .outputPremultiplied: true,
        ])
        self.transitionRenderer = TransitionRenderer()
        super.init()
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [self] in
            guard !isCancelled else {
                request.finishCancelledRequest()
                return
            }

            autoreleasepool {
                do {
                    let outputBuffer = try compositeFrame(for: request)
                    request.finish(withComposedVideoFrame: outputBuffer)
                } catch {
                    request.finish(with: error)
                }
            }
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        isCancelled = true
        renderQueue.async { [self] in
            isCancelled = false
        }
    }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // CIContext handles resource management internally
    }

    // MARK: - Core Compositing

    private func compositeFrame(for request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        // Try to read our custom instruction
        guard let instruction = request.videoCompositionInstruction as? CompositorInstruction else {
            // Fallback: pass through first source frame for backwards compatibility
            return try passthroughFrame(for: request)
        }

        let compositionTime = Rational(request.compositionTime)

        // Handle transition case
        if let transition = instruction.transitionInfo {
            return try renderTransition(transition, instruction: instruction,
                                        request: request, time: compositionTime)
        }

        // Build composited image from layers bottom to top
        var composited: CIImage? = nil
        for layer in instruction.layerInstructions {
            guard let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else { continue }
            var image = CIImage(cvPixelBuffer: sourceBuffer)

            // Apply effect stack
            image = applyEffects(layer.effectStack, to: image, at: compositionTime)

            // Apply opacity
            if layer.opacity < 1.0 {
                image = applyOpacity(layer.opacity, to: image)
            }

            // Composite onto result
            if let existing = composited {
                composited = applyBlendMode(layer.blendMode, top: image, bottom: existing)
            } else {
                composited = image
            }
        }

        guard let finalImage = composited else {
            return try passthroughFrame(for: request)
        }

        return try renderToPixelBuffer(finalImage, request: request)
    }

    // MARK: - Transition Rendering

    private func renderTransition(_ transition: TransitionInfo,
                                  instruction: CompositorInstruction,
                                  request: AVAsynchronousVideoCompositionRequest,
                                  time: Rational) throws -> CVPixelBuffer {
        // Get the two source frames for the transition
        guard let fromBuffer = request.sourceFrame(byTrackID: transition.fromTrackID),
              let toBuffer = request.sourceFrame(byTrackID: transition.toTrackID) else {
            return try passthroughFrame(for: request)
        }

        var fromImage = CIImage(cvPixelBuffer: fromBuffer)
        var toImage = CIImage(cvPixelBuffer: toBuffer)

        // Apply per-layer effects to each side of the transition
        for layer in instruction.layerInstructions {
            if layer.trackID == transition.fromTrackID {
                fromImage = applyEffects(layer.effectStack, to: fromImage, at: time)
                if layer.opacity < 1.0 {
                    fromImage = applyOpacity(layer.opacity, to: fromImage)
                }
            } else if layer.trackID == transition.toTrackID {
                toImage = applyEffects(layer.effectStack, to: toImage, at: time)
                if layer.opacity < 1.0 {
                    toImage = applyOpacity(layer.opacity, to: toImage)
                }
            }
        }

        let result = transitionRenderer.render(from: fromImage, to: toImage,
                                               type: transition.type,
                                               progress: transition.progress)
        return try renderToPixelBuffer(result, request: request)
    }

    // MARK: - Effects Application

    private func applyEffects(_ effectStack: EffectStack?, to image: CIImage, at time: Rational) -> CIImage {
        guard let stack = effectStack else { return image }
        var result = image
        for instance in stack.activeEffects {
            let values = instance.currentValues(at: time)
            let filterEffect = CIFilterEffect(filterName: instance.pluginID,
                                              parameterMapping: buildParameterMapping(values))
            result = filterEffect.apply(to: result, parameters: values)
        }
        return result
    }

    /// Builds a parameter mapping where each parameter name maps to itself as the CIFilter key.
    /// CIFilter parameters typically use the same keys as our parameter names.
    private func buildParameterMapping(_ values: ParameterValues) -> [String: String] {
        var mapping: [String: String] = [:]
        for key in values.allKeys {
            mapping[key] = key
        }
        return mapping
    }

    // MARK: - Opacity

    private func applyOpacity(_ opacity: Double, to image: CIImage) -> CIImage {
        // Use CIColorMatrix to multiply alpha channel
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        // Alpha vector: multiply alpha by opacity
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    // MARK: - Blend Modes

    private func applyBlendMode(_ mode: BlendMode, top: CIImage, bottom: CIImage) -> CIImage {
        let filterName: String? = switch mode {
        case .normal: nil
        case .add: "CIAdditionCompositing"
        case .multiply: "CIMultiplyCompositing"
        case .screen: "CIScreenBlendMode"
        case .overlay: "CIOverlayBlendMode"
        case .softLight: "CISoftLightBlendMode"
        case .hardLight: "CIHardLightBlendMode"
        case .difference: "CIDifferenceBlendMode"
        }

        guard let name = filterName else {
            // Normal blend: simple compositing
            return top.composited(over: bottom)
        }

        guard let filter = CIFilter(name: name) else {
            return top.composited(over: bottom)
        }
        filter.setValue(top, forKey: kCIInputImageKey)
        filter.setValue(bottom, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? top.composited(over: bottom)
    }

    // MARK: - Output Rendering

    private func renderToPixelBuffer(_ image: CIImage,
                                     request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        let outputBuffer = request.renderContext.newPixelBuffer()
        guard let buffer = outputBuffer else {
            throw NSError(domain: "MetalCompositor", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create output pixel buffer"])
        }

        let renderSize = request.renderContext.size
        // Crop the image to the render size, anchored at origin
        let cropRect = CGRect(origin: .zero, size: renderSize)
        let croppedImage = image.cropped(to: cropRect)

        let outputColorSpace = hdrConfig.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        ciContext.render(croppedImage, to: buffer, bounds: cropRect, colorSpace: outputColorSpace)
        return buffer
    }

    // MARK: - Standalone Rendering (for BackgroundRenderer)

    /// Render a CIImage to a CVPixelBuffer of the given size.
    /// Used by BackgroundRenderer for pre-rendering frames outside of AVVideoCompositing.
    public func renderImageToPixelBuffer(
        _ image: CIImage,
        size: CGSize
    ) -> CVPixelBuffer? {
        let pixelFormat = hdrConfig.isHDR ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        let attributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        let cropRect = CGRect(origin: .zero, size: size)
        let croppedImage = image.cropped(to: cropRect)
        let outputColorSpace = hdrConfig.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        ciContext.render(croppedImage, to: buffer, bounds: cropRect, colorSpace: outputColorSpace)
        return buffer
    }

    // MARK: - Fallback

    private func passthroughFrame(for request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        let sourceTrackIDs = request.sourceTrackIDs
        guard let firstTrackID = sourceTrackIDs.first?.int32Value,
              let sourceBuffer = request.sourceFrame(byTrackID: firstTrackID) else {
            throw NSError(domain: "MetalCompositor", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No source frames available"])
        }
        return sourceBuffer
    }
}
