import CoreImage
import CoreMediaPlus
import Foundation

/// Errors that can occur during LUT loading.
public enum LUTError: Error, Sendable {
    case fileNotFound
    case invalidFormat(String)
    case unsupportedFileType(String)
    case invalidSize(Int)
}

/// Loads 3D LUT files in .cube and .3dl formats and creates CIFilter-based color transformations.
public final class LUTLoader: Sendable {

    public init() {}

    /// Loads a LUT from the specified file URL.
    /// Supports .cube and .3dl file extensions.
    public func load(from url: URL) throws -> LUTData {
        let ext = url.pathExtension.lowercased()
        let contents = try String(contentsOf: url, encoding: .utf8)

        switch ext {
        case "cube":
            return try parseCubeFile(contents)
        case "3dl":
            return try parse3DLFile(contents)
        default:
            throw LUTError.unsupportedFileType(ext)
        }
    }

    /// Creates a CIFilter from the loaded LUT data.
    public func createFilter(from lut: LUTData) -> CIFilter? {
        let size = lut.size
        let count = size * size * size
        var cubeData = [Float](repeating: 0, count: count * 4)

        for i in 0..<min(lut.entries.count, count) {
            let entry = lut.entries[i]
            cubeData[i * 4 + 0] = entry.r
            cubeData[i * 4 + 1] = entry.g
            cubeData[i * 4 + 2] = entry.b
            cubeData[i * 4 + 3] = 1.0
        }

        let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }

        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
        return filter
    }

    // MARK: - .cube Parser

    private func parseCubeFile(_ contents: String) throws -> LUTData {
        var size = 0
        var entries: [LUTEntry] = []
        var title = ""

        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Parse metadata
            if trimmed.uppercased().hasPrefix("TITLE") {
                title = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                continue
            }

            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
                continue
            }

            // Skip DOMAIN_MIN, DOMAIN_MAX, and other metadata
            if trimmed.uppercased().hasPrefix("DOMAIN_") || trimmed.uppercased().hasPrefix("LUT_1D") {
                continue
            }

            // Parse data lines (three floats per line)
            let components = trimmed.split(separator: " ").compactMap { Float($0) }
            if components.count >= 3 {
                entries.append(LUTEntry(r: components[0], g: components[1], b: components[2]))
            }
        }

        guard size > 0 else {
            throw LUTError.invalidFormat("Missing LUT_3D_SIZE in .cube file")
        }

        let expectedCount = size * size * size
        guard entries.count == expectedCount else {
            throw LUTError.invalidFormat("Expected \(expectedCount) entries for size \(size), got \(entries.count)")
        }

        return LUTData(size: size, title: title, entries: entries)
    }

    // MARK: - .3dl Parser

    private func parse3DLFile(_ contents: String) throws -> LUTData {
        var entries: [LUTEntry] = []
        var size = 0
        var meshSize = 0

        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let components = trimmed.split(separator: " ").compactMap { Int($0) }

            // First valid line with multiple values defines the shaper LUT input range
            if size == 0 && components.count > 3 {
                // This is the shaper LUT line (e.g., "0 64 128 192 ... 1023")
                // The count tells us the mesh size
                meshSize = components.count
                size = meshSize
                continue
            }

            // Data lines have 3 integer values (R G B), typically 0-4095 for 12-bit
            if components.count == 3 {
                let maxVal: Float = 4095.0  // 12-bit range
                entries.append(LUTEntry(
                    r: Float(components[0]) / maxVal,
                    g: Float(components[1]) / maxVal,
                    b: Float(components[2]) / maxVal
                ))
            }
        }

        // Determine cube size from entry count
        if size == 0 {
            let cubeRoot = Int(round(pow(Double(entries.count), 1.0 / 3.0)))
            if cubeRoot * cubeRoot * cubeRoot == entries.count {
                size = cubeRoot
            }
        }

        guard size > 0 else {
            throw LUTError.invalidFormat("Could not determine LUT size from .3dl file")
        }

        let expectedCount = size * size * size
        guard entries.count == expectedCount else {
            throw LUTError.invalidFormat("Expected \(expectedCount) entries for size \(size), got \(entries.count)")
        }

        return LUTData(size: size, title: "", entries: entries)
    }
}

/// A single RGB entry in the LUT.
public struct LUTEntry: Sendable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Parsed 3D LUT data ready for use with CIColorCube filters.
public struct LUTData: Sendable {
    public let size: Int
    public let title: String
    public let entries: [LUTEntry]

    public init(size: Int, title: String, entries: [LUTEntry]) {
        self.size = size
        self.title = title
        self.entries = entries
    }
}

/// Applies a loaded LUT to images in the effect pipeline.
public final class LUTEffect: Sendable {
    private let lutData: LUTData
    private let cubeData: Data
    private let cubeSize: Int

    public init(lutData: LUTData) {
        self.lutData = lutData
        self.cubeSize = lutData.size

        let count = lutData.size * lutData.size * lutData.size
        var floats = [Float](repeating: 0, count: count * 4)
        for i in 0..<min(lutData.entries.count, count) {
            let entry = lutData.entries[i]
            floats[i * 4 + 0] = entry.r
            floats[i * 4 + 1] = entry.g
            floats[i * 4 + 2] = entry.b
            floats[i * 4 + 3] = 1.0
        }
        self.cubeData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Applies the LUT to the input image. The `intensity` parameter (0..1) controls
    /// the blend between original and LUT-graded image.
    public func apply(to image: CIImage, parameters: ParameterValues) -> CIImage {
        let intensity = parameters.floatValue("intensity", default: 1.0)

        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cubeSize, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")

        guard let lutImage = filter.outputImage else { return image }

        // Blend with original based on intensity
        if intensity >= 1.0 {
            return lutImage
        } else if intensity <= 0.0 {
            return image
        }

        guard let blend = CIFilter(name: "CIDissolveTransition") else { return lutImage }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(lutImage, forKey: kCIInputTargetImageKey)
        blend.setValue(NSNumber(value: intensity), forKey: "inputTime")
        return blend.outputImage ?? lutImage
    }
}
