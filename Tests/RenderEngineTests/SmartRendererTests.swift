import XCTest
@testable import RenderEngine
@testable import CoreMediaPlus

final class SmartRendererTests: XCTestCase {

    let renderer = SmartRenderer()

    // MARK: - Passthrough Tests

    func testPassthroughWhenAllMatch() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .h264,
            width: 1920,
            height: 1080
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].isPassthrough)
    }

    func testReencodeWhenCodecMismatch() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .h264,
            width: 1920,
            height: 1080
        )
        let format = ExportFormat(codec: .hevc, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertEqual(segments.count, 1)
        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenResolutionMismatch() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .h264,
            width: 3840,
            height: 2160
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenEffectsApplied() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(5, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            hasEffects: true
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenTransformApplied() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(5, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            hasTransform: true
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenOpacityReduced() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(5, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            opacity: 0.5
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenNonNormalBlendMode() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(5, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            blendMode: .multiply
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    func testReencodeWhenComposited() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(5, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            isComposited: true
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)

        XCTAssertFalse(segments[0].isPassthrough)
    }

    // MARK: - Multiple Clips

    func testMixedPassthroughAndReencode() {
        let passthroughClip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .hevc,
            width: 1920,
            height: 1080
        )
        let reencodeClip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: Rational(10, 1), duration: Rational(5, 1)),
            codec: .hevc,
            width: 1920,
            height: 1080,
            hasEffects: true
        )
        let format = ExportFormat(codec: .hevc, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [passthroughClip, reencodeClip], outputFormat: format)

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].isPassthrough)
        XCTAssertFalse(segments[1].isPassthrough)
    }

    // MARK: - Passthrough Ratio

    func testPassthroughRatioAllPassthrough() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .h264,
            width: 1920,
            height: 1080
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)
        let ratio = renderer.passthroughRatio(segments: segments)

        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    func testPassthroughRatioNonePassthrough() {
        let clip = SourceClipInfo(
            clipID: UUID(),
            timeRange: TimeRange(start: .zero, duration: Rational(10, 1)),
            codec: .h264,
            width: 1920,
            height: 1080,
            hasEffects: true
        )
        let format = ExportFormat(codec: .h264, width: 1920, height: 1080, frameRate: Rational(30, 1))
        let segments = renderer.analyze(clips: [clip], outputFormat: format)
        let ratio = renderer.passthroughRatio(segments: segments)

        XCTAssertEqual(ratio, 0.0, accuracy: 0.001)
    }

    func testPassthroughRatioEmpty() {
        let ratio = renderer.passthroughRatio(segments: [])
        XCTAssertEqual(ratio, 0.0)
    }
}
