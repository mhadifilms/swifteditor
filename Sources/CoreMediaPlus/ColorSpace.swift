import Foundation

/// Color space identifiers for the rendering pipeline.
public enum ColorSpace: String, Codable, Sendable {
    case sRGB
    case rec709
    case rec2020
    case p3
    case acescg
    case acesCCT
    case sLog3
    case logC
    case vLog
}
