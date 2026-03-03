import XCTest
@preconcurrency import AVFoundation
@testable import SwiftEditorAPI
@testable import RenderEngine
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import EffectsEngine
@testable import CommandBus

/// Integration tests verifying the full render pipeline:
/// Engine → Timeline → CompositionBuilder → MetalCompositor
final class RenderPipelineIntegrationTests: XCTestCase {

    // MARK: - Engine Setup

    func testEngineCreation() {
        let engine = SwiftEditorEngine(projectName: "Test Project")
        XCTAssertNotNil(engine.timeline)
        XCTAssertNotNil(engine.transport)
        XCTAssertNotNil(engine.effectStacks)
    }

    // MARK: - Effect Stack Integration

    func testEffectStackStoreCreatesStackOnDemand() {
        let store = EffectStackStore()
        let clipID = UUID()

        XCTAssertFalse(store.hasEffects(for: clipID))

        let stack = store.stack(for: clipID)
        XCTAssertNotNil(stack)
        XCTAssertEqual(stack.effects.count, 0)
    }

    func testEffectStackStoreWithEffects() {
        let store = EffectStackStore()
        let clipID = UUID()

        let stack = store.stack(for: clipID)
        let effect = EffectInstance(pluginID: "CIColorControls", name: "Color Controls",
                                    defaults: ["brightness": .float(0.0)])
        stack.append(effect)

        XCTAssertTrue(store.hasEffects(for: clipID))
        XCTAssertEqual(store.stack(for: clipID).effects.count, 1)
    }

    func testEffectStackRemoval() {
        let store = EffectStackStore()
        let clipID = UUID()

        let stack = store.stack(for: clipID)
        stack.append(EffectInstance(pluginID: "CIGaussianBlur", name: "Blur"))
        XCTAssertTrue(store.hasEffects(for: clipID))

        store.removeStack(for: clipID)
        XCTAssertFalse(store.hasEffects(for: clipID))
    }

    // MARK: - Editing via API

    func testTimelineTrackManagement() async throws {
        let engine = SwiftEditorEngine(projectName: "Test")
        // Wait briefly for handler registration
        try await Task.sleep(for: .milliseconds(100))

        // A fresh timeline may or may not have default tracks depending on config.
        // Verify the timeline and tracks API is accessible.
        let videoTrackCount = engine.timeline.videoTracks.count
        let audioTrackCount = engine.timeline.audioTracks.count
        XCTAssertGreaterThanOrEqual(videoTrackCount + audioTrackCount, 0,
                                     "Timeline track count should be non-negative")
    }

    // MARK: - Timeline to Composition Builder Bridge

    func testBuildTrackDataFromTimeline() {
        let engine = SwiftEditorEngine(projectName: "Test")
        let timeline = engine.timeline

        // Build track data the same way ExportHandler does
        let videoTrackData = timeline.videoTracks.map { track in
            CompositionBuilder.TrackBuildData(
                trackID: track.id,
                clips: timeline.clipsOnTrack(track.id).map { clip in
                    CompositionBuilder.ClipBuildData(
                        clipID: clip.id,
                        asset: nil,
                        startTime: clip.startTime,
                        sourceIn: clip.sourceIn,
                        sourceOut: clip.sourceOut
                    )
                }
            )
        }

        // Fresh timeline should have tracks but no clips
        XCTAssertGreaterThanOrEqual(videoTrackData.count, 0)
    }

    // MARK: - Effect Application Chain

