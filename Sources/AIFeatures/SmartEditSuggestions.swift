// AIFeatures — Smart edit suggestions and auto-highlight detection
import AVFoundation
import CoreMedia
import Foundation

/// A suggested edit point with a reason and confidence score.
public struct EditSuggestion: Sendable {
    public enum Reason: String, Sendable {
        case sceneCut = "scene_cut"
        case audioPeak = "audio_peak"
        case silenceGap = "silence_gap"
        case combined = "combined"
    }

    public let time: CMTime
    public let reason: Reason
    /// Confidence score (0.0-1.0).
    public let confidence: Float

    public init(time: CMTime, reason: Reason, confidence: Float) {
        self.time = time
        self.reason = reason
        self.confidence = confidence
    }
}

/// Suggests edit points by combining scene detection with audio peak analysis.
public struct SmartCutSuggester: Sendable {
    /// Minimum interval between suggestions in seconds, to avoid clustering.
    public let minimumInterval: TimeInterval
    /// Audio amplitude threshold (0.0-1.0) for peak detection.
    public let audioPeakThreshold: Float
    /// Scene cut correlation threshold.
    public let sceneCutThreshold: Float

    public init(
        minimumInterval: TimeInterval = 1.0,
        audioPeakThreshold: Float = 0.8,
        sceneCutThreshold: Float = 0.35
    ) {
        self.minimumInterval = minimumInterval
        self.audioPeakThreshold = audioPeakThreshold
        self.sceneCutThreshold = sceneCutThreshold
    }

    /// Suggest edit points in an asset by combining scene cuts and audio peaks.
    /// Returns suggestions sorted by time.
    public func suggestCuts(in asset: AVAsset) async throws -> [EditSuggestion] {
        let cuts = try await detectSceneCuts(in: asset)
        let peaks = try await detectAudioPeaks(in: asset)

        var suggestions: [EditSuggestion] = []

        // Add scene cut suggestions
        for cutTime in cuts {
            suggestions.append(EditSuggestion(
                time: cutTime,
                reason: .sceneCut,
                confidence: 0.9
            ))
        }

        // Add audio peak suggestions
        for peak in peaks {
            suggestions.append(EditSuggestion(
                time: peak.time,
                reason: .audioPeak,
                confidence: peak.amplitude
            ))
        }

        // Sort by time
        suggestions.sort { CMTimeCompare($0.time, $1.time) < 0 }

        // Merge nearby suggestions into combined ones
        return mergeNearbySuggestions(suggestions)
    }

    /// Merge suggestions that are within minimumInterval of each other.
    /// Combined suggestions get a boosted confidence.
    private func mergeNearbySuggestions(_ suggestions: [EditSuggestion]) -> [EditSuggestion] {
        guard !suggestions.isEmpty else { return [] }

        var merged: [EditSuggestion] = []
        var i = 0

        while i < suggestions.count {
            let current = suggestions[i]
            var bestConfidence = current.confidence
            var hasSceneCut = current.reason == .sceneCut
            var hasAudioPeak = current.reason == .audioPeak

            // Look ahead for nearby suggestions
            var j = i + 1
            while j < suggestions.count {
                let next = suggestions[j]
                let gap = CMTimeGetSeconds(next.time) - CMTimeGetSeconds(current.time)
                if gap <= minimumInterval {
                    bestConfidence = max(bestConfidence, next.confidence)
                    if next.reason == .sceneCut { hasSceneCut = true }
                    if next.reason == .audioPeak { hasAudioPeak = true }
                    j += 1
                } else {
                    break
                }
            }

            let reason: EditSuggestion.Reason
            let confidence: Float
            if hasSceneCut && hasAudioPeak {
                reason = .combined
                confidence = min(1.0, bestConfidence * 1.2)
            } else if hasSceneCut {
                reason = .sceneCut
                confidence = bestConfidence
            } else if hasAudioPeak {
                reason = .audioPeak
                confidence = bestConfidence
            } else {
                reason = current.reason
                confidence = bestConfidence
            }

            merged.append(EditSuggestion(
                time: current.time,
                reason: reason,
                confidence: confidence
            ))

            i = j
        }

        return merged
    }

    // MARK: - Private Detection

    private func detectSceneCuts(in asset: AVAsset) async throws -> [CMTime] {
        let detector = SceneCutDetector(threshold: sceneCutThreshold)
        return try await detector.detectCuts(in: asset)
    }

    private func detectAudioPeaks(in asset: AVAsset) async throws -> [(time: CMTime, amplitude: Float)] {
        let reader = try AVAssetReader(asset: asset)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var peaks: [(time: CMTime, amplitude: Float)] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard let data = dataPointer else { continue }
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { continue }

            // Find the peak amplitude in this buffer
            let samples = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                Array(UnsafeBufferPointer(start: ptr, count: sampleCount))
            }

            let maxSample = samples.map { abs(Int32($0)) }.max() ?? 0
            let normalizedAmplitude = Float(maxSample) / Float(Int16.max)

            if normalizedAmplitude >= audioPeakThreshold {
                peaks.append((time: time, amplitude: normalizedAmplitude))
            }
        }

        return peaks
    }
}

// MARK: - Auto Highlight Detection

/// A detected highlight moment in a video.
public struct Highlight: Sendable {
    public let timeRange: CMTimeRange
    public let score: Float
    public let label: String

    public init(timeRange: CMTimeRange, score: Float, label: String) {
        self.timeRange = timeRange
        self.score = score
        self.label = label
    }
}

/// Detects interesting moments in video by combining scene density, audio energy, and
/// other signals. Useful for automatically selecting highlights from long recordings.
public struct AutoHighlightDetector: Sendable {
    /// Duration of each analysis window in seconds.
    public let windowDuration: TimeInterval
    /// Minimum score (0.0-1.0) for a window to be considered a highlight.
    public let scoreThreshold: Float

    public init(windowDuration: TimeInterval = 5.0, scoreThreshold: Float = 0.6) {
        self.windowDuration = windowDuration
        self.scoreThreshold = scoreThreshold
    }

    /// Detect highlights in an asset by analyzing scene cuts and audio energy per window.
    public func detectHighlights(in asset: AVAsset) async throws -> [Highlight] {
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return [] }

        // Get scene cuts
        let detector = SceneCutDetector(threshold: 0.35)
        let sceneCuts = try await detector.detectCuts(in: asset)
        let sceneCutSeconds = sceneCuts.map { CMTimeGetSeconds($0) }

        // Divide the asset into windows and score each
        let windowCount = Int(ceil(totalSeconds / windowDuration))
        var highlights: [Highlight] = []

        for i in 0..<windowCount {
            let windowStart = Double(i) * windowDuration
            let windowEnd = min(windowStart + windowDuration, totalSeconds)

            // Count scene cuts in this window
            let cutsInWindow = sceneCutSeconds.filter { $0 >= windowStart && $0 < windowEnd }
            let cutDensity = Float(cutsInWindow.count) / Float(windowDuration)
            // Normalize: 0 cuts = 0, 3+ cuts per window = 1.0
            let cutScore = min(1.0, cutDensity / 0.6)

            // Combined score (can be extended with audio energy, face count, etc.)
            let score = cutScore

            if score >= scoreThreshold {
                let startTime = CMTime(seconds: windowStart, preferredTimescale: 600)
                let endTime = CMTime(seconds: windowEnd, preferredTimescale: 600)
                let range = CMTimeRange(start: startTime, end: endTime)

                highlights.append(Highlight(
                    timeRange: range,
                    score: score,
                    label: "High activity (\(cutsInWindow.count) cuts)"
                ))
            }
        }

        return highlights
    }
}
