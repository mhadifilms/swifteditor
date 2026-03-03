#if canImport(AppKit)
import AppKit
import CoreImage
import Foundation

/// Renders a TitleTemplate into a CIImage using CoreText/NSAttributedString.
public final class TitleRenderer: Sendable {

    public init() {}

    /// Renders the given title template at the specified output size.
    public func render(template: TitleTemplate, size: CGSize) -> CIImage {
        let scaledFontSize = template.fontSize * template.scale
        guard scaledFontSize > 0, size.width > 0, size.height > 0 else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        let font = NSFont(name: template.font, size: scaledFontSize)
            ?? NSFont.systemFont(ofSize: scaledFontSize)

        let attributedString = buildAttributedString(template: template, font: font)
        let textSize = measureText(attributedString, maxWidth: size.width * 0.9)

        // Determine background rect if needed
        let bgPadding: CGFloat = 8
        let bgSize = CGSize(
            width: textSize.width + bgPadding * 2,
            height: textSize.height + bgPadding * 2
        )

        // Total canvas is the full output size
        let bitmapWidth = Int(size.width)
        let bitmapHeight = Int(size.height)
        guard bitmapWidth > 0, bitmapHeight > 0 else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: bitmapWidth,
            height: bitmapHeight,
            bitsPerComponent: 8,
            bytesPerRow: bitmapWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        // Compute text origin based on normalized position and alignment
        let anchorX = size.width * template.position.x
        let anchorY = size.height * template.position.y

        let textX: CGFloat
        switch template.alignment {
        case .left:
            textX = anchorX
        case .center:
            textX = anchorX - textSize.width / 2
        case .right:
            textX = anchorX - textSize.width
        }
        let textY = anchorY - textSize.height / 2

        // Apply rotation around anchor point
        context.saveGState()
        if template.rotation != 0 {
            context.translateBy(x: anchorX, y: anchorY)
            context.rotate(by: template.rotation)
            context.translateBy(x: -anchorX, y: -anchorY)
        }

        // Apply opacity
        context.setAlpha(template.opacity)

        // Draw background if specified
        if let bg = template.backgroundColor {
            let bgColor = NSColor(
                red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a
            )
            let bgRect = CGRect(
                x: textX - bgPadding,
                y: textY - bgPadding,
                width: bgSize.width,
                height: bgSize.height
            )
            bgColor.setFill()
            context.fill(bgRect)
        }

        // Draw shadow
        if template.shadowEnabled {
            let shadowColor = NSColor(white: 0, alpha: 0.7)
            let shadow = NSShadow()
            shadow.shadowOffset = template.shadowOffset
            shadow.shadowBlurRadius = template.shadowBlur
            shadow.shadowColor = shadowColor
            shadow.set()
        }

        // Draw outline by drawing text with stroke first, then fill on top
        let textRect = CGRect(origin: CGPoint(x: textX, y: textY), size: textSize)
        if template.outlineEnabled {
            let outlineAttrs = buildOutlineAttributedString(template: template, font: font)
            outlineAttrs.draw(in: textRect)
        }

        // Draw fill text
        attributedString.draw(in: textRect)

        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size))
        }

        return CIImage(cgImage: cgImage)
    }

    // MARK: - Private

    private func buildAttributedString(template: TitleTemplate, font: NSFont) -> NSAttributedString {
        let color = NSColor(
            red: template.color.r,
            green: template.color.g,
            blue: template.color.b,
            alpha: template.color.a
        )
        let paragraphStyle = NSMutableParagraphStyle()
        switch template.alignment {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        return NSAttributedString(string: template.text, attributes: attributes)
    }

    private func buildOutlineAttributedString(template: TitleTemplate, font: NSFont) -> NSAttributedString {
        let outlineColor = NSColor(
            red: template.outlineColor.r,
            green: template.outlineColor.g,
            blue: template.outlineColor.b,
            alpha: template.outlineColor.a
        )
        let paragraphStyle = NSMutableParagraphStyle()
        switch template.alignment {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: outlineColor,
            .strokeWidth: template.outlineWidth * 2, // positive = stroke only
            .paragraphStyle: paragraphStyle,
        ]
        return NSAttributedString(string: template.text, attributes: attributes)
    }

    private func measureText(_ attributedString: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: ceil(boundingRect.width),
            height: ceil(boundingRect.height)
        )
    }
}
#endif
