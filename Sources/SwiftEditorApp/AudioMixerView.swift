import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus

/// Audio mixer panel with per-track volume faders and meters.
/// Shown in the Audio workspace.
struct AudioMixerView: View {
    let engine: SwiftEditorEngine

    @State private var meterLevelL: Float = 0
    @State private var meterLevelR: Float = 0
    @State private var meterTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio Mixer")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlassSidebarHeader()

            Divider()

            if engine.timeline.audioTracks.isEmpty && engine.timeline.videoTracks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No Tracks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 2) {
                        // Video track audio strips
                        ForEach(engine.timeline.videoTracks) { track in
                            MixerChannelStrip(
                                name: "V\(engine.timeline.videoTracks.firstIndex(where: { $0.id == track.id }).map { $0 + 1 } ?? 0)",
                                color: .blue,
                                trackID: track.id,
                                engine: engine
                            )
                        }

                        // Audio track strips
                        ForEach(engine.timeline.audioTracks) { track in
                            MixerChannelStrip(
                                name: "A\(engine.timeline.audioTracks.firstIndex(where: { $0.id == track.id }).map { $0 + 1 } ?? 0)",
                                color: .green,
                                trackID: track.id,
                                engine: engine,
                                audioTrack: track
                            )
                        }

                        Divider()
                            .frame(height: 200)

                        // Master strip — uses metered levels
                        MasterChannelStrip(
                            meterLevelL: meterLevelL,
                            meterLevelR: meterLevelR
                        )
                    }
                    .padding(12)
                }
            }
        }
        .onAppear {
            startMetering()
        }
        .onDisappear {
            stopMetering()
        }
    }

    private func startMetering() {
        engine.audio.installMeteringTap { [self] peakL, peakR in
            DispatchQueue.main.async {
                self.meterLevelL = peakL
                self.meterLevelR = peakR
            }
        }
    }

    private func stopMetering() {
        engine.audio.removeMeteringTap()
    }
}

/// A single mixer channel strip with fader, meter, pan, mute, and solo.
/// Connected to the AudioAPI for real volume/pan/mute control.
struct MixerChannelStrip: View {
    let name: String
    let color: Color
    let trackID: UUID
    let engine: SwiftEditorEngine
    var audioTrack: AudioTrackModel? = nil

    @State private var volume: Float = 0.8
    @State private var pan: Float = 0.0
    @State private var isMuted = false
    @State private var isSolo = false

    var body: some View {
        VStack(spacing: 6) {
            // Label
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isMuted ? .tertiary : .primary)

            // Meter (placeholder levels based on volume)
            HStack(spacing: 1) {
                MeterBar(level: isMuted ? 0 : volume * 0.9, color: color)
                MeterBar(level: isMuted ? 0 : volume * 0.85, color: color)
            }
            .frame(width: 16, height: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) meter level")
            .accessibilityValue(isMuted ? "Muted" : "\(Int(volume * 100)) percent")

            // Fader
            Slider(value: $volume, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 20)
                .accessibilityLabel("\(name) volume")
                .accessibilityHint("Adjust the volume level for \(name)")
                .accessibilityValue(dbString)
                .onChange(of: volume) { _, newValue in
                    let effectiveVolume: Float = isMuted ? 0 : newValue
                    engine.audio.setVolume(effectiveVolume, for: trackID)
                    audioTrack?.volume = Double(newValue)
                }

            // dB readout
            Text(dbString)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40)

            // Pan knob (simplified as slider)
            HStack(spacing: 2) {
                Text("L")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Slider(value: $pan, in: -1...1)
                    .controlSize(.mini)
                    .frame(width: 40)
                    .accessibilityLabel("\(name) pan")
                    .accessibilityHint("Adjust the stereo pan position for \(name)")
                    .onChange(of: pan) { _, newValue in
                        engine.audio.setPan(newValue, for: trackID)
                        audioTrack?.pan = Double(newValue)
                    }
                Text("R")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            // Mute / Solo
            HStack(spacing: 4) {
                Button {
                    isMuted.toggle()
                    let effectiveVolume: Float = isMuted ? 0 : volume
                    engine.audio.setVolume(effectiveVolume, for: trackID)
                    audioTrack?.isMuted = isMuted
                } label: {
                    Text("M")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 16)
                        .background(isMuted ? Color.red.opacity(0.7) : Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute \(name)" : "Mute \(name)")
                .accessibilityHint("Toggle mute for this channel")

                Button {
                    isSolo.toggle()
                    audioTrack?.isSolo = isSolo
                } label: {
                    Text("S")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 16)
                        .background(isSolo ? Color.yellow.opacity(0.7) : Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSolo ? "Unsolo \(name)" : "Solo \(name)")
                .accessibilityHint("Toggle solo for this channel")
            }
        }
        .frame(width: 60)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.05))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) channel strip")
        .onAppear {
            // Initialize from track model if available
            if let audioTrack {
                volume = Float(audioTrack.volume)
                pan = Float(audioTrack.pan)
                isMuted = audioTrack.isMuted
                isSolo = audioTrack.isSolo
            }
        }
    }

    private var dbString: String {
        if volume <= 0 { return "-inf" }
        let db = 20 * log10(volume)
        return String(format: "%.1f", db)
    }
}

/// Master channel strip displaying metered output levels.
struct MasterChannelStrip: View {
    let meterLevelL: Float
    let meterLevelR: Float

    @State private var masterVolume: Float = 1.0

    var body: some View {
        VStack(spacing: 6) {
            Text("Master")
                .font(.system(size: 9, weight: .medium))

            HStack(spacing: 1) {
                MeterBar(level: meterLevelL * masterVolume, color: .orange)
                MeterBar(level: meterLevelR * masterVolume, color: .orange)
            }
            .frame(width: 16, height: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Master meter level")
            .accessibilityValue("Left \(Int(meterLevelL * 100)) percent, Right \(Int(meterLevelR * 100)) percent")

            Slider(value: $masterVolume, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 20)
                .accessibilityLabel("Master volume")
                .accessibilityHint("Adjust the master output volume level")
                .accessibilityValue(masterDbString)

            Text(masterDbString)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40)
        }
        .frame(width: 60)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.05))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Master channel strip")
    }

    private var masterDbString: String {
        if masterVolume <= 0 { return "-inf" }
        let db = 20 * log10(masterVolume)
        return String(format: "%.1f", db)
    }
}

/// Simple vertical meter bar visualization.
struct MeterBar: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: geo.size.height * CGFloat(1 - level))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.red, .yellow, color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: geo.size.height * CGFloat(level))
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(1)
    }
}
