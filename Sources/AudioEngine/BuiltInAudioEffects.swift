@preconcurrency import AVFoundation
import AudioToolbox
import CoreMediaPlus
import Foundation
import PluginKit

// MARK: - Built-in Audio Effect Descriptor

/// Describes a built-in audio effect that wraps an Apple AudioUnit.
public struct BuiltInAudioEffectDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: BuiltInAudioEffectCategory
    public let effectType: AudioEffectType
    public let parameterDescriptors: [ParameterDescriptor]

    public init(
        id: String,
        name: String,
        category: BuiltInAudioEffectCategory,
        effectType: AudioEffectType,
        parameterDescriptors: [ParameterDescriptor]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.effectType = effectType
        self.parameterDescriptors = parameterDescriptors
    }
}

/// Categories for built-in audio effects.
public enum BuiltInAudioEffectCategory: String, Sendable, Codable, CaseIterable {
    case equalizer
    case dynamics
    case reverb
    case delay
}

// MARK: - Registry

/// Static registry of all built-in audio effects.
public enum BuiltInAudioEffects {
    public static let all: [BuiltInAudioEffectDescriptor] = [
        // Parametric EQ
        BuiltInAudioEffectDescriptor(
            id: "builtin.audio.parametricEQ",
            name: "Parametric EQ",
            category: .equalizer,
            effectType: .eq,
            parameterDescriptors: [
                .float(name: "lowFrequency", displayName: "Low Frequency",
                       defaultValue: 200, min: 20, max: 500),
                .float(name: "lowGain", displayName: "Low Gain",
                       defaultValue: 0, min: -24, max: 24),
                .float(name: "midFrequency", displayName: "Mid Frequency",
                       defaultValue: 1000, min: 200, max: 8000),
                .float(name: "midGain", displayName: "Mid Gain",
                       defaultValue: 0, min: -24, max: 24),
                .float(name: "highFrequency", displayName: "High Frequency",
                       defaultValue: 6000, min: 2000, max: 20000),
                .float(name: "highGain", displayName: "High Gain",
                       defaultValue: 0, min: -24, max: 24),
                .float(name: "globalGain", displayName: "Output Gain",
                       defaultValue: 0, min: -24, max: 24),
            ]
        ),

        // Compressor
        BuiltInAudioEffectDescriptor(
            id: "builtin.audio.compressor",
            name: "Compressor",
            category: .dynamics,
            effectType: .compressor,
            parameterDescriptors: [
                .float(name: "threshold", displayName: "Threshold (dB)",
                       defaultValue: -20, min: -40, max: 20),
                .float(name: "headRoom", displayName: "Head Room (dB)",
                       defaultValue: 5, min: 0.1, max: 40),
                .float(name: "attackTime", displayName: "Attack (s)",
                       defaultValue: 0.001, min: 0.0001, max: 0.2),
                .float(name: "releaseTime", displayName: "Release (s)",
                       defaultValue: 0.05, min: 0.01, max: 3.0),
                .float(name: "masterGain", displayName: "Makeup Gain (dB)",
                       defaultValue: 0, min: -40, max: 40),
            ]
        ),

        // Reverb
        BuiltInAudioEffectDescriptor(
            id: "builtin.audio.reverb",
            name: "Reverb",
            category: .reverb,
            effectType: .reverb,
            parameterDescriptors: [
                .float(name: "wetDryMix", displayName: "Dry/Wet Mix",
                       defaultValue: 30, min: 0, max: 100),
            ]
        ),

        // Delay
        BuiltInAudioEffectDescriptor(
            id: "builtin.audio.delay",
            name: "Delay",
            category: .delay,
            effectType: .delay,
            parameterDescriptors: [
                .float(name: "delayTime", displayName: "Delay Time (s)",
                       defaultValue: 0.3, min: 0, max: 2.0),
                .float(name: "feedback", displayName: "Feedback (%)",
                       defaultValue: 40, min: -100, max: 100),
                .float(name: "lowPassCutoff", displayName: "Low Pass Cutoff (Hz)",
                       defaultValue: 15000, min: 10, max: 20000),
                .float(name: "wetDryMix", displayName: "Dry/Wet Mix",
                       defaultValue: 20, min: 0, max: 100),
            ]
        ),
    ]

    /// Looks up a built-in audio effect descriptor by its ID.
    public static func descriptor(for id: String) -> BuiltInAudioEffectDescriptor? {
        all.first { $0.id == id }
    }

    /// Returns all descriptors in a given category.
    public static func descriptors(in category: BuiltInAudioEffectCategory) -> [BuiltInAudioEffectDescriptor] {
        all.filter { $0.category == category }
    }

