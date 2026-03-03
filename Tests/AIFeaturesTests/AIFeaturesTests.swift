import Testing
import CoreMedia
import Foundation
@testable import AIFeatures

@Suite("AIFeatures Tests")
struct AIFeaturesTests {

    // MARK: - SceneCutDetector Tests

    @Suite("SceneCutDetector")
    struct SceneCutDetectorTests {

        @Test("Default threshold is 0.35")
        func defaultThreshold() {
            let detector = SceneCutDetector()
            #expect(detector.threshold == 0.35)
        }

        @Test("Custom threshold is stored correctly")
        func customThreshold() {
            let detector = SceneCutDetector(threshold: 0.5)
            #expect(detector.threshold == 0.5)
        }

        @Test("Identical histograms have correlation of 1.0")
        func identicalHistogramsCorrelation() {
            var histogram = [Float](repeating: 0, count: 256)
            histogram[50] = 0.3
            histogram[100] = 0.4
            histogram[200] = 0.3

            let correlation = SceneCutDetector.correlate(histogram, histogram)
            #expect(abs(correlation - 1.0) < 0.001)
        }

        @Test("Orthogonal histograms have correlation of 0.0")
        func orthogonalHistogramsCorrelation() {
            var a = [Float](repeating: 0, count: 256)
            var b = [Float](repeating: 0, count: 256)
            a[0] = 1.0
            b[128] = 1.0

            let correlation = SceneCutDetector.correlate(a, b)
            #expect(abs(correlation) < 0.001)
        }

        @Test("Similar histograms have high correlation")
        func similarHistogramsCorrelation() {
            var a = [Float](repeating: 0, count: 256)
            var b = [Float](repeating: 0, count: 256)
            // Nearly identical distributions
            for i in 0..<256 {
                a[i] = Float(i) / 255.0
                b[i] = Float(i) / 255.0 + 0.01
            }

            let correlation = SceneCutDetector.correlate(a, b)
            #expect(correlation > 0.99)
        }

        @Test("Dissimilar histograms have low correlation")
        func dissimilarHistogramsCorrelation() {
            var a = [Float](repeating: 0, count: 256)
            var b = [Float](repeating: 0, count: 256)
            // Opposite distributions
            for i in 0..<256 {
                a[i] = Float(i) / 255.0
                b[i] = Float(255 - i) / 255.0
            }

            let correlation = SceneCutDetector.correlate(a, b)
            // Reversed distribution should have low (possibly negative) correlation
            #expect(correlation < 0.5)
        }

        @Test("Zero histograms return zero correlation")
        func zeroHistogramsCorrelation() {
            let a = [Float](repeating: 0, count: 256)
            let b = [Float](repeating: 0, count: 256)

            let correlation = SceneCutDetector.correlate(a, b)
            #expect(correlation == 0)
        }

        @Test("Threshold comparison logic: correlation below threshold means scene cut")
        func thresholdLogic() {
            let detector = SceneCutDetector(threshold: 0.5)
            // A correlation of 0.3 is below the 0.5 threshold, so it should be a cut
            #expect(0.3 < detector.threshold)
            // A correlation of 0.7 is above the threshold, not a cut
            #expect(!(0.7 < detector.threshold))
        }

        @Test("Bin count is 256")
        func binCount() {
            #expect(SceneCutDetector.binCount == 256)
        }
    }

    // MARK: - TranscriptionResult Tests

    @Suite("TranscriptionResult")
    struct TranscriptionResultTests {

        @Test("Full text concatenates all segments")
        func fullText() {
            let segments = [
                TranscriptionSegment(text: "Hello", timestamp: 0.0, duration: 0.5, confidence: 0.9),
                TranscriptionSegment(text: "world", timestamp: 0.5, duration: 0.5, confidence: 0.95),
            ]
            let result = TranscriptionResult(segments: segments, clipDuration: 1.0)
            #expect(result.fullText == "Hello world")
        }

        @Test("Average confidence calculation")
        func averageConfidence() {
            let segments = [
                TranscriptionSegment(text: "a", timestamp: 0.0, duration: 0.5, confidence: 0.8),
                TranscriptionSegment(text: "b", timestamp: 0.5, duration: 0.5, confidence: 1.0),
            ]
            let result = TranscriptionResult(segments: segments, clipDuration: 1.0)
            #expect(abs(result.averageConfidence - 0.9) < 0.001)
        }

