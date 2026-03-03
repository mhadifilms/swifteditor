import Foundation
import Testing

@testable import CoreMediaPlus
@testable import EffectsEngine

@Suite("TrackingData Interpolation Tests")
struct TrackingDataInterpolationTests {

    static let sampleData = TrackingData(samples: [
        TrackingResult(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            confidence: 1.0,
            time: Rational(0, 1)
        ),
        TrackingResult(
            boundingBox: CGRect(x: 0.5, y: 0.6, width: 0.1, height: 0.2),
            confidence: 0.5,
            time: Rational(10, 1)
        ),
    ])

    @Test("Empty tracking data returns zero")
    func emptyData() {
        let data = TrackingData()
        let pos = data.positionAt(time: Rational(5, 1))
        #expect(pos.x == 0)
        #expect(pos.y == 0)

        let scale = data.scaleAt(time: Rational(5, 1))
        #expect(scale.width == 0)
        #expect(scale.height == 0)
    }

    @Test("Position at first sample time")
    func positionAtStart() {
        let pos = Self.sampleData.positionAt(time: Rational(0, 1))
        // Center of CGRect(0.1, 0.2, 0.3, 0.4) = (0.25, 0.4)
        #expect(abs(pos.x - 0.25) < 0.001)
        #expect(abs(pos.y - 0.4) < 0.001)
    }

    @Test("Position at last sample time")
    func positionAtEnd() {
        let pos = Self.sampleData.positionAt(time: Rational(10, 1))
        // Center of CGRect(0.5, 0.6, 0.1, 0.2) = (0.55, 0.7)
        #expect(abs(pos.x - 0.55) < 0.001)
        #expect(abs(pos.y - 0.7) < 0.001)
    }

    @Test("Position interpolated at midpoint")
    func positionAtMidpoint() {
        let pos = Self.sampleData.positionAt(time: Rational(5, 1))
        // Midpoint bounding box: lerp between (0.1,0.2,0.3,0.4) and (0.5,0.6,0.1,0.2) at t=0.5
        // x: 0.1 + 0.2 = 0.3, y: 0.2 + 0.2 = 0.4, w: 0.3 - 0.1 = 0.2, h: 0.4 - 0.1 = 0.3
        // Center: (0.3 + 0.2/2, 0.4 + 0.3/2) = (0.4, 0.55)
        #expect(abs(pos.x - 0.4) < 0.001)
        #expect(abs(pos.y - 0.55) < 0.001)
    }

    @Test("Before first sample clamps to first")
    func beforeFirstSample() {
        let box = Self.sampleData.boundingBoxAt(time: Rational(-5, 1))
        #expect(abs(box.origin.x - 0.1) < 0.001)
        #expect(abs(box.origin.y - 0.2) < 0.001)
    }

    @Test("After last sample clamps to last")
    func afterLastSample() {
        let box = Self.sampleData.boundingBoxAt(time: Rational(20, 1))
        #expect(abs(box.origin.x - 0.5) < 0.001)
        #expect(abs(box.origin.y - 0.6) < 0.001)
    }

    @Test("Scale interpolation at midpoint")
    func scaleAtMidpoint() {
        let scale = Self.sampleData.scaleAt(time: Rational(5, 1))
        // Width: lerp(0.3, 0.1, 0.5) = 0.2
        // Height: lerp(0.4, 0.2, 0.5) = 0.3
        #expect(abs(scale.width - 0.2) < 0.001)
        #expect(abs(scale.height - 0.3) < 0.001)
    }

    @Test("Confidence interpolation")
    func confidenceInterpolation() {
        let conf = Self.sampleData.confidenceAt(time: Rational(5, 1))
        // lerp(1.0, 0.5, 0.5) = 0.75
        #expect(abs(conf - 0.75) < 0.001)
    }

    @Test("Single sample returns constant for any time")
    func singleSample() {
        let data = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5),
                confidence: 0.9,
                time: Rational(5, 1)
            ),
        ])
        let pos = data.positionAt(time: Rational(100, 1))
        #expect(abs(pos.x - 0.4) < 0.001)  // 0.2 + 0.4/2
        #expect(abs(pos.y - 0.55) < 0.001)  // 0.3 + 0.5/2
    }
}

@Suite("LinkedEffect Tests")
struct LinkedEffectTests {

