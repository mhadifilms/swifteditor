import CoreGraphics
import CoreMediaPlus
import Foundation

/// Horizontal text alignment for titles.
public enum TextAlignment: String, Codable, Sendable {
    case left
    case center
    case right
}

/// Template describing a title's visual properties.
public struct TitleTemplate: Sendable, Codable {
    public var text: String
    public var font: String
    public var fontSize: CGFloat
    public var color: (r: Double, g: Double, b: Double, a: Double)
    public var backgroundColor: (r: Double, g: Double, b: Double, a: Double)?
    public var position: CGPoint // normalized 0-1
    public var alignment: TextAlignment
    public var scale: CGFloat
    public var rotation: CGFloat // radians
    public var opacity: CGFloat

    // Shadow
    public var shadowEnabled: Bool
    public var shadowOffset: CGSize
    public var shadowBlur: CGFloat

    // Outline
    public var outlineEnabled: Bool
    public var outlineColor: (r: Double, g: Double, b: Double, a: Double)
    public var outlineWidth: CGFloat

    public init(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: CGFloat = 48,
        color: (r: Double, g: Double, b: Double, a: Double) = (1, 1, 1, 1),
        backgroundColor: (r: Double, g: Double, b: Double, a: Double)? = nil,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        alignment: TextAlignment = .center,
        scale: CGFloat = 1.0,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1.0,
        shadowEnabled: Bool = false,
        shadowOffset: CGSize = CGSize(width: 2, height: -2),
        shadowBlur: CGFloat = 4,
        outlineEnabled: Bool = false,
        outlineColor: (r: Double, g: Double, b: Double, a: Double) = (0, 0, 0, 1),
        outlineWidth: CGFloat = 2
    ) {
        self.text = text
        self.font = font
        self.fontSize = fontSize
        self.color = color
        self.backgroundColor = backgroundColor
        self.position = position
        self.alignment = alignment
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.shadowEnabled = shadowEnabled
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
        self.outlineEnabled = outlineEnabled
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case text, font, fontSize
        case colorR, colorG, colorB, colorA
        case bgColorR, bgColorG, bgColorB, bgColorA, hasBgColor
        case positionX, positionY, alignment
        case scale, rotation, opacity
        case shadowEnabled, shadowOffsetW, shadowOffsetH, shadowBlur
        case outlineEnabled, outlineColorR, outlineColorG, outlineColorB, outlineColorA, outlineWidth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        font = try c.decode(String.self, forKey: .font)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        color = (
            try c.decode(Double.self, forKey: .colorR),
            try c.decode(Double.self, forKey: .colorG),
            try c.decode(Double.self, forKey: .colorB),
            try c.decode(Double.self, forKey: .colorA)
        )
        let hasBg = try c.decode(Bool.self, forKey: .hasBgColor)
        if hasBg {
            backgroundColor = (
                try c.decode(Double.self, forKey: .bgColorR),
                try c.decode(Double.self, forKey: .bgColorG),
                try c.decode(Double.self, forKey: .bgColorB),
                try c.decode(Double.self, forKey: .bgColorA)
            )
        } else {
            backgroundColor = nil
        }
        position = CGPoint(
            x: try c.decode(CGFloat.self, forKey: .positionX),
            y: try c.decode(CGFloat.self, forKey: .positionY)
        )
        alignment = try c.decode(TextAlignment.self, forKey: .alignment)
        scale = try c.decode(CGFloat.self, forKey: .scale)
        rotation = try c.decode(CGFloat.self, forKey: .rotation)
        opacity = try c.decode(CGFloat.self, forKey: .opacity)
        shadowEnabled = try c.decode(Bool.self, forKey: .shadowEnabled)
        shadowOffset = CGSize(
            width: try c.decode(CGFloat.self, forKey: .shadowOffsetW),
            height: try c.decode(CGFloat.self, forKey: .shadowOffsetH)
        )
        shadowBlur = try c.decode(CGFloat.self, forKey: .shadowBlur)
        outlineEnabled = try c.decode(Bool.self, forKey: .outlineEnabled)
        outlineColor = (
            try c.decode(Double.self, forKey: .outlineColorR),
            try c.decode(Double.self, forKey: .outlineColorG),
            try c.decode(Double.self, forKey: .outlineColorB),
            try c.decode(Double.self, forKey: .outlineColorA)
        )
        outlineWidth = try c.decode(CGFloat.self, forKey: .outlineWidth)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(font, forKey: .font)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(color.r, forKey: .colorR)
        try c.encode(color.g, forKey: .colorG)
        try c.encode(color.b, forKey: .colorB)
        try c.encode(color.a, forKey: .colorA)
        try c.encode(backgroundColor != nil, forKey: .hasBgColor)
        if let bg = backgroundColor {
            try c.encode(bg.r, forKey: .bgColorR)
            try c.encode(bg.g, forKey: .bgColorG)
            try c.encode(bg.b, forKey: .bgColorB)
            try c.encode(bg.a, forKey: .bgColorA)
        }
        try c.encode(position.x, forKey: .positionX)
        try c.encode(position.y, forKey: .positionY)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(scale, forKey: .scale)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(shadowOffset.width, forKey: .shadowOffsetW)
        try c.encode(shadowOffset.height, forKey: .shadowOffsetH)
        try c.encode(shadowBlur, forKey: .shadowBlur)
        try c.encode(outlineEnabled, forKey: .outlineEnabled)
        try c.encode(outlineColor.r, forKey: .outlineColorR)
        try c.encode(outlineColor.g, forKey: .outlineColorG)
        try c.encode(outlineColor.b, forKey: .outlineColorB)
        try c.encode(outlineColor.a, forKey: .outlineColorA)
        try c.encode(outlineWidth, forKey: .outlineWidth)
    }
}

