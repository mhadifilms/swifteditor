import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus

/// Audio mixer panel with per-track volume faders and meters.
/// Shown in the Audio workspace.
struct AudioMixerView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio Mixer")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if engine.timeline.audioTracks.isEmpty && engine.timeline.videoTracks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
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
                                color: .blue
                            )
                        }

                        // Audio track strips
                        ForEach(engine.timeline.audioTracks) { track in
                            MixerChannelStrip(
                                name: "A\(engine.timeline.audioTracks.firstIndex(where: { $0.id == track.id }).map { $0 + 1 } ?? 0)",
                                color: .green
                            )
                        }

                        Divider()
                            .frame(height: 200)

                        // Master
                        MixerChannelStrip(name: "Master", color: .orange, isMaster: true)
                    }
                    .padding(12)
                }
            }
        }
    }
}

/// A single mixer channel strip with fader, meter, pan, mute, and solo.
struct MixerChannelStrip: View {
    let name: String
    let color: Color
    var isMaster: Bool = false

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

            // Meter (placeholder)
            HStack(spacing: 1) {
                MeterBar(level: volume * 0.9, color: color)
                MeterBar(level: volume * 0.85, color: color)
            }
            .frame(width: 16, height: 120)

            // Fader
            Slider(value: $volume, in: 0...1)
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 20)
                .accessibilityLabel("\(name) volume")
                .accessibilityHint("Adjust the volume level for \(name)")
                .accessibilityValue(dbString)

            // dB readout
            Text(dbString)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40)

            if !isMaster {
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
                    Text("R")
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                // Mute / Solo
                HStack(spacing: 4) {
                    Button {
                        isMuted.toggle()
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
        }
        .frame(width: 60)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.05))
        )
    }

    private var dbString: String {
        if volume <= 0 { return "-inf" }
        let db = 20 * log10(volume)
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
