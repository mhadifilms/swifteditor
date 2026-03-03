import SwiftUI
import AppKit
@preconcurrency import AVFoundation
import SwiftEditorAPI
import TimelineKit
import AudioEngine
import MediaManager
import EffectsEngine
import CoreMediaPlus

/// The timeline panel with track headers, clip lanes, ruler, and playhead.
struct TimelinePanelView: View {
    let engine: SwiftEditorEngine
    let selectedTool: EditingTool

    @State private var pixelsPerSecond: CGFloat = 40.0
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrubbing: Bool = false

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

                        // Subtitle track headers
                        ForEach(engine.timeline.subtitleTracks) { track in
                            TrackHeaderView(name: track.name, type: .subtitle,
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
                            // Ruler with scrubbing gestures
                            TimelineRulerView(
                                pixelsPerSecond: pixelsPerSecond,
                                totalWidth: CGFloat(canvasWidth)
                            )
                            .frame(height: rulerHeight)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isScrubbing = true
                                        let seconds = max(0, Double(value.location.x) / Double(pixelsPerSecond))
                                        let time = Rational(seconds: seconds)
                                        Task { await engine.transport.seek(to: time) }
                                    }
                                    .onEnded { _ in
                                        isScrubbing = false
                                    }
                            )
                            .accessibilityAddTraits(.allowsDirectInteraction)
                            .accessibilityHint("Tap or drag to scrub the playhead")

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

                                // Subtitle track lanes
                                ForEach(engine.timeline.subtitleTracks) { track in
                                    SubtitleTrackLaneView(
                                        track: track,
                                        pixelsPerSecond: pixelsPerSecond,
                                        trackHeight: trackHeight
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
            .liquidGlassBar()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var totalTrackHeight: CGFloat {
        CGFloat(engine.timeline.videoTracks.count + engine.timeline.audioTracks.count + engine.timeline.subtitleTracks.count) * trackHeight
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
            Image(systemName: trackIcon)
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
                .fill(trackBackgroundColor)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trackLabel) track: \(name)\(isMuted ? ", muted" : "")\(isLocked ? ", locked" : "")")
    }

    private var trackIcon: String {
        switch type {
        case .video: return "video"
        case .audio: return "speaker.wave.2"
        case .subtitle: return "captions.bubble"
        }
    }

    private var trackBackgroundColor: Color {
        switch type {
        case .video: return Color.blue.opacity(0.05)
        case .audio: return Color.green.opacity(0.05)
        case .subtitle: return Color.yellow.opacity(0.05)
        }
    }

    private var trackLabel: String {
        switch type {
        case .video: return "Video"
        case .audio: return "Audio"
        case .subtitle: return "Subtitle"
        }
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

    @State private var dropIndicatorX: CGFloat?

    var body: some View {
        ZStack(alignment: .leading) {
            // Lane background — tap empty area to deselect all
            Rectangle()
                .fill(isVideo
                      ? Color.blue.opacity(0.03)
                      : Color.green.opacity(0.03))
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.timeline.selection = .empty
                }

            // Clips
            ForEach(clips) { clip in
                ClipView(
                    clip: clip,
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeight: trackHeight,
                    isVideo: isVideo,
                    isSelected: isClipSelected(clip.id),
                    selectedTool: selectedTool,
                    engine: engine
                )
                .offset(x: CGFloat(clip.startTime.seconds) * pixelsPerSecond)
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        // Shift+click: additive selection
                        var ids = engine.timeline.selection.selectedClipIDs
                        ids.insert(clip.id)
                        engine.timeline.selection = SelectionState(selectedClipIDs: ids)
                    } else if NSEvent.modifierFlags.contains(.command) {
                        // Cmd+click: toggle selection
                        var ids = engine.timeline.selection.selectedClipIDs
                        if ids.contains(clip.id) {
                            ids.remove(clip.id)
                        } else {
                            ids.insert(clip.id)
                        }
                        engine.timeline.selection = SelectionState(selectedClipIDs: ids)
                    } else {
                        // Plain click: exclusive selection
                        engine.timeline.selection = SelectionState(selectedClipIDs: [clip.id])
                    }
                }
            }

            // Transition handles between adjacent clips
            ForEach(adjacentClipPairs, id: \.0.id) { clipA, clipB in
                TransitionHandleView(
                    clipA: clipA,
                    clipB: clipB,
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeight: trackHeight,
                    engine: engine
                )
            }

            // Drop position indicator
            if let x = dropIndicatorX {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: trackHeight)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onDrop(of: [.mediaAssetTransfer], delegate: TrackLaneDropDelegate(
            trackID: track,
            pixelsPerSecond: pixelsPerSecond,
            engine: engine,
            dropIndicatorX: $dropIndicatorX
        ))
    }

