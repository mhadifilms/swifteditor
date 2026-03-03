@preconcurrency import AVFoundation
import CoreMediaPlus
import EffectsEngine

/// Custom video composition instruction carrying per-layer metadata for MetalCompositor.
public final class CompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing: Bool = true
    public let containsTweening: Bool = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    /// Per-layer rendering instructions ordered bottom to top.
    public let layerInstructions: [LayerInstruction]

    /// Optional transition between two layers.
    public let transitionInfo: TransitionInfo?

    public init(timeRange: CMTimeRange,
                sourceTrackIDs: [CMPersistentTrackID],
                layerInstructions: [LayerInstruction],
                transitionInfo: TransitionInfo? = nil) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = sourceTrackIDs.map { NSNumber(value: $0) as NSValue }
        self.layerInstructions = layerInstructions
        self.transitionInfo = transitionInfo
        super.init()
    }
}

/// Describes how a single source layer should be rendered.
public struct LayerInstruction: Sendable {
    public let trackID: CMPersistentTrackID
    public let clipID: UUID
    public let opacity: Double
    public let blendMode: BlendMode
    public let effectStack: EffectStack?

    public init(trackID: CMPersistentTrackID, clipID: UUID,
                opacity: Double = 1.0, blendMode: BlendMode = .normal,
                effectStack: EffectStack? = nil) {
        self.trackID = trackID
        self.clipID = clipID
        self.opacity = opacity
        self.blendMode = blendMode
        self.effectStack = effectStack
    }
}

/// Describes a transition between two layers.
public struct TransitionInfo: Sendable {
    public let type: TransitionType
    public let progress: Double
    public let fromTrackID: CMPersistentTrackID
    public let toTrackID: CMPersistentTrackID

    public init(type: TransitionType, progress: Double,
                fromTrackID: CMPersistentTrackID, toTrackID: CMPersistentTrackID) {
        self.type = type
        self.progress = progress
        self.fromTrackID = fromTrackID
        self.toTrackID = toTrackID
    }
}