    @Test("Evaluate with position links")
    func evaluatePositionLinks() {
        let tracking = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                confidence: 1.0,
                time: Rational(0, 1)
            ),
            TrackingResult(
                boundingBox: CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2),
                confidence: 1.0,
                time: Rational(10, 1)
            ),
        ])

        let linked = LinkedEffect(
            effectPluginID: "builtin.blur",
            baseParameters: ["radius": .float(5.0)],
            trackingData: tracking,
            links: [
                TrackingLink(source: .positionX, targetParameter: "centerX"),
                TrackingLink(source: .positionY, targetParameter: "centerY"),
            ]
        )

        let params = linked.evaluateAt(time: Rational(5, 1))

        // At t=5 midpoint: posX center = lerp(0.1, 0.9, 0.5) = 0.5
        if case .float(let cx) = params["centerX"] {
            #expect(abs(cx - 0.5) < 0.001)
        } else {
            Issue.record("Expected float for centerX")
        }

        if case .float(let cy) = params["centerY"] {
            #expect(abs(cy - 0.5) < 0.001)
        } else {
            Issue.record("Expected float for centerY")
        }

        // Base parameter should be preserved
        #expect(params["radius"] == .float(5.0))
    }

    @Test("Evaluate with scale and offset")
    func evaluateWithScaleAndOffset() {
        let tracking = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
                confidence: 0.8,
                time: Rational(0, 1)
            ),
        ])

        let linked = LinkedEffect(
            effectPluginID: "test",
            trackingData: tracking,
            links: [
                TrackingLink(source: .scaleX, targetParameter: "zoom", scale: 2.0, offset: 1.0),
            ]
        )

        let params = linked.evaluateAt(time: Rational(0, 1))
        // scaleX = 0.5, final = 0.5 * 2.0 + 1.0 = 2.0
        if case .float(let zoom) = params["zoom"] {
            #expect(abs(zoom - 2.0) < 0.001)
        } else {
            Issue.record("Expected float for zoom")
        }
    }

    @Test("Tracking link overrides base parameter")
    func trackingOverridesBase() {
        let tracking = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.4),
                confidence: 1.0,
                time: Rational(0, 1)
            ),
        ])

        let linked = LinkedEffect(
            effectPluginID: "test",
            baseParameters: ["posX": .float(999.0)],
            trackingData: tracking,
            links: [
                TrackingLink(source: .positionX, targetParameter: "posX"),
            ]
        )

        let params = linked.evaluateAt(time: Rational(0, 1))
        // positionX center = 0.0 + 0.4/2 = 0.2, should override 999.0
        if case .float(let v) = params["posX"] {
            #expect(abs(v - 0.2) < 0.001)
        } else {
            Issue.record("Expected float for posX")
        }
    }

    @Test("Confidence link evaluation")
    func confidenceLink() {
        let tracking = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
                confidence: 0.6,
                time: Rational(0, 1)
            ),
        ])

        let linked = LinkedEffect(
            effectPluginID: "test",
            trackingData: tracking,
            links: [
                TrackingLink(source: .confidence, targetParameter: "opacity"),
            ]
        )

        let params = linked.evaluateAt(time: Rational(0, 1))
        if case .float(let opacity) = params["opacity"] {
            #expect(abs(opacity - 0.6) < 0.01)
        } else {
            Issue.record("Expected float for opacity")
        }
    }
}

@Suite("TrackingResult Serialization Tests")
struct TrackingResultSerializationTests {

    @Test("TrackingResult round-trips through JSON")
    func trackingResultCodable() throws {
        let original = TrackingResult(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            confidence: 0.95,
            time: Rational(5, 600)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrackingResult.self, from: data)

        #expect(decoded == original)
    }

    @Test("TrackingData round-trips through JSON")
    func trackingDataCodable() throws {
        let original = TrackingData(samples: [
            TrackingResult(
                boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
                confidence: 1.0,
                time: Rational(0, 1)
            ),
            TrackingResult(
                boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25),
                confidence: 0.7,
                time: Rational(30, 1)
            ),
        ])

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrackingData.self, from: data)

        #expect(decoded == original)
    }

    @Test("TrackingLink round-trips through JSON")
    func trackingLinkCodable() throws {
        let original = TrackingLink(
            source: .positionX,
            targetParameter: "centerX",
            scale: 1920.0,
            offset: -960.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrackingLink.self, from: data)

        #expect(decoded == original)
    }
}
