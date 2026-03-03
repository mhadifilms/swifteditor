import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus

/// The timeline panel with track headers, clip lanes, ruler, and playhead.
struct TimelinePanelView: View {
    let engine: SwiftEditorEngine
    let selectedTool: EditingTool

    @State private var pixelsPerSecond: CGFloat = 40.0
    @State private var scrollOffset: CGFloat = 0

    private let trackHeight: CGFloat = 48
    private let rulerHeight: CGFloat = 24
    private let headerWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Track headers (left side)
                    VStack(spacing: 0) {
                        // Ruler spacer
                        Rectangle()
                            .fill(.clear)
                            .frame(height: rulerHeight)
                            .overlay(alignment: .trailing) {
                                Text(timecodeString(engine.transport.currentTime))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 4)
                            }

                        // Video track headers
                        ForEach(engine.timeline.videoTracks) { track in
                            TrackHeaderView(name: track.name, type: .video,
                                            isMuted: track.isMuted, isLocked: track.isLocked)
                                .frame(height: trackHeight)
                        }

                        // Audio track headers
                        ForEach(engine.timeline.audioTracks) { track in
                            TrackHeaderView(name: track.name, type: .audio,
                                            isMuted: track.isMuted, isLocked: track.isLocked)
                                .frame(height: trackHeight)
                        }

                        Spacer()
                    }
                    .frame(width: headerWidth)
                    .background(.bar)

                    Divider()

                    // Timeline canvas (right side)
                    ScrollView(.horizontal, showsIndicators: true) {
                        let canvasWidth = max(
                            engine.timeline.duration.seconds * Double(pixelsPerSecond) + 200,
                            Double(geometry.size.width - headerWidth)
                        )

                        ZStack(alignment: .topLeading) {
                            // Ruler
                            TimelineRulerView(
                                pixelsPerSecond: pixelsPerSecond,
                                totalWidth: CGFloat(canvasWidth)
                            )
                            .frame(height: rulerHeight)

                            // Track lanes
                            VStack(spacing: 0) {
                                Spacer()
                                    .frame(height: rulerHeight)

                                ForEach(engine.timeline.videoTracks) { track in
                                    TrackLaneView(
                                        track: track.id,
                                        clips: engine.timeline.clipsOnTrack(track.id),
                                        pixelsPerSecond: pixelsPerSecond,
                                        trackHeight: trackHeight,
                                        isVideo: true,
                                        selection: engine.timeline.selection,
                                        engine: engine,
                                        selectedTool: selectedTool
                                    )
                                    .frame(height: trackHeight)
                                }

                                ForEach(engine.timeline.audioTracks) { track in
                                    TrackLaneView(
                                        track: track.id,
                                        clips: engine.timeline.clipsOnTrack(track.id),
                                        pixelsPerSecond: pixelsPerSecond,
                                        trackHeight: trackHeight,
                                        isVideo: false,
                                        selection: engine.timeline.selection,
                                        engine: engine,
                                        selectedTool: selectedTool
                                    )
                                    .frame(height: trackHeight)
                                }

                                Spacer()
                            }

                            // Marker indicators
                            ForEach(engine.timeline.markerManager.sortedMarkers) { marker in
                                MarkerIndicatorView(
                                    marker: marker,
                                    pixelsPerSecond: pixelsPerSecond,
                                    height: rulerHeight + totalTrackHeight
                                )
                            }

                            // Playhead
                            PlayheadView(
                                currentTime: engine.transport.currentTime,
                                pixelsPerSecond: pixelsPerSecond,
                                height: rulerHeight + totalTrackHeight
                            )
                        }
                        .frame(width: CGFloat(canvasWidth))
                    }
                }
            }

            // Zoom slider
            HStack {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $pixelsPerSecond, in: 10...200)
                    .frame(width: 120)
                    .accessibilityLabel("Timeline zoom")
                    .accessibilityHint("Adjust the zoom level of the timeline")
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var totalTrackHeight: CGFloat {
        CGFloat(engine.timeline.videoTracks.count + engine.timeline.audioTracks.count) * trackHeight
    }

    private func timecodeString(_ time: Rational) -> String {
        let total = time.seconds
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let frames = Int((total - Double(Int(total))) * 24)
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - Track Header

struct TrackHeaderView: View {
    let name: String
    let type: CoreMediaPlus.TrackType
    let isMuted: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type == .video ? "video" : "speaker.wave.2")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
            }
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 2)
                .fill(type == .video
                      ? Color.blue.opacity(0.05)
                      : Color.green.opacity(0.05))
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type == .video ? "Video" : "Audio") track: \(name)\(isMuted ? ", muted" : "")\(isLocked ? ", locked" : "")")
    }
}

