import Foundation

/// Audio format parameters.
public struct AudioParams: Codable, Sendable, Hashable {
    public var sampleRate: Int
    public var channelCount: Int
    public var bitDepth: Int

    public init(sampleRate: Int = 48000, channelCount: Int = 2, bitDepth: Int = 32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
    }
}