// MARK: - Title Presets

/// Built-in title presets for common use cases.
public enum TitlePreset: String, CaseIterable, Sendable {
    case lowerThird
    case centerTitle
    case creditsCrawl

    public func makeTemplate(text: String) -> TitleTemplate {
        switch self {
        case .lowerThird:
            return TitleTemplate.lowerThird(text: text)
        case .centerTitle:
            return TitleTemplate.centerTitle(text: text)
        case .creditsCrawl:
            return TitleTemplate.creditsCrawl(text: text)
        }
    }
}

// MARK: - Factory Methods

extension TitleTemplate {
    /// Lower-third title positioned near the bottom of the frame.
    public static func lowerThird(text: String) -> TitleTemplate {
        TitleTemplate(
            text: text,
            font: "Helvetica Neue",
            fontSize: 36,
            color: (1, 1, 1, 1),
            backgroundColor: (0, 0, 0, 0.6),
            position: CGPoint(x: 0.05, y: 0.15),
            alignment: .left,
            shadowEnabled: true,
            shadowOffset: CGSize(width: 1, height: -1),
            shadowBlur: 3
        )
    }

    /// Large centered title for establishing shots or chapter headings.
    public static func centerTitle(text: String) -> TitleTemplate {
        TitleTemplate(
            text: text,
            font: "Helvetica Neue",
            fontSize: 72,
            color: (1, 1, 1, 1),
            position: CGPoint(x: 0.5, y: 0.5),
            alignment: .center,
            shadowEnabled: true,
            shadowOffset: CGSize(width: 2, height: -2),
            shadowBlur: 6,
            outlineEnabled: true,
            outlineColor: (0, 0, 0, 0.8),
            outlineWidth: 2
        )
    }

    /// Credits crawl text positioned at the bottom, typically scrolled upward via keyframes.
    public static func creditsCrawl(text: String) -> TitleTemplate {
        TitleTemplate(
            text: text,
            font: "Helvetica Neue",
            fontSize: 28,
            color: (1, 1, 1, 1),
            position: CGPoint(x: 0.5, y: 0.0),
            alignment: .center
        )
    }
}