    private func isClipSelected(_ clipID: UUID) -> Bool {
        selection.selectedClipIDs.contains(clipID)
    }

    /// Pairs of adjacent (or nearly adjacent) clips on this track, sorted by start time.
    private var adjacentClipPairs: [(ClipModel, ClipModel)] {
        let sorted = clips.sorted { $0.startTime < $1.startTime }
        guard sorted.count >= 2 else { return [] }
        var pairs: [(ClipModel, ClipModel)] = []
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            let aEnd = a.startTime + a.duration
            let gap = (b.startTime - aEnd).seconds
            if gap < 0.1 {
                pairs.append((a, b))
            }
        }
        return pairs
    }
}

// MARK: - Track Lane Drop Delegate

/// Handles drag-and-drop of media assets onto a timeline track lane.
/// Shows a vertical drop indicator during hover and performs an insert edit on drop.
struct TrackLaneDropDelegate: DropDelegate {
    let trackID: UUID
    let pixelsPerSecond: CGFloat
    let engine: SwiftEditorEngine
    @Binding var dropIndicatorX: CGFloat?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.mediaAssetTransfer])
    }

    func dropEntered(info: DropInfo) {
        dropIndicatorX = max(0, info.location.x)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropIndicatorX = max(0, info.location.x)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        dropIndicatorX = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        dropIndicatorX = nil
        let providers = info.itemProviders(for: [.mediaAssetTransfer])
        guard let provider = providers.first else { return false }

        let dropX = max(0, info.location.x)
        let dropSeconds = Double(dropX) / Double(pixelsPerSecond)
        let dropTime = Rational(seconds: dropSeconds)

        provider.loadDataRepresentation(forTypeIdentifier: "com.swifteditor.mediaAssetTransfer") { data, _ in
            guard let data,
                  let transfer = try? JSONDecoder().decode(MediaAssetTransfer.self, from: data)
            else { return }

            let sourceOut = Rational(seconds: transfer.durationSeconds)
            Task { @MainActor in
                try? await engine.editing.insertEdit(
                    sourceAssetID: transfer.assetID,
                    trackID: trackID,
                    at: dropTime,
                    sourceIn: .zero,
                    sourceOut: sourceOut
                )
            }
        }
        return true
    }
}

// MARK: - Clip View

struct ClipView: View {
    let clip: ClipModel
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
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

            // Thumbnail strip for video clips
            if isVideo && width > 20 {
                ThumbnailStripView(
                    clip: clip,
                    engine: engine,
                    pixelsPerSecond: pixelsPerSecond,
                    clipWidth: width,
                    trackHeight: trackHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: width)
                .padding(.vertical, 3)
                .allowsHitTesting(false)
            }

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
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                .frame(width: width - 16)
            }

            // Real waveform rendering for audio clips
            if !isVideo && width > 20 {
                WaveformView(
                    clip: clip,
                    engine: engine,
                    pixelsPerSecond: pixelsPerSecond,
                    clipWidth: width
                )
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
        .shadow(color: isSelected ? (isVideo ? Color.blue : Color.green).opacity(0.5) : .clear, radius: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isVideo ? "Video" : "Audio") clip\(isSelected ? ", selected" : "")\(clip.isEnabled ? "" : ", disabled")")
        .accessibilityHint("Tap to select this clip. Shift+click to add to selection, Command+click to toggle")
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

// MARK: - Real Waveform View

/// Displays actual waveform data from the audio engine, with caching.
struct WaveformView: View {
    let clip: ClipModel
    let engine: SwiftEditorEngine
    let pixelsPerSecond: CGFloat
    let clipWidth: CGFloat

    @State private var waveformData: WaveformData?
    @State private var isLoading = false

    var body: some View {
        Canvas { context, size in
            guard let data = waveformData, !data.samples.isEmpty else {
                drawPlaceholder(context: context, size: size)
                return
            }

            let channel = data.samples[0]
            guard !channel.isEmpty else { return }

            let midY = size.height / 2
            let clipDurationSeconds = clip.duration.seconds
            guard clipDurationSeconds > 0 else { return }

            let samplesPerPixel = Double(channel.count) / (clipDurationSeconds * Double(pixelsPerSecond))
            let totalPixels = Int(size.width)

            for px in 0..<totalPixels {
                let startIdx = max(Int(Double(px) * samplesPerPixel), 0)
                let endIdx = min(Int(Double(px + 1) * samplesPerPixel), channel.count)
                guard startIdx < endIdx else { continue }

                var minVal: Float = 1.0
                var maxVal: Float = -1.0
                for i in startIdx..<endIdx {
                    let sample = channel[i]
                    if sample.minValue < minVal { minVal = sample.minValue }
                    if sample.maxValue > maxVal { maxVal = sample.maxValue }
                }

                let topY = midY - CGFloat(maxVal) * midY
                let bottomY = midY - CGFloat(minVal) * midY
                let barHeight = max(bottomY - topY, 1)

                let rect = CGRect(x: CGFloat(px), y: topY, width: 1, height: barHeight)
                context.fill(Path(rect), with: .color(.white.opacity(0.35)))
            }
        }
        .task(id: WaveformTaskID(clipID: clip.id, pps: Int(pixelsPerSecond))) {
            await loadWaveform()
        }
    }

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        let rect = CGRect(x: 0, y: midY - 1, width: size.width, height: 2)
        context.fill(Path(rect), with: .color(.white.opacity(0.15)))
    }

    private func loadWaveform() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let asset = engine.importedAsset(by: clip.sourceAssetID) else { return }

        let samplesPerSec = max(10, Int(pixelsPerSecond))
        do {
            let data = try await engine.waveforms.generateWaveform(
                for: asset.url,
                samplesPerSecond: samplesPerSec
            )
            waveformData = data
        } catch {
            // Keep placeholder on failure
        }
    }
}