// MARK: - Track Lane

struct TrackLaneView: View {
    let track: UUID
    let clips: [ClipModel]
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    let isVideo: Bool
    let selection: SelectionState
    let engine: SwiftEditorEngine
    let selectedTool: EditingTool

    var body: some View {
        ZStack(alignment: .leading) {
            // Lane background
            Rectangle()
                .fill(isVideo
                      ? Color.blue.opacity(0.03)
                      : Color.green.opacity(0.03))

            // Clips
            ForEach(clips) { clip in
                ClipView(
                    clip: clip,
                    pixelsPerSecond: pixelsPerSecond,
                    isVideo: isVideo,
                    isSelected: isClipSelected(clip.id),
                    selectedTool: selectedTool,
                    engine: engine
                )
                .offset(x: CGFloat(clip.startTime.seconds) * pixelsPerSecond)
                .onTapGesture {
                    engine.timeline.selection = SelectionState(selectedClipIDs: [clip.id])
                }
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func isClipSelected(_ clipID: UUID) -> Bool {
        selection.selectedClipIDs.contains(clipID)
    }
}

// MARK: - Clip View

struct ClipView: View {
    let clip: ClipModel
    let pixelsPerSecond: CGFloat
    let isVideo: Bool
    let isSelected: Bool
    let selectedTool: EditingTool
    let engine: SwiftEditorEngine

    private let trimHandleWidth: CGFloat = 6

    var body: some View {
        let width = max(CGFloat(clip.duration.seconds) * pixelsPerSecond, 4)

        ZStack {
            // Main clip body
            RoundedRectangle(cornerRadius: 4)
                .fill(clipColor)
                .frame(width: width)
                .padding(.vertical, 3)

            // Selection border
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
                .frame(width: width)
                .padding(.vertical, 3)

            // Clip label
            if width > 50 {
                HStack(spacing: 2) {
                    if hasEffects {
                        Image(systemName: "sparkles")
                            .font(.system(size: 7))
                    }
                    Text(clip.sourceAssetID.uuidString.prefix(6))
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: width - 16)
            }

            // Audio waveform placeholder (for audio clips)
            if !isVideo && width > 20 {
                WaveformPlaceholder()
                    .frame(width: width - 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }

            // Speed indicator
            if clip.speed != 1.0 && width > 30 {
                Text(String(format: "%.1fx", clip.speed))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: width, alignment: .bottomTrailing)
                    .padding(4)
                    .offset(y: 10)
            }

            // Trim handles (visible when trim tool selected or clip is selected)
            if (selectedTool == .trim || isSelected) && width > 20 {
                // Left trim handle
                TrimHandleView(edge: .leading)
                    .frame(width: trimHandleWidth)
                    .offset(x: -(width / 2) + trimHandleWidth / 2)
                    .gesture(trimDragGesture(edge: .leading))

                // Right trim handle
                TrimHandleView(edge: .trailing)
                    .frame(width: trimHandleWidth)
                    .offset(x: (width / 2) - trimHandleWidth / 2)
                    .gesture(trimDragGesture(edge: .trailing))
            }
        }
        .frame(width: width)
        .opacity(clip.isEnabled ? 1.0 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isVideo ? "Video" : "Audio") clip\(isSelected ? ", selected" : "")\(clip.isEnabled ? "" : ", disabled")")
        .accessibilityHint("Tap to select this clip")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var clipColor: Color {
        if isVideo {
            return isSelected ? .blue : .blue.opacity(0.7)
        } else {
            return isSelected ? .green : .green.opacity(0.7)
        }
    }

    private var hasEffects: Bool {
        engine.effectStacks.hasEffects(for: clip.id)
    }

    private func trimDragGesture(edge: TrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onEnded { value in
                let deltaSeconds = Double(value.translation.width) / Double(pixelsPerSecond)
                let delta = Rational(Int64(deltaSeconds * 600), 600)
                let newTime: Rational
                switch edge {
                case .leading:
                    newTime = clip.startTime + delta
                case .trailing:
                    newTime = clip.startTime + clip.duration + delta
                }
                engine.timeline.requestClipResize(clipID: clip.id, edge: edge, to: newTime)
            }
    }
}

// MARK: - Trim Handle

struct TrimHandleView: View {
    let edge: TrimEdge

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.4))
            .overlay {
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 1.5)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("\(edge == .leading ? "Left" : "Right") trim handle")
            .accessibilityHint("Drag to trim the \(edge == .leading ? "start" : "end") of the clip")
    }
}

// MARK: - Audio Waveform Placeholder

struct WaveformPlaceholder: View {
    var body: some View {
        Canvas { context, size in
            // Draw a simple simulated waveform
            let midY = size.height / 2
            let step: CGFloat = 3
            var x: CGFloat = 0
            while x < size.width {
                let height = CGFloat.random(in: 2...(size.height * 0.8))
                let rect = CGRect(x: x, y: midY - height / 2, width: 2, height: height)
                context.fill(Path(rect), with: .color(.white.opacity(0.25)))
                x += step
            }
        }
    }
}

// MARK: - Marker Indicator

struct MarkerIndicatorView: View {
    let marker: TimelineMarker
    let pixelsPerSecond: CGFloat
    let height: CGFloat

