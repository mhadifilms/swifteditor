import Foundation
import CoreMediaPlus
import CoreMedia
import CoreVideo

#if canImport(Metal)
import Metal
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Plugin Bundle

/// A loadable plugin bundle that provides metadata and creates processing nodes.
public protocol PluginBundle: Sendable {
    init()
    var manifest: PluginManifest { get }
    func createProcessingNode() -> any ProcessingNode
}

// MARK: - Plugin Host

/// The host environment that plugins interact with for logging and context.
public protocol PluginHost: Sendable {
    func log(_ level: LogLevel, message: String, plugin: String)
    func parameterChanged(_ name: String, value: ParameterValue, plugin: String)
}

// MARK: - Processing Node

/// Base protocol for all processing nodes in the plugin system.
public protocol ProcessingNode: Sendable {
    var identifier: String { get }
    var parameterDescriptors: [ParameterDescriptor] { get }
    func prepare(host: any PluginHost) async throws
    func teardown() async
}

// MARK: - Video Effect

/// A video effect that processes a single input frame.
public protocol VideoEffect: ProcessingNode {
    #if canImport(Metal)
    func process(
        input: MTLTexture,
        output: MTLTexture,
        parameters: ParameterValues,
        time: Rational,
        commandBuffer: MTLCommandBuffer
    ) async throws
    #endif

    func process(
        input: CVPixelBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> CVPixelBuffer
}

// MARK: - Video Transition

/// A video transition that blends between two input frames.
public protocol VideoTransition: ProcessingNode {
    #if canImport(Metal)
    func process(
        from: MTLTexture,
        to: MTLTexture,
        output: MTLTexture,
        progress: Double,
        parameters: ParameterValues,
        commandBuffer: MTLCommandBuffer
    ) async throws
    #endif

    func process(
        from: CVPixelBuffer,
        to: CVPixelBuffer,
        progress: Double,
        parameters: ParameterValues
    ) async throws -> CVPixelBuffer
}

// MARK: - Video Generator

/// A video generator that produces frames without input.
public protocol VideoGenerator: ProcessingNode {
    #if canImport(Metal)
    func generate(
        output: MTLTexture,
        parameters: ParameterValues,
        time: Rational,
        commandBuffer: MTLCommandBuffer
    ) async throws
    #endif

    func generate(
        parameters: ParameterValues,
        time: Rational,
        size: CGSize
    ) async throws -> CVPixelBuffer
}

// MARK: - Audio Effect

/// An audio effect that processes audio sample buffers.
public protocol AudioEffect: ProcessingNode {
    #if canImport(AVFoundation)
    func process(
        input: AVAudioPCMBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> AVAudioPCMBuffer
    #endif

    func process(
        input: UnsafeBufferPointer<Float>,
        output: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double,
        parameters: ParameterValues,
        time: Rational
    ) async throws
}

// MARK: - Codec Plugin

/// A codec plugin that provides encoding and decoding capabilities.
public protocol CodecPlugin: ProcessingNode {
    var supportedMediaTypes: [String] { get }

    func decode(
        sampleBuffer: CMSampleBuffer
    ) async throws -> CVPixelBuffer

    func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTime: Rational
    ) async throws -> CMSampleBuffer
}

// MARK: - Export Format Plugin

/// An export format plugin that writes output to a specific container format.
public protocol ExportFormatPlugin: ProcessingNode {
    var fileExtension: String { get }
    var mimeType: String { get }

    func beginExport(to url: URL, videoParams: VideoParams, audioParams: AudioParams) async throws
    func writeVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: Rational) async throws
    func writeAudioSamples(_ buffer: UnsafeBufferPointer<Float>, channelCount: Int, at time: Rational) async throws
    func finishExport() async throws
}
