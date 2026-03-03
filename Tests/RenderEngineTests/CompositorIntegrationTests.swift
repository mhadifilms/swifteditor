@preconcurrency import AVFoundation
import XCTest
@testable import RenderEngine
@testable import CoreMediaPlus
@testable import EffectsEngine

// MARK: - CompositionBuilder Instruction Generation Tests

final class CompositionBuilderInstructionTests: XCTestCase {

    let builder = CompositionBuilder()

    func testEmptyTracksProduceNoInstructions() async throws {
        let result = try await builder.buildComposition(
            videoTracks: [],
            audioTracks: [],
            renderSize: CGSize(width: 1920, height: 1080),
            frameDuration: CMTime(value: 1, timescale: 24)
        )

        XCTAssertTrue(result.videoComposition.instructions.isEmpty)
        XCTAssertNil(result.audioMix)
    }

    func testEmptyClipsProduceNoInstructions() async throws {
        let videoTracks = [
            CompositionBuilder.TrackBuildData(trackID: UUID(), clips: []),
        ]

        let result = try await builder.buildComposition(
            videoTracks: videoTracks,
            audioTracks: [],
            renderSize: CGSize(width: 1920, height: 1080),
            frameDuration: CMTime(value: 1, timescale: 24)
        )

        XCTAssertTrue(result.videoComposition.instructions.isEmpty)
    }

    func testVideoCompositionUsesMetalCompositor() async throws {
        let result = try await builder.buildComposition(
            videoTracks: [],
            audioTracks: [],
            renderSize: CGSize(width: 1920, height: 1080),
            frameDuration: CMTime(value: 1, timescale: 24)
        )

        XCTAssertTrue(result.videoComposition.customVideoCompositorClass === MetalCompositor.self)
    }

    func testRenderSizeAndFrameDuration() async throws {
        let renderSize = CGSize(width: 3840, height: 2160)
        let frameDuration = CMTime(value: 1, timescale: 60)

        let result = try await builder.buildComposition(
            videoTracks: [],
            audioTracks: [],
            renderSize: renderSize,
            frameDuration: frameDuration
        )

        XCTAssertEqual(result.videoComposition.renderSize, renderSize)
        XCTAssertEqual(result.videoComposition.frameDuration, frameDuration)
    }

    // MARK: - ClipBuildData

    func testClipBuildDataDuration() {
        let clip = CompositionBuilder.ClipBuildData(
            clipID: UUID(),
            asset: nil,
            startTime: Rational(0, 600),
            sourceIn: Rational(600, 600),
            sourceOut: Rational(3600, 600)
        )

        // 3600/600 - 600/600 = 3000/600 = 5/1
        XCTAssertEqual(clip.duration, Rational(5, 1))
    }

    func testClipBuildDataDefaults() {
        let clip = CompositionBuilder.ClipBuildData(
            clipID: UUID(),
            asset: nil,
            startTime: .zero,
            sourceIn: .zero,
            sourceOut: Rational(1, 1)
        )

        XCTAssertNil(clip.effectStack)
        XCTAssertEqual(clip.volume, 1.0)
        XCTAssertEqual(clip.opacity, 1.0)
        XCTAssertEqual(clip.blendMode, .normal)
    }

    func testClipBuildDataCustomValues() {
        let stack = EffectStack()
        let clip = CompositionBuilder.ClipBuildData(
            clipID: UUID(),
            asset: nil,
            startTime: .zero,
            sourceIn: .zero,
            sourceOut: Rational(1, 1),
            effectStack: stack,
            volume: 0.5,
            opacity: 0.7,
            blendMode: .multiply
        )

        XCTAssertNotNil(clip.effectStack)
        XCTAssertEqual(clip.volume, 0.5)
        XCTAssertEqual(clip.opacity, 0.7)
        XCTAssertEqual(clip.blendMode, .multiply)
    }

    // MARK: - CompositionResult Structure

    func testCompositionResultContainsAllComponents() async throws {
        let result = try await builder.buildComposition(
            videoTracks: [],
            audioTracks: [],
            renderSize: CGSize(width: 1920, height: 1080),
            frameDuration: CMTime(value: 1, timescale: 24)
        )

        // Verify all parts of the result are present
        XCTAssertNotNil(result.composition)
        XCTAssertNotNil(result.videoComposition)
        // audioMix is nil when there are no audio tracks
        XCTAssertNil(result.audioMix)
    }
}