        @Test("Average confidence is zero for empty segments")
        func emptyAverageConfidence() {
            let result = TranscriptionResult(segments: [], clipDuration: 0)
            #expect(result.averageConfidence == 0)
        }

        @Test("Segments in time range returns correct subset")
        func segmentsInRange() {
            let segments = [
                TranscriptionSegment(text: "first", timestamp: 0.0, duration: 1.0, confidence: 0.9),
                TranscriptionSegment(text: "second", timestamp: 1.5, duration: 1.0, confidence: 0.9),
                TranscriptionSegment(text: "third", timestamp: 3.0, duration: 1.0, confidence: 0.9),
            ]
            let result = TranscriptionResult(segments: segments, clipDuration: 4.0)

            let inRange = result.segments(in: 1.0...2.0)
            #expect(inRange.count == 2)
            #expect(inRange[0].text == "first")   // ends at 1.0, overlaps range start
            #expect(inRange[1].text == "second")   // starts at 1.5, within range
        }

        @Test("Segments in range returns empty for non-overlapping range")
        func segmentsOutOfRange() {
            let segments = [
                TranscriptionSegment(text: "first", timestamp: 0.0, duration: 0.5, confidence: 0.9),
            ]
            let result = TranscriptionResult(segments: segments, clipDuration: 0.5)

            let inRange = result.segments(in: 5.0...10.0)
            #expect(inRange.isEmpty)
        }

        @Test("TranscriptionSegment startTime and endTime CMTime conversion")
        func segmentTimeConversion() {
            let segment = TranscriptionSegment(text: "test", timestamp: 2.5, duration: 1.0, confidence: 0.9)
            #expect(abs(CMTimeGetSeconds(segment.startTime) - 2.5) < 0.01)
            #expect(abs(CMTimeGetSeconds(segment.endTime) - 3.5) < 0.01)
        }
    }

    // MARK: - SearchableTimeline Tests

    @Suite("SearchableTimeline")
    struct SearchableTimelineTests {

