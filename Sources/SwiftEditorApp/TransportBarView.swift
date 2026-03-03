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
                transportButton(systemImage: "backward.frame.fill", help: "Step Backward") {
                    engine.transport.stepBackward()
                }

                transportButton(systemImage: "stop.fill", help: "Stop") {
                    engine.transport.stop()
                }

                transportButton(
                    systemImage: engine.transport.isPlaying ? "pause.fill" : "play.fill",
                    help: engine.transport.isPlaying ? "Pause" : "Play"
                ) {
                    if engine.transport.isPlaying {
                        engine.transport.pause()
                    } else {
                        engine.transport.play()
                    }
                }

                transportButton(systemImage: "forward.frame.fill", help: "Step Forward") {
                    engine.transport.stepForward()
                }
            }

            Divider()
                .frame(height: 20)

            // Timecode
            TimecodeDisplay(time: engine.transport.currentTime)

            Spacer()

            // Duration
            HStack(spacing: 4) {
                Text("Duration:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimecodeDisplay(time: engine.timeline.duration)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func transportButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
