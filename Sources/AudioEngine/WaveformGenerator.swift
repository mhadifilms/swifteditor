import AVFoundation
import Foundation

/// A single sample point in a waveform, representing a time bucket.
public struct WaveformSample: Sendable {
    public let minValue: Float
    public let maxValue: Float
    public let rmsValue: Float

    public init(minValue: Float, maxValue: Float, rmsValue: Float) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.rmsValue = rmsValue
    }
}

/// Extracted waveform data for one or more audio channels.
public struct WaveformData: Sendable {
    /// Number of audio channels.
    public let channelCount: Int
    /// Samples per second used during generation.
    public let sampleRate: Int
    /// Per-channel waveform samples. Outer array = channels, inner array = time buckets.
    public let samples: [[WaveformSample]]

    public init(channelCount: Int, sampleRate: Int, samples: [[WaveformSample]]) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.samples = samples
    }
}

/// Generates downsampled waveform data from audio files using AVAssetReader.
public final class WaveformGenerator: Sendable {

    public init() {}

    /// Generate waveform data for the audio asset at the given URL.
    /// - Parameters:
    ///   - url: File URL of the audio asset.
    ///   - samplesPerSecond: Desired waveform resolution (default 100).
    /// - Returns: Downsampled waveform data per channel.
    public func generateWaveform(
        for url: URL,
        samplesPerSecond: Int = 100
    ) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw WaveformError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw WaveformError.readerFailed(reader.error)
        }

        // Read all raw float samples.
        var interleavedSamples: [Float] = []
        var channelCount = 0
        var nativeSampleRate = 0.0

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            if channelCount == 0 {
                if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                {
                    channelCount = Int(asbd.pointee.mChannelsPerFrame)
                    nativeSampleRate = asbd.pointee.mSampleRate
                }
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            let floatCount = length / MemoryLayout<Float>.size
            let startIndex = interleavedSamples.count
            interleavedSamples.append(contentsOf: repeatElement(Float(0), count: floatCount))
            interleavedSamples.withUnsafeMutableBufferPointer { ptr in
                let rawPtr = UnsafeMutableRawBufferPointer(
                    start: ptr.baseAddress!.advanced(by: startIndex),
                    count: floatCount * MemoryLayout<Float>.size
                )
                CMBlockBufferCopyDataBytes(
                    blockBuffer, atOffset: 0, dataLength: length, destination: rawPtr.baseAddress!
                )
            }
        }

        if reader.status == .failed {
            throw WaveformError.readerFailed(reader.error)
        }

        guard channelCount > 0, nativeSampleRate > 0 else {
            throw WaveformError.noAudioTrack
        }

        let totalFrames = interleavedSamples.count / channelCount
        let duration = Double(totalFrames) / nativeSampleRate
        let totalBuckets = max(1, Int(duration * Double(samplesPerSecond)))
        let framesPerBucket = max(1, totalFrames / totalBuckets)

        // Downsample per channel.
        var channelSamples: [[WaveformSample]] = Array(
            repeating: [], count: channelCount
        )

        for ch in 0..<channelCount {
            var buckets: [WaveformSample] = []
            buckets.reserveCapacity(totalBuckets)

            for bucket in 0..<totalBuckets {
                let startFrame = bucket * framesPerBucket
                let endFrame = min(startFrame + framesPerBucket, totalFrames)
                guard startFrame < endFrame else {
                    buckets.append(WaveformSample(minValue: 0, maxValue: 0, rmsValue: 0))
                    continue
                }

                var minVal: Float = .greatestFiniteMagnitude
                var maxVal: Float = -.greatestFiniteMagnitude
                var sumSquares: Float = 0

                for frame in startFrame..<endFrame {
                    let sample = interleavedSamples[frame * channelCount + ch]
                    if sample < minVal { minVal = sample }
                    if sample > maxVal { maxVal = sample }
                    sumSquares += sample * sample
                }

                let count = Float(endFrame - startFrame)
                let rms = (sumSquares / count).squareRoot()
                buckets.append(WaveformSample(minValue: minVal, maxValue: maxVal, rmsValue: rms))
            }

            channelSamples[ch] = buckets
        }

        return WaveformData(
            channelCount: channelCount,
            sampleRate: samplesPerSecond,
            samples: channelSamples
        )
    }
}

/// Errors from waveform generation.
public enum WaveformError: Error, Sendable {
    case noAudioTrack
    case readerFailed(Error?)
}
