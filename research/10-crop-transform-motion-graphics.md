# 10 - Crop, Transform & Motion Graphics

## Table of Contents
1. [Crop Tool Implementation](#1-crop-tool-implementation)
2. [Ken Burns Effect](#2-ken-burns-effect)
3. [Transform Properties System](#3-transform-properties-system)
4. [Keyframe Animation System Design](#4-keyframe-animation-system-design)
5. [Keyframe Interpolation Types & Algorithms](#5-keyframe-interpolation-types--algorithms)
6. [Picture-in-Picture Implementation](#6-picture-in-picture-implementation)
7. [Split Screen Layouts](#7-split-screen-layouts)
8. [Text / Title System](#8-text--title-system)
9. [Shape Layers & Drawing](#9-shape-layers--drawing)
10. [Masking System](#10-masking-system)
11. [Motion Path Animation](#11-motion-path-animation)
12. [Speed Curves / Bezier Keyframe Editor UI](#12-speed-curves--bezier-keyframe-editor-ui)
13. [2D Motion Tracking (Vision Framework)](#13-2d-motion-tracking-vision-framework)
14. [CGAffineTransform & CATransform3D for Video](#14-cgaffinetransform--catransform3d-for-video)
15. [Transform Pipeline in AVVideoComposition](#15-transform-pipeline-in-avvideocomposition)
16. [Custom Video Compositor (AVVideoCompositing)](#16-custom-video-compositor-avvideocompositing)
17. [VideoLab Framework Architecture Reference](#17-videolab-framework-architecture-reference)
18. [WWDC Sessions & References](#18-wwdc-sessions--references)

---

## 1. Crop Tool Implementation

### Overview
Cropping in a professional NLE involves two approaches:
- **AVFoundation built-in**: `setCropRectangle(_:at:)` on `AVMutableVideoCompositionLayerInstruction`
- **Custom compositor**: More flexible, applies crop in a Metal/CIFilter render pipeline

### Aspect Ratio Presets

```swift
enum CropAspectRatio: CaseIterable {
    case free
    case ratio16x9
    case ratio4x3
    case ratio1x1
    case ratio9x16
    case ratio21x9
    case ratio2x1

    var ratio: CGFloat? {
        switch self {
        case .free:     return nil
        case .ratio16x9: return 16.0 / 9.0
        case .ratio4x3:  return 4.0 / 3.0
        case .ratio1x1:  return 1.0
        case .ratio9x16: return 9.0 / 16.0
        case .ratio21x9: return 21.0 / 9.0
        case .ratio2x1:  return 2.0
        }
    }

    var displayName: String {
        switch self {
        case .free:     return "Free"
        case .ratio16x9: return "16:9"
        case .ratio4x3:  return "4:3"
        case .ratio1x1:  return "1:1"
        case .ratio9x16: return "9:16"
        case .ratio21x9: return "21:9"
        case .ratio2x1:  return "2:1"
        }
    }
}
```

### Crop Data Model

```swift
struct CropRegion: Codable, Equatable {
    /// Normalized 0...1 rect within source frame
    var normalizedRect: CGRect

    /// Aspect ratio constraint (nil = free)
    var aspectRatio: CGFloat?

    static var full: CropRegion {
        CropRegion(normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Convert to pixel rect given source dimensions
    func pixelRect(sourceSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * sourceSize.width,
            y: normalizedRect.origin.y * sourceSize.height,
            width: normalizedRect.size.width * sourceSize.width,
            height: normalizedRect.size.height * sourceSize.height
        )
    }
}
```

### AVFoundation setCropRectangle Approach

```swift
func applyCrop(to track: AVAssetTrack,
               cropRect: CGRect,
               composition: AVMutableVideoComposition) {
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: track.asset!.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

    // Set crop rectangle
    layerInstruction.setCropRectangle(cropRect, at: .zero)

    // Apply transform to reposition cropped content to origin
    let transform = CGAffineTransform(translationX: -cropRect.origin.x,
                                       y: -cropRect.origin.y)
    layerInstruction.setTransform(transform, at: .zero)

    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]
    composition.renderSize = cropRect.size
}
```

### CIImage-Based Crop (Custom Compositor Approach)

```swift
// Inside AVMutableVideoComposition handler
let composition = AVMutableVideoComposition(asset: asset) { request in
    let sourceImage = request.sourceImage

    // Crop to region
    let cropRect = CGRect(x: 100, y: 50, width: 1280, height: 720)
    let croppedImage = sourceImage.cropped(to: cropRect)

    // Translate to origin
    let translated = croppedImage.transformed(
        by: CGAffineTransform(translationX: -cropRect.origin.x,
                               y: -cropRect.origin.y)
    )

    request.finish(with: translated, context: nil)
}
composition.renderSize = CGSize(width: 1280, height: 720)
```

### Animated Crop (Crop Ramp)

```swift
// Animate crop over time using setCropRectangleRamp
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

let startCrop = CGRect(x: 0, y: 0, width: 1920, height: 1080)
let endCrop = CGRect(x: 200, y: 100, width: 1280, height: 720)
let timeRange = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600),
                             duration: CMTime(seconds: 3, preferredTimescale: 600))

layerInstruction.setCropRectangleRamp(
    fromStartCropRectangle: startCrop,
    toEndCropRectangle: endCrop,
    timeRange: timeRange
)
```

---

## 2. Ken Burns Effect

### Overview
The Ken Burns effect is an animated crop/pan/zoom over an image or video, creating the illusion of camera movement from still images. It uses two crop settings: one at clip start, one at clip end.

### Implementation Strategy

```swift
struct KenBurnsEffect {
    /// Start crop region (normalized 0-1)
    var startRegion: CGRect
    /// End crop region (normalized 0-1)
    var endRegion: CGRect
    /// Duration
    var duration: CMTime
    /// Easing function
    var easing: EasingFunction = .easeInOut
}

func applyKenBurns(effect: KenBurnsEffect,
                    sourceSize: CGSize,
                    outputSize: CGSize) -> AVMutableVideoComposition {
    let asset: AVAsset = // ... your asset

    let composition = AVMutableVideoComposition(asset: asset) { request in
        let sourceImage = request.sourceImage
        let time = request.compositionTime
        let progress = time.seconds / effect.duration.seconds
        let easedProgress = effect.easing.apply(CGFloat(progress))

        // Interpolate crop region
        let currentRect = CGRect(
            x: lerp(effect.startRegion.origin.x, effect.endRegion.origin.x, easedProgress),
            y: lerp(effect.startRegion.origin.y, effect.endRegion.origin.y, easedProgress),
            width: lerp(effect.startRegion.width, effect.endRegion.width, easedProgress),
            height: lerp(effect.startRegion.height, effect.endRegion.height, easedProgress)
        )

        // Convert normalized to pixel rect
        let pixelRect = CGRect(
            x: currentRect.origin.x * sourceSize.width,
            y: currentRect.origin.y * sourceSize.height,
            width: currentRect.width * sourceSize.width,
            height: currentRect.height * sourceSize.height
        )

        // Crop and scale to output
        let cropped = sourceImage.cropped(to: pixelRect)
        let scaleX = outputSize.width / pixelRect.width
        let scaleY = outputSize.height / pixelRect.height
        let scaled = cropped
            .transformed(by: CGAffineTransform(translationX: -pixelRect.origin.x,
                                                y: -pixelRect.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        request.finish(with: scaled, context: nil)
    }

    composition.renderSize = outputSize
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    return composition
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    return a + (b - a) * t
}
```

---

## 3. Transform Properties System

### Core Transform Data Model

```swift
struct TransformProperties: Codable, Equatable {
    /// Position offset from center (in points)
    var position: CGPoint = .zero

    /// Scale factor (1.0 = 100%)
    var scale: CGSize = CGSize(width: 1.0, height: 1.0)

    /// Rotation angle in radians
    var rotation: CGFloat = 0.0

    /// Anchor point for rotation/scale (normalized 0-1, default center)
    var anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Opacity (0.0 - 1.0)
    var opacity: CGFloat = 1.0

    /// Whether to maintain uniform scale
    var uniformScale: Bool = true
}

extension TransformProperties {
    /// Build CGAffineTransform for given frame size
    /// Order: translate anchor to origin -> scale -> rotate -> translate back -> position
    func affineTransform(frameSize: CGSize) -> CGAffineTransform {
        let anchorX = anchorPoint.x * frameSize.width
        let anchorY = anchorPoint.y * frameSize.height

        var transform = CGAffineTransform.identity

        // Move anchor point to origin
        transform = transform.translatedBy(x: -anchorX, y: -anchorY)

        // Apply scale
        transform = transform.scaledBy(x: scale.width, y: scale.height)

        // Apply rotation
        transform = transform.rotated(by: rotation)

        // Move anchor point back
        transform = transform.translatedBy(x: anchorX, y: anchorY)

        // Apply position offset
        transform = transform.translatedBy(x: position.x, y: position.y)

        return transform
    }

    /// Build CATransform3D with optional perspective
    func transform3D(frameSize: CGSize, perspective: CGFloat = 0) -> CATransform3D {
        var t = CATransform3DIdentity

        // Set perspective (m34 controls depth illusion)
        if perspective != 0 {
            t.m34 = -1.0 / perspective
        }

        let anchorX = anchorPoint.x * frameSize.width
        let anchorY = anchorPoint.y * frameSize.height

        // Translate to anchor
        t = CATransform3DTranslate(t, anchorX, anchorY, 0)

        // Scale
        t = CATransform3DScale(t, scale.width, scale.height, 1.0)

        // Rotate around Z axis
        t = CATransform3DRotate(t, rotation, 0, 0, 1)

        // Translate back
        t = CATransform3DTranslate(t, -anchorX, -anchorY, 0)

        // Position offset
        t = CATransform3DTranslate(t, position.x, position.y, 0)

        return t
    }
}
```

### CGAffineTransform Order of Operations

**Critical**: The order of transform concatenation matters significantly.

```
point_new = point * M1 * M2
```

When using `concatenating()`:
- `M1.concatenating(M2)` means M1 is applied first, then M2
- For anchor-point rotation: translate-to-origin, rotate, translate-back

```swift
// Rotate around a custom anchor point
func rotateAroundPoint(angle: CGFloat, center: CGPoint) -> CGAffineTransform {
    let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
    let rotate = CGAffineTransform(rotationAngle: angle)
    let fromOrigin = CGAffineTransform(translationX: center.x, y: center.y)
    return toOrigin.concatenating(rotate).concatenating(fromOrigin)
}

// Scale around a custom anchor point
func scaleAroundPoint(sx: CGFloat, sy: CGFloat, center: CGPoint) -> CGAffineTransform {
    let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
    let scale = CGAffineTransform(scaleX: sx, y: sy)
    let fromOrigin = CGAffineTransform(translationX: center.x, y: center.y)
    return toOrigin.concatenating(scale).concatenating(fromOrigin)
}
```

### CATransform3D for 3D Effects

```swift
extension CATransform3D {
    /// Create a perspective transform
    static func perspective(_ eyeDistance: CGFloat) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m34 = -1.0 / eyeDistance  // Typical values: 500-2000
        return t
    }

    /// Rotate around X axis (tilt forward/backward)
    func rotatedX(_ angle: CGFloat) -> CATransform3D {
        CATransform3DRotate(self, angle, 1, 0, 0)
    }

    /// Rotate around Y axis (turn left/right)
    func rotatedY(_ angle: CGFloat) -> CATransform3D {
        CATransform3DRotate(self, angle, 0, 1, 0)
    }

    /// Rotate around Z axis (spin)
    func rotatedZ(_ angle: CGFloat) -> CATransform3D {
        CATransform3DRotate(self, angle, 0, 0, 1)
    }
}
```

---

## 4. Keyframe Animation System Design

### Core Keyframe Data Model

```swift
/// A single keyframe at a specific time
struct Keyframe<Value: Interpolatable>: Identifiable, Codable where Value: Codable {
    let id: UUID

    /// Time position (seconds from clip start)
    var time: Double

    /// Value at this keyframe
    var value: Value

    /// Interpolation type to NEXT keyframe
    var interpolation: InterpolationType

    /// Bezier control points for cubic interpolation (normalized 0-1)
    /// controlOut = outgoing handle from this keyframe
    /// controlIn = incoming handle to the NEXT keyframe
    var controlPointOut: CGPoint
    var controlPointIn: CGPoint

    init(time: Double, value: Value,
         interpolation: InterpolationType = .smooth,
         controlPointOut: CGPoint = CGPoint(x: 0.33, y: 0.0),
         controlPointIn: CGPoint = CGPoint(x: 0.67, y: 1.0)) {
        self.id = UUID()
        self.time = time
        self.value = value
        self.interpolation = interpolation
        self.controlPointOut = controlPointOut
        self.controlPointIn = controlPointIn
    }
}

/// Interpolation types (matches industry standards: After Effects, Premiere, DaVinci)
enum InterpolationType: String, Codable, CaseIterable {
    case linear         // Constant rate between keyframes
    case smooth         // Auto-bezier (Catmull-Rom style)
    case bezier         // Manual bezier control points
    case easeIn         // Accelerates from previous keyframe
    case easeOut        // Decelerates into next keyframe
    case easeInOut      // Accelerates then decelerates
    case hold           // No interpolation, value jumps at next keyframe
}

/// Protocol for values that can be interpolated
protocol Interpolatable {
    static func interpolate(from: Self, to: Self, progress: Double) -> Self
}

extension CGFloat: Interpolatable {
    static func interpolate(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        from + (to - from) * CGFloat(progress)
    }
}

extension CGPoint: Interpolatable {
    static func interpolate(from: CGPoint, to: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: CGFloat.interpolate(from: from.x, to: to.x, progress: progress),
            y: CGFloat.interpolate(from: from.y, to: to.y, progress: progress)
        )
    }
}

extension CGSize: Interpolatable {
    static func interpolate(from: CGSize, to: CGSize, progress: Double) -> CGSize {
        CGSize(
            width: CGFloat.interpolate(from: from.width, to: to.width, progress: progress),
            height: CGFloat.interpolate(from: from.height, to: to.height, progress: progress)
        )
    }
}
```

### Keyframe Track

```swift
/// A track of keyframes for a single animatable property
struct KeyframeTrack<Value: Interpolatable & Codable>: Codable {
    var keyframes: [Keyframe<Value>]

    /// Whether animation is enabled (vs. using static value)
    var isAnimated: Bool { keyframes.count > 1 }

    /// Get interpolated value at time
    func value(at time: Double) -> Value {
        guard !keyframes.isEmpty else {
            fatalError("KeyframeTrack has no keyframes")
        }

        // Sort keyframes by time
        let sorted = keyframes.sorted { $0.time < $1.time }

        // Before first keyframe
        if time <= sorted.first!.time {
            return sorted.first!.value
        }

        // After last keyframe
        if time >= sorted.last!.time {
            return sorted.last!.value
        }

        // Find surrounding keyframes
        for i in 0..<(sorted.count - 1) {
            let kf0 = sorted[i]
            let kf1 = sorted[i + 1]

            if time >= kf0.time && time <= kf1.time {
                let segmentDuration = kf1.time - kf0.time
                guard segmentDuration > 0 else { return kf0.value }

                let linearProgress = (time - kf0.time) / segmentDuration
                let easedProgress = applyInterpolation(
                    type: kf0.interpolation,
                    progress: linearProgress,
                    controlOut: kf0.controlPointOut,
                    controlIn: kf1.controlPointIn
                )

                return Value.interpolate(from: kf0.value, to: kf1.value, progress: easedProgress)
            }
        }

        return sorted.last!.value
    }

    /// Add a keyframe, maintaining time order
    mutating func addKeyframe(_ keyframe: Keyframe<Value>) {
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }

    /// Remove keyframe by ID
    mutating func removeKeyframe(id: UUID) {
        keyframes.removeAll { $0.id == id }
    }
}
```

### Animated Transform Properties

```swift
/// Complete animatable transform for a video clip
struct AnimatedTransform: Codable {
    var positionX: KeyframeTrack<CGFloat>
    var positionY: KeyframeTrack<CGFloat>
    var scaleX: KeyframeTrack<CGFloat>
    var scaleY: KeyframeTrack<CGFloat>
    var rotation: KeyframeTrack<CGFloat>
    var anchorPointX: KeyframeTrack<CGFloat>
    var anchorPointY: KeyframeTrack<CGFloat>
    var opacity: KeyframeTrack<CGFloat>

    /// Get transform properties at a given time
    func properties(at time: Double) -> TransformProperties {
        TransformProperties(
            position: CGPoint(
                x: positionX.value(at: time),
                y: positionY.value(at: time)
            ),
            scale: CGSize(
                width: scaleX.value(at: time),
                height: scaleY.value(at: time)
            ),
            rotation: rotation.value(at: time),
            anchorPoint: CGPoint(
                x: anchorPointX.value(at: time),
                y: anchorPointY.value(at: time)
            ),
            opacity: opacity.value(at: time)
        )
    }

    /// Create with static (non-animated) default values
    static var identity: AnimatedTransform {
        AnimatedTransform(
            positionX: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 0)]),
            positionY: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 0)]),
            scaleX: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 1.0)]),
            scaleY: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 1.0)]),
            rotation: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 0)]),
            anchorPointX: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 0.5)]),
            anchorPointY: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 0.5)]),
            opacity: KeyframeTrack(keyframes: [Keyframe(time: 0, value: 1.0)])
        )
    }
}
```

---

## 5. Keyframe Interpolation Types & Algorithms

### Cubic Bezier Interpolation

The parametric equation for a cubic Bezier curve with parameter `t` (0 to 1):

```
B(t) = (1-t)^3 * P0 + 3*(1-t)^2 * t * P1 + 3*(1-t) * t^2 * P2 + t^3 * P3
```

Where P0=(0,0), P1=controlOut, P2=controlIn, P3=(1,1) for timing functions.

```swift
/// Cubic bezier timing function
/// controlPoints define the curve shape: (x1,y1) and (x2,y2)
/// where P0 = (0,0) and P3 = (1,1)
struct CubicBezierTimingFunction {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    // Standard presets (matching CSS / CAMediaTimingFunction)
    static let linear = CubicBezierTimingFunction(x1: 0, y1: 0, x2: 1, y2: 1)
    static let easeIn = CubicBezierTimingFunction(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeOut = CubicBezierTimingFunction(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = CubicBezierTimingFunction(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    // After Effects-style presets
    static let easeInQuad = CubicBezierTimingFunction(x1: 0.55, y1: 0.085, x2: 0.68, y2: 0.53)
    static let easeOutQuad = CubicBezierTimingFunction(x1: 0.25, y1: 0.46, x2: 0.45, y2: 0.94)
    static let easeInCubic = CubicBezierTimingFunction(x1: 0.55, y1: 0.055, x2: 0.675, y2: 0.19)
    static let easeOutCubic = CubicBezierTimingFunction(x1: 0.215, y1: 0.61, x2: 0.355, y2: 1)

    /// Evaluate the Y value for a given X (time progress)
    /// Uses Newton's method to solve for t given x, then evaluates y
    func evaluate(at x: Double) -> Double {
        let t = solveCurveX(x)
        return sampleCurveY(t)
    }

    // Parametric bezier for X coordinate
    private func sampleCurveX(_ t: Double) -> Double {
        // B(t) = 3*(1-t)^2*t*x1 + 3*(1-t)*t^2*x2 + t^3
        return ((1.0 - 3.0 * x2 + 3.0 * x1) * t + (3.0 * x2 - 6.0 * x1)) * t + (3.0 * x1) * t
    }

    // Parametric bezier for Y coordinate
    private func sampleCurveY(_ t: Double) -> Double {
        return ((1.0 - 3.0 * y2 + 3.0 * y1) * t + (3.0 * y2 - 6.0 * y1)) * t + (3.0 * y1) * t
    }

    // Derivative of X bezier
    private func sampleCurveDerivativeX(_ t: Double) -> Double {
        return (3.0 * (1.0 - 3.0 * x2 + 3.0 * x1)) * t * t +
               (2.0 * (3.0 * x2 - 6.0 * x1)) * t +
               (3.0 * x1)
    }

    /// Newton's method to find t for a given x value
    private func solveCurveX(_ x: Double, epsilon: Double = 1e-6) -> Double {
        var t = x  // Initial guess

        // Newton-Raphson iterations
        for _ in 0..<8 {
            let xEstimate = sampleCurveX(t) - x
            if abs(xEstimate) < epsilon { return t }
            let derivative = sampleCurveDerivativeX(t)
            if abs(derivative) < epsilon { break }
            t -= xEstimate / derivative
        }

        // Fallback: bisection method
        var t0: Double = 0.0
        var t1: Double = 1.0
        t = x

        while t0 < t1 {
            let xEst = sampleCurveX(t)
            if abs(xEst - x) < epsilon { return t }
            if x > xEst { t0 = t } else { t1 = t }
            t = (t1 - t0) * 0.5 + t0
        }

        return t
    }
}
```

### Complete Interpolation Function

```swift
func applyInterpolation(type: InterpolationType,
                         progress: Double,
                         controlOut: CGPoint,
                         controlIn: CGPoint) -> Double {
    switch type {
    case .linear:
        return progress

    case .hold:
        return 0.0  // Value stays at start until next keyframe

    case .easeIn:
        return CubicBezierTimingFunction.easeIn.evaluate(at: progress)

    case .easeOut:
        return CubicBezierTimingFunction.easeOut.evaluate(at: progress)

    case .easeInOut:
        return CubicBezierTimingFunction.easeInOut.evaluate(at: progress)

    case .smooth:
        // Catmull-Rom style: auto-computed control points
        return CubicBezierTimingFunction(
            x1: 0.25, y1: 0.1,
            x2: 0.75, y2: 0.9
        ).evaluate(at: progress)

    case .bezier:
        // Use the manually set control points
        return CubicBezierTimingFunction(
            x1: Double(controlOut.x), y1: Double(controlOut.y),
            x2: Double(controlIn.x), y2: Double(controlIn.y)
        ).evaluate(at: progress)
    }
}
```

### Easing Functions Library

```swift
enum EasingFunction {
    case linear
    case easeIn, easeOut, easeInOut
    case quadIn, quadOut, quadInOut
    case cubicIn, cubicOut, cubicInOut
    case backIn, backOut, backInOut
    case elasticIn, elasticOut
    case bounceOut

    func apply(_ t: CGFloat) -> CGFloat {
        switch self {
        case .linear:      return t
        case .easeIn:      return t * t * t
        case .easeOut:     return 1 - pow(1 - t, 3)
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .quadIn:      return t * t
        case .quadOut:     return 1 - (1 - t) * (1 - t)
        case .quadInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .cubicIn:     return t * t * t
        case .cubicOut:    return 1 - pow(1 - t, 3)
        case .cubicInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .backIn:
            let c1: CGFloat = 1.70158
            let c3 = c1 + 1
            return c3 * t * t * t - c1 * t * t
        case .backOut:
            let c1: CGFloat = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case .backInOut:
            let c1: CGFloat = 1.70158
            let c2 = c1 * 1.525
            if t < 0.5 {
                return (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
            } else {
                return (pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
            }
        case .elasticIn:
            let c4 = (2 * .pi) / 3
            return t == 0 ? 0 : t == 1 ? 1 :
                -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c4)
        case .elasticOut:
            let c4 = (2 * .pi) / 3
            return t == 0 ? 0 : t == 1 ? 1 :
                pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        case .bounceOut:
            let n1: CGFloat = 7.5625
            let d1: CGFloat = 2.75
            var t = t
            if t < 1 / d1 {
                return n1 * t * t
            } else if t < 2 / d1 {
                t -= 1.5 / d1
                return n1 * t * t + 0.75
            } else if t < 2.5 / d1 {
                t -= 2.25 / d1
                return n1 * t * t + 0.9375
            } else {
                t -= 2.625 / d1
                return n1 * t * t + 0.984375
            }
        }
    }
}
```

---

## 6. Picture-in-Picture Implementation

### Using AVMutableVideoCompositionLayerInstruction

```swift
func createPictureInPicture(
    mainAsset: AVAsset,
    overlayAsset: AVAsset,
    pipPosition: PiPPosition = .bottomRight,
    pipScale: CGFloat = 0.25,
    outputSize: CGSize = CGSize(width: 1920, height: 1080)
) async throws -> (AVMutableComposition, AVMutableVideoComposition) {

    let composition = AVMutableComposition()

    // Add main video track
    let mainTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    let mainVideoTrack = try await mainAsset.loadTracks(withMediaType: .video).first!
    let duration = try await mainAsset.load(.duration)
    try mainTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                   of: mainVideoTrack, at: .zero)

    // Add overlay video track
    let overlayTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    let overlayVideoTrack = try await overlayAsset.loadTracks(withMediaType: .video).first!
    let overlayDuration = try await overlayAsset.load(.duration)
    try overlayTrack.insertTimeRange(CMTimeRange(start: .zero, duration: overlayDuration),
                                      of: overlayVideoTrack, at: .zero)

    // Create video composition
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = outputSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    // Main layer instruction - full frame
    let mainInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: mainTrack)
    mainInstruction.setTransform(.identity, at: .zero)

    // PiP layer instruction - scaled and positioned
    let overlayInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: overlayTrack)

    let pipSize = CGSize(width: outputSize.width * pipScale,
                          height: outputSize.height * pipScale)
    let margin: CGFloat = 20

    let pipOrigin: CGPoint
    switch pipPosition {
    case .topLeft:
        pipOrigin = CGPoint(x: margin, y: margin)
    case .topRight:
        pipOrigin = CGPoint(x: outputSize.width - pipSize.width - margin, y: margin)
    case .bottomLeft:
        pipOrigin = CGPoint(x: margin, y: outputSize.height - pipSize.height - margin)
    case .bottomRight:
        pipOrigin = CGPoint(x: outputSize.width - pipSize.width - margin,
                             y: outputSize.height - pipSize.height - margin)
    }

    let pipTransform = CGAffineTransform(scaleX: pipScale, y: pipScale)
        .concatenating(CGAffineTransform(translationX: pipOrigin.x, y: pipOrigin.y))
    overlayInstruction.setTransform(pipTransform, at: .zero)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    // Order matters: first = bottom, last = top
    instruction.layerInstructions = [mainInstruction, overlayInstruction]

    videoComposition.instructions = [instruction]

    return (composition, videoComposition)
}

enum PiPPosition {
    case topLeft, topRight, bottomLeft, bottomRight
}
```

---

## 7. Split Screen Layouts

### Split Screen Configuration

```swift
enum SplitScreenLayout {
    case sideBySide        // 2 videos, left/right
    case topBottom         // 2 videos, top/bottom
    case threeUp           // 3 videos (1 large + 2 small)
    case quadrant          // 4 videos in 2x2 grid
    case custom([SplitRegion])
}

struct SplitRegion {
    /// Normalized rect within output frame (0-1)
    var frame: CGRect
    /// Track index for this region
    var trackIndex: Int
}

func createSplitScreenTransforms(
    layout: SplitScreenLayout,
    outputSize: CGSize,
    trackCount: Int
) -> [CGAffineTransform] {
    switch layout {
    case .sideBySide:
        let halfWidth = outputSize.width / 2
        return [
            // Left half
            CGAffineTransform(scaleX: 0.5, y: 1.0),
            // Right half
            CGAffineTransform(scaleX: 0.5, y: 1.0)
                .concatenating(CGAffineTransform(translationX: halfWidth, y: 0))
        ]

    case .topBottom:
        let halfHeight = outputSize.height / 2
        return [
            CGAffineTransform(scaleX: 1.0, y: 0.5),
            CGAffineTransform(scaleX: 1.0, y: 0.5)
                .concatenating(CGAffineTransform(translationX: 0, y: halfHeight))
        ]

    case .quadrant:
        let halfW = outputSize.width / 2
        let halfH = outputSize.height / 2
        return [
            // Top-left
            CGAffineTransform(scaleX: 0.5, y: 0.5),
            // Top-right
            CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: halfW, y: 0)),
            // Bottom-left
            CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: 0, y: halfH)),
            // Bottom-right
            CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: halfW, y: halfH))
        ]

    case .threeUp:
        let halfW = outputSize.width / 2
        let halfH = outputSize.height / 2
        return [
            // Large left
            CGAffineTransform(scaleX: 0.5, y: 1.0),
            // Small top-right
            CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: halfW, y: 0)),
            // Small bottom-right
            CGAffineTransform(scaleX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(translationX: halfW, y: halfH))
        ]

    case .custom(let regions):
        return regions.map { region in
            CGAffineTransform(scaleX: region.frame.width, y: region.frame.height)
                .concatenating(CGAffineTransform(
                    translationX: region.frame.origin.x * outputSize.width,
                    y: region.frame.origin.y * outputSize.height
                ))
        }
    }
}
```

---

## 8. Text / Title System

### Approach 1: CIAttributedTextImageGenerator (Recommended for Real-Time)

```swift
func createTextOverlayComposition(
    asset: AVAsset,
    text: String,
    font: NSFont,
    color: NSColor,
    position: CGPoint,
    outputSize: CGSize
) -> AVMutableVideoComposition {

    // Create attributed string
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
    shadow.shadowOffset = CGSize(width: 2, height: -2)
    shadow.shadowBlurRadius = 4

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .shadow: shadow
    ]
    let attributedText = NSAttributedString(string: text, attributes: attributes)

    // Create CIFilter for text generation
    let textFilter = CIFilter.attributedTextImageGenerator()
    textFilter.text = attributedText
    textFilter.scaleFactor = 2.0  // Retina

    let composition = AVMutableVideoComposition(asset: asset) { request in
        let sourceImage = request.sourceImage

        guard let textImage = textFilter.outputImage else {
            request.finish(with: sourceImage, context: nil)
            return
        }

        // Position the text
        let transform = CGAffineTransform(
            translationX: position.x,
            y: position.y
        )
        let positionedText = textImage.transformed(by: transform)

        // Composite text over video
        let composited = positionedText.composited(over: sourceImage)

        request.finish(with: composited, context: nil)
    }

    composition.renderSize = outputSize
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    return composition
}
```

### Approach 2: Core Text + CGContext -> Metal Texture

For maximum control and performance, render text to a shared memory buffer accessible by both CGContext and Metal:

```swift
class TextRenderer {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    /// Render attributed string to a CIImage for compositing
    func renderText(_ attributedString: NSAttributedString,
                     maxSize: CGSize) -> CIImage? {
        // Create Core Text framesetter
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        // Determine text size
        var fitRange = CFRangeMake(0, 0)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRangeMake(0, attributedString.length),
            nil,
            maxSize,
            &fitRange
        )

        let width = Int(ceil(textSize.width))
        let height = Int(ceil(textSize.height))

        guard width > 0, height > 0 else { return nil }

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip coordinate system for Core Text
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // Create frame and draw
        let path = CGPath(rect: CGRect(x: 0, y: 0,
                                        width: CGFloat(width),
                                        height: CGFloat(height)), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)

        // Convert to CIImage
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    /// Render text directly to a Metal texture (shared memory approach)
    func renderTextToTexture(_ attributedString: NSAttributedString,
                              textureSize: CGSize) -> MTLTexture? {
        let width = Int(textureSize.width)
        let height = Int(textureSize.height)

        // Page-aligned allocation for shared GPU/CPU memory
        let pageSize = Int(getpagesize())
        let bytesPerRow = ((width * 4 + pageSize - 1) / pageSize) * pageSize
        let totalBytes = bytesPerRow * height

        // Allocate page-aligned memory
        var rawPointer: UnsafeMutableRawPointer?
        posix_memalign(&rawPointer, pageSize, totalBytes)
        guard let pointer = rawPointer else { return nil }

        // Create Metal buffer from the same memory
        guard let buffer = device.makeBuffer(
            bytesNoCopy: pointer,
            length: totalBytes,
            options: .storageModeShared,
            deallocator: { ptr, _ in free(ptr) }
        ) else {
            free(pointer)
            return nil
        }

        // Create CGContext pointing to same memory
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pointer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw text with Core Text
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0,
                                        width: CGFloat(width),
                                        height: CGFloat(height)), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)

        // Create texture descriptor pointing to the buffer memory
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        return buffer.makeTexture(
            descriptor: descriptor,
            offset: 0,
            bytesPerRow: bytesPerRow
        )
    }
}
```

### Approach 3: AVVideoCompositionCoreAnimationTool (Export Only)

**Important limitation**: This approach works only for offline rendering (export), NOT for real-time preview. Use `AVSynchronizedLayer` for playback.

```swift
func addTextLayerToExport(
    videoComposition: AVMutableVideoComposition,
    videoSize: CGSize,
    text: String,
    font: NSFont,
    position: CGPoint
) {
    // Video layer (where video content renders)
    let videoLayer = CALayer()
    videoLayer.frame = CGRect(origin: .zero, size: videoSize)

    // Parent layer (contains everything)
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: videoSize)

    // Text layer
    let textLayer = CATextLayer()
    textLayer.string = text
    textLayer.font = font
    textLayer.fontSize = font.pointSize
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .center
    textLayer.frame = CGRect(x: position.x, y: position.y, width: 500, height: 100)
    textLayer.contentsScale = 2.0

    // Optional: animate text
    let fadeIn = CABasicAnimation(keyPath: "opacity")
    fadeIn.fromValue = 0.0
    fadeIn.toValue = 1.0
    fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + 1.0
    fadeIn.duration = 0.5
    fadeIn.fillMode = .forwards
    fadeIn.isRemovedOnCompletion = false
    textLayer.add(fadeIn, forKey: "fadeIn")

    // Layer hierarchy: parent > video + text
    parentLayer.addSublayer(videoLayer)
    parentLayer.addSublayer(textLayer)

    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
    )
}
```

---

## 9. Shape Layers & Drawing

### Shape Layer Data Model

```swift
struct ShapeLayer: Codable, Identifiable {
    let id: UUID
    var shapeType: ShapeType
    var fillColor: CodableColor?
    var strokeColor: CodableColor?
    var strokeWidth: CGFloat
    var opacity: CGFloat
    var transform: AnimatedTransform
    var timeRange: CMTimeRange

    enum ShapeType: Codable {
        case rectangle(cornerRadius: CGFloat)
        case ellipse
        case polygon(sides: Int)
        case star(points: Int, innerRadius: CGFloat, outerRadius: CGFloat)
        case bezierPath(points: [BezierPathPoint])
        case line(from: CGPoint, to: CGPoint)
    }
}

struct BezierPathPoint: Codable {
    var point: CGPoint
    var controlIn: CGPoint?   // Incoming tangent handle
    var controlOut: CGPoint?  // Outgoing tangent handle
}
```

### Rendering Shapes via CIImage

```swift
func renderShape(_ shape: ShapeLayer,
                  at time: Double,
                  canvasSize: CGSize) -> CIImage? {
    let width = Int(canvasSize.width)
    let height = Int(canvasSize.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Clear background (transparent)
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))

    // Apply animated transform
    let props = shape.transform.properties(at: time)
    let affine = props.affineTransform(frameSize: canvasSize)
    context.concatenate(affine)

    // Set fill and stroke
    if let fill = shape.fillColor?.nsColor {
        context.setFillColor(fill.cgColor)
    }
    if let stroke = shape.strokeColor?.nsColor {
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(shape.strokeWidth)
    }

    // Draw shape
    let rect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
    switch shape.shapeType {
    case .rectangle(let cornerRadius):
        let path = CGPath(roundedRect: rect.insetBy(dx: 50, dy: 50),
                           cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                           transform: nil)
        context.addPath(path)

    case .ellipse:
        context.addEllipse(in: rect.insetBy(dx: 50, dy: 50))

    case .bezierPath(let points):
        if let first = points.first {
            context.move(to: first.point)
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                if let cp1 = prev.controlOut, let cp2 = curr.controlIn {
                    context.addCurve(to: curr.point, control1: cp1, control2: cp2)
                } else {
                    context.addLine(to: curr.point)
                }
            }
        }

    default: break
    }

    context.setAlpha(props.opacity)
    if shape.fillColor != nil { context.fillPath() }
    if shape.strokeColor != nil { context.strokePath() }

    guard let cgImage = context.makeImage() else { return nil }
    return CIImage(cgImage: cgImage)
}
```

---

## 10. Masking System

### Mask Data Model

```swift
struct MaskDefinition: Codable, Identifiable {
    let id: UUID
    var maskType: MaskType
    var inverted: Bool = false
    var feather: CGFloat = 0         // Blur radius for soft edges
    var expansion: CGFloat = 0       // Expand/contract mask boundary
    var opacity: CGFloat = 1.0
    var blendMode: MaskBlendMode = .add

    enum MaskType: Codable {
        case rectangle(CGRect, cornerRadius: CGFloat)
        case ellipse(CGRect)
        case bezierPath([BezierPathPoint], closed: Bool)
        case gradient(GradientMask)
        case trackingLinked(trackingDataID: UUID)  // Linked to motion tracking data
    }

    enum MaskBlendMode: String, Codable {
        case add          // Union of masks
        case subtract     // Difference
        case intersect    // Intersection
        case lighten      // Max of mask values
        case darken       // Min of mask values
    }
}

struct GradientMask: Codable {
    var startPoint: CGPoint
    var endPoint: CGPoint
    var type: GradientType

    enum GradientType: Codable {
        case linear
        case radial(startRadius: CGFloat, endRadius: CGFloat)
    }
}
```

### Applying Masks with CIFilter

```swift
func applyMask(to sourceImage: CIImage,
                mask: MaskDefinition,
                frameSize: CGSize) -> CIImage {

    // Generate mask image
    var maskImage = generateMaskImage(mask: mask, size: frameSize)

    // Apply feathering (Gaussian blur)
    if mask.feather > 0 {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = maskImage
        blurFilter.radius = Float(mask.feather)
        maskImage = blurFilter.outputImage ?? maskImage
    }

    // Invert if needed
    if mask.inverted {
        let invertFilter = CIFilter.colorInvert()
        invertFilter.inputImage = maskImage
        maskImage = invertFilter.outputImage ?? maskImage
    }

    // Apply mask using CIBlendWithMask
    let blendFilter = CIFilter.blendWithMask()
    blendFilter.inputImage = sourceImage
    blendFilter.backgroundImage = CIImage.clear.cropped(to: sourceImage.extent)
    blendFilter.maskImage = maskImage

    return blendFilter.outputImage ?? sourceImage
}

func generateMaskImage(mask: MaskDefinition, size: CGSize) -> CIImage {
    let width = Int(size.width)
    let height = Int(size.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return CIImage.clear }

    // Black background (masked area)
    context.setFillColor(CGColor.black)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // White = visible area
    context.setFillColor(CGColor.white)

    switch mask.maskType {
    case .rectangle(let rect, let cornerRadius):
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius,
                           cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.fillPath()

    case .ellipse(let rect):
        context.fillEllipse(in: rect)

    case .bezierPath(let points, let closed):
        if let first = points.first {
            context.move(to: first.point)
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                if let cp1 = prev.controlOut, let cp2 = curr.controlIn {
                    context.addCurve(to: curr.point, control1: cp1, control2: cp2)
                } else {
                    context.addLine(to: curr.point)
                }
            }
            if closed { context.closePath() }
            context.fillPath()
        }

    case .gradient(let gradientMask):
        let colors = [CGColor.white, CGColor.black] as CFArray
        let locations: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: colors,
                                         locations: locations) else { break }
        switch gradientMask.type {
        case .linear:
            context.drawLinearGradient(gradient,
                                        start: gradientMask.startPoint,
                                        end: gradientMask.endPoint,
                                        options: [])
        case .radial(let startRadius, let endRadius):
            context.drawRadialGradient(gradient,
                                        startCenter: gradientMask.startPoint,
                                        startRadius: startRadius,
                                        endCenter: gradientMask.endPoint,
                                        endRadius: endRadius,
                                        options: [])
        }

    case .trackingLinked:
        break // Handled by motion tracking system
    }

    guard let cgImage = context.makeImage() else { return CIImage.clear }
    return CIImage(cgImage: cgImage)
}
```

---

## 11. Motion Path Animation

### Overview
Motion paths allow objects to follow a bezier curve for position animation, like After Effects' spatial interpolation.

### Motion Path Data Model

```swift
struct MotionPath: Codable {
    var points: [MotionPathPoint]
    var closed: Bool = false

    struct MotionPathPoint: Codable {
        var position: CGPoint
        var time: Double          // Time at this position (seconds)
        var tangentIn: CGPoint?   // Incoming bezier handle
        var tangentOut: CGPoint?  // Outgoing bezier handle
    }

    /// Sample position at a given time
    func position(at time: Double) -> CGPoint {
        guard points.count >= 2 else {
            return points.first?.position ?? .zero
        }

        let sorted = points.sorted { $0.time < $1.time }

        if time <= sorted.first!.time { return sorted.first!.position }
        if time >= sorted.last!.time { return sorted.last!.position }

        for i in 0..<(sorted.count - 1) {
            let p0 = sorted[i]
            let p1 = sorted[i + 1]

            if time >= p0.time && time <= p1.time {
                let progress = (time - p0.time) / (p1.time - p0.time)

                // Cubic bezier interpolation for spatial path
                let cp0 = p0.position
                let cp1 = p0.tangentOut ?? CGPoint(
                    x: p0.position.x + (p1.position.x - p0.position.x) / 3,
                    y: p0.position.y + (p1.position.y - p0.position.y) / 3
                )
                let cp2 = p1.tangentIn ?? CGPoint(
                    x: p1.position.x - (p1.position.x - p0.position.x) / 3,
                    y: p1.position.y - (p1.position.y - p0.position.y) / 3
                )
                let cp3 = p1.position

                return cubicBezierPoint(t: CGFloat(progress),
                                         p0: cp0, p1: cp1, p2: cp2, p3: cp3)
            }
        }

        return sorted.last!.position
    }
}

/// Evaluate a point on a cubic bezier curve
func cubicBezierPoint(t: CGFloat,
                       p0: CGPoint, p1: CGPoint,
                       p2: CGPoint, p3: CGPoint) -> CGPoint {
    let mt = 1 - t
    let mt2 = mt * mt
    let mt3 = mt2 * mt
    let t2 = t * t
    let t3 = t2 * t

    return CGPoint(
        x: mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x,
        y: mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y
    )
}
```

---

## 12. Speed Curves / Bezier Keyframe Editor UI

### Speed / Time Remapping

```swift
struct SpeedRamp: Codable {
    var keyframes: [SpeedKeyframe]

    struct SpeedKeyframe: Codable {
        var time: Double        // Timeline time (seconds)
        var speed: Double       // Speed multiplier (1.0 = normal, 2.0 = 2x, 0.5 = half)
        var interpolation: InterpolationType
        var controlOut: CGPoint
        var controlIn: CGPoint
    }

    /// Map timeline time to source media time
    func sourceTime(for timelineTime: Double) -> Double {
        guard keyframes.count >= 2 else {
            return timelineTime * (keyframes.first?.speed ?? 1.0)
        }

        let sorted = keyframes.sorted { $0.time < $1.time }
        var sourceTime: Double = 0
        var lastTime = sorted[0].time

        for i in 0..<(sorted.count - 1) {
            let kf0 = sorted[i]
            let kf1 = sorted[i + 1]

            if timelineTime <= kf1.time {
                let segmentProgress = (timelineTime - kf0.time) / (kf1.time - kf0.time)
                let easedProgress = applyInterpolation(
                    type: kf0.interpolation,
                    progress: segmentProgress,
                    controlOut: kf0.controlOut,
                    controlIn: kf1.controlIn
                )
                let avgSpeed = kf0.speed + (kf1.speed - kf0.speed) * easedProgress
                sourceTime += (timelineTime - lastTime) * avgSpeed
                return sourceTime
            }

            // Accumulate source time for completed segments
            let avgSpeed = (kf0.speed + kf1.speed) / 2.0
            sourceTime += (kf1.time - kf0.time) * avgSpeed
            lastTime = kf1.time
        }

        // After last keyframe
        sourceTime += (timelineTime - lastTime) * (sorted.last?.speed ?? 1.0)
        return sourceTime
    }
}
```

### AVFoundation Time Remapping

```swift
// Using scaleTimeRange for simple speed changes
func applySpeedChange(composition: AVMutableComposition,
                       timeRange: CMTimeRange,
                       speedFactor: Double) {
    let newDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: 1.0 / speedFactor)
    composition.scaleTimeRange(timeRange, toDuration: newDuration)
}

// For variable speed: use CMTimeMapping with custom compositor
// Each segment of the video gets its own time mapping
func createVariableSpeedComposition(
    asset: AVAsset,
    speedRamp: SpeedRamp
) async throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    )!

    let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first!
    let duration = try await asset.load(.duration)

    // Insert full clip
    try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: duration),
        of: sourceVideoTrack,
        at: .zero
    )

    // Apply speed changes to segments
    let sortedKeyframes = speedRamp.keyframes.sorted { $0.time < $1.time }

    for i in 0..<(sortedKeyframes.count - 1) {
        let kf0 = sortedKeyframes[i]
        let kf1 = sortedKeyframes[i + 1]
        let avgSpeed = (kf0.speed + kf1.speed) / 2.0

        let startTime = CMTime(seconds: kf0.time, preferredTimescale: 600)
        let segmentDuration = CMTime(seconds: kf1.time - kf0.time, preferredTimescale: 600)
        let newDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1.0 / avgSpeed)

        let range = CMTimeRange(start: startTime, duration: segmentDuration)
        composition.scaleTimeRange(range, toDuration: newDuration)
    }

    return composition
}
```

### Bezier Keyframe Editor UI (SwiftUI)

```swift
struct KeyframeGraphEditor: View {
    @Binding var keyframes: [Keyframe<CGFloat>]
    let timeRange: ClosedRange<Double>
    let valueRange: ClosedRange<CGFloat>

    @State private var draggedKeyframe: UUID?
    @State private var draggedHandle: HandleType?

    enum HandleType {
        case controlIn, controlOut
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, canvasSize in
                // Draw grid
                drawGrid(context: &context, size: canvasSize)

                // Draw interpolation curves between keyframes
                let sortedKFs = keyframes.sorted { $0.time < $1.time }
                for i in 0..<(sortedKFs.count - 1) {
                    drawCurveSegment(
                        context: &context,
                        from: sortedKFs[i],
                        to: sortedKFs[i + 1],
                        size: canvasSize
                    )
                }

                // Draw keyframe diamonds and handles
                for kf in sortedKFs {
                    let point = mapToCanvas(time: kf.time, value: kf.value, size: canvasSize)

                    // Draw bezier handles
                    if kf.interpolation == .bezier {
                        let handleOut = CGPoint(
                            x: point.x + kf.controlPointOut.x * 50,
                            y: point.y - kf.controlPointOut.y * 50
                        )
                        // Handle line
                        var handlePath = Path()
                        handlePath.move(to: point)
                        handlePath.addLine(to: handleOut)
                        context.stroke(handlePath, with: .color(.yellow), lineWidth: 1)

                        // Handle dot
                        context.fill(
                            Path(ellipseIn: CGRect(x: handleOut.x - 4, y: handleOut.y - 4,
                                                    width: 8, height: 8)),
                            with: .color(.yellow)
                        )
                    }

                    // Diamond keyframe marker
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: point.x, y: point.y - 6))
                    diamond.addLine(to: CGPoint(x: point.x + 6, y: point.y))
                    diamond.addLine(to: CGPoint(x: point.x, y: point.y + 6))
                    diamond.addLine(to: CGPoint(x: point.x - 6, y: point.y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.white))
                    context.stroke(diamond, with: .color(.gray), lineWidth: 1)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(location: value.location, size: size)
                    }
                    .onEnded { _ in
                        draggedKeyframe = nil
                        draggedHandle = nil
                    }
            )
        }
        .background(Color.black.opacity(0.8))
    }

    private func mapToCanvas(time: Double, value: CGFloat, size: CGSize) -> CGPoint {
        let x = (time - timeRange.lowerBound) / (timeRange.upperBound - timeRange.lowerBound)
        let y = (value - valueRange.lowerBound) / (valueRange.upperBound - valueRange.lowerBound)
        return CGPoint(x: CGFloat(x) * size.width, y: (1 - y) * size.height)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        // Draw horizontal and vertical grid lines
        let gridColor = Color.gray.opacity(0.3)
        for i in 0...10 {
            let x = CGFloat(i) / 10 * size.width
            let y = CGFloat(i) / 10 * size.height

            var vLine = Path()
            vLine.move(to: CGPoint(x: x, y: 0))
            vLine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vLine, with: .color(gridColor), lineWidth: 0.5)

            var hLine = Path()
            hLine.move(to: CGPoint(x: 0, y: y))
            hLine.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(hLine, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawCurveSegment(context: inout GraphicsContext,
                                    from kf0: Keyframe<CGFloat>,
                                    to kf1: Keyframe<CGFloat>,
                                    size: CGSize) {
        let p0 = mapToCanvas(time: kf0.time, value: kf0.value, size: size)
        let p3 = mapToCanvas(time: kf1.time, value: kf1.value, size: size)

        var path = Path()
        path.move(to: p0)

        switch kf0.interpolation {
        case .linear:
            path.addLine(to: p3)
        case .hold:
            path.addLine(to: CGPoint(x: p3.x, y: p0.y))
            path.addLine(to: p3)
        default:
            // Bezier curve
            let p1 = CGPoint(
                x: p0.x + kf0.controlPointOut.x * (p3.x - p0.x),
                y: p0.y - kf0.controlPointOut.y * (p3.y - p0.y)
            )
            let p2 = CGPoint(
                x: p0.x + kf1.controlPointIn.x * (p3.x - p0.x),
                y: p0.y - kf1.controlPointIn.y * (p3.y - p0.y)
            )
            path.addCurve(to: p3, control1: p1, control2: p2)
        }

        context.stroke(path, with: .color(.green), lineWidth: 2)
    }

    private func handleDrag(location: CGPoint, size: CGSize) {
        // Hit-test keyframes and handles, update positions
        // (Simplified - production code needs proper hit testing)
    }
}
```

---

## 13. 2D Motion Tracking (Vision Framework)

### VNTrackObjectRequest

```swift
import Vision

class MotionTracker {
    private var sequenceHandler = VNSequenceRequestHandler()
    private var currentObservation: VNDetectedObjectObservation?

    /// Track result for a single frame
    struct TrackingResult {
        let boundingBox: CGRect  // Normalized 0-1 coordinates
        let confidence: Float
        let frameTime: CMTime
    }

    /// Initialize tracking with a bounding box in the first frame
    func startTracking(
        initialBoundingBox: CGRect,
        in pixelBuffer: CVPixelBuffer
    ) throws -> TrackingResult {
        // Create initial observation
        let observation = VNDetectedObjectObservation(
            boundingBox: initialBoundingBox
        )
        currentObservation = observation

        // Perform initial tracking request
        let request = VNTrackObjectRequest(detectedObject: observation)
        request.trackingLevel = .accurate

        try sequenceHandler.perform([request], on: pixelBuffer)

        guard let result = request.results?.first as? VNDetectedObjectObservation else {
            throw TrackingError.noResults
        }

        currentObservation = result
        return TrackingResult(
            boundingBox: result.boundingBox,
            confidence: result.confidence,
            frameTime: .zero
        )
    }

    /// Track to the next frame
    func trackNextFrame(
        pixelBuffer: CVPixelBuffer,
        frameTime: CMTime
    ) throws -> TrackingResult {
        guard let observation = currentObservation else {
            throw TrackingError.notInitialized
        }

        let request = VNTrackObjectRequest(detectedObject: observation)
        request.trackingLevel = .accurate

        try sequenceHandler.perform([request], on: pixelBuffer)

        guard let result = request.results?.first as? VNDetectedObjectObservation else {
            throw TrackingError.noResults
        }

        currentObservation = result
        return TrackingResult(
            boundingBox: result.boundingBox,
            confidence: result.confidence,
            frameTime: frameTime
        )
    }

    enum TrackingError: Error {
        case notInitialized
        case noResults
        case trackingLost
    }
}
```

### Full Video Tracking Pipeline

```swift
class VideoTrackingPipeline {
    private let tracker = MotionTracker()

    /// Track an object through an entire video asset
    func trackObject(
        in asset: AVAsset,
        initialBoundingBox: CGRect,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> [MotionTracker.TrackingResult] {

        let reader = try AVAssetReader(asset: asset)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let duration = try await asset.load(.duration)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack,
                                                     outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        var results: [MotionTracker.TrackingResult] = []
        var isFirstFrame = true

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let result: MotionTracker.TrackingResult

            if isFirstFrame {
                result = try tracker.startTracking(
                    initialBoundingBox: initialBoundingBox,
                    in: pixelBuffer
                )
                isFirstFrame = false
            } else {
                result = try tracker.trackNextFrame(
                    pixelBuffer: pixelBuffer,
                    frameTime: presentationTime
                )
            }

            // Check if tracking confidence is too low
            if result.confidence < 0.3 {
                break  // Tracking lost
            }

            results.append(result)

            let progress = presentationTime.seconds / duration.seconds
            progressHandler(min(1.0, progress))
        }

        return results
    }

    /// Convert tracking results to keyframe animation
    func trackingToKeyframes(
        results: [MotionTracker.TrackingResult],
        frameSize: CGSize
    ) -> (KeyframeTrack<CGFloat>, KeyframeTrack<CGFloat>) {

        var xTrack = KeyframeTrack<CGFloat>(keyframes: [])
        var yTrack = KeyframeTrack<CGFloat>(keyframes: [])

        for result in results {
            let centerX = result.boundingBox.midX * frameSize.width
            let centerY = (1 - result.boundingBox.midY) * frameSize.height  // Flip Y

            xTrack.addKeyframe(Keyframe(
                time: result.frameTime.seconds,
                value: centerX,
                interpolation: .smooth
            ))
            yTrack.addKeyframe(Keyframe(
                time: result.frameTime.seconds,
                value: centerY,
                interpolation: .smooth
            ))
        }

        return (xTrack, yTrack)
    }
}
```

### VNGenerateOpticalFlowRequest (Motion Estimation)

```swift
/// Optical flow for per-pixel motion estimation
func computeOpticalFlow(
    from previousBuffer: CVPixelBuffer,
    to currentBuffer: CVPixelBuffer
) throws -> VNPixelBufferObservation? {
    let request = VNGenerateOpticalFlowRequest(
        targetedCVPixelBuffer: currentBuffer
    )
    request.computationAccuracy = .medium

    let handler = VNImageRequestHandler(cvPixelBuffer: previousBuffer)
    try handler.perform([request])

    return request.results?.first as? VNPixelBufferObservation
    // Returns a 2-channel float16 pixel buffer with (dx, dy) per pixel
}
```

---

## 14. CGAffineTransform & CATransform3D for Video

### CGAffineTransform Matrix Structure

```
| a  b  0 |
| c  d  0 |
| tx ty 1 |
```

- `a`, `d` = scale factors (horizontal, vertical)
- `b`, `c` = rotation/shear components
- `tx`, `ty` = translation

### Transform Pipeline for Video

```swift
extension TransformProperties {
    /// Build the complete transform for use in video composition
    /// The standard order is: Anchor -> Scale -> Rotate -> Translate
    func videoTransform(sourceSize: CGSize, outputSize: CGSize) -> CGAffineTransform {
        let ax = anchorPoint.x * sourceSize.width
        let ay = anchorPoint.y * sourceSize.height

        // Center the source in the output
        let centerOffsetX = (outputSize.width - sourceSize.width) / 2
        let centerOffsetY = (outputSize.height - sourceSize.height) / 2

        return CGAffineTransform.identity
            // 1. Move anchor to origin
            .translatedBy(x: -ax, y: -ay)
            // 2. Scale
            .scaledBy(x: scale.width, y: scale.height)
            // 3. Rotate
            .rotated(by: rotation)
            // 4. Move anchor back
            .translatedBy(x: ax, y: ay)
            // 5. Center in output
            .translatedBy(x: centerOffsetX, y: centerOffsetY)
            // 6. Apply position offset
            .translatedBy(x: position.x, y: position.y)
    }
}
```

### Applying Transform in CIImage Pipeline

```swift
func applyTransformToFrame(
    sourceImage: CIImage,
    properties: TransformProperties,
    outputSize: CGSize
) -> CIImage {
    let sourceSize = sourceImage.extent.size
    let transform = properties.videoTransform(sourceSize: sourceSize, outputSize: outputSize)

    var result = sourceImage.transformed(by: transform)

    // Apply opacity
    if properties.opacity < 1.0 {
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = result
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(properties.opacity))
        result = colorMatrix.outputImage ?? result
    }

    return result
}
```

---

## 15. Transform Pipeline in AVVideoComposition

### Built-in Approach: Layer Instructions

```swift
func buildTransformComposition(
    asset: AVAsset,
    transforms: [TimeTransform]
) async throws -> AVMutableVideoComposition {
    let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
    let duration = try await asset.load(.duration)

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = CGSize(width: 1920, height: 1080)
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

    // Apply transform ramps for animation
    for i in 0..<(transforms.count - 1) {
        let current = transforms[i]
        let next = transforms[i + 1]

        let timeRange = CMTimeRange(
            start: CMTime(seconds: current.time, preferredTimescale: 600),
            duration: CMTime(seconds: next.time - current.time, preferredTimescale: 600)
        )

        layerInstruction.setTransformRamp(
            fromStart: current.transform,
            toEnd: next.transform,
            timeRange: timeRange
        )

        // Also animate opacity if needed
        layerInstruction.setOpacityRamp(
            fromStartOpacity: Float(current.opacity),
            toEndOpacity: Float(next.opacity),
            timeRange: timeRange
        )
    }

    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    return videoComposition
}

struct TimeTransform {
    var time: Double
    var transform: CGAffineTransform
    var opacity: CGFloat
}
```

### Custom Compositor Approach (Full Pipeline)

```swift
// Use this for maximum flexibility (multiple layers, effects, masks)
func buildCustomComposition(
    asset: AVAsset,
    animatedTransform: AnimatedTransform,
    outputSize: CGSize
) -> AVMutableVideoComposition {

    let composition = AVMutableVideoComposition(asset: asset) { request in
        let sourceImage = request.sourceImage
        let time = request.compositionTime.seconds

        // Get animated properties at current time
        let props = animatedTransform.properties(at: time)

        // Apply transform
        let sourceSize = sourceImage.extent.size
        let transform = props.videoTransform(sourceSize: sourceSize, outputSize: outputSize)
        var result = sourceImage.transformed(by: transform)

        // Apply opacity
        if props.opacity < 1.0 {
            let colorMatrix = CIFilter.colorMatrix()
            colorMatrix.inputImage = result
            colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(props.opacity))
            result = colorMatrix.outputImage ?? result
        }

        // Crop to output bounds
        result = result.cropped(to: CGRect(origin: .zero, size: outputSize))

        request.finish(with: result, context: nil)
    }

    composition.renderSize = outputSize
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    return composition
}
```

---

## 16. Custom Video Compositor (AVVideoCompositing)

### Full Implementation

Based on Apple's WWDC 2013 Session 612 "Advanced Editing with AV Foundation":

```swift
class CustomVideoCompositor: NSObject, AVVideoCompositing {

    // MARK: - Required Properties

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    // MARK: - State

    private let renderingQueue = DispatchQueue(label: "com.app.compositor.rendering")
    private let renderContextQueue = DispatchQueue(label: "com.app.compositor.context")
    private var renderContext: AVVideoCompositionRenderContext?
    private var shouldCancelAllRequests = false

    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .cacheIntermediates: false
    ])

    // MARK: - AVVideoCompositing Protocol

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextQueue.sync {
            self.renderContext = newRenderContext
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderingQueue.async { [weak self] in
            guard let self = self else { return }

            if self.shouldCancelAllRequests {
                request.finishCancelledRequest()
                return
            }

            // Get render context
            guard let renderContext = self.renderContextQueue.sync(execute: { self.renderContext }) else {
                request.finish(with: NSError(domain: "Compositor", code: -1))
                return
            }

            // Process the frame
            if let outputPixelBuffer = self.newRenderedPixelBuffer(for: request,
                                                                     renderContext: renderContext) {
                request.finish(withComposedVideoFrame: outputPixelBuffer)
            } else {
                request.finish(with: NSError(domain: "Compositor", code: -2))
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        shouldCancelAllRequests = true
        renderingQueue.async { [weak self] in
            self?.shouldCancelAllRequests = false
        }
    }

    // MARK: - Rendering

    private func newRenderedPixelBuffer(
        for request: AVAsynchronousVideoCompositionRequest,
        renderContext: AVVideoCompositionRenderContext
    ) -> CVPixelBuffer? {

        guard let instruction = request.videoCompositionInstruction
                as? CustomCompositionInstruction else {
            return nil
        }

        // Allocate output buffer from pool
        guard let outputBuffer = renderContext.newPixelBuffer() else { return nil }

        let outputSize = renderContext.size

        // Start with transparent background
        var compositeImage = CIImage(color: .clear)
            .cropped(to: CGRect(origin: .zero, size: outputSize))

        // Composite each layer (bottom to top)
        for layerConfig in instruction.layers {
            guard let sourceBuffer = request.sourceFrame(byTrackID: layerConfig.trackID) else {
                continue
            }

            var layerImage = CIImage(cvPixelBuffer: sourceBuffer)
            let currentTime = request.compositionTime.seconds

            // Apply animated transform
            let props = layerConfig.animatedTransform.properties(at: currentTime)
            let transform = props.videoTransform(
                sourceSize: layerImage.extent.size,
                outputSize: outputSize
            )
            layerImage = layerImage.transformed(by: transform)

            // Apply opacity
            if props.opacity < 1.0 {
                let colorMatrix = CIFilter.colorMatrix()
                colorMatrix.inputImage = layerImage
                colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(props.opacity))
                layerImage = colorMatrix.outputImage ?? layerImage
            }

            // Apply crop if any
            if let crop = layerConfig.cropRegion {
                let pixelRect = crop.pixelRect(sourceSize: layerImage.extent.size)
                layerImage = layerImage.cropped(to: pixelRect)
            }

            // Apply mask if any
            if let mask = layerConfig.mask {
                layerImage = applyMask(to: layerImage, mask: mask, frameSize: outputSize)
            }

            // Composite over current result
            compositeImage = layerImage.composited(over: compositeImage)
        }

        // Render to output buffer
        ciContext.render(compositeImage,
                          to: outputBuffer,
                          bounds: CGRect(origin: .zero, size: outputSize),
                          colorSpace: CGColorSpaceCreateDeviceRGB())

        return outputBuffer
    }
}

// MARK: - Custom Instruction

class CustomCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    struct LayerConfig {
        var trackID: CMPersistentTrackID
        var animatedTransform: AnimatedTransform
        var cropRegion: CropRegion?
        var mask: MaskDefinition?
    }

    var layers: [LayerConfig]

    init(timeRange: CMTimeRange, layers: [LayerConfig]) {
        self.timeRange = timeRange
        self.layers = layers
        self.requiredSourceTrackIDs = layers.map { NSValue(bytes: &$0.trackID,
                                                             objCType: "i") }
        super.init()
    }
}
```

### Performance Optimization Flags (from WWDC 2013)

```swift
// In instruction protocol:

// passthroughTrackID: Bypass compositor for frames that don't need processing
// Set to a valid track ID when only one source needs to pass through unchanged
var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

// requiredSourceTrackIDs: Only request needed tracks (nil = ALL tracks)
// ALWAYS set this to avoid unnecessary frame decoding
var requiredSourceTrackIDs: [NSValue]?

// containsTweening: Set false when animation has stopped
// Allows the system to reuse the last rendered frame
var containsTweening: Bool = true
```

---

## 17. VideoLab Framework Architecture Reference

VideoLab (github.com/ruanjx/VideoLab) is a high-performance Swift video editing framework built on AVFoundation + Metal with an After Effects-inspired architecture.

### Key Architecture Concepts

**RenderLayer** - Basic unit (video, image, audio, or pure effect):
- Has `Source` protocol for media input
- Has `timeRange` for timeline position
- Has `transform` for spatial properties
- Has `operations` array for effect chain
- Has `audioConfiguration` for volume/pitch

**RenderComposition** - Top-level container:
- Contains array of `RenderLayer`
- Sets `renderSize`, `frameDuration`
- Supports `CALayer` for vector text animations

**RenderLayerGroup** - Pre-composition (inherits RenderLayer):
- Contains nested group of `RenderLayer`s
- Equivalent to After Effects pre-compose

**KeyframeAnimation** - Animation system:
- `keyPath` - target property path (e.g., `"transform.scale"`)
- `values` - array of values at each keyframe
- `keyTimes` - array of time positions
- `timingFunctions` - easing between keyframes

**Source Protocol**:
```swift
public protocol Source {
    var selectedTimeRange: CMTimeRange { get set }
    func tracks(for type: AVMediaType) -> [AVAssetTrack]
    func texture(at time: CMTime) -> Texture?
}
```

**Rendering Pipeline**:
1. RenderLayers -> AVCompositionTracks (video reuses tracks when non-overlapping)
2. Time intervals -> Instructions (any intersecting VideoRenderLayer becomes a blend parameter)
3. Rendering order: bottom-up (process own texture, then blend into previous)
4. AudioRenderLayers -> MTAudioProcessingTap for real-time processing

---

## 18. WWDC Sessions & References

### Essential WWDC Sessions

- **WWDC 2013, Session 612**: "Advanced Editing with AV Foundation" - Custom compositors, AVVideoCompositing protocol, render pipeline access, passthroughTrackID/requiredSourceTrackIDs/containsTweening optimization flags
- **WWDC 2015, Session 506**: "Editing Movies in AV Foundation" - New movie file editing classes
- **WWDC 2020, Session 10009**: "Edit and play back HDR video with AVFoundation" - HDR custom compositors, CIFilter pipeline
- **WWDC 2021**: "What's new in AVFoundation" - Per-frame metadata in custom compositor callbacks
- **WWDC 2022, Session 10114**: "Display EDR content with Core Image, Metal, and SwiftUI"
- **WWDC 2023, Session 10157**: "Wind your way through advanced animations in SwiftUI" - CubicKeyframe, Catmull-Rom splines

### Key Apple Documentation

- `AVMutableVideoCompositionLayerInstruction` - setTransform, setTransformRamp, setCropRectangle, setCropRectangleRamp, setOpacity, setOpacityRamp
- `AVVideoCompositing` protocol - startRequest, renderContextChanged, sourcePixelBufferAttributes
- `AVVideoCompositionCoreAnimationTool` - CALayer integration (export only, use AVSynchronizedLayer for playback)
- `VNTrackObjectRequest` / `VNTrackRectangleRequest` - Object tracking
- `VNGenerateOpticalFlowRequest` - Per-pixel motion estimation
- `CIAttributedTextImageGenerator` - Text rendering to CIImage
- `CIBlendWithMask` / `CIBlendWithAlphaMask` - Mask compositing

### Open-Source References

- **VideoLab** (github.com/ruanjx/VideoLab) - AE-like Swift video composition framework with keyframe animation, Metal rendering, layer groups
- **Cabbage** (github.com/VideoFlint/Cabbage) - Swift video editing framework with transitions
- **AVCustomEdit** - Apple sample code for custom compositors with Metal
- **BezierKit** (github.com/hfutrell/BezierKit) - Cubic/quadratic bezier curves in Swift
- **Easing** (github.com/manuelCarlos/Easing) - Complete easing functions library in Swift
- **MetalPetal** (github.com/MetalPetal/MetalPetal) - GPU-accelerated image/video processing
- **shared-graphics-tools** (github.com/computer-graphics-tools/shared-graphics-tools) - MTLSharedGraphicsBuffer for CGContext+Metal shared memory

### Shared Memory Pattern (CGContext + Metal)

For rendering text/shapes to video with zero-copy GPU access:
1. Allocate page-aligned memory with `posix_memalign`
2. Create `MTLBuffer` with `makeBuffer(bytesNoCopy:)` pointing to that memory
3. Create `CGContext` with `CGContext(data:)` pointing to same memory
4. Draw with Core Text/Core Graphics on CPU
5. Create `MTLTexture` from buffer with `buffer.makeTexture(descriptor:offset:bytesPerRow:)`
6. Use texture in Metal pipeline - zero copy between CPU and GPU

**Key consideration**: Synchronize CPU/GPU access - do not read from Metal while CoreGraphics is writing.

---

## Summary: Recommended Architecture for NLE Transform Pipeline

1. **Data Model**: Use `AnimatedTransform` with per-property `KeyframeTrack`s supporting multiple interpolation types
2. **Interpolation Engine**: Implement `CubicBezierTimingFunction` with Newton's method solver for accurate bezier evaluation
3. **Rendering**: Use `AVMutableVideoComposition` with CIImage handler for single-track, or custom `AVVideoCompositing` for multi-track
4. **Text Rendering**: Use `CIAttributedTextImageGenerator` for simple text, or Core Text + shared memory buffer for complex typography
5. **Masking**: Generate mask images via CGContext, apply with `CIBlendWithMask`
6. **Motion Tracking**: Use Vision's `VNTrackObjectRequest` for bounding box tracking, `VNGenerateOpticalFlowRequest` for dense motion
7. **Keyframe UI**: SwiftUI Canvas with drag gestures for bezier handle manipulation
8. **Performance**: Always set `requiredSourceTrackIDs`, `passthroughTrackID`, and `containsTweening` flags on instructions
