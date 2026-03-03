@preconcurrency import AVFoundation
import CoreMediaPlus
import Foundation

/// Status of proxy generation for an asset.
public enum ProxyStatus: Sendable {
    case notStarted
    case generating(progress: Float)
    case ready(url: URL)
    case failed(Error)
}

extension ProxyStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notStarted: return "notStarted"
        case .generating(let p): return "generating(\(Int(p * 100))%)"
        case .ready(let url): return "ready(\(url.lastPathComponent))"
        case .failed(let e): return "failed(\(e.localizedDescription))"
        }
    }
}

/// Background transcoding of media to lightweight proxy format.
public actor ProxyGenerator {

    /// Errors specific to proxy generation.
    public enum Error: Swift.Error, Sendable {
        case noVideoTrack
        case writerSetupFailed(String)
        case readingFailed(String)
        case writingFailed(String)
        case cancelled
    }

    public init() {}

    // MARK: - Public API

    /// Generate a proxy file for the given source URL.
    ///
    /// - Parameters:
    ///   - sourceURL: Original high-resolution media file.
    ///   - preset: Quality/resolution preset controlling output parameters.
    ///   - outputDirectory: Directory in which to write the proxy file.
    /// - Returns: URL of the generated proxy file.
    public func generateProxy(
        for sourceURL: URL,
        preset: ProxyPreset,
        outputDirectory: URL
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw Error.noVideoTrack
        }

        let sourceSize = try await videoTrack.load(.naturalSize)
        let proxySize = Self.proxySize(for: sourceSize, preset: preset)

        // Build output URL
        let proxyName = sourceURL.deletingPathExtension().lastPathComponent + "_proxy.mov"
        let outputURL = outputDirectory.appendingPathComponent(proxyName)

        // Remove existing proxy if present
        try? FileManager.default.removeItem(at: outputURL)

        // Configure reader
        let reader = try AVAssetReader(asset: asset)
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        guard reader.canAdd(videoReaderOutput) else {
            throw Error.writerSetupFailed("Cannot add video reader output")
        }
        reader.add(videoReaderOutput)

        // Audio track (optional)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first {
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
            )
            if reader.canAdd(output) {
                reader.add(output)
                audioReaderOutput = output
            }
        }

        // Configure writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422Proxy,
            AVVideoWidthKey: proxySize.width,
            AVVideoHeightKey: proxySize.height,
        ]
        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        videoWriterInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoWriterInput) else {
            throw Error.writerSetupFailed("Cannot add video writer input")
        }
        writer.add(videoWriterInput)

        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioSettings
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input
            }
        }

        // Transcode
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write video
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            videoWriterInput.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if Task.isCancelled {
                        reader.cancelReading()
                        writer.cancelWriting()
                        continuation.resume(throwing: Error.cancelled)
                        return
                    }
                    if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                        videoWriterInput.append(sampleBuffer)
                    } else {
                        videoWriterInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        // Write audio
        if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                audioInput.requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                    while audioInput.isReadyForMoreMediaData {
                        if Task.isCancelled {
                            continuation.resume(throwing: Error.cancelled)
                            return
                        }
                        if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                            audioInput.append(sampleBuffer)
                        } else {
                            audioInput.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                }
            }
        }

        await writer.finishWriting()

        if let writerError = writer.error {
            throw Error.writingFailed(writerError.localizedDescription)
        }
        if reader.status == .failed, let readerError = reader.error {
            throw Error.readingFailed(readerError.localizedDescription)
        }

        return outputURL
    }

    /// Create an `AsyncStream` that reports proxy generation progress and yields the final URL.
    public func generateProxyWithProgress(
        for sourceURL: URL,
        preset: ProxyPreset,
        outputDirectory: URL
    ) -> AsyncStream<ProxyStatus> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.generating(progress: 0))
                do {
                    let url = try await self.generateProxy(
                        for: sourceURL, preset: preset, outputDirectory: outputDirectory
                    )
                    continuation.yield(.ready(url: url))
                } catch {
                    continuation.yield(.failed(error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    /// Compute the proxy output resolution.
    private static func proxySize(for source: CGSize, preset: ProxyPreset) -> (width: Int, height: Int) {
        switch preset {
        case .halfResolution, .proresProxy:
            // Half the source resolution, rounded to even numbers
            let w = max(Int(source.width / 2) & ~1, 2)
            let h = max(Int(source.height / 2) & ~1, 2)
            return (w, h)
        case .quarterResolution:
            let w = max(Int(source.width / 4) & ~1, 2)
            let h = max(Int(source.height / 4) & ~1, 2)
            return (w, h)
        }
    }
}