    /// Creates an AudioEffectInstance from a descriptor ID with default parameters.
    public static func createInstance(for id: String) -> AudioEffectInstance? {
        guard let desc = descriptor(for: id) else { return nil }
        return AudioEffectInstance(name: desc.name, effectType: desc.effectType)
    }
}

// MARK: - PluginKit AudioEffect Conformances

/// Parametric EQ audio effect wrapping Apple's built-in N-band parametric EQ.
public final class ParametricEQEffect: AudioEffect, @unchecked Sendable {
    public let identifier = "builtin.audio.parametricEQ"
    public let parameterDescriptors: [ParameterDescriptor] =
        BuiltInAudioEffects.descriptor(for: "builtin.audio.parametricEQ")?.parameterDescriptors ?? []

    private var eq: AVAudioUnitEQ?

    public init() {}

    public func prepare(host: any PluginHost) async throws {
        eq = AVAudioUnitEQ(numberOfBands: 3)
    }

    public func teardown() async {
        eq = nil
    }

    #if canImport(AVFoundation)
    public func process(
        input: AVAudioPCMBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> AVAudioPCMBuffer {
        // Parameter application happens through the AVAudioUnit node in the engine graph.
        // This method is for offline/software processing if needed.
        return input
    }
    #endif

    public func process(
        input: UnsafeBufferPointer<Float>,
        output: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double,
        parameters: ParameterValues,
        time: Rational
    ) async throws {
        // Passthrough for software path — real processing happens via AVAudioEngine graph
        guard let inputBase = input.baseAddress,
              let outputBase = output.baseAddress else { return }
        outputBase.update(from: inputBase, count: min(input.count, output.count))
    }
}

/// Dynamics compressor audio effect wrapping Apple's kAudioUnitSubType_DynamicsProcessor.
public final class CompressorEffect: AudioEffect, @unchecked Sendable {
    public let identifier = "builtin.audio.compressor"
    public let parameterDescriptors: [ParameterDescriptor] =
        BuiltInAudioEffects.descriptor(for: "builtin.audio.compressor")?.parameterDescriptors ?? []

    public init() {}

    public func prepare(host: any PluginHost) async throws {}
    public func teardown() async {}

    #if canImport(AVFoundation)
    public func process(
        input: AVAudioPCMBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> AVAudioPCMBuffer {
        return input
    }
    #endif

    public func process(
        input: UnsafeBufferPointer<Float>,
        output: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double,
        parameters: ParameterValues,
        time: Rational
    ) async throws {
        guard let inputBase = input.baseAddress,
              let outputBase = output.baseAddress else { return }
        outputBase.update(from: inputBase, count: min(input.count, output.count))
    }
}

/// Reverb audio effect wrapping Apple's AVAudioUnitReverb (kAudioUnitSubType_Reverb2).
public final class ReverbEffect: AudioEffect, @unchecked Sendable {
    public let identifier = "builtin.audio.reverb"
    public let parameterDescriptors: [ParameterDescriptor] =
        BuiltInAudioEffects.descriptor(for: "builtin.audio.reverb")?.parameterDescriptors ?? []

    public init() {}

    public func prepare(host: any PluginHost) async throws {}
    public func teardown() async {}

    #if canImport(AVFoundation)
    public func process(
        input: AVAudioPCMBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> AVAudioPCMBuffer {
        return input
    }
    #endif

    public func process(
        input: UnsafeBufferPointer<Float>,
        output: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double,
        parameters: ParameterValues,
        time: Rational
    ) async throws {
        guard let inputBase = input.baseAddress,
              let outputBase = output.baseAddress else { return }
        outputBase.update(from: inputBase, count: min(input.count, output.count))
    }
}

/// Delay audio effect wrapping Apple's AVAudioUnitDelay.
public final class DelayEffect: AudioEffect, @unchecked Sendable {
    public let identifier = "builtin.audio.delay"
    public let parameterDescriptors: [ParameterDescriptor] =
        BuiltInAudioEffects.descriptor(for: "builtin.audio.delay")?.parameterDescriptors ?? []

    public init() {}

    public func prepare(host: any PluginHost) async throws {}
    public func teardown() async {}

    #if canImport(AVFoundation)
    public func process(
        input: AVAudioPCMBuffer,
        parameters: ParameterValues,
        time: Rational
    ) async throws -> AVAudioPCMBuffer {
        return input
    }
    #endif

    public func process(
        input: UnsafeBufferPointer<Float>,
        output: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Double,
        parameters: ParameterValues,
        time: Rational
    ) async throws {
        guard let inputBase = input.baseAddress,
              let outputBase = output.baseAddress else { return }
        outputBase.update(from: inputBase, count: min(input.count, output.count))
    }
}
