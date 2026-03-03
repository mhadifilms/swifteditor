import CoreImage
import CoreMediaPlus
import Foundation

/// Direction for directional transitions (wipe, push, slide).
public enum TransitionDirection: String, Codable, Sendable {
    case left, right, up, down
}

/// Available transition types.
public enum TransitionType: Sendable, Codable {
    case crossDissolve
    case dipToBlack
    case dipToWhite
    case wipe(direction: TransitionDirection)
    case push(direction: TransitionDirection)
    case slide(direction: TransitionDirection)
}

/// Instance of a transition applied between two adjacent clips.
public struct TransitionInstance: Identifiable, Sendable, Codable {
    public let id: UUID
    public var type: TransitionType
    public var duration: Rational
    public let clipAID: UUID
    public let clipBID: UUID

    public init(
        id: UUID = UUID(),
        type: TransitionType,
        duration: Rational,
        clipAID: UUID,
        clipBID: UUID
    ) {
        self.id = id
        self.type = type
        self.duration = duration
        self.clipAID = clipAID
        self.clipBID = clipBID
    }
}

/// Renders transition frames by blending two CIImages at a given progress.
public final class TransitionRenderer: Sendable {

    public init() {}

    /// Blends two images according to the transition type and progress (0.0 = fully A, 1.0 = fully B).
    public func render(
        from imageA: CIImage,
        to imageB: CIImage,
        type: TransitionType,
        progress: Double
    ) -> CIImage {
        let t = min(max(progress, 0.0), 1.0)
        switch type {
        case .crossDissolve:
            return renderCrossDissolve(from: imageA, to: imageB, progress: t)
        case .dipToBlack:
            return renderDipToColor(from: imageA, to: imageB, progress: t, isWhite: false)
        case .dipToWhite:
            return renderDipToColor(from: imageA, to: imageB, progress: t, isWhite: true)
        case .wipe(let direction):
            return renderWipe(from: imageA, to: imageB, direction: direction, progress: t)
        case .push(let direction):
            return renderPush(from: imageA, to: imageB, direction: direction, progress: t)
        case .slide(let direction):
            return renderSlide(from: imageA, to: imageB, direction: direction, progress: t)
        }
    }

    // MARK: - Cross Dissolve

    private func renderCrossDissolve(from imageA: CIImage, to imageB: CIImage, progress: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIDissolveTransition") else {
            return progress < 0.5 ? imageA : imageB
        }
        filter.setValue(imageA, forKey: kCIInputImageKey)
        filter.setValue(imageB, forKey: kCIInputTargetImageKey)
        filter.setValue(NSNumber(value: progress), forKey: "inputTime")
        return filter.outputImage ?? (progress < 0.5 ? imageA : imageB)
    }

    // MARK: - Dip to Color

    private func renderDipToColor(from imageA: CIImage, to imageB: CIImage, progress: Double, isWhite: Bool) -> CIImage {
        // First half: fade A to color. Second half: fade color to B.
        if progress < 0.5 {
            let fadeProgress = progress * 2.0 // 0..1 over first half
            let ev = isWhite ? fadeProgress * 10.0 : -(fadeProgress * 10.0)
            return applyExposure(to: imageA, ev: ev)
        } else {
            let fadeProgress = (progress - 0.5) * 2.0 // 0..1 over second half
            let ev = isWhite ? (1.0 - fadeProgress) * 10.0 : -((1.0 - fadeProgress) * 10.0)
            return applyExposure(to: imageB, ev: ev)
        }
    }

    private func applyExposure(to image: CIImage, ev: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: ev), forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    // MARK: - Wipe

    private func renderWipe(from imageA: CIImage, to imageB: CIImage, direction: TransitionDirection, progress: Double) -> CIImage {
        let extent = imageA.extent.union(imageB.extent)
        let mask = generateWipeMask(extent: extent, direction: direction, progress: progress)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return progress < 0.5 ? imageA : imageB
        }
        blendFilter.setValue(imageB, forKey: kCIInputImageKey)
        blendFilter.setValue(imageA, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        return blendFilter.outputImage ?? (progress < 0.5 ? imageA : imageB)
    }

    private func generateWipeMask(extent: CGRect, direction: TransitionDirection, progress: Double) -> CIImage {
        // Generate a linear gradient mask for the wipe direction
        let start: CIVector
        let end: CIVector

        switch direction {
        case .left:
            start = CIVector(x: extent.maxX, y: 0)
            end = CIVector(x: extent.minX, y: 0)
        case .right:
            start = CIVector(x: extent.minX, y: 0)
            end = CIVector(x: extent.maxX, y: 0)
        case .up:
            start = CIVector(x: 0, y: extent.minY)
            end = CIVector(x: 0, y: extent.maxY)
        case .down:
            start = CIVector(x: 0, y: extent.maxY)
            end = CIVector(x: 0, y: extent.minY)
        }

        guard let gradient = CIFilter(name: "CILinearGradient") else {
            return CIImage.white.cropped(to: extent)
        }
        gradient.setValue(start, forKey: "inputPoint0")
        gradient.setValue(end, forKey: "inputPoint1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.black, forKey: "inputColor1")

        guard let gradientImage = gradient.outputImage else {
            return CIImage.white.cropped(to: extent)
        }

        // Threshold the gradient based on progress to create a hard wipe edge.
        // Use CIColorClamp to shift the gradient.
        let shifted = gradientImage.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: (progress - 0.5) * 20.0,
        ])

        return shifted.cropped(to: extent)
    }

    // MARK: - Push

    private func renderPush(from imageA: CIImage, to imageB: CIImage, direction: TransitionDirection, progress: Double) -> CIImage {
        let extent = imageA.extent.union(imageB.extent)
        let w = extent.width
        let h = extent.height

        let (offsetAX, offsetAY, offsetBX, offsetBY): (CGFloat, CGFloat, CGFloat, CGFloat) = {
            switch direction {
            case .left:
                return (-w * progress, 0, w * (1.0 - progress), 0)
            case .right:
                return (w * progress, 0, -w * (1.0 - progress), 0)
            case .up:
                return (0, h * progress, 0, -h * (1.0 - progress))
            case .down:
                return (0, -h * progress, 0, h * (1.0 - progress))
            }
        }()

        let transformedA = imageA.transformed(by: CGAffineTransform(translationX: offsetAX, y: offsetAY))
        let transformedB = imageB.transformed(by: CGAffineTransform(translationX: offsetBX, y: offsetBY))

        return transformedB.composited(over: transformedA).cropped(to: extent)
    }

    // MARK: - Slide

    private func renderSlide(from imageA: CIImage, to imageB: CIImage, direction: TransitionDirection, progress: Double) -> CIImage {
        // Slide: B slides in over A (A stays stationary)
        let extent = imageA.extent.union(imageB.extent)
        let w = extent.width
        let h = extent.height

        let (offsetBX, offsetBY): (CGFloat, CGFloat) = {
            switch direction {
            case .left:
                return (w * (1.0 - progress), 0)
            case .right:
                return (-w * (1.0 - progress), 0)
            case .up:
                return (0, -h * (1.0 - progress))
            case .down:
                return (0, h * (1.0 - progress))
            }
        }()

        let transformedB = imageB.transformed(by: CGAffineTransform(translationX: offsetBX, y: offsetBY))
        return transformedB.composited(over: imageA).cropped(to: extent)
    }
}

// MARK: - CIImage convenience

private extension CIImage {
    static let white = CIImage(color: CIColor.white)
    static let black = CIImage(color: CIColor.black)
}
