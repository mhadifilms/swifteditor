@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import AIFeatures

/// Facade for AI-powered editing features: scene detection, transcription, search,
/// object tracking, and face analysis.
public final class AIFeaturesAPI: @unchecked Sendable {
    private let searchTimeline: SearchableTimeline

    public init() {
        self.searchTimeline = SearchableTimeline()
    }

    // MARK: - Scene Detection

    /// Detect scene cuts in a video file by comparing luminance histograms.
    public func detectSceneCuts(in assetURL: URL, threshold: Float = 0.35) async throws -> [CMTime] {
        let asset = AVURLAsset(url: assetURL)
        let detector = SceneCutDetector(threshold: threshold)
        return try await detector.detectCuts(in: asset)
    }

    /// Suggest edit points by combining scene detection with audio peak analysis.
    public func suggestEditPoints(
        in assetURL: URL,
        minimumInterval: TimeInterval = 1.0,
        audioPeakThreshold: Float = 0.8,
        sceneCutThreshold: Float = 0.35
    ) async throws -> [EditSuggestion] {
        let asset = AVURLAsset(url: assetURL)
        let suggester = SmartCutSuggester(
            minimumInterval: minimumInterval,
            audioPeakThreshold: audioPeakThreshold,
            sceneCutThreshold: sceneCutThreshold
        )
        return try await suggester.suggestCuts(in: asset)
    }

    /// Detect highlight moments in a video by analyzing scene density.
    public func detectHighlights(
        in assetURL: URL,
        windowDuration: TimeInterval = 5.0,
        scoreThreshold: Float = 0.6
    ) async throws -> [Highlight] {
        let asset = AVURLAsset(url: assetURL)
        let detector = AutoHighlightDetector(
            windowDuration: windowDuration,
            scoreThreshold: scoreThreshold
        )
        return try await detector.detectHighlights(in: asset)
    }

    // MARK: - Transcription

    /// Transcribe speech in an audio or video file.
    public func transcribe(url: URL, locale: Locale = .current) async throws -> TranscriptionResult {
        let transcriber = ClipTranscriber(locale: locale)
        return try await transcriber.transcribe(url: url)
    }

    /// Request speech recognition authorization from the user.
    public func requestTranscriptionAuthorization() async -> Bool {
        let status = await ClipTranscriber.requestAuthorization()
        return status == .authorized
    }

    // MARK: - Search

    /// Index transcription segments for a clip in the searchable timeline.
    public func indexTranscription(clipID: UUID, segments: [TranscriptionSegment]) {
        searchTimeline.indexTranscription(clipID: clipID, segments: segments)
    }

    /// Remove all indexed segments for a clip.
    public func removeClipFromIndex(_ clipID: UUID) {
        searchTimeline.removeClip(clipID)
    }

    /// Search indexed transcriptions for matching clips and timeline positions.
    public func search(query: String) -> [SearchHit] {
        searchTimeline.search(query: query)
    }

    /// The number of indexed words across all clips.
    public var indexedWordCount: Int {
        searchTimeline.indexedWordCount
    }

    // MARK: - Object Tracking

    /// Create a single-object tracker.
    public func createObjectTracker(
        accurate: Bool = true,
        minimumConfidence: Float = 0.3
    ) -> ObjectTracker {
        ObjectTracker(useAccurateTracking: accurate, minimumConfidence: minimumConfidence)
    }

    /// Create a multi-object tracker.
    public func createMultiObjectTracker(
        accurate: Bool = false,
        minimumConfidence: Float = 0.3
    ) -> MultiObjectTracker {
        MultiObjectTracker(useAccurateTracking: accurate, minimumConfidence: minimumConfidence)
    }

    // MARK: - Face Analysis

    /// Detect faces with landmark details in a video frame.
    public func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [FaceInfo] {
        let analyzer = FaceAnalyzer()
        return try analyzer.detectFaces(in: pixelBuffer)
    }

    /// Detect face capture quality for selecting best thumbnail frames.
    public func detectFaceQuality(in pixelBuffer: CVPixelBuffer) throws -> [(boundingBox: CGRect, quality: Float)] {
        let analyzer = FaceAnalyzer()
        return try analyzer.detectFaceQuality(in: pixelBuffer)
    }
}