/// Identity for the waveform loading task so it re-fires on zoom changes.
private struct WaveformTaskID: Equatable {
    let clipID: UUID
    let pps: Int
}

// MARK: - Thumbnail Strip View

/// Displays a horizontal strip of video thumbnails across the clip width.
struct ThumbnailStripView: View {
    let clip: ClipModel
    let engine: SwiftEditorEngine
    let pixelsPerSecond: CGFloat
    let clipWidth: CGFloat
    let trackHeight: CGFloat

    @State private var thumbnails: [Int: CGImage] = [:]
    @State private var isLoading = false

    private var thumbnailCount: Int {
        let thumbWidth: CGFloat = 60
        return max(1, Int(clipWidth / thumbWidth))
    }

    private var thumbWidth: CGFloat {
        clipWidth / CGFloat(max(thumbnailCount, 1))
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<thumbnailCount, id: \.self) { index in
                if let cgImage = thumbnails[index] {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbWidth, height: trackHeight - 6)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: thumbWidth, height: trackHeight - 6)
                }
            }
        }
        .task(id: ThumbnailTaskID(clipID: clip.id, count: thumbnailCount)) {
            await loadThumbnails()
        }
    }

    private func loadThumbnails() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let asset = engine.importedAsset(by: clip.sourceAssetID) else { return }

        let count = thumbnailCount
        let thumbSize = CGSize(width: 120, height: 68)
        let clipDuration = clip.duration.seconds
        guard clipDuration > 0 else { return }

        for i in 0..<count {
            let timeFraction = Double(i) / Double(max(count, 1))
            let timeSeconds = clip.sourceIn.seconds + timeFraction * clipDuration
            let time = Rational(seconds: timeSeconds)

            do {
                let image = try await engine.media.generateThumbnail(
                    for: asset.url,
                    at: time,
                    size: thumbSize
                )
                thumbnails[i] = image
            } catch {
                // Skip failed thumbnails — slot remains a placeholder
            }
        }
    }
}

/// Identity for the thumbnail loading task so it re-fires when zoom changes thumbnail count.
private struct ThumbnailTaskID: Equatable {
    let clipID: UUID
    let count: Int
}

// MARK: - Transition Handle View

/// A diamond handle at the edit point between two adjacent clips.
struct TransitionHandleView: View {
    let clipA: ClipModel
    let clipB: ClipModel
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    let engine: SwiftEditorEngine

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0

    private var editPointX: CGFloat {
        let aEnd = clipA.startTime + clipA.duration
        return CGFloat(aEnd.seconds) * pixelsPerSecond
    }

    private var existingTransition: TransitionInstance? {
        engine.transitions.transition(between: clipA.id, and: clipB.id)
    }

    private var transitionWidth: CGFloat {
        if let t = existingTransition {
            return CGFloat(t.duration.seconds) * pixelsPerSecond
        }
        return 0
    }

