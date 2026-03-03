# Audio Engine for Multi-Track NLE

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [AVAudioEngine Fundamentals](#2-avaudioengine-fundamentals)
3. [Multi-Track Audio Mixing](#3-multi-track-audio-mixing)
4. [Audio Effects Processing](#4-audio-effects-processing)
5. [Custom Audio Effects (AUAudioUnit v3)](#5-custom-audio-effects-auaudiounit-v3)
6. [Waveform Generation & Visualization](#6-waveform-generation--visualization)
7. [Audio Metering (Peak & RMS)](#7-audio-metering-peak--rms)
8. [Sample-Accurate Audio-Video Synchronization](#8-sample-accurate-audio-video-synchronization)
9. [AVAudioMix for Export](#9-avaudiomix-for-export)
10. [Voiceover/Narration Recording](#10-voiceovernarration-recording)
11. [Fades, Crossfades & Ducking](#11-fades-crossfades--ducking)
12. [Keyframeable Volume & Pan Automation](#12-keyframeable-volume--pan-automation)
13. [Audio Format Support](#13-audio-format-support)
14. [Offline / Manual Rendering](#14-offline--manual-rendering)
15. [Timeline Scrubbing & Seeking](#15-timeline-scrubbing--seeking)
16. [FFT & Spectral Analysis](#16-fft--spectral-analysis)
17. [MTAudioProcessingTap](#17-mtaudioprocessingtap)
18. [Recommended Libraries](#18-recommended-libraries)
19. [WWDC Session References](#19-wwdc-session-references)
20. [NLE Audio Engine Architecture Design](#20-nle-audio-engine-architecture-design)

---

## 1. Architecture Overview

An NLE audio engine requires two distinct audio processing paths:

### Real-Time Playback Path (AVAudioEngine)
Used during timeline playback for monitoring with effects:
```
[AVAudioPlayerNode (Track 1)] --\
[AVAudioPlayerNode (Track 2)] ----> [AVAudioMixerNode] --> [Effects Chain] --> [Main Mixer] --> [Output]
[AVAudioPlayerNode (Track N)] --/
[AVAudioInputNode (Voiceover)] -/
```

### Export Path (AVMutableAudioMix + AVAssetExportSession)
Used for final render/export with baked-in volume automation:
```
[AVMutableComposition] --> [AVMutableAudioMix with InputParameters] --> [AVAssetExportSession]
```

### Core Audio Stack (Top to Bottom)
```
AVAudioEngine (High-level Swift API)
    |
AVAudioNode / AVAudioUnit (Node graph)
    |
Audio Units (AUAudioUnit v3)
    |
Core Audio (C API, HAL, Audio Toolbox)
    |
Audio Hardware
```

**Key Principle**: Use `AVAudioEngine` for real-time playback and monitoring. Use `AVMutableAudioMix` + `AVAssetExportSession` for final export. These are complementary systems, not alternatives.

---

## 2. AVAudioEngine Fundamentals

### Basic Engine Setup

```swift
import AVFoundation

class NLEAudioEngine {
    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private let mainMixer: AVAudioMixerNode

    init() {
        // The engine creates a singleton mainMixerNode and outputNode on demand
        mainMixer = engine.mainMixerNode

        // Configure audio session (iOS only; macOS does not use AVAudioSession)
        #if os(iOS)
        configureAudioSession()
        #endif

        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord enables simultaneous input + output (for voiceover)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48000)     // 48 kHz is standard for video
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer for low latency
            try session.setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }
    #endif

    func start() throws {
        // prepare() pre-allocates resources; call before start()
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    func pause() {
        engine.pause()
        // pause() stops hardware but does NOT deallocate resources (unlike stop())
        // Call engine.reset() if you want to clear pending scheduled events
    }

    private func handleConfigurationChange() {
        // Engine is stopped on config change; rewire connections and restart
        makeConnections()
        try? engine.start()
    }

    private func makeConnections() {
        // Rebuild all node connections here
    }
}
```

### Key AVAudioEngine Properties
- `engine.mainMixerNode` -- Singleton mixer; auto-created on first access
- `engine.outputNode` -- Hardware output; always exists
- `engine.inputNode` -- Hardware input (microphone); exists on demand
- `engine.isRunning` -- Whether the engine's audio hardware is active
- `engine.manualRenderingMode` -- For offline processing

### Node Lifecycle
1. **Create** the node: `let player = AVAudioPlayerNode()`
2. **Attach** to engine: `engine.attach(player)`
3. **Connect** nodes: `engine.connect(player, to: mixer, format: format)`
4. **Start** engine: `try engine.start()`
5. **Use** the node: `player.play()`
6. **Detach** when done: `engine.detach(player)` (auto-disconnects)

**Important**: Dynamic reconnections must occur upstream of a mixer. You can attach/detach nodes while the engine is running, but connecting/disconnecting should be done carefully to avoid audio glitches.

---

## 3. Multi-Track Audio Mixing

### Multi-Track Engine with Per-Track Volume and Pan

```swift
class MultiTrackMixer {
    private let engine = AVAudioEngine()
    private var tracks: [AudioTrack] = []

    struct AudioTrack {
        let id: String
        let playerNode: AVAudioPlayerNode
        var volume: Float = 1.0    // 0.0 - 1.0
        var pan: Float = 0.0       // -1.0 (left) to 1.0 (right)
        var isMuted: Bool = false
        var isSoloed: Bool = false
        var audioFile: AVAudioFile?
    }

    func addTrack(id: String, fileURL: URL) throws -> AudioTrack {
        let player = AVAudioPlayerNode()
        let file = try AVAudioFile(forReading: fileURL)

        engine.attach(player)

        // Connect to main mixer; each player gets its own input bus
        let format = file.processingFormat
        engine.connect(player, to: engine.mainMixerNode, format: format)

        var track = AudioTrack(id: id, playerNode: player, audioFile: file)
        tracks.append(track)
        return track
    }

    func removeTrack(id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let track = tracks[index]
        track.playerNode.stop()
        engine.detach(track.playerNode)  // auto-disconnects
        tracks.remove(at: index)
    }

    func setVolume(_ volume: Float, forTrack id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].volume = volume
        // AVAudioPlayerNode conforms to AVAudioMixing protocol
        tracks[index].playerNode.volume = tracks[index].isMuted ? 0.0 : volume
    }

    func setPan(_ pan: Float, forTrack id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].pan = pan
        tracks[index].playerNode.pan = pan
    }

    func setMute(_ muted: Bool, forTrack id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].isMuted = muted
        tracks[index].playerNode.volume = muted ? 0.0 : tracks[index].volume
    }

    /// Play all tracks from a specific time position
    func playAll(from time: TimeInterval) {
        guard engine.isRunning else { return }

        // Get a common start time for sample-accurate sync
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let now = engine.outputNode.lastRenderTime!
        // Add a small offset to ensure all players start at exactly the same time
        let startSampleTime = now.sampleTime + AVAudioFramePosition(0.1 * sampleRate)
        let startTime = AVAudioTime(sampleTime: startSampleTime, atRate: sampleRate)

        for track in tracks {
            guard let file = track.audioFile else { continue }
            track.playerNode.stop()

            // Calculate the start frame within the file
            let startFrame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
            let frameCount = AVAudioFrameCount(file.length - startFrame)

            guard startFrame < file.length, frameCount > 0 else { continue }

            // Schedule a segment of the file
            track.playerNode.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil           // nil = play immediately after previously scheduled content
            )

            // Play at the synchronized start time
            track.playerNode.play(at: startTime)
        }
    }

    func stopAll() {
        for track in tracks {
            track.playerNode.stop()
        }
    }

    /// Get current playback position in seconds
    func currentTime(for trackId: String) -> TimeInterval? {
        guard let track = tracks.first(where: { $0.id == trackId }),
              let nodeTime = track.playerNode.lastRenderTime,
              let playerTime = track.playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
```

### Fan-Out Connections (Sending One Source to Multiple Destinations)

```swift
// Connect sampler to both the main mixer and a distortion effect
let destinations: [AVAudioConnectionPoint] = [
    AVAudioConnectionPoint(node: engine.mainMixerNode, bus: 1),
    AVAudioConnectionPoint(node: distortion, bus: 0)
]
engine.connect(sampler, to: destinations, fromBus: 0, format: stereoFormat)
```

### Sub-Mixer Pattern for Track Groups

```swift
// Create a sub-mixer for a group of tracks (e.g., "Dialog" group)
let dialogMixer = AVAudioMixerNode()
engine.attach(dialogMixer)
engine.connect(dialogMixer, to: engine.mainMixerNode, format: nil)

// Connect dialog tracks to the sub-mixer
for dialogTrack in dialogTracks {
    engine.connect(dialogTrack.playerNode, to: dialogMixer, format: nil)
}

// Control group volume
dialogMixer.outputVolume = 0.8
```

---

## 4. Audio Effects Processing

### Built-in AVAudioUnit Effects

AVAudioEngine provides several built-in effect nodes:

| Effect Class | Description | Key Properties |
|---|---|---|
| `AVAudioUnitReverb` | Room simulation | `wetDryMix`, factory presets |
| `AVAudioUnitDelay` | Echo/delay | `delayTime`, `feedback`, `wetDryMix` |
| `AVAudioUnitDistortion` | Distortion/overdrive | `wetDryMix`, factory presets |
| `AVAudioUnitEQ` | Parametric equalizer | `bands[]`, `globalGain` |
| `AVAudioUnitTimePitch` | Time stretch + pitch shift | `pitch`, `rate` |
| `AVAudioUnitVarispeed` | Playback speed (changes pitch) | `rate` |

### Effects Chain Setup

```swift
class AudioEffectsChain {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    let reverb = AVAudioUnitReverb()
    let delay = AVAudioUnitDelay()

    func setupEffectsChain() {
        // Attach all nodes
        engine.attach(player)
        engine.attach(eq)
        engine.attach(reverb)
        engine.attach(delay)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        // Chain: Player -> EQ -> Reverb -> Delay -> MainMixer -> Output
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: delay, format: format)
        engine.connect(delay, to: engine.mainMixerNode, format: format)

        // Configure EQ bands
        configureEQ()

        // Configure reverb
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 30  // 30% wet

        // Configure delay
        delay.delayTime = 0.3          // 300ms
        delay.feedback = 40            // 40% feedback
        delay.lowPassCutoff = 8000     // Low-pass at 8kHz
        delay.wetDryMix = 20           // 20% wet
    }

    private func configureEQ() {
        let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

        for (index, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 1.0     // 1 octave bandwidth
            band.gain = 0.0          // Flat (no boost/cut) -- range: -96 to +24 dB
            band.bypass = false
        }
        eq.globalGain = 0.0  // No global gain adjustment
    }

    /// Bypass an individual effect
    func setEffectBypass(_ node: AVAudioUnitEffect, bypass: Bool) {
        node.bypass = bypass
    }
}
```

### AVAudioUnitReverb Presets

```swift
// Available factory presets:
let presets: [(String, AVAudioUnitReverbPreset)] = [
    ("Small Room",   .smallRoom),
    ("Medium Room",  .mediumRoom),
    ("Large Room",   .largeRoom),
    ("Medium Hall",  .mediumHall),
    ("Large Hall",   .largeHall),
    ("Plate",        .plate),
    ("Medium Chamber", .mediumChamber),
    ("Large Chamber",  .largeChamber),
    ("Cathedral",    .cathedral),
    ("Large Room 2", .largeRoom2),
    ("Medium Hall 2", .mediumHall2),
    ("Medium Hall 3", .mediumHall3),
    ("Large Hall 2", .largeHall2)
]
```

### AVAudioUnitEQ Filter Types

```swift
// Available filter types for EQ bands:
enum AVAudioUnitEQFilterType {
    case parametric       // Bell curve boost/cut around center frequency
    case lowPass          // Passes frequencies below cutoff
    case highPass         // Passes frequencies above cutoff
    case resonantLowPass  // Low pass with resonance peak
    case resonantHighPass // High pass with resonance peak
    case bandPass         // Passes frequencies in a range
    case bandStop         // Rejects frequencies in a range (notch filter)
    case lowShelf         // Boosts/cuts below cutoff
    case highShelf        // Boosts/cuts above cutoff
    case resonantLowShelf
    case resonantHighShelf
}
```

---

## 5. Custom Audio Effects (AUAudioUnit v3)

For effects not provided by Apple (e.g., compressor, limiter, noise gate), create custom Audio Units.

### Custom AUAudioUnit Subclass

```swift
import AudioToolbox
import AVFoundation

// Step 1: Define AudioComponentDescription
extension AudioComponentDescription {
    static let customEffect = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("cmpx"),  // "compressor" sub-type
        componentManufacturer: fourCC("MyAp"),
        componentFlags: 0,
        componentFlagsMask: 0
    )
}

private func fourCC(_ string: String) -> FourCharCode {
    assert(string.count == 4)
    var result: FourCharCode = 0
    for char in string.utf16 {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}

// Step 2: Create custom AUAudioUnit
class CompressorAudioUnit: AUAudioUnit {
    let inputBus: AUAudioUnitBus
    let outputBus: AUAudioUnitBus
    var _internalRenderBlock: AUInternalRenderBlock

    // Parameters
    var threshold: Float = -20.0    // dB
    var ratio: Float = 4.0          // compression ratio
    var attack: Float = 0.01        // seconds
    var release: Float = 0.1        // seconds
    var makeupGain: Float = 0.0     // dB

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)

        _internalRenderBlock = { _, _, _, _, _, _, _ in
            return kAudioUnitErr_Uninitialized
        }
        try super.init(componentDescription: componentDescription, options: options)

        // Set up the actual render block
        _internalRenderBlock = { [weak self] actionFlags, timestamp, frameCount,
            outputBusNumber, outputData, renderEvent, pullInputBlock in

            guard let self = self else { return kAudioUnitErr_Uninitialized }

            // Pull input audio
            let inputStatus = pullInputBlock?(actionFlags, timestamp, frameCount, 0, outputData)
            guard inputStatus == noErr else { return inputStatus ?? kAudioUnitErr_NoConnection }

            // Process each buffer (channel)
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in ablPointer {
                let samples = UnsafeMutableBufferPointer<Float>(buffer)
                for i in 0..<Int(frameCount) {
                    // Simple hard-knee compression
                    let inputDB = 20.0 * log10f(max(abs(samples[i]), 1e-10))
                    if inputDB > self.threshold {
                        let overDB = inputDB - self.threshold
                        let compressedDB = self.threshold + overDB / self.ratio
                        let gainReduction = compressedDB - inputDB
                        let gainLinear = powf(10.0, (gainReduction + self.makeupGain) / 20.0)
                        samples[i] *= gainLinear
                    }
                }
            }
            return noErr
        }
    }

    override var inputBusses: AUAudioUnitBusArray {
        AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
    }

    override var outputBusses: AUAudioUnitBusArray {
        AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        _internalRenderBlock
    }
}
```

### AVAudioEffectNode Wrapper (Simplified Pattern)

```swift
/// A convenience wrapper to create AVAudioUnitEffect nodes with closure-based DSP
class AVAudioEffectNode: AVAudioUnitEffect {
    convenience init(renderBlock: @escaping AUInternalRenderBlock) {
        // Register the custom AUAudioUnit subclass
        AUAudioUnit.registerSubclass(
            CompressorAudioUnit.self,
            as: .customEffect,
            name: "CustomEffect",
            version: 0
        )
        self.init(audioComponentDescription: .customEffect)

        // Inject the render block
        if let au = self.auAudioUnit as? CompressorAudioUnit {
            au._internalRenderBlock = renderBlock
        }
    }
}

// Usage: Insert into the engine graph
let compressor = AVAudioEffectNode(renderBlock: { actionFlags, timestamp, frameCount,
    outputBusNumber, outputData, renderEvent, pullInputBlock in

    let inputStatus = pullInputBlock?(actionFlags, timestamp, frameCount, 0, outputData)
    guard inputStatus == noErr else { return inputStatus ?? kAudioUnitErr_NoConnection }

    // Apply compression DSP here...

    return noErr
})

engine.attach(compressor)
engine.connect(player, to: compressor, format: nil)
engine.connect(compressor, to: engine.mainMixerNode, format: nil)
```

---

## 6. Waveform Generation & Visualization

### Option A: DSWaveformImage (Recommended for NLE)

**Installation**: Swift Package Manager -- `https://github.com/dmrschmidt/DSWaveformImage` (v14.0.0+)

Supports iOS 15+, macOS 12+, visionOS 1.0+. Two modules: `DSWaveformImage` (core) and `DSWaveformImageViews` (SwiftUI/UIKit views).

#### SwiftUI Static Waveform

```swift
import DSWaveformImage
import DSWaveformImageViews

struct AudioClipWaveform: View {
    let audioURL: URL

    var body: some View {
        WaveformView(audioURL: audioURL) { shape in
            shape.fill(Color.green)
        } placeholder: {
            ProgressView()
        }
        .frame(height: 60)
    }
}
```

#### SwiftUI Styled Waveform

```swift
WaveformView(audioURL: audioURL) { shape in
    shape.fill(
        LinearGradient(
            colors: [.blue, .cyan],
            startPoint: .bottom,
            endPoint: .top
        )
    )
}
```

#### Real-Time Live Waveform

```swift
struct LiveWaveformView: View {
    @State var samples: [Float] = []

    var body: some View {
        WaveformLiveCanvas(samples: samples)
            .frame(height: 60)
    }

    func addSample(_ amplitude: Float) {
        samples.append(amplitude)
    }
}
```

#### Programmatic Waveform Image Generation

```swift
import DSWaveformImage

let drawer = WaveformImageDrawer()
let audioURL = URL(fileURLWithPath: "/path/to/audio.wav")

// Generate waveform image asynchronously
let image = try await drawer.waveformImage(
    fromAudioAt: audioURL,
    with: Waveform.Configuration(
        size: CGSize(width: 800, height: 60),
        style: .filled(.green)
    ),
    renderer: LinearWaveformRenderer()
)
```

#### Extract Raw Amplitude Samples

```swift
let analyzer = WaveformAnalyzer()
// Get 1000 amplitude samples (normalized 0...1)
let samples = try await analyzer.samples(fromAudioAt: audioURL, count: 1000)
```

### Option B: AudioKit Waveform (GPU-Accelerated)

**Repository**: `https://github.com/AudioKit/Waveform`

Uses Metal shaders for GPU-accelerated rendering. Best for very large waveforms or real-time animation. Written in 91.6% Swift + 8.4% Metal.

### Option C: Custom Waveform with vDSP

```swift
import AVFoundation
import Accelerate

func generateWaveformSamples(from url: URL, targetSampleCount: Int) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let totalFrames = AVAudioFrameCount(file.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
        throw NSError(domain: "Waveform", code: 1)
    }
    try file.read(into: buffer)

    guard let channelData = buffer.floatChannelData?[0] else {
        throw NSError(domain: "Waveform", code: 2)
    }

    let framesPerSample = Int(totalFrames) / targetSampleCount
    var output = [Float](repeating: 0, count: targetSampleCount)

    for i in 0..<targetSampleCount {
        let start = i * framesPerSample
        let count = min(framesPerSample, Int(totalFrames) - start)

        // Use vDSP for fast RMS calculation of each segment
        var rms: Float = 0
        vDSP_rmsqv(channelData.advanced(by: start), 1, &rms, vDSP_Length(count))
        output[i] = rms
    }

    return output
}
```

### Rendering Styles Available (DSWaveformImage)

| Style | Description |
|---|---|
| `.filled(Color)` | Solid fill |
| `.outlined(Color, lineWidth)` | Envelope outline |
| `.gradient([Color])` | Gradient fill |
| `.gradientOutlined([Color], lineWidth)` | Gradient + outline |
| `.striped(Waveform.Style.StripeConfig)` | Striped bars |

Two renderer types: `LinearWaveformRenderer` (default), `CircularWaveformRenderer`.

---

## 7. Audio Metering (Peak & RMS)

### Installing a Tap for Level Metering

```swift
class AudioMeter {
    var peakLevel: Float = -160.0     // dB
    var rmsLevel: Float = -160.0      // dB
    var peakLevelRight: Float = -160.0
    var rmsLevelRight: Float = -160.0

    /// Install a metering tap on any audio node
    func installMeter(on node: AVAudioNode, bus: Int = 0) {
        let format = node.outputFormat(forBus: bus)

        // NOTE: Only ONE tap per bus is allowed
        node.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processBuffer(buffer)
        }
    }

    func removeMeter(from node: AVAudioNode, bus: Int = 0) {
        node.removeTap(onBus: bus)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        for channel in 0..<min(channelCount, 2) {
            let data = channelData[channel]

            // Calculate RMS using Accelerate for performance
            var rms: Float = 0
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(frameLength))

            // Calculate peak
            var peak: Float = 0
            vDSP_maxmgv(data, 1, &peak, vDSP_Length(frameLength))

            // Convert to dB (range: -160 to 0)
            let rmsDB = 20 * log10(max(rms, 1e-8))
            let peakDB = 20 * log10(max(peak, 1e-8))

            // Apply smoothing (ballistic filter)
            let smoothingFactor: Float = 0.3  // Lower = slower decay

            if channel == 0 {
                self.rmsLevel = max(rmsDB, self.rmsLevel - smoothingFactor)
                self.peakLevel = max(peakDB, self.peakLevel - smoothingFactor)
            } else {
                self.rmsLevelRight = max(rmsDB, self.rmsLevelRight - smoothingFactor)
                self.peakLevelRight = max(peakDB, self.peakLevelRight - smoothingFactor)
            }
        }
    }

    /// Normalize dB value to 0...1 range for UI display
    /// Uses -60 dB as floor (typical for professional meters)
    func normalizedLevel(_ db: Float, floor: Float = -60.0) -> Float {
        if db <= floor { return 0.0 }
        if db >= 0.0 { return 1.0 }
        return (db - floor) / (0.0 - floor)
    }
}
```

### Per-Track Metering in Multi-Track Setup

```swift
// For per-track metering, install taps on individual player nodes:
for track in tracks {
    audioMeter.installMeter(on: track.playerNode)
}

// For master output metering, install on the main mixer:
audioMeter.installMeter(on: engine.mainMixerNode)
```

### SwiftUI Meter View

```swift
struct LevelMeterView: View {
    let level: Float  // normalized 0...1
    let peak: Float   // normalized 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background
                Rectangle().fill(Color.gray.opacity(0.3))

                // RMS level bar with gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),
                                .init(color: .yellow, location: 0.7),
                                .init(color: .red, location: 0.95)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geo.size.height * CGFloat(level))

                // Peak indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 2)
                    .offset(y: -geo.size.height * CGFloat(peak))
            }
        }
        .frame(width: 12)
    }
}
```

---

## 8. Sample-Accurate Audio-Video Synchronization

### Understanding AVAudioEngine Timing

AVAudioPlayerNode operates with three timing concepts:

1. **Render Time** (global): `node.lastRenderTime` -- engine-wide timeline in samples
2. **Node Time** (local): A node's perspective of render time
3. **Player Time**: Maps to the audio file's position in the scheduled content

```swift
// Get current playback position accurately
func currentPlaybackTime(for player: AVAudioPlayerNode) -> TimeInterval? {
    guard let nodeTime = player.lastRenderTime,
          nodeTime.isSampleTimeValid,
          let playerTime = player.playerTime(forNodeTime: nodeTime) else {
        return nil
    }
    return Double(playerTime.sampleTime) / playerTime.sampleRate
}
```

### Synchronizing Multiple Players

```swift
func playSynchronized(_ players: [AVAudioPlayerNode]) {
    // All players must be attached and connected to the engine
    let outputNode = engine.outputNode
    guard let lastRenderTime = outputNode.lastRenderTime else { return }

    // Schedule all players to start at the same sample time
    let sampleRate = outputNode.outputFormat(forBus: 0).sampleRate
    // Add a small lookahead (100ms) to ensure all buffers are ready
    let startSample = lastRenderTime.sampleTime + AVAudioFramePosition(0.1 * sampleRate)
    let startTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)

    for player in players {
        player.play(at: startTime)
    }
}
```

### Audio-Video Sync Strategy for NLE

```swift
class AVSyncController {
    private let audioEngine: MultiTrackMixer
    private var displayLink: CVDisplayLink?
    private var masterClock: CMClock

    init() {
        self.masterClock = CMClockGetHostTimeClock()
        self.audioEngine = MultiTrackMixer()
    }

    /// The video playback position drives audio scheduling
    /// Video renders via CVDisplayLink callback; audio follows
    func seek(to time: CMTime) {
        let seconds = CMTimeGetSeconds(time)

        // Stop all audio players
        audioEngine.stopAll()

        // Re-schedule audio from the new position
        audioEngine.playAll(from: seconds)
    }

    /// Convert between audio sample time and video CMTime
    func cmTime(fromSampleTime sampleTime: AVAudioFramePosition,
                sampleRate: Double) -> CMTime {
        return CMTimeMakeWithSeconds(
            Double(sampleTime) / sampleRate,
            preferredTimescale: 600  // Common timescale for video
        )
    }

    func sampleTime(fromCMTime time: CMTime, sampleRate: Double) -> AVAudioFramePosition {
        return AVAudioFramePosition(CMTimeGetSeconds(time) * sampleRate)
    }
}
```

### Key Sync Principles
- Use **48000 Hz** sample rate (standard for video production)
- Video timescale of **600** (LCM of 24, 25, 30 fps) works well for audio alignment
- The `CMTime` is the universal time currency in AVFoundation
- When seeking, always stop and re-schedule audio players; do NOT try to seek a playing `AVAudioPlayerNode`
- For scrubbing, use short buffer scheduling with `.interrupts` option

---

## 9. AVAudioMix for Export

### Volume Automation During Export

```swift
import AVFoundation

class AudioExporter {

    /// Export a composition with volume automation applied
    func exportWithAudioMix(
        composition: AVMutableComposition,
        volumeKeyframes: [(time: CMTime, volume: Float)],
        outputURL: URL
    ) async throws {
        // Get all audio tracks from the composition
        let audioTracks = composition.tracks(withMediaType: .audio)

        var inputParameters: [AVMutableAudioMixInputParameters] = []

        for track in audioTracks {
            let params = AVMutableAudioMixInputParameters(track: track)

            // Apply volume keyframes as volume ramps
            for i in 0..<volumeKeyframes.count - 1 {
                let current = volumeKeyframes[i]
                let next = volumeKeyframes[i + 1]

                let timeRange = CMTimeRange(
                    start: current.time,
                    end: next.time
                )

                params.setVolumeRamp(
                    fromStartVolume: current.volume,
                    toEndVolume: next.volume,
                    timeRange: timeRange
                )
            }

            inputParameters.append(params)
        }

        // Create the audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        // Configure exporter
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "Export", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not create export session"
            ])
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.audioMix = audioMix

        await exporter.export()

        if let error = exporter.error {
            throw error
        }
    }

    /// Fade in at the beginning of a track
    func createFadeIn(for track: AVCompositionTrack,
                      duration: CMTime) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolumeRamp(
            fromStartVolume: 0.0,
            toEndVolume: 1.0,
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        return params
    }

    /// Fade out at the end of a track
    func createFadeOut(for track: AVCompositionTrack,
                       trackDuration: CMTime,
                       fadeDuration: CMTime) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)
        let fadeStart = trackDuration - fadeDuration
        params.setVolumeRamp(
            fromStartVolume: 1.0,
            toEndVolume: 0.0,
            timeRange: CMTimeRange(start: fadeStart, duration: fadeDuration)
        )
        return params
    }

    /// Set volume at a specific point (instantaneous change)
    func setVolume(_ volume: Float, at time: CMTime,
                   for track: AVCompositionTrack) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolume(volume, at: time)
        return params
    }
}
```

### Using AVAssetReader for Custom Audio Export

```swift
/// Read audio with mix applied, for custom processing during export
func readAudioWithMix(asset: AVAsset, audioMix: AVAudioMix) throws -> AVAudioPCMBuffer {
    let reader = try AVAssetReader(asset: asset)

    let audioTracks = asset.tracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else { throw NSError(domain: "Export", code: 2) }

    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: true,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2
    ]

    // Mix output reads all audio tracks mixed together
    let mixOutput = AVAssetReaderAudioMixOutput(
        audioTracks: audioTracks,
        audioSettings: outputSettings
    )
    mixOutput.audioMix = audioMix  // Apply the volume automation

    reader.add(mixOutput)
    reader.startReading()

    // Read all sample buffers...
    while reader.status == .reading {
        if let sampleBuffer = mixOutput.copyNextSampleBuffer() {
            // Process audio samples
        }
    }
    // Return processed buffer
    fatalError("Full implementation needed based on use case")
}
```

---

## 10. Voiceover/Narration Recording

### Simultaneous Playback + Recording

```swift
class VoiceoverRecorder {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var outputFile: AVAudioFile?
    private var isRecording = false

    func setup() throws {
        #if os(iOS)
        // CRITICAL: Use .playAndRecord category for simultaneous input + output
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [
            .defaultToSpeaker,
            .allowBluetooth
        ])
        try session.setActive(true)
        #endif

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        try engine.start()
    }

    /// Start recording from microphone while playing timeline audio
    func startRecording(saveTo url: URL) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output file matching input format
        outputFile = try AVAudioFile(
            forWriting: url,
            settings: inputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Install tap on input node to capture microphone audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, time in
            guard let self = self, self.isRecording else { return }
            do {
                try self.outputFile?.write(from: buffer)
            } catch {
                print("Error writing audio: \(error)")
            }
        }

        isRecording = true
    }

    func stopRecording() {
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        outputFile = nil  // Close the file
    }

    /// Play back the timeline audio while recording
    func playTimeline(file: AVAudioFile) {
        player.scheduleFile(file, at: nil)
        player.play()
    }

    /// Record a voiceover directly to the main mixer output (includes both mic + timeline)
    func startMixedRecording(saveTo url: URL) throws {
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)

        outputFile = try AVAudioFile(forWriting: url, settings: format.settings)

        mainMixer.installTap(onBus: 0, bufferSize: 4096, format: format) {
            [weak self] buffer, time in
            try? self?.outputFile?.write(from: buffer)
        }

        isRecording = true
    }
}
```

### Input Monitoring (Hear Yourself While Recording)

```swift
// The input node is automatically connected to the main mixer when you start the engine
// If you want to monitor input with effects:
let inputNode = engine.inputNode
let inputFormat = inputNode.outputFormat(forBus: 0)

let inputMixer = AVAudioMixerNode()
engine.attach(inputMixer)
engine.connect(inputNode, to: inputMixer, format: inputFormat)
engine.connect(inputMixer, to: engine.mainMixerNode, format: inputFormat)

// Control monitoring volume separately
inputMixer.outputVolume = 0.5
```

---

## 11. Fades, Crossfades & Ducking

### Fade In / Fade Out During Playback

```swift
class AudioFader {

    /// Linear volume fade using a timer (for real-time playback)
    func fade(player: AVAudioPlayerNode,
              from startVolume: Float,
              to endVolume: Float,
              duration: TimeInterval,
              completion: (() -> Void)? = nil) {

        let steps = Int(duration * 60) // 60 updates per second
        let volumeStep = (endVolume - startVolume) / Float(steps)
        let timeStep = duration / Double(steps)

        player.volume = startVolume

        var currentStep = 0
        Timer.scheduledTimer(withTimeInterval: timeStep, repeats: true) { timer in
            currentStep += 1
            if currentStep >= steps {
                player.volume = endVolume
                timer.invalidate()
                completion?()
            } else {
                player.volume = startVolume + volumeStep * Float(currentStep)
            }
        }
    }

    /// Exponential fade (sounds more natural to human ears)
    /// velocity: 0 = linear, 2-5 = natural sounding
    func exponentialFade(player: AVAudioPlayerNode,
                         from startVolume: Float,
                         to endVolume: Float,
                         duration: TimeInterval,
                         velocity: Float = 3.0) {
        let steps = Int(duration * 60)
        let timeStep = duration / Double(steps)

        var currentStep = 0
        Timer.scheduledTimer(withTimeInterval: timeStep, repeats: true) { timer in
            currentStep += 1
            if currentStep >= steps {
                player.volume = endVolume
                timer.invalidate()
            } else {
                let progress = Float(currentStep) / Float(steps)
                let curved = pow(progress, velocity)
                player.volume = startVolume + (endVolume - startVolume) * curved
            }
        }
    }
}
```

### Crossfade Between Two Clips

```swift
/// Crossfade between outgoing and incoming audio clips
func crossfade(outgoing: AVAudioPlayerNode,
               incoming: AVAudioPlayerNode,
               duration: TimeInterval) {
    let fader = AudioFader()

    // Start incoming at zero volume
    incoming.volume = 0.0
    incoming.play()

    // Fade out the outgoing
    fader.exponentialFade(player: outgoing, from: 1.0, to: 0.0, duration: duration) {
        outgoing.stop()
    }

    // Fade in the incoming
    fader.exponentialFade(player: incoming, from: 0.0, to: 1.0, duration: duration)
}
```

### Volume Automation During Export (Crossfade)

```swift
/// Create a crossfade between two adjacent clips during export
func createCrossfadeParams(
    trackA: AVCompositionTrack,
    trackB: AVCompositionTrack,
    crossfadeStart: CMTime,
    crossfadeDuration: CMTime
) -> [AVMutableAudioMixInputParameters] {

    let paramsA = AVMutableAudioMixInputParameters(track: trackA)
    let paramsB = AVMutableAudioMixInputParameters(track: trackB)

    let crossfadeRange = CMTimeRange(start: crossfadeStart, duration: crossfadeDuration)

    // Track A fades out
    paramsA.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: crossfadeRange)

    // Track B fades in
    paramsB.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: crossfadeRange)

    return [paramsA, paramsB]
}
```

### Audio Ducking

#### System-Level Ducking (AVAudioSession)

```swift
// Simple: Duck other apps' audio when your app plays
#if os(iOS)
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, options: [.duckOthers])
try session.setActive(true)
#endif
```

#### Custom Ducking in NLE (Programmatic)

```swift
class AudioDucker {
    /// Automatically reduce music volume when dialog is present
    /// This is used during real-time playback
    func applyDucking(musicPlayer: AVAudioPlayerNode,
                      dialogPlayer: AVAudioPlayerNode,
                      duckLevel: Float = 0.2,          // Music level when dialog plays
                      normalLevel: Float = 1.0,         // Music level when no dialog
                      attackTime: TimeInterval = 0.3,    // How fast to duck
                      releaseTime: TimeInterval = 0.5) { // How fast to restore

        // Install a tap on the dialog track to detect voice activity
        let format = dialogPlayer.outputFormat(forBus: 0)
        dialogPlayer.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            guard let channelData = buffer.floatChannelData else { return }

            // Calculate RMS level of dialog
            var rms: Float = 0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(buffer.frameLength))
            let dbLevel = 20 * log10(max(rms, 1e-8))

            // If dialog is above threshold, duck the music
            let threshold: Float = -40.0  // dB
            DispatchQueue.main.async {
                if dbLevel > threshold {
                    // Dialog detected -- duck music
                    musicPlayer.volume = duckLevel
                } else {
                    // No dialog -- restore music
                    musicPlayer.volume = normalLevel
                }
            }
        }
    }

    /// Generate ducking keyframes for export
    func generateDuckingKeyframes(
        dialogTimes: [(start: CMTime, end: CMTime)],
        duckLevel: Float = 0.2,
        fadeDuration: CMTime = CMTime(seconds: 0.3, preferredTimescale: 600)
    ) -> [(time: CMTime, volume: Float)] {
        var keyframes: [(time: CMTime, volume: Float)] = []
        keyframes.append((time: .zero, volume: 1.0))

        for dialog in dialogTimes {
            // Ramp down before dialog starts
            let duckStart = dialog.start - fadeDuration
            keyframes.append((time: duckStart, volume: 1.0))
            keyframes.append((time: dialog.start, volume: duckLevel))

            // Ramp back up after dialog ends
            let duckEnd = dialog.end
            keyframes.append((time: duckEnd, volume: duckLevel))
            let restoreEnd = duckEnd + fadeDuration
            keyframes.append((time: restoreEnd, volume: 1.0))
        }

        return keyframes
    }
}
```

---

## 12. Keyframeable Volume & Pan Automation

### Keyframe Data Model

```swift
import CoreMedia

struct AudioKeyframe: Identifiable, Comparable {
    let id = UUID()
    var time: CMTime
    var value: Float           // Volume: 0...1, Pan: -1...1
    var interpolation: InterpolationType

    enum InterpolationType {
        case linear            // Straight line between keyframes
        case hold              // Step function (no interpolation)
        case bezier(Float)     // Curved interpolation with tension parameter
        case logarithmic       // Natural-sounding volume curves
    }

    static func < (lhs: AudioKeyframe, rhs: AudioKeyframe) -> Bool {
        CMTimeCompare(lhs.time, rhs.time) < 0
    }
}

class AudioAutomation {
    var volumeKeyframes: [AudioKeyframe] = []
    var panKeyframes: [AudioKeyframe] = []

    /// Get interpolated volume at a specific time
    func volume(at time: CMTime) -> Float {
        return interpolatedValue(keyframes: volumeKeyframes, at: time)
    }

    /// Get interpolated pan at a specific time
    func pan(at time: CMTime) -> Float {
        return interpolatedValue(keyframes: panKeyframes, at: time)
    }

    private func interpolatedValue(keyframes: [AudioKeyframe], at time: CMTime) -> Float {
        guard !keyframes.isEmpty else { return 1.0 }

        let sorted = keyframes.sorted()

        // Before first keyframe
        if CMTimeCompare(time, sorted.first!.time) <= 0 {
            return sorted.first!.value
        }

        // After last keyframe
        if CMTimeCompare(time, sorted.last!.time) >= 0 {
            return sorted.last!.value
        }

        // Find surrounding keyframes
        for i in 0..<sorted.count - 1 {
            let current = sorted[i]
            let next = sorted[i + 1]

            if CMTimeCompare(time, current.time) >= 0 &&
               CMTimeCompare(time, next.time) <= 0 {

                switch current.interpolation {
                case .hold:
                    return current.value

                case .linear:
                    let totalDuration = CMTimeGetSeconds(next.time - current.time)
                    let elapsed = CMTimeGetSeconds(time - current.time)
                    let progress = Float(elapsed / totalDuration)
                    return current.value + (next.value - current.value) * progress

                case .bezier(let tension):
                    let totalDuration = CMTimeGetSeconds(next.time - current.time)
                    let elapsed = CMTimeGetSeconds(time - current.time)
                    let t = Float(elapsed / totalDuration)
                    // Cubic bezier with tension
                    let curved = t * t * (3.0 - 2.0 * t) * tension + t * (1.0 - tension)
                    return current.value + (next.value - current.value) * curved

                case .logarithmic:
                    let totalDuration = CMTimeGetSeconds(next.time - current.time)
                    let elapsed = CMTimeGetSeconds(time - current.time)
                    let t = Float(elapsed / totalDuration)
                    // Logarithmic curve (more natural for volume)
                    let curved = log10(1.0 + 9.0 * t)
                    return current.value + (next.value - current.value) * curved
                }
            }
        }

        return 1.0
    }
}
```

### Applying Automation During Playback

```swift
class AutomationPlayer {
    private let engine = AVAudioEngine()
    private var automationTimer: Timer?
    private var tracks: [(player: AVAudioPlayerNode, automation: AudioAutomation)] = []

    /// Start playback with real-time automation
    func play(from startTime: CMTime) {
        // Start a high-frequency timer to update volume/pan
        let updateInterval = 1.0 / 60.0  // 60 Hz updates

        automationTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateAutomation()
        }
    }

    private func updateAutomation() {
        for (player, automation) in tracks {
            guard let nodeTime = player.lastRenderTime,
                  let playerTime = player.playerTime(forNodeTime: nodeTime) else {
                continue
            }

            let currentTime = CMTimeMakeWithSeconds(
                Double(playerTime.sampleTime) / playerTime.sampleRate,
                preferredTimescale: 600
            )

            // Apply interpolated values
            player.volume = automation.volume(at: currentTime)
            player.pan = automation.pan(at: currentTime)
        }
    }

    func stop() {
        automationTimer?.invalidate()
        automationTimer = nil
    }
}
```

### Converting Keyframes to AVMutableAudioMixInputParameters for Export

```swift
extension AudioAutomation {
    /// Convert volume keyframes to AVMutableAudioMixInputParameters for export
    func toMixInputParameters(track: AVCompositionTrack) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)

        let sorted = volumeKeyframes.sorted()

        // Set initial volume
        if let first = sorted.first {
            params.setVolume(first.value, at: first.time)
        }

        // Apply ramps between keyframes
        for i in 0..<sorted.count - 1 {
            let current = sorted[i]
            let next = sorted[i + 1]

            switch current.interpolation {
            case .hold:
                // Hold: set volume at start, then set new volume at next keyframe
                params.setVolume(current.value, at: current.time)

            case .linear, .bezier, .logarithmic:
                // Linear ramp (AVFoundation only supports linear ramps natively)
                // For bezier/log curves, subdivide into many small linear ramps
                if case .linear = current.interpolation {
                    params.setVolumeRamp(
                        fromStartVolume: current.value,
                        toEndVolume: next.value,
                        timeRange: CMTimeRange(start: current.time, end: next.time)
                    )
                } else {
                    // Approximate curves with multiple linear segments
                    let segments = 20
                    let totalDuration = CMTimeGetSeconds(next.time - current.time)
                    for s in 0..<segments {
                        let t1 = Double(s) / Double(segments)
                        let t2 = Double(s + 1) / Double(segments)
                        let startTime = current.time + CMTimeMakeWithSeconds(
                            t1 * totalDuration, preferredTimescale: 600)
                        let endTime = current.time + CMTimeMakeWithSeconds(
                            t2 * totalDuration, preferredTimescale: 600)

                        let v1 = interpolateValue(current.value, next.value,
                                                   progress: Float(t1),
                                                   type: current.interpolation)
                        let v2 = interpolateValue(current.value, next.value,
                                                   progress: Float(t2),
                                                   type: current.interpolation)

                        params.setVolumeRamp(
                            fromStartVolume: v1,
                            toEndVolume: v2,
                            timeRange: CMTimeRange(start: startTime, end: endTime)
                        )
                    }
                }
            }
        }

        return params
    }

    private func interpolateValue(_ start: Float, _ end: Float,
                                   progress: Float,
                                   type: AudioKeyframe.InterpolationType) -> Float {
        switch type {
        case .logarithmic:
            let curved = log10(1.0 + 9.0 * progress)
            return start + (end - start) * curved
        case .bezier(let tension):
            let t = progress
            let curved = t * t * (3.0 - 2.0 * t) * tension + t * (1.0 - tension)
            return start + (end - start) * curved
        default:
            return start + (end - start) * progress
        }
    }
}
```

---

## 13. Audio Format Support

### Natively Supported Formats

| Format | File Extensions | Read | Write | Notes |
|---|---|---|---|---|
| AAC | .aac, .m4a | Yes | Yes | Lossy, hardware-accelerated decode |
| Apple Lossless (ALAC) | .m4a | Yes | Yes | Lossless compression |
| WAV | .wav | Yes | Yes | Uncompressed PCM |
| AIFF | .aif, .aiff | Yes | Yes | Uncompressed PCM |
| CAF | .caf | Yes | Yes | Apple container; supports all codecs |
| MP3 | .mp3 | Yes | No* | Read-only; *needs third-party for encode |
| FLAC | .flac | Yes | Yes | macOS 11+ / iOS 14.5+ |
| AC-3 / E-AC-3 | .ac3, .eac3 | Yes | No | Dolby Digital |
| Opus | .opus | Yes | Yes | macOS 11+ / iOS 14+ |

### AVAudioFile: Reading Any Supported Format

```swift
// AVAudioFile automatically decodes to PCM for processing
let file = try AVAudioFile(forReading: url)
// file.processingFormat is always PCM (Float32 or Float64)
// file.fileFormat describes the on-disk format

print("File format: \(file.fileFormat)")
print("Processing format: \(file.processingFormat)")
print("Duration: \(Double(file.length) / file.processingFormat.sampleRate) seconds")
print("Sample rate: \(file.processingFormat.sampleRate) Hz")
print("Channels: \(file.processingFormat.channelCount)")
```

### AVAudioConverter: Format Conversion

```swift
/// Convert audio between formats (e.g., WAV to AAC)
func convertAudio(inputURL: URL, outputURL: URL,
                  outputFormat: AVAudioFormat,
                  outputSettings: [String: Any]) throws {
    let inputFile = try AVAudioFile(forReading: inputURL)
    let inputFormat = inputFile.processingFormat

    let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

    let outputFile = try AVAudioFile(
        forWriting: outputURL,
        settings: outputSettings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )

    let bufferCapacity: AVAudioFrameCount = 4096
    let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: bufferCapacity)!

    while true {
        try inputFile.read(into: inputBuffer)
        if inputBuffer.frameLength == 0 { break }

        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: bufferCapacity
        )!

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { packetCount, status in
            status.pointee = .haveData
            return inputBuffer
        }

        if let error = error { throw error }
        try outputFile.write(from: outputBuffer)
    }
}
```

### Common Output Settings for Export

```swift
// AAC export settings (standard for video)
let aacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitRateKey: 256000  // 256 kbps
]

// WAV/PCM export settings (lossless)
let wavSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 24,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsNonInterleaved: false
]

// FLAC export settings (lossless compressed)
let flacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatFLAC,
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2
]

// Apple Lossless export settings
let alacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatAppleLossless,
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitDepthHintKey: 24
]
```

---

## 14. Offline / Manual Rendering

### Complete Offline Rendering Example

Offline rendering is essential for NLE export: apply the full effects chain to audio faster than real-time.

```swift
class OfflineAudioRenderer {

    /// Render audio file through an effects chain offline (faster than real-time)
    func renderOffline(
        inputURL: URL,
        outputURL: URL,
        configureEffects: (AVAudioEngine, AVAudioPlayerNode) -> Void
    ) throws {
        let sourceFile = try AVAudioFile(forReading: inputURL)
        let format = sourceFile.processingFormat

        // Create engine and nodes
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)

        // Let the caller configure effects chain
        configureEffects(engine, player)

        // Schedule the source file
        player.scheduleFile(sourceFile, at: nil)

        // Enable offline manual rendering
        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format,
                                              maximumFrameCount: maxFrames)

        try engine.start()
        player.play()

        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: sourceFile.fileFormat.settings
        )

        // Create render buffer
        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )!

        // Render loop
        while engine.manualRenderingSampleTime < sourceFile.length {
            let framesToRender = min(
                buffer.frameCapacity,
                AVAudioFrameCount(sourceFile.length - engine.manualRenderingSampleTime)
            )

            let status = try engine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode:
                break  // Input node has no more data
            case .cannotDoInCurrentContext:
                break  // Retry next iteration
            case .error:
                throw NSError(domain: "OfflineRender", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Render failed"])
            @unknown default:
                break
            }
        }

        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
    }
}

// Usage:
let renderer = OfflineAudioRenderer()
try renderer.renderOffline(inputURL: inputURL, outputURL: outputURL) { engine, player in
    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.largeChamber)
    reverb.wetDryMix = 40

    let eq = AVAudioUnitEQ(numberOfBands: 3)
    // Configure EQ bands...

    engine.attach(reverb)
    engine.attach(eq)

    let format = player.outputFormat(forBus: 0)
    engine.connect(player, to: eq, format: format)
    engine.connect(eq, to: reverb, format: format)
    engine.connect(reverb, to: engine.mainMixerNode, format: format)
}
```

### Key Notes on Offline Rendering
- Do NOT use AVAudioPlayerNode with **realtime** manual rendering mode; use it only with **offline** mode
- In offline mode, there are no real-time constraints; nodes may use more expensive algorithms
- Manual rendering mode is set per-engine; a separate engine is typically created for export
- The `manualRenderingSampleTime` property tracks progress through the render

---

## 15. Timeline Scrubbing & Seeking

### Seeking to a Position

```swift
class AudioScrubber {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var audioFiles: [AVAudioFile] = []

    /// Seek to a specific time in the timeline
    func seek(to time: TimeInterval) {
        for (index, player) in players.enumerated() {
            guard index < audioFiles.count else { continue }
            let file = audioFiles[index]

            // Stop current playback
            player.stop()

            // Calculate the frame to start from
            let sampleRate = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(time * sampleRate)

            guard startFrame < file.length else { continue }

            let remainingFrames = AVAudioFrameCount(file.length - startFrame)

            // Schedule segment from the seek position
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: remainingFrames,
                at: nil
            )
        }
    }

    /// Scrub: play a very short segment at the cursor position
    func scrub(at time: TimeInterval, duration: TimeInterval = 0.05) {
        for (index, player) in players.enumerated() {
            guard index < audioFiles.count else { continue }
            let file = audioFiles[index]

            player.stop()

            let sampleRate = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(time * sampleRate)
            let frameCount = AVAudioFrameCount(duration * sampleRate)

            guard startFrame < file.length else { continue }
            let actualFrameCount = min(frameCount, AVAudioFrameCount(file.length - startFrame))

            // Use .interrupts to cancel any previously scheduled buffers
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: actualFrameCount,
                at: nil
            )
            player.play()
        }
    }
}
```

### Seeking Best Practices
- Always **stop** the player before scheduling new content
- Use `scheduleSegment` to start from an arbitrary frame position
- For scrubbing, play very short segments (30-100ms)
- The `.interrupts` option on `scheduleBuffer` can cancel pending buffers
- Add a small pre-roll buffer to avoid clicks at seek points

---

## 16. FFT & Spectral Analysis

### Using Accelerate/vDSP for FFT

```swift
import Accelerate

class AudioSpectralAnalyzer {
    private let fftSize: Int
    private let fftSetup: vDSP_DFT_Setup
    private var window: [Float]

    init(fftSize: Int = 2048) {
        self.fftSize = fftSize
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil, vDSP_Length(fftSize), .FORWARD
        )!

        // Create Hann window to reduce spectral leakage
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    /// Compute magnitude spectrum from audio buffer
    func analyze(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let frameCount = min(Int(buffer.frameLength), fftSize)

        // Apply window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(frameCount))

        // Split into real and imaginary parts
        var realInput = [Float](repeating: 0, count: fftSize / 2)
        var imagInput = [Float](repeating: 0, count: fftSize / 2)
        var realOutput = [Float](repeating: 0, count: fftSize / 2)
        var imagOutput = [Float](repeating: 0, count: fftSize / 2)

        // Deinterleave
        for i in 0..<fftSize / 2 {
            realInput[i] = windowed[2 * i]
            imagInput[i] = windowed[2 * i + 1]
        }

        // Perform FFT
        vDSP_DFT_Execute(fftSetup, &realInput, &imagInput, &realOutput, &imagOutput)

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var complex = DSPSplitComplex(realp: &realOutput, imagp: &imagOutput)
        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Convert to dB
        var dbMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        var one: Float = 1.0
        vDSP_vdbcon(&magnitudes, 1, &one, &dbMagnitudes, 1, vDSP_Length(fftSize / 2), 0)

        return dbMagnitudes
    }

    /// Get frequency for a given bin index
    func frequency(forBin bin: Int, sampleRate: Double) -> Double {
        return Double(bin) * sampleRate / Double(fftSize)
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }
}

// Usage: Install tap and analyze
func startSpectrumAnalysis(on node: AVAudioNode) {
    let analyzer = AudioSpectralAnalyzer(fftSize: 2048)
    let format = node.outputFormat(forBus: 0)

    node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
        let spectrum = analyzer.analyze(buffer: buffer)
        // Update UI with spectrum data
        DispatchQueue.main.async {
            // Update spectrum visualization
        }
    }
}
```

---

## 17. MTAudioProcessingTap

MTAudioProcessingTap allows real-time audio processing within the AVFoundation playback pipeline (AVPlayer). This is useful for processing audio during video playback without AVAudioEngine.

```swift
import AVFoundation
import MediaToolbox

class AudioTapProcessor {

    /// Attach an audio processing tap to an AVPlayerItem's audio track
    func attachTap(to playerItem: AVPlayerItem,
                   processBlock: @escaping (UnsafeMutablePointer<AudioBufferList>,
                                            CMItemCount) -> Void) {
        guard let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first else {
            return
        }

        // Create tap callbacks
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )

        if status == noErr, let tap = tap {
            let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
            inputParams.audioTapProcessor = tap.takeRetainedValue()

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            playerItem.audioMix = audioMix
        }
    }
}

// Tap callback functions (C-style)
private func tapInit(tap: MTAudioProcessingTap,
                      clientInfo: UnsafeMutableRawPointer?,
                      tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {}
private func tapPrepare(tap: MTAudioProcessingTap,
                         maxFrames: CMItemCount,
                         processingFormat: UnsafePointer<AudioStreamBasicDescription>) {}
private func tapUnprepare(tap: MTAudioProcessingTap) {}

private func tapProcess(tap: MTAudioProcessingTap,
                         numberFrames: CMItemCount,
                         flags: MTAudioProcessingTapFlags,
                         bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                         numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                         flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    // Get the source audio
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    // Process audio buffers here (e.g., apply effects, analyze levels)
    // IMPORTANT: This runs on a real-time thread -- no blocking calls!
}
```

**Key Limitation**: MTAudioProcessingTap does NOT work with HTTP Live Streaming or all remote sources.

---

## 18. Recommended Libraries

### Waveform Visualization

| Library | Stars | Features | SPM |
|---|---|---|---|
| [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) | High | SwiftUI/UIKit, static + live, 5 styles | Yes |
| [AudioKit/Waveform](https://github.com/AudioKit/Waveform) | 250+ | GPU (Metal) accelerated, SwiftUI | Yes |
| [FDWaveformView](https://github.com/fulldecent/FDWaveformView) | High | UIKit, antialiased, scrubbing | Yes |
| [SoundWaveForm](https://github.com/benoit-pereira-da-silva/SoundWaveForm) | Moderate | macOS + iOS, video support | Yes |

### Audio Frameworks

| Library | Purpose | Notes |
|---|---|---|
| [AudioKit](https://github.com/AudioKit/AudioKit) | Full audio toolkit | Synthesis, effects, analysis. SPM. |
| [Chassis-iOS](https://github.com/diatrevolo/Chassis-iOS) | Multi-track wrapper | Wraps AVAudioEngine for multi-track |
| [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) | Core Audio wrapper | macOS device management |

### Recommended Stack for NLE

1. **Audio Engine**: `AVAudioEngine` (native, no dependencies)
2. **Waveform Rendering**: `DSWaveformImage` (best SwiftUI support) or custom with `vDSP`
3. **Export Audio Mix**: `AVMutableAudioMix` with `AVAssetExportSession`
4. **Effects**: Built-in `AVAudioUnit*` nodes + custom `AUAudioUnit v3` for compressor/limiter
5. **Spectral Analysis**: `Accelerate` framework (`vDSP_DFT`)
6. **Format Handling**: `AVAudioFile` + `AVAudioConverter`

---

## 19. WWDC Session References

### Essential Sessions

| Year | Session | Title | Key Topics |
|---|---|---|---|
| 2014 | 502 | AVAudioEngine in Practice | Core architecture, node graph, mixing, scheduling |
| 2015 | 507 | What's New in Core Audio | Audio Units, performance |
| 2015 | 508 | Audio Unit Extensions | AUv3 architecture, app extensions |
| 2016 | 507 | Delivering an Exceptional Audio Experience | Session management, interruptions, routing |
| 2017 | 501 | What's New in Audio | Manual rendering mode (offline + realtime) |
| 2019 | 510 | What's New in AVAudioEngine | AVAudioSourceNode, AVAudioSinkNode, spatial audio |
| 2023 | 10235 | What's New in Voice Processing | Advanced ducking, muted talker detection |

### Key Takeaways from WWDC Sessions

**WWDC 2014 -- AVAudioEngine in Practice**
- AVAudioEngine provides a higher-level Swift/ObjC API over Core Audio
- Node graph architecture: source nodes -> processing nodes -> destination nodes
- `AVAudioPlayerNode` supports scheduling files, segments, and buffers
- The engine can be dynamically reconfigured while running (upstream of mixers)

**WWDC 2017 -- Manual Rendering Mode**
- Two modes: Offline (no real-time constraints) and Realtime (block-based)
- Essential for export pipelines in NLE apps
- `renderOffline(_:to:)` for offline bounce
- Realtime manual rendering for custom output routing

**WWDC 2019 -- AVAudioSourceNode & AVAudioSinkNode**
- `AVAudioSourceNode`: Generate audio from a render block (synthesizers, tone generators)
- `AVAudioSinkNode`: Consume audio in a render block (custom output, analysis)
- Both operate under real-time constraints when connected to hardware
- Render block has ~11ms at 44.1kHz / 512 buffer size

```swift
// AVAudioSourceNode: Generate a sine wave
let sampleRate: Double = 48000
var phase: Double = 0
let frequency: Double = 440

let sineNode = AVAudioSourceNode { _, timestamp, frameCount, audioBufferList in
    let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
    let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate

    for frame in 0..<Int(frameCount) {
        let value = Float(sin(phase))
        phase += phaseIncrement
        if phase >= 2.0 * Double.pi { phase -= 2.0 * Double.pi }

        for buffer in ablPointer {
            let buf = UnsafeMutableBufferPointer<Float>(buffer)
            buf[frame] = value
        }
    }
    return noErr
}
```

**WWDC 2023 -- Voice Processing**
- AVAudioEngine voice processing for echo cancellation and noise suppression
- Advanced ducking API: `AVAudioVoiceProcessingOtherAudioDuckingConfiguration`
- Controls for ducking level and behavior
- Available on macOS, iOS, and tvOS

---

## 20. NLE Audio Engine Architecture Design

### Recommended Architecture for Our NLE App

```
┌─────────────────────────────────────────────────────────┐
│                    NLEAudioEngine                        │
│                                                          │
│  ┌──────────────┐                                        │
│  │  Track 1     │──┐                                     │
│  │  PlayerNode  │  │    ┌──────────┐                     │
│  │  + EQ        │  ├───>│ Sub-Mixer│                     │
│  │  + Compressor│  │    │ (Dialog) │──┐                  │
│  ├──────────────┤  │    └──────────┘  │                  │
│  │  Track 2     │──┘                  │  ┌────────────┐  │
│  │  PlayerNode  │                     ├─>│ Main Mixer │─>│ Output
│  │  + EQ        │                     │  │ + Limiter  │  │
│  ├──────────────┤                     │  └────────────┘  │
│  │  Track 3     │──┐                  │                  │
│  │  PlayerNode  │  │    ┌──────────┐  │                  │
│  │  + EQ        │  ├───>│ Sub-Mixer│──┘                  │
│  │  + Reverb    │  │    │ (Music)  │                     │
│  ├──────────────┤  │    └──────────┘                     │
│  │  Track 4     │──┘                                     │
│  │  PlayerNode  │                                        │
│  └──────────────┘                                        │
│                                                          │
│  ┌──────────────┐                                        │
│  │  Input Node  │  (Voiceover recording)                 │
│  │  (Microphone)│─────────────────────────┐              │
│  └──────────────┘                         │              │
│                                      [Tap: Record]       │
│                                                          │
│  Components:                                             │
│  - AudioMeter (per-track + master)                       │
│  - AudioAutomation (volume/pan keyframes per track)      │
│  - AudioScrubber (timeline seeking)                      │
│  - WaveformGenerator (per-clip visualization)            │
│  - AudioExporter (offline render + AVMutableAudioMix)    │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Use AVAudioEngine for playback, not AVPlayer**: AVAudioEngine gives us per-track control, effects insertion, and metering. AVPlayer is too high-level for a multi-track NLE.

2. **Sub-Mixers for track groups**: Group related tracks (Dialog, Music, SFX) into sub-mixers for group-level volume control and effects.

3. **Separate engines for playback vs export**: Use one `AVAudioEngine` in normal mode for real-time playback, and a separate engine in manual rendering mode for export (offline bounce).

4. **AVMutableAudioMix for final export**: Volume automation during export uses `AVMutableAudioMixInputParameters.setVolumeRamp()` -- this is baked into the exported file.

5. **48 kHz sample rate**: Standard for video production. Set this as the engine's preferred rate.

6. **Effects per track, not per clip**: Each track has its own effect chain (EQ, compressor, reverb send). This matches the DaVinci Resolve / Premiere Pro model.

7. **Timer-driven automation**: A 60 Hz timer reads keyframe values and applies them to player nodes' `volume` and `pan` properties during playback.

8. **Waveform caching**: Generate waveform data once per clip (using `WaveformAnalyzer` or custom vDSP code) and cache it. Re-render visuals on zoom level change.

### Thread Safety Notes
- AVAudioEngine render callbacks run on the **audio render thread** (real-time)
- Never allocate memory, lock mutexes, or call ObjC/Swift runtime in render callbacks
- Use `installTap` for metering/recording (not real-time critical)
- UI updates must be dispatched to the main thread
- Volume/pan property changes on `AVAudioPlayerNode` are thread-safe

---

## References

### Apple Documentation
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)
- [AVAudioMixerNode](https://developer.apple.com/documentation/avfaudio/avaudiomixernode)
- [AVAudioUnitEQ](https://developer.apple.com/documentation/avfaudio/avaudiouniteq)
- [AVAudioUnitReverb](https://developer.apple.com/documentation/avfaudio/avaudiounitreverb)
- [AVMutableAudioMix](https://developer.apple.com/documentation/avfoundation/avmutableaudiomix)
- [AVMutableAudioMixInputParameters](https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters)
- [AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
- [Performing Offline Audio Processing](https://developer.apple.com/documentation/avfaudio/audio_engine/performing_offline_audio_processing)
- [Audio Unit v3 Plug-Ins](https://developer.apple.com/documentation/audiotoolbox/audio-unit-v3-plug-ins)

### GitHub Repositories
- [AVAEMixerSample-Swift](https://github.com/ooper-shlab/AVAEMixerSample-Swift) -- Apple's mixer sample in Swift
- [Chassis-iOS](https://github.com/diatrevolo/Chassis-iOS) -- Multi-track AVAudioEngine wrapper
- [AVAEManualRendering](https://github.com/cntrump/AVAEManualRendering) -- Offline rendering example
- [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage) -- Waveform visualization
- [AudioKit/Waveform](https://github.com/AudioKit/Waveform) -- GPU-accelerated waveform
- [AudioKit](https://github.com/AudioKit/AudioKit) -- Complete audio framework
- [MTAudioTap](https://github.com/f728743/MTAudioTap) -- Audio processing tap example
- [MTAudioProcessingTap-in-Swift](https://github.com/gchilds/MTAudioProcessingTap-in-Swift) -- Swift tap example

### Articles & Tutorials
- [Audio Mixing on iOS (Medium)](https://medium.com/@ian.mundy/audio-mixing-on-ios-4cd51dfaac9a)
- [AVAudioEngine Tutorial (Kodeco)](https://www.kodeco.com/21672160-avaudioengine-tutorial-for-ios-getting-started)
- [AVAudioEffectNode: Custom Effects (orjpap.github.io)](https://orjpap.github.io/swift/low-level/audio/avfoundation/2024/09/19/avAudioEffectNode.html)
- [AVAudioSourceNode, AVAudioSinkNode (orjpap.github.io)](https://orjpap.github.io/swift/real-time/audio/avfoundation/2020/06/19/avaudiosourcenode.html)
- [Making Sense of Time in AVAudioPlayerNode (Medium)](https://medium.com/@mehsamadi/making-sense-of-time-in-avaudioplayernode-475853f84eb6)
- [Audio API Overview (objc.io)](https://www.objc.io/issues/24-audio/audio-api-overview/)
- [Audio Ducking (Make App Pie)](https://makeapppie.com/2019/04/24/ducking-sound-in-avaudiosession/)