    var body: some View {
        let x = CGFloat(marker.time.seconds) * pixelsPerSecond

        VStack(spacing: 0) {
            // Marker diamond
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(markerColor)

            // Vertical line
            Rectangle()
                .fill(markerColor.opacity(0.4))
                .frame(width: 1, height: height - 10)
        }
        .offset(x: x - 4)
        .help(marker.name.isEmpty ? "Marker" : marker.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Marker\(marker.name.isEmpty ? "" : ": \(marker.name)")")
        .accessibilityHint("Timeline marker at the current position")
    }

    private var markerColor: Color {
        switch marker.color {
        case .blue: return .blue
        case .green: return .green
        case .red: return .red
        case .yellow: return .yellow
        case .orange: return .orange
        case .purple: return .purple
        default: return .blue
        }
    }
}

// MARK: - Ruler

struct TimelineRulerView: View {
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let interval = tickInterval
            let totalSeconds = totalWidth / pixelsPerSecond
            var t: CGFloat = 0

            while t <= totalSeconds {
                let x = t * pixelsPerSecond
                let isMajor = Int(t) % Int(interval.major) == 0

                // Tick mark
                let tickHeight: CGFloat = isMajor ? 12 : 6
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height - tickHeight))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

                // Label for major ticks
                if isMajor && x > 0 {
                    let text = Text(formatRulerTime(t))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: x, y: 6))
                }

                t += interval.minor
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var tickInterval: (major: CGFloat, minor: CGFloat) {
        if pixelsPerSecond >= 80 {
            return (5, 1)
        } else if pixelsPerSecond >= 30 {
            return (10, 2)
        } else {
            return (30, 5)
        }
    }

    private func formatRulerTime(_ seconds: CGFloat) -> String {
        let totalSec = Int(seconds)
        if totalSec >= 3600 {
            return String(format: "%d:%02d:%02d", totalSec / 3600, (totalSec % 3600) / 60, totalSec % 60)
        } else {
            return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
        }
    }
}

// MARK: - Playhead

struct PlayheadView: View {
    let currentTime: Rational
    let pixelsPerSecond: CGFloat
    let height: CGFloat

    var body: some View {
        let x = CGFloat(currentTime.seconds) * pixelsPerSecond

        ZStack(alignment: .top) {
            // Playhead line
            Rectangle()
                .fill(Color.red)
                .frame(width: 1, height: height)

            // Playhead triangle
            Path { path in
                path.move(to: CGPoint(x: -5, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 8))
                path.closeSubpath()
            }
            .fill(Color.red)
            .frame(width: 10, height: 8)
        }
        .offset(x: x)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playhead")
        .accessibilityHint("Indicates the current playback position on the timeline")
    }
}