    var body: some View {
        ZStack {
            // Transition region overlay (if a transition exists)
            if let transition = existingTransition {
                RoundedRectangle(cornerRadius: 2)
                    .fill(transitionColor(for: transition.type).opacity(0.3))
                    .frame(
                        width: max(transitionWidth + dragOffset, 4),
                        height: trackHeight - 10
                    )
                    .overlay {
                        if isHovered {
                            Text(transitionLabel(for: transition.type))
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .offset(x: editPointX - transitionWidth / 2)
            }

            // Diamond handle at edit point
            Image(systemName: existingTransition != nil ? "diamond.fill" : "diamond")
                .font(.system(size: 10))
                .foregroundStyle(handleColor)
                .offset(x: editPointX)
                .onHover { hovering in
                    isHovered = hovering
                }
                .gesture(transitionDragGesture)
                .onTapGesture(count: 2) {
                    openTransitionEditor()
                }
                .help(transitionHelpText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Edit point\(existingTransition != nil ? " with transition" : "")")
                .accessibilityHint("Double-click to open transition editor, drag to adjust duration")
        }
    }

    private var handleColor: Color {
        if isDragging { return .yellow }
        if isHovered { return .white }
        if existingTransition != nil { return .orange }
        return .white.opacity(0.5)
    }

    private var transitionHelpText: String {
        if let t = existingTransition {
            return "\(transitionLabel(for: t.type)) (\(String(format: "%.2fs", t.duration.seconds)))"
        }
        return "Edit point — double-click to add transition"
    }

    private var transitionDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                let deltaSeconds = Double(value.translation.width) / Double(pixelsPerSecond)
                if let transition = existingTransition {
                    let newDuration = max(0.0, transition.duration.seconds + deltaSeconds)
                    let newRational = Rational(seconds: newDuration)
                    Task {
                        try? await engine.transitions.removeTransition(transitionID: transition.id)
                        try? await engine.transitions.addTransition(
                            clipAID: clipA.id,
                            clipBID: clipB.id,
                            type: transitionTypeString(transition.type),
                            duration: newRational
                        )
                    }
                }
                dragOffset = 0
            }
    }

    private func openTransitionEditor() {
        if existingTransition == nil {
            let defaultDuration = Rational(seconds: 1.0)
            Task {
                try? await engine.transitions.addTransition(
                    clipAID: clipA.id,
                    clipBID: clipB.id,
                    type: "crossDissolve",
                    duration: defaultDuration
                )
            }
        }
    }

    private func transitionColor(for type: TransitionType) -> Color {
        switch type {
        case .crossDissolve: return .orange
        case .dipToBlack: return .gray
        case .dipToWhite: return .white
        case .wipe: return .cyan
        case .push: return .purple
        case .slide: return .mint
        }
    }

    private func transitionLabel(for type: TransitionType) -> String {
        switch type {
        case .crossDissolve: return "Dissolve"
        case .dipToBlack: return "Dip Black"
        case .dipToWhite: return "Dip White"
        case .wipe: return "Wipe"
        case .push: return "Push"
        case .slide: return "Slide"
        }
    }

    private func transitionTypeString(_ type: TransitionType) -> String {
        switch type {
        case .crossDissolve: return "crossDissolve"
        case .dipToBlack: return "dipToBlack"
        case .dipToWhite: return "dipToWhite"
        case .wipe: return "wipe"
        case .push: return "push"
        case .slide: return "slide"
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
        .liquidGlassRuler()
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

// MARK: - Subtitle Track Lane

struct SubtitleTrackLaneView: View {
    let track: SubtitleTrackModel
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Lane background
            Rectangle()
                .fill(Color.yellow.opacity(0.03))

            // Subtitle cue blocks
            ForEach(track.sortedCues) { cue in
                SubtitleCueView(cue: cue, pixelsPerSecond: pixelsPerSecond)
                    .frame(height: trackHeight - 6)
                    .offset(x: CGFloat(cue.startTime.seconds) * pixelsPerSecond, y: 0)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct SubtitleCueView: View {
    let cue: SubtitleCue
    let pixelsPerSecond: CGFloat

    var body: some View {
        let width = max(CGFloat(cue.duration.seconds) * pixelsPerSecond, 8)

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow.opacity(0.6))
            .frame(width: width)
            .overlay {
                if width > 40 {
                    Text(cue.text)
                        .font(.system(size: 9))
                        .foregroundStyle(.black.opacity(0.8))
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .frame(width: width)
                }
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Subtitle: \(cue.text)")
            .accessibilityHint("Subtitle cue on the timeline")
    }
}
