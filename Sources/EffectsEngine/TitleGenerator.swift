#if canImport(AppKit)
import CoreImage
import CoreMediaPlus
import Foundation

/// Generates title frames with keyframeable properties.
/// Conforms to the generator pattern: produces CIImage frames without source input.
public final class TitleGenerator: Sendable {
    public let template: TitleTemplate
    private let renderer: TitleRenderer

    /// Keyframe tracks for animatable properties.
    /// Supported keys: "positionX", "positionY", "scale", "opacity",
    /// "colorR", "colorG", "colorB", "colorA", "rotation".
    public let keyframeTracks: [String: KeyframeTrack]

    public init(
        template: TitleTemplate,
        keyframeTracks: [String: KeyframeTrack] = [:]
    ) {
        self.template = template
        self.keyframeTracks = keyframeTracks
        self.renderer = TitleRenderer()
    }

    /// Generates a title frame at the given time with the specified output size.
    /// Evaluates keyframe tracks to animate properties over time.
    public func generateFrame(at time: Rational, size: CGSize) -> CIImage {
        var t = template

        // Evaluate keyframes and override template properties
        if let track = keyframeTracks["positionX"], let val = track.value(at: time) {
            if case .float(let v) = val {
                t.position = CGPoint(x: v, y: t.position.y)
            }
        }
        if let track = keyframeTracks["positionY"], let val = track.value(at: time) {
            if case .float(let v) = val {
                t.position = CGPoint(x: t.position.x, y: v)
            }
        }
        if let track = keyframeTracks["scale"], let val = track.value(at: time) {
            if case .float(let v) = val {
                t.scale = v
            }
        }
        if let track = keyframeTracks["opacity"], let val = track.value(at: time) {
            if case .float(let v) = val {
                t.opacity = v
            }
        }
        if let track = keyframeTracks["rotation"], let val = track.value(at: time) {
            if case .float(let v) = val {
                t.rotation = v
            }
        }
        if let track = keyframeTracks["color"], let val = track.value(at: time) {
            if case .color(let r, let g, let b, let a) = val {
                t.color = (r, g, b, a)
            }
        }

        return renderer.render(template: t, size: size)
    }
}
#endif
