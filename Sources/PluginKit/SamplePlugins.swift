import Foundation
import CoreMediaPlus
import CoreVideo

#if canImport(Metal)
import Metal
#endif

// MARK: - Invert Effect

/// A reference implementation of VideoEffect that inverts pixel colors.
public final class InvertEffect: VideoEffect, @unchecked Sendable {
    public let identifier = "sample.invertEffect"

    public let parameterDescriptors: [ParameterDescriptor] = [
        .float(name: "intensity", displayName: "Intensity", defaultValue: 1.0, min: 0.0, max: 1.0)
    ]

    private var host: (any PluginHost)?

    public init() {}

    public func prepare(host: any PluginHost) async throws {
        self.host = host
        host.log(.info, message: "InvertEffect prepared", plugin: identifier)
    }

    public func teardown() async {
        host?.log(.info, message: "InvertEffect torn down", plugin: identifier)
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
        // GPU path: encode a compute shader to invert colors.
        // Requires a metallib with an "invertKernel" function to be loaded separately.
        // This is a reference implementation; in production, use MetalLibraryLoader
        // to load the pipeline and dispatch the compute kernel.
        host?.log(.debug, message: "Metal process called at \(time)", plugin: identifier)
    }
    #endif

    public func process(
        input: CVPixelBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> CVPixelBuffer {
        let intensity = parameters.floatValue("intensity", default: 1.0)
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

        // BGRA format: invert B, G, R channels; preserve A
        for i in stride(from: 0, to: totalBytes, by: 4) {
            if i + 3 < totalBytes {
                let blendFactor = UInt8(intensity * 255.0)
                dst[i]     = UInt8(clamping: Int(src[i]) + ((Int(255 - src[i]) - Int(src[i])) * Int(blendFactor)) / 255)     // B
                dst[i + 1] = UInt8(clamping: Int(src[i+1]) + ((Int(255 - src[i+1]) - Int(src[i+1])) * Int(blendFactor)) / 255) // G
                dst[i + 2] = UInt8(clamping: Int(src[i+2]) + ((Int(255 - src[i+2]) - Int(src[i+2])) * Int(blendFactor)) / 255) // R
                dst[i + 3] = src[i + 3]                                                                                         // A
            }
        }

        return output
    }
}

// MARK: - Invert Effect Bundle

/// Plugin bundle descriptor for the InvertEffect sample plugin.
public struct InvertEffectBundle: PluginBundle {
    public init() {}

    public var manifest: PluginManifest {
        PluginManifest(
            identifier: "sample.invertEffect",
            name: "Invert Colors",
            version: "1.0.0",
            author: "SwiftEditor",
            category: .videoEffect,
            minimumHostVersion: "1.0.0",
            capabilities: [.realTimeCapable]
        )
    }

    public func createProcessingNode() -> any ProcessingNode {
        InvertEffect()
    }
}

// MARK: - Test Tone Generator

/// A reference implementation of VideoGenerator that produces a solid color
/// cycling through hues over time — useful for testing the generator pipeline.
public final class TestToneGenerator: VideoGenerator, @unchecked Sendable {
    public let identifier = "sample.testToneGenerator"

    public let parameterDescriptors: [ParameterDescriptor] = [
        .float(name: "speed", displayName: "Cycle Speed", defaultValue: 1.0, min: 0.1, max: 10.0),
        .float(name: "brightness", displayName: "Brightness", defaultValue: 1.0, min: 0.0, max: 1.0)
    ]

    private var host: (any PluginHost)?

    public init() {}

    public func prepare(host: any PluginHost) async throws {
        self.host = host
        host.log(.info, message: "TestToneGenerator prepared", plugin: identifier)
    }

    public func teardown() async {
        host?.log(.info, message: "TestToneGenerator torn down", plugin: identifier)
        host = nil
    }

    #if canImport(Metal)
    public func generate(
        output: MTLTexture,
        parameters: ParameterValues,
        time: Rational,
        commandBuffer: MTLCommandBuffer
    ) async throws {
        // GPU path: fill output texture with a cycling color.
        // In production, use MetalLibraryLoader to load and dispatch a compute kernel.
        host?.log(.debug, message: "Metal generate called at \(time)", plugin: identifier)
    }
    #endif

    public func generate(
        parameters: ParameterValues,
        time: Rational,
        size: CGSize
    ) async throws -> CVPixelBuffer {
        let speed = parameters.floatValue("speed", default: 1.0)
        let brightness = parameters.floatValue("brightness", default: 1.0)

        let width = Int(size.width)
        let height = Int(size.height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let output = pixelBuffer else {
            // Return a minimal 1x1 buffer as fallback
            var fallback: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &fallback)
            return fallback!
        }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(output) else {
            return output
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Cycle hue based on time
        let hue = (time.seconds * speed).truncatingRemainder(dividingBy: 1.0)
        let (r, g, b) = hsvToRGB(h: hue, s: 1.0, v: brightness)

        let bVal = UInt8(clamping: Int(b * 255))
        let gVal = UInt8(clamping: Int(g * 255))
        let rVal = UInt8(clamping: Int(r * 255))

        for row in 0..<height {
            let rowOffset = row * bytesPerRow
            for col in 0..<width {
                let offset = rowOffset + col * 4
                ptr[offset]     = bVal  // B
                ptr[offset + 1] = gVal  // G
                ptr[offset + 2] = rVal  // R
                ptr[offset + 3] = 255   // A
            }
        }

        return output
    }

    // MARK: - Color Helpers

    private func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let i = Int(h * 6.0)
        let f = h * 6.0 - Double(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)

        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        case 5: return (v, p, q)
        default: return (v, v, v)
        }
    }
}

// MARK: - Test Tone Generator Bundle

/// Plugin bundle descriptor for the TestToneGenerator sample plugin.
public struct TestToneGeneratorBundle: PluginBundle {
    public init() {}

    public var manifest: PluginManifest {
        PluginManifest(
            identifier: "sample.testToneGenerator",
            name: "Test Tone Generator",
            version: "1.0.0",
            author: "SwiftEditor",
            category: .generator,
            minimumHostVersion: "1.0.0",
            capabilities: [.realTimeCapable]
        )
    }

    public func createProcessingNode() -> any ProcessingNode {
        TestToneGenerator()
    }
}
