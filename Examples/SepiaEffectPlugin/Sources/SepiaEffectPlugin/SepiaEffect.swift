import Foundation
import CoreVideo
import CoreMediaPlus
import PluginKit

#if canImport(Metal)
import Metal
#endif

// MARK: - Sepia Tone Effect

/// A video effect plugin that applies a sepia tone filter.
/// Demonstrates how to build a custom SwiftEditor plugin conforming to VideoEffect.
public final class SepiaEffect: VideoEffect, @unchecked Sendable {
    public let identifier = "com.example.sepiaEffect"

    public let parameterDescriptors: [ParameterDescriptor] = [
        .float(name: "intensity", displayName: "Intensity", defaultValue: 1.0, min: 0.0, max: 1.0),
        .float(name: "warmth", displayName: "Warmth", defaultValue: 0.5, min: 0.0, max: 1.0)
    ]

    private var host: (any PluginHost)?

    public init() {}

    public func prepare(host: any PluginHost) async throws {
        self.host = host
        host.log(.info, message: "SepiaEffect prepared", plugin: identifier)
    }

    public func teardown() async {
        host?.log(.info, message: "SepiaEffect torn down", plugin: identifier)
        host = nil
    }

    #if canImport(Metal)
    public func process(
        input: MTLTexture,
        output: MTLTexture,
        parameters: ParameterValues,
        time: Rational,
        commandBuffer: MTLCommandBuffer
    ) async throws {
        // GPU path: In production, load a Metal compute kernel that applies the sepia matrix.
        // For this sample, the CPU path below serves as the reference implementation.
        host?.log(.debug, message: "Metal process called at \(time)", plugin: identifier)
    }
    #endif

    public func process(
        input: CVPixelBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> CVPixelBuffer {
        let intensity = parameters.floatValue("intensity", default: 1.0)
        let warmth = parameters.floatValue("warmth", default: 0.5)

        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        let format = CVPixelBufferGetPixelFormatType(input)

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            format,
            nil,
            &outputBuffer
        )
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return input
        }

        CVPixelBufferLockBaseAddress(input, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(input, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(input),
              let dstBase = CVPixelBufferGetBaseAddress(output) else {
            return input
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(input)
        let totalBytes = bytesPerRow * height

        let src = srcBase.assumingMemoryBound(to: UInt8.self)
        let dst = dstBase.assumingMemoryBound(to: UInt8.self)

        // Sepia tone matrix coefficients (with warmth adjustment)
        let rR = 0.393 + warmth * 0.1
        let rG = 0.769
        let rB = 0.189
        let gR = 0.349
        let gG = 0.686 + warmth * 0.05
        let gB = 0.168
        let bR = 0.272
        let bG = 0.534
        let bB = 0.131

        // BGRA pixel format
        for i in stride(from: 0, to: totalBytes, by: 4) {
            guard i + 3 < totalBytes else { break }

            let b = Double(src[i])
            let g = Double(src[i + 1])
            let r = Double(src[i + 2])
            let a = src[i + 3]

            let sepiaR = min(255, r * rR + g * rG + b * rB)
            let sepiaG = min(255, r * gR + g * gG + b * gB)
            let sepiaB = min(255, r * bR + g * bG + b * bB)

            // Blend between original and sepia based on intensity
            dst[i]     = UInt8(clamping: Int(b + (sepiaB - b) * intensity))
            dst[i + 1] = UInt8(clamping: Int(g + (sepiaG - g) * intensity))
            dst[i + 2] = UInt8(clamping: Int(r + (sepiaR - r) * intensity))
            dst[i + 3] = a
        }

        return output
    }
}
