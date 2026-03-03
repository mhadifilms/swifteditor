import AudioToolbox
import AVFoundation
import Foundation
import Observation

/// Manages an ordered chain of audio effects for a single track.
/// Each effect maps to an AVAudioUnit node that can be wired into an AVAudioEngine graph.
@Observable
public final class AudioEffectChain: @unchecked Sendable {

    /// The ordered list of effect instances in this chain.
    public private(set) var effects: [AudioEffectInstance] = []

    /// The AVAudioUnit nodes corresponding to each effect, keyed by effect ID.
    private var audioUnits: [UUID: AVAudioUnit] = [:]

    public init() {}

    // MARK: - Effect Management

    /// Append an effect to the end of the chain.
    public func append(_ effect: AudioEffectInstance) {
        effects.append(effect)
    }

    /// Remove an effect by ID. Returns the removed instance, if found.
    @discardableResult
    public func remove(id: UUID) -> AudioEffectInstance? {
        audioUnits.removeValue(forKey: id)
        guard let index = effects.firstIndex(where: { $0.id == id }) else { return nil }
        return effects.remove(at: index)
    }

    /// Move an effect from one position to another.
    public func move(fromIndex: Int, toIndex: Int) {
        guard effects.indices.contains(fromIndex), toIndex >= 0, toIndex <= effects.count else {
            return
        }
        let effect = effects.remove(at: fromIndex)
        let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        effects.insert(effect, at: min(insertIndex, effects.count))
    }

    /// Toggle the enabled state of an effect and update its audio unit bypass.
    public func toggleEnabled(id: UUID) {
        guard let effect = effects.first(where: { $0.id == id }) else { return }
        effect.isEnabled.toggle()
        if let unit = audioUnits[id] as? AVAudioUnitEffect {
            unit.bypass = !effect.isEnabled
        }
    }

    // MARK: - Audio Unit Construction

    /// Build (or retrieve cached) AVAudioUnit nodes for all enabled effects in order.
    /// Returns the nodes in chain order, ready for insertion into an AVAudioEngine graph.
    public func buildAudioUnits() -> [AVAudioUnit] {
        var nodes: [AVAudioUnit] = []
        for effect in effects {
            if let existing = audioUnits[effect.id] {
                if let unitEffect = existing as? AVAudioUnitEffect {
                    unitEffect.bypass = !effect.isEnabled
                }
                applyParameters(to: existing, effect: effect)
                nodes.append(existing)
            } else if let unit = Self.buildAudioUnit(for: effect) {
                audioUnits[effect.id] = unit
                nodes.append(unit)
            }
        }
        return nodes
    }

    /// Create an AVAudioUnit for a given effect instance.
    public static func buildAudioUnit(for effect: AudioEffectInstance) -> AVAudioUnit? {
        let unit: AVAudioUnit?
        switch effect.effectType {
        case .eq:
            unit = makeEQ(parameters: effect.parameters)
        case .compressor:
            unit = makeCompressor(parameters: effect.parameters)
        case .reverb:
            unit = makeReverb(parameters: effect.parameters)
        case .delay:
            unit = makeDelay(parameters: effect.parameters)
        case .custom(let desc):
            unit = makeCustom(description: desc)
        }
        if let unitEffect = unit as? AVAudioUnitEffect {
            unitEffect.bypass = !effect.isEnabled
        }
        return unit
    }

    // MARK: - Built-in Effect Factories

    /// Create a 3-band parametric EQ (low / mid / high).
    private static func makeEQ(parameters: [String: Float]) -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        let lowBand = eq.bands[0]
        lowBand.filterType = .lowShelf
        lowBand.frequency = parameters["lowFrequency"] ?? 200
        lowBand.gain = parameters["lowGain"] ?? 0
        lowBand.bypass = false

