import XCTest
@testable import RenderEngine
@testable import CoreMediaPlus
@testable import EffectsEngine
@preconcurrency import AVFoundation

final class CompositorInstructionTests: XCTestCase {

    // MARK: - CompositorInstruction

    func testInstructionCreation() {
        let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 5, preferredTimescale: 600))
        let trackIDs: [CMPersistentTrackID] = [1, 2]
        let layers = [
            LayerInstruction(trackID: 1, clipID: UUID()),
            LayerInstruction(trackID: 2, clipID: UUID(), opacity: 0.5, blendMode: .screen),
        ]

        let instruction = CompositorInstruction(
            timeRange: timeRange,
            sourceTrackIDs: trackIDs,
            layerInstructions: layers
        )

        XCTAssertEqual(instruction.timeRange, timeRange)
        XCTAssertEqual(instruction.layerInstructions.count, 2)
        XCTAssertEqual(instruction.requiredSourceTrackIDs?.count, 2)
        XCTAssertNil(instruction.transitionInfo)
        XCTAssertTrue(instruction.enablePostProcessing)
        XCTAssertTrue(instruction.containsTweening)
    }

    func testInstructionWithTransition() {
        let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let transition = TransitionInfo(
            type: .crossDissolve,
            progress: 0.5,
            fromTrackID: 1,
            toTrackID: 2
        )

        let instruction = CompositorInstruction(
            timeRange: timeRange,
            sourceTrackIDs: [1, 2],
            layerInstructions: [
                LayerInstruction(trackID: 1, clipID: UUID()),
                LayerInstruction(trackID: 2, clipID: UUID()),
            ],
            transitionInfo: transition
        )

        XCTAssertNotNil(instruction.transitionInfo)
        XCTAssertEqual(instruction.transitionInfo?.progress, 0.5)
    }

    // MARK: - LayerInstruction

    func testLayerInstructionDefaults() {
        let clipID = UUID()
        let layer = LayerInstruction(trackID: 1, clipID: clipID)

        XCTAssertEqual(layer.trackID, 1)
        XCTAssertEqual(layer.clipID, clipID)
        XCTAssertEqual(layer.opacity, 1.0)
        XCTAssertEqual(layer.blendMode, .normal)
        XCTAssertNil(layer.effectStack)
    }

    func testLayerInstructionWithEffects() {
        let stack = EffectStack()
        let effect = EffectInstance(pluginID: "CIColorControls", name: "Color Controls",
                                    defaults: ["brightness": .float(0.5)])
        stack.append(effect)

        let layer = LayerInstruction(
            trackID: 1, clipID: UUID(),
            opacity: 0.8, blendMode: .multiply,
            effectStack: stack
        )

        XCTAssertEqual(layer.opacity, 0.8)
        XCTAssertEqual(layer.blendMode, .multiply)
        XCTAssertNotNil(layer.effectStack)
        XCTAssertEqual(layer.effectStack?.effects.count, 1)
    }

    // MARK: - TransitionInfo

    func testTransitionInfoCrossDissolve() {
        let info = TransitionInfo(type: .crossDissolve, progress: 0.3, fromTrackID: 1, toTrackID: 2)
        XCTAssertEqual(info.progress, 0.3)
        XCTAssertEqual(info.fromTrackID, 1)
        XCTAssertEqual(info.toTrackID, 2)
    }
}
