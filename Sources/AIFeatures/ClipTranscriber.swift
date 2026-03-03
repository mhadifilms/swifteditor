// AIFeatures — Speech transcription and searchable timeline
import AVFoundation
import CoreMedia
import Foundation
import Speech

/// A timestamped segment from speech recognition.
public struct TranscriptionSegment: Sendable, Identifiable, Codable {
    public let id: UUID
    public let text: String
    /// Seconds from the start of the audio.
    public let timestamp: TimeInterval
    /// Duration in seconds.
    public let duration: TimeInterval
    /// Confidence score (0.0-1.0).
    public let confidence: Float

    public init(text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Float) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
    }

    public var startTime: CMTime {
        CMTime(seconds: timestamp, preferredTimescale: 600)
    }

    public var endTime: CMTime {
        CMTime(seconds: timestamp + duration, preferredTimescale: 600)
    }
}

/// Complete transcription result for a clip.
public struct TranscriptionResult: Sendable {
    public let segments: [TranscriptionSegment]
    public let fullText: String
    public let clipDuration: TimeInterval

    public init(segments: [TranscriptionSegment], clipDuration: TimeInterval) {
        self.segments = segments
        self.fullText = segments.map(\.text).joined(separator: " ")
        self.clipDuration = clipDuration
    }

    /// Returns segments that overlap a given time range (in seconds).
    public func segments(in range: ClosedRange<TimeInterval>) -> [TranscriptionSegment] {
        segments.filter { segment in
            let segEnd = segment.timestamp + segment.duration
            return segment.timestamp <= range.upperBound && segEnd >= range.lowerBound
        }
    }

    /// Average confidence across all segments.
    public var averageConfidence: Float {
        guard !segments.isEmpty else { return 0 }
        return segments.map(\.confidence).reduce(0, +) / Float(segments.count)
    }
}

/// Wraps SFSpeechRecognizer for clip transcription.
public final class ClipTranscriber: @unchecked Sendable {
    private let speechRecognizer: SFSpeechRecognizer

    public init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }

    /// Request speech recognition authorization.
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Whether the recognizer is available for use.
    public var isAvailable: Bool {
        speechRecognizer.isAvailable
    }

    /// Transcribe an audio or video file and return a TranscriptionResult.
    public func transcribe(url: URL) async throws -> TranscriptionResult {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let segments: [TranscriptionSegment] = try await withCheckedThrowingContinuation { continuation in
            speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result, result.isFinal else { return }

                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        timestamp: segment.timestamp,
                        duration: segment.duration,
                        confidence: segment.confidence
                    )
                }
                continuation.resume(returning: segments)
            }
        }

        let duration: TimeInterval
        if let lastSegment = segments.last {
            duration = lastSegment.timestamp + lastSegment.duration
        } else {
            duration = 0
        }

        return TranscriptionResult(segments: segments, clipDuration: duration)
    }
}

// MARK: - Searchable Timeline

/// An entry in the searchable timeline index.
public struct SearchHit: Sendable {
    public let clipID: UUID
    public let segment: TranscriptionSegment
    public let time: CMTime

    public init(clipID: UUID, segment: TranscriptionSegment) {
        self.clipID = clipID
        self.segment = segment
        self.time = segment.startTime
    }
}

/// Indexes transcription segments for full-text search across clips.
public final class SearchableTimeline: Sendable {
    /// Thread-safe word index storage.
    private let _index: WordIndex

    public init() {
        _index = WordIndex()
    }

    /// Index transcription segments for a clip.
    public func indexTranscription(clipID: UUID, segments: [TranscriptionSegment]) {
        _index.add(clipID: clipID, segments: segments)
    }

    /// Remove all indexed segments for a clip.
    public func removeClip(_ clipID: UUID) {
        _index.remove(clipID: clipID)
    }

    /// Search for a query string. Returns matching clips and their timeline positions.
    /// Matches any segment containing any of the query words.
    public func search(query: String) -> [SearchHit] {
        let queryWords = query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else { return [] }

        return _index.search(words: queryWords)
    }

    /// The number of indexed words.
    public var indexedWordCount: Int {
        _index.wordCount
    }
}

/// Thread-safe inverted word index backed by a lock.
private final class WordIndex: Sendable {
    private struct Entry: Sendable {
        let clipID: UUID
        let segment: TranscriptionSegment
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var storage: [String: [Entry]] = [:]

    func add(clipID: UUID, segments: [TranscriptionSegment]) {
        lock.lock()
        defer { lock.unlock() }

        for segment in segments {
            let words = segment.text
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            for word in words {
                storage[word, default: []].append(Entry(clipID: clipID, segment: segment))
            }
        }
    }

    func remove(clipID: UUID) {
        lock.lock()
        defer { lock.unlock() }

        for key in storage.keys {
            storage[key]?.removeAll { $0.clipID == clipID }
            if storage[key]?.isEmpty == true {
                storage.removeValue(forKey: key)
            }
        }
    }

    func search(words: [String]) -> [SearchHit] {
        lock.lock()
        defer { lock.unlock() }

        var hits: [SearchHit] = []
        var seen = Set<UUID>()

        for word in words {
            guard let entries = storage[word] else { continue }
            for entry in entries {
                // Deduplicate by segment ID
                if seen.insert(entry.segment.id).inserted {
                    hits.append(SearchHit(clipID: entry.clipID, segment: entry.segment))
                }
            }
        }

        return hits
    }

    var wordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}