        let midBand = eq.bands[1]
        midBand.filterType = .parametric
        midBand.frequency = parameters["midFrequency"] ?? 1000
        midBand.gain = parameters["midGain"] ?? 0
        midBand.bandwidth = 1.0
        midBand.bypass = false

        let highBand = eq.bands[2]
        highBand.filterType = .highShelf
        highBand.frequency = parameters["highFrequency"] ?? 6000
        highBand.gain = parameters["highGain"] ?? 0
        highBand.bypass = false

        eq.globalGain = parameters["globalGain"] ?? 0

        return eq
    }

    /// Create a dynamics processor (compressor) using the system AU.
    private static func makeCompressor(parameters: [String: Float]) -> AVAudioUnitEffect {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let compressor = AVAudioUnitEffect(audioComponentDescription: desc)

        let au = compressor.audioUnit
        let threshold = parameters["threshold"] ?? -20
        let headRoom = parameters["headRoom"] ?? 5
        let attackTime = parameters["attackTime"] ?? 0.001
        let releaseTime = parameters["releaseTime"] ?? 0.05
        let masterGain = parameters["masterGain"] ?? 0

        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, threshold, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, headRoom, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, attackTime, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, releaseTime, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, masterGain, 0)

        return compressor
    }

    /// Create a reverb effect using AVAudioUnitReverb.
    private static func makeReverb(parameters: [String: Float]) -> AVAudioUnitReverb {
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = parameters["wetDryMix"] ?? 30
        return reverb
    }

    /// Create a delay effect using AVAudioUnitDelay.
    private static func makeDelay(parameters: [String: Float]) -> AVAudioUnitDelay {
        let delay = AVAudioUnitDelay()
        delay.delayTime = TimeInterval(parameters["delayTime"] ?? 0.3)
        delay.feedback = parameters["feedback"] ?? 40
        delay.lowPassCutoff = parameters["lowPassCutoff"] ?? 15000
        delay.wetDryMix = parameters["wetDryMix"] ?? 20
        return delay
    }

    /// Create a custom effect from an AudioComponentDescription.
    private static func makeCustom(description: AudioComponentDescription) -> AVAudioUnitEffect? {
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    // MARK: - Parameter Application

    /// Apply current parameter values from an effect instance onto its audio unit.
    private func applyParameters(to unit: AVAudioUnit, effect: AudioEffectInstance) {
        let params = effect.parameters
        switch effect.effectType {
        case .eq:
            guard let eq = unit as? AVAudioUnitEQ, eq.bands.count >= 3 else { return }
            eq.bands[0].frequency = params["lowFrequency"] ?? 200
            eq.bands[0].gain = params["lowGain"] ?? 0
            eq.bands[1].frequency = params["midFrequency"] ?? 1000
            eq.bands[1].gain = params["midGain"] ?? 0
            eq.bands[2].frequency = params["highFrequency"] ?? 6000
            eq.bands[2].gain = params["highGain"] ?? 0
            eq.globalGain = params["globalGain"] ?? 0

        case .compressor:
            let au = unit.audioUnit
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, params["threshold"] ?? -20, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, params["headRoom"] ?? 5, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, params["attackTime"] ?? 0.001, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, params["releaseTime"] ?? 0.05, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, params["masterGain"] ?? 0, 0)

        case .reverb:
            guard let reverb = unit as? AVAudioUnitReverb else { return }
            reverb.wetDryMix = params["wetDryMix"] ?? 30

        case .delay:
            guard let delay = unit as? AVAudioUnitDelay else { return }
            delay.delayTime = TimeInterval(params["delayTime"] ?? 0.3)
            delay.feedback = params["feedback"] ?? 40
            delay.lowPassCutoff = params["lowPassCutoff"] ?? 15000
            delay.wetDryMix = params["wetDryMix"] ?? 20

        case .custom:
            break
        }
    }

    /// Remove all cached audio units (call when detaching from engine).
    public func clearAudioUnits() {
        audioUnits.removeAll()
    }
}