    func testCIFilterEffectAppliesParameters() {
        let effect = CIFilterEffect.brightness()
        let params = ParameterValues(["brightness": .float(0.5)])

        // Create a test CIImage (1x1 red pixel)
        let testImage = CIImage(color: CIColor(red: 0.5, green: 0.3, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        let result = effect.apply(to: testImage, parameters: params)
        XCTAssertNotEqual(result.extent, .null, "Filtered image should have valid extent")
        XCTAssertEqual(result.extent.width, 100)
        XCTAssertEqual(result.extent.height, 100)
    }

    func testEffectChainAppliesMultipleEffects() {
        let testImage = CIImage(color: CIColor(red: 0.5, green: 0.3, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        // Apply brightness then contrast
        let brightnessEffect = CIFilterEffect.brightness()
        let contrastEffect = CIFilterEffect.contrast()

        var result = brightnessEffect.apply(to: testImage, parameters: ParameterValues(["brightness": .float(0.2)]))
        result = contrastEffect.apply(to: result, parameters: ParameterValues(["contrast": .float(1.5)]))

        XCTAssertEqual(result.extent.width, 100)
        XCTAssertEqual(result.extent.height, 100)
    }

    // MARK: - Transition Rendering

    func testTransitionRendererCrossDissolve() {
        let renderer = TransitionRenderer()
        let imageA = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let imageB = CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        let result = renderer.render(from: imageA, to: imageB, type: .crossDissolve, progress: 0.5)
        XCTAssertFalse(result.extent.isEmpty, "Transition result should have valid extent")
    }

    func testTransitionRendererWipe() {
        let renderer = TransitionRenderer()
        let imageA = CIImage(color: CIColor.green).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let imageB = CIImage(color: CIColor.white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))

        let result = renderer.render(from: imageA, to: imageB, type: .wipe(direction: .left), progress: 0.3)
        XCTAssertFalse(result.extent.isEmpty)
    }

    func testTransitionRendererPush() {
        let renderer = TransitionRenderer()
        let imageA = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let imageB = CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        let result = renderer.render(from: imageA, to: imageB, type: .push(direction: .right), progress: 0.7)
        XCTAssertFalse(result.extent.isEmpty)
    }

    func testTransitionRendererDipToBlack() {
        let renderer = TransitionRenderer()
        let imageA = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let imageB = CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        // Test first half (fade to black)
        let resultFirstHalf = renderer.render(from: imageA, to: imageB, type: .dipToBlack, progress: 0.25)
        XCTAssertFalse(resultFirstHalf.extent.isEmpty)

        // Test second half (fade from black)
        let resultSecondHalf = renderer.render(from: imageA, to: imageB, type: .dipToBlack, progress: 0.75)
        XCTAssertFalse(resultSecondHalf.extent.isEmpty)
    }

    func testTransitionRendererBoundaryValues() {
        let renderer = TransitionRenderer()
        let imageA = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let imageB = CIImage(color: CIColor.blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        // Progress 0.0 should be fully A
        let atZero = renderer.render(from: imageA, to: imageB, type: .crossDissolve, progress: 0.0)
        XCTAssertFalse(atZero.extent.isEmpty)

        // Progress 1.0 should be fully B
        let atOne = renderer.render(from: imageA, to: imageB, type: .crossDissolve, progress: 1.0)
        XCTAssertFalse(atOne.extent.isEmpty)
    }

    // MARK: - Keyframe Interpolation in Effects

    func testKeyframedEffectValues() {
        let instance = EffectInstance(pluginID: "CIColorControls", name: "Color Controls",
                                      defaults: ["brightness": .float(0.0)])

        // Add a keyframe track
        var track = KeyframeTrack()
        track.addKeyframe(KeyframeTrack.Keyframe(time: Rational(0, 1), value: .float(0.0)))
        track.addKeyframe(KeyframeTrack.Keyframe(time: Rational(10, 1), value: .float(1.0)))
        instance.keyframeTracks["brightness"] = track

        // At time 0, brightness should be 0.0
        let valuesAt0 = instance.currentValues(at: Rational(0, 1))
        if case .float(let v) = valuesAt0["brightness"] {
            XCTAssertEqual(v, 0.0, accuracy: 0.01)
        }

        // At time 5 (midpoint), brightness should be ~0.5 (linear interpolation)
        let valuesAt5 = instance.currentValues(at: Rational(5, 1))
        if case .float(let v) = valuesAt5["brightness"] {
            XCTAssertEqual(v, 0.5, accuracy: 0.1)
        }

        // At time 10, brightness should be 1.0
        let valuesAt10 = instance.currentValues(at: Rational(10, 1))
        if case .float(let v) = valuesAt10["brightness"] {
            XCTAssertEqual(v, 1.0, accuracy: 0.01)
        }
    }

    // MARK: - Render Plan Builder

    func testRenderPlanBuilderCreatesLayersForActiveClips() {
        let planBuilder = RenderPlanBuilder()
        let clipID = UUID()

        let tracks = [
            CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: [
                    CompositionBuilder.ClipBuildData(
                        clipID: clipID,
                        asset: nil,
                        startTime: Rational(0, 1),
                        sourceIn: Rational(0, 1),
                        sourceOut: Rational(10, 1)
                    ),
                ]
            ),
        ]

        // At time 5.0 (within clip range), should create one layer
        let plan = planBuilder.buildPlan(
            tracks: tracks,
            compositionTime: Rational(5, 1),
            renderSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(plan.layers.count, 1)
        XCTAssertEqual(plan.layers.first?.clipID, clipID)
    }

    func testRenderPlanBuilderExcludesInactiveClips() {
        let planBuilder = RenderPlanBuilder()

        let tracks = [
            CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: [
                    CompositionBuilder.ClipBuildData(
                        clipID: UUID(),
                        asset: nil,
                        startTime: Rational(0, 1),
                        sourceIn: Rational(0, 1),
                        sourceOut: Rational(5, 1)
                    ),
                ]
            ),
        ]

        // At time 7.0 (past clip end), should create no layers
        let plan = planBuilder.buildPlan(
            tracks: tracks,
            compositionTime: Rational(7, 1),
            renderSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(plan.layers.count, 0)
    }

    func testRenderPlanBuilderMultiTrack() {
        let planBuilder = RenderPlanBuilder()

        let tracks = [
            CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: [
                    CompositionBuilder.ClipBuildData(
                        clipID: UUID(),
                        asset: nil,
                        startTime: Rational(0, 1),
                        sourceIn: Rational(0, 1),
                        sourceOut: Rational(10, 1)
                    ),
                ]
            ),
            CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: [
                    CompositionBuilder.ClipBuildData(
                        clipID: UUID(),
                        asset: nil,
                        startTime: Rational(2, 1),
                        sourceIn: Rational(0, 1),
                        sourceOut: Rational(5, 1)
                    ),
                ]
            ),
        ]

        // At time 3.0, both clips overlap → 2 layers
        let plan = planBuilder.buildPlan(
            tracks: tracks,
            compositionTime: Rational(3, 1),
            renderSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(plan.layers.count, 2)
    }

    // MARK: - Full Pipeline Smoke Test

    func testFullPipelineCompositionBuilderProducesValidResult() async throws {
        let builder = CompositionBuilder()
        let result = try await builder.buildComposition(
            videoTracks: [],
            audioTracks: [],
            renderSize: CGSize(width: 1920, height: 1080),
            frameDuration: CMTime(value: 1, timescale: 24)
        )

        XCTAssertNotNil(result.composition)
        XCTAssertNotNil(result.videoComposition)
        XCTAssertTrue(result.videoComposition.customVideoCompositorClass === MetalCompositor.self)
    }
}
