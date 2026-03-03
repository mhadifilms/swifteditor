import Foundation
import CoreMediaPlus

/// Describes a single layer to be composited in a render pass.
public struct RenderLayer: Sendable, Hashable {
    public let clipID: UUID
    public let sourceTime: Rational
    public let transform: RenderTransform
    public let opacity: Double
    public let blendMode: BlendMode
    public let effectStackHash: Int

    public init(
        clipID: UUID,
        sourceTime: Rational,
        transform: RenderTransform = .identity,
        opacity: Double = 1.0,
        blendMode: BlendMode = .normal,
        effectStackHash: Int = 0
    ) {
        self.clipID = clipID
        self.sourceTime = sourceTime
        self.transform = transform
        self.opacity = opacity
        self.blendMode = blendMode
        self.effectStackHash = effectStackHash
    }

    /// The frame hash used for cache lookup of this layer.
    public var frameHash: FrameHash {
        FrameHash(clipID: clipID, sourceTime: sourceTime, effectStackHash: effectStackHash)
    }
}

/// 2D transform applied to a layer during compositing.
public struct RenderTransform: Sendable, Hashable {
    public let translateX: Double
    public let translateY: Double
    public let scaleX: Double
    public let scaleY: Double
    public let rotation: Double

    public static let identity = RenderTransform(
        translateX: 0, translateY: 0,
        scaleX: 1, scaleY: 1,
        rotation: 0
    )

    public init(translateX: Double, translateY: Double,
                scaleX: Double, scaleY: Double,
                rotation: Double) {
        self.translateX = translateX
        self.translateY = translateY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
    }
}

/// Describes the full render plan for a single output frame.
/// Contains an ordered list of layers from bottom (first) to top (last).
public struct RenderPlan: Sendable {
    public let compositionTime: Rational
    public let renderSize: CGSize
    public let layers: [RenderLayer]

    public init(compositionTime: Rational, renderSize: CGSize, layers: [RenderLayer]) {
        self.compositionTime = compositionTime
        self.renderSize = renderSize
        self.layers = layers
    }

    /// Combined hash of all layers, suitable for full-frame cache lookup.
    public var frameHash: Int {
        var hasher = Hasher()
        hasher.combine(compositionTime)
        hasher.combine(renderSize.width)
        hasher.combine(renderSize.height)
        for layer in layers {
            hasher.combine(layer)
        }
        return hasher.finalize()
    }
}

/// Builds a RenderPlan from timeline track data at a given composition time.
public struct RenderPlanBuilder: Sendable {

    public init() {}

    /// Build a render plan for the given composition time.
    /// Tracks are ordered bottom to top; clips are matched by checking if the
    /// composition time falls within their timeline range.
    public func buildPlan(
        tracks: [CompositionBuilder.TrackBuildData],
        compositionTime: Rational,
        renderSize: CGSize
    ) -> RenderPlan {
        var layers: [RenderLayer] = []

        for track in tracks {
            for clip in track.clips {
                let clipEnd = clip.startTime + clip.duration
                guard compositionTime >= clip.startTime, compositionTime < clipEnd else {
                    continue
                }

                let offsetInClip = compositionTime - clip.startTime
                let sourceTime = clip.sourceIn + offsetInClip

                let effectHash: Int
                if let stack = clip.effectStack {
                    var hasher = Hasher()
                    for effect in stack.activeEffects {
                        hasher.combine(effect.id)
                    }
                    effectHash = hasher.finalize()
                } else {
                    effectHash = 0
                }

                let layer = RenderLayer(
                    clipID: clip.clipID,
                    sourceTime: sourceTime,
                    effectStackHash: effectHash
                )
                layers.append(layer)
            }
        }

        return RenderPlan(
            compositionTime: compositionTime,
            renderSize: renderSize,
            layers: layers
        )
    }
}
