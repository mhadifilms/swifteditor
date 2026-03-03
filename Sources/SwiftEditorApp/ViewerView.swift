import SwiftUI
import SwiftEditorAPI
import ViewerKit
import CoreMediaPlus

/// Video viewer panel showing the timeline output at the current playhead position.
struct ViewerView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        ZStack {
            // Black background for the viewer area
            Color.black

            if engine.timeline.duration > .zero {
                // Placeholder for Metal-rendered frame
                // In production, this wraps an MTKView via NSViewRepresentable
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.gray.opacity(0.3))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text("No Media")
                        .foregroundStyle(.gray.opacity(0.6))
                        .font(.title3)
                }
            }

            // Timecode overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    TimecodeDisplay(time: engine.transport.currentTime)
                        .padding(8)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}

/// Displays timecode in HH:MM:SS:FF format.
struct TimecodeDisplay: View {
    let time: Rational
    let frameRate: Double = 24.0

    var body: some View {
        Text(formattedTimecode)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
    }

    private var formattedTimecode: String {
        let totalSeconds = time.seconds
        guard totalSeconds >= 0 else { return "00:00:00:00" }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds - Double(Int(totalSeconds))) * frameRate)

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