        @Test("Indexing and searching a word returns hits")
        func basicSearch() {
            let timeline = SearchableTimeline()
            let clipID = UUID()
            let segments = [
                TranscriptionSegment(text: "Hello world", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ]

            timeline.indexTranscription(clipID: clipID, segments: segments)
            let hits = timeline.search(query: "hello")

            #expect(hits.count == 1)
            #expect(hits[0].clipID == clipID)
        }

        @Test("Search is case-insensitive")
        func caseInsensitiveSearch() {
            let timeline = SearchableTimeline()
            let clipID = UUID()
            let segments = [
                TranscriptionSegment(text: "HELLO World", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ]

            timeline.indexTranscription(clipID: clipID, segments: segments)

            #expect(!timeline.search(query: "hello").isEmpty)
            #expect(!timeline.search(query: "WORLD").isEmpty)
            #expect(!timeline.search(query: "Hello").isEmpty)
        }

        @Test("Search returns empty for non-matching query")
        func noResults() {
            let timeline = SearchableTimeline()
            let clipID = UUID()
            let segments = [
                TranscriptionSegment(text: "Hello world", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ]

            timeline.indexTranscription(clipID: clipID, segments: segments)
            let hits = timeline.search(query: "goodbye")

            #expect(hits.isEmpty)
        }

        @Test("Empty query returns no results")
        func emptyQuery() {
            let timeline = SearchableTimeline()
            let clipID = UUID()
            let segments = [
                TranscriptionSegment(text: "Hello", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ]

            timeline.indexTranscription(clipID: clipID, segments: segments)
            #expect(timeline.search(query: "").isEmpty)
            #expect(timeline.search(query: "   ").isEmpty)
        }

        @Test("Multiple clips are indexed and searchable")
        func multiClipSearch() {
            let timeline = SearchableTimeline()
            let clip1 = UUID()
            let clip2 = UUID()

            timeline.indexTranscription(clipID: clip1, segments: [
                TranscriptionSegment(text: "morning news", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ])
            timeline.indexTranscription(clipID: clip2, segments: [
                TranscriptionSegment(text: "evening news", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ])

            let hits = timeline.search(query: "news")
            #expect(hits.count == 2)

            let clipIDs = Set(hits.map(\.clipID))
            #expect(clipIDs.contains(clip1))
            #expect(clipIDs.contains(clip2))
        }

        @Test("Remove clip removes it from search results")
        func removeClip() {
            let timeline = SearchableTimeline()
            let clipID = UUID()

            timeline.indexTranscription(clipID: clipID, segments: [
                TranscriptionSegment(text: "test content", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ])
            #expect(!timeline.search(query: "test").isEmpty)

            timeline.removeClip(clipID)
            #expect(timeline.search(query: "test").isEmpty)
        }

        @Test("Indexed word count tracks unique words")
        func wordCount() {
            let timeline = SearchableTimeline()
            let clipID = UUID()

            timeline.indexTranscription(clipID: clipID, segments: [
                TranscriptionSegment(text: "one two three", timestamp: 0.0, duration: 1.0, confidence: 0.9),
            ])
            #expect(timeline.indexedWordCount == 3)
        }

        @Test("Multi-word query matches segments containing any word")
        func multiWordQuery() {
            let timeline = SearchableTimeline()
            let clipID = UUID()

            timeline.indexTranscription(clipID: clipID, segments: [
                TranscriptionSegment(text: "the quick brown fox", timestamp: 0.0, duration: 1.0, confidence: 0.9),
                TranscriptionSegment(text: "jumped over the lazy dog", timestamp: 1.0, duration: 1.0, confidence: 0.9),
            ])

            let hits = timeline.search(query: "fox dog")
            #expect(hits.count == 2)
        }
    }

    // MARK: - EditSuggestion Tests

    @Suite("EditSuggestion")
    struct EditSuggestionTests {

        @Test("EditSuggestion stores all fields correctly")
        func creation() {
            let time = CMTime(seconds: 5.0, preferredTimescale: 600)
            let suggestion = EditSuggestion(time: time, reason: .sceneCut, confidence: 0.9)

            #expect(abs(CMTimeGetSeconds(suggestion.time) - 5.0) < 0.01)
            #expect(suggestion.reason == .sceneCut)
            #expect(suggestion.confidence == 0.9)
        }

        @Test("EditSuggestion reason raw values")
        func reasonRawValues() {
            #expect(EditSuggestion.Reason.sceneCut.rawValue == "scene_cut")
            #expect(EditSuggestion.Reason.audioPeak.rawValue == "audio_peak")
            #expect(EditSuggestion.Reason.silenceGap.rawValue == "silence_gap")
            #expect(EditSuggestion.Reason.combined.rawValue == "combined")
        }
    }

    // MARK: - FaceInfo Tests

    @Suite("FaceInfo")
    struct FaceInfoTests {

        @Test("FaceInfo stores all fields correctly")
        func creation() {
            let info = FaceInfo(
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                roll: 0.1,
                yaw: -0.2,
                confidence: 0.95
            )

            #expect(abs(info.boundingBox.origin.x - 0.1) < 0.001)
            #expect(info.roll == 0.1)
            #expect(info.yaw == -0.2)
            #expect(info.confidence == 0.95)
        }

        @Test("FaceInfo with nil roll and yaw")
        func nilOrientation() {
            let info = FaceInfo(boundingBox: .zero, roll: nil, yaw: nil, confidence: 0.5)
            #expect(info.roll == nil)
            #expect(info.yaw == nil)
        }
    }

    // MARK: - Highlight Tests

    @Suite("Highlight")
    struct HighlightTests {

        @Test("Highlight stores fields correctly")
        func creation() {
            let range = CMTimeRange(
                start: CMTime(seconds: 10.0, preferredTimescale: 600),
                end: CMTime(seconds: 15.0, preferredTimescale: 600)
            )
            let highlight = Highlight(timeRange: range, score: 0.85, label: "Action scene")

            #expect(abs(CMTimeGetSeconds(highlight.timeRange.start) - 10.0) < 0.01)
            #expect(abs(CMTimeGetSeconds(highlight.timeRange.end) - 15.0) < 0.01)
            #expect(highlight.score == 0.85)
            #expect(highlight.label == "Action scene")
        }
    }
}
