import SwiftUI
import SwiftEditorAPI
import ViewerKit
import CoreMediaPlus

/// Transport controls for playback: play/pause, stop, step, seek.
struct TransportBarView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        HStack(spacing: 16) {
            // Transport controls
            HStack(spacing: 8) {
                transportButton(systemImage: "backward.frame.fill", help: "Step Backward",
                                a11yLabel: "Step Backward", a11yHint: "Move the playhead one frame backward") {
                    engine.transport.stepBackward()
                }

                transportButton(systemImage: "stop.fill", help: "Stop",
                                a11yLabel: "Stop", a11yHint: "Stop playback and return to the beginning") {
                    engine.transport.stop()
                }

                transportButton(
                    systemImage: engine.transport.isPlaying ? "pause.fill" : "play.fill",
                    help: engine.transport.isPlaying ? "Pause" : "Play",
                    a11yLabel: engine.transport.isPlaying ? "Pause" : "Play",
                    a11yHint: engine.transport.isPlaying ? "Pause playback" : "Start playback from the current position"
                ) {
                    if engine.transport.isPlaying {
                        engine.transport.pause()
                    } else {
                        engine.transport.play()
                    }
                }

                transportButton(systemImage: "forward.frame.fill", help: "Step Forward",
                                a11yLabel: "Step Forward", a11yHint: "Move the playhead one frame forward") {
                    engine.transport.stepForward()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transport controls")

            Divider()
                .frame(height: 20)

            // Timecode
            TimecodeDisplay(time: engine.transport.currentTime)
                .accessibilityLabel("Current timecode")

            Spacer()

            // Duration
            HStack(spacing: 4) {
                Text("Duration:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimecodeDisplay(time: engine.timeline.duration)
                    .accessibilityLabel("Total duration")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassBar()
    }

    private func transportButton(systemImage: String, help: String,
                                 a11yLabel: String, a11yHint: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
    }
}
