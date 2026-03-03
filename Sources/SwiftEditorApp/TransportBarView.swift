import SwiftUI
import SwiftEditorAPI
import ViewerKit
import CoreMediaPlus

/// Transport controls for playback: play/pause, stop, step, seek.
struct TransportBarView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        LiquidGlassContainer(spacing: 8) {
            HStack(spacing: 16) {
                // Transport controls
                HStack(spacing: 8) {
                    transportButton(systemImage: "backward.frame.fill", help: "Step Backward",
                                    a11yLabel: "Step Backward", a11yHint: "Move the playhead one frame backward",
                                    prominent: false) {
                        engine.transport.stepBackward()
                    }

                    transportButton(systemImage: "stop.fill", help: "Stop",
                                    a11yLabel: "Stop", a11yHint: "Stop playback and return to the beginning",
                                    prominent: false) {
                        engine.transport.stop()
                    }

                    transportButton(
                        systemImage: engine.transport.isPlaying ? "pause.fill" : "play.fill",
                        help: engine.transport.isPlaying ? "Pause" : "Play",
                        a11yLabel: engine.transport.isPlaying ? "Pause" : "Play",
                        a11yHint: engine.transport.isPlaying ? "Pause playback" : "Start playback from the current position",
                        prominent: true
                    ) {
                        if engine.transport.isPlaying {
                            engine.transport.pause()
                        } else {
                            engine.transport.play()
                        }
                    }

                    transportButton(systemImage: "forward.frame.fill", help: "Step Forward",
                                    a11yLabel: "Step Forward", a11yHint: "Move the playhead one frame forward",
                                    prominent: false) {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassBar()
    }

    @ViewBuilder
    private func transportButton(systemImage: String, help: String,
                                 a11yLabel: String, a11yHint: String,
                                 prominent: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .modifier(TransportButtonStyle(prominent: prominent))
        .help(help)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
    }
}

/// Applies glass/glassProminent button style with backward compat.
private struct TransportButtonStyle: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.liquidGlassProminentButton()
        } else {
            content.liquidGlassButton()
        }
    }
}
