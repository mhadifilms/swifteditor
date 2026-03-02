# SwiftUI Advanced Patterns for Professional NLE UI

## Table of Contents
1. [Custom Canvas / NSViewRepresentable](#1-custom-canvas--nsviewrepresentable)
2. [Split View / Panel System](#2-split-view--panel-system)
3. [Drag and Drop](#3-drag-and-drop)
4. [Context Menus](#4-context-menus)
5. [Custom Controls](#5-custom-controls)
6. [Performance](#6-performance)
7. [Focus and Keyboard](#7-focus-and-keyboard)
8. [Window Management](#8-window-management)
9. [AppKit Interop](#9-appkit-interop)
10. [Table / Outline Views](#10-table--outline-views)

---

## 1. Custom Canvas / NSViewRepresentable

### 1.1 When to Drop to AppKit

SwiftUI should handle most UI (inspectors, panels, menus), but the timeline view needs AppKit for:
- Custom hit testing (clip selection, trim handles, rubber-band selection)
- High-performance drawing (hundreds of clips, waveforms, thumbnails)
- CALayer-backed rendering for smooth scrolling/zooming
- Direct Core Animation control for playhead animation
- Precise mouse tracking (drag, scrub, resize)

### 1.2 Timeline View as NSViewRepresentable

```swift
import SwiftUI
import AppKit

struct TimelineViewRepresentable: NSViewRepresentable {
    @Binding var timeline: TimelineModel
    @Binding var playheadTime: CMTime
    @Binding var selectedClipIDs: Set<UUID>
    @Binding var zoomScale: Double
    var onClipMoved: ((UUID, CMTime) -> Void)?

    func makeNSView(context: Context) -> TimelineNSView {
        let view = TimelineNSView()
        view.delegate = context.coordinator
        view.wantsLayer = true   // enable CALayer backing
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        return view
    }

    func updateNSView(_ nsView: TimelineNSView, context: Context) {
        nsView.timeline = timeline
        nsView.playheadTime = playheadTime
        nsView.selectedClipIDs = selectedClipIDs
        nsView.zoomScale = zoomScale
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, TimelineNSViewDelegate {
        var parent: TimelineViewRepresentable

        init(_ parent: TimelineViewRepresentable) {
            self.parent = parent
        }

        func timelineView(_ view: TimelineNSView, didSelectClips clipIDs: Set<UUID>) {
            parent.selectedClipIDs = clipIDs
        }

        func timelineView(_ view: TimelineNSView, didMoveClip clipID: UUID, to time: CMTime) {
            parent.onClipMoved?(clipID, time)
        }

        func timelineView(_ view: TimelineNSView, didScrubTo time: CMTime) {
            parent.playheadTime = time
        }
    }
}
```

### 1.3 CALayer-Backed Timeline View (AppKit)

```swift
import AppKit
import QuartzCore
import CoreMedia

protocol TimelineNSViewDelegate: AnyObject {
    func timelineView(_ view: TimelineNSView, didSelectClips clipIDs: Set<UUID>)
    func timelineView(_ view: TimelineNSView, didMoveClip clipID: UUID, to time: CMTime)
    func timelineView(_ view: TimelineNSView, didScrubTo time: CMTime)
}

class TimelineNSView: NSView {
    weak var delegate: TimelineNSViewDelegate?

    var timeline: TimelineModel = TimelineModel()
    var playheadTime: CMTime = .zero
    var selectedClipIDs: Set<UUID> = []
    var zoomScale: Double = 1.0

    // Layer hierarchy for performance
    private var trackLayers: [CALayer] = []
    private let playheadLayer = CAShapeLayer()
    private let rulerLayer = CALayer()
    private let clipLayerPool = LayerPool<ClipLayer>()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        guard let rootLayer = layer else { return }

        // Ruler at top
        rulerLayer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        rootLayer.addSublayer(rulerLayer)

        // Playhead
        playheadLayer.strokeColor = NSColor.systemRed.cgColor
        playheadLayer.lineWidth = 2.0
        playheadLayer.zPosition = 1000  // always on top
        rootLayer.addSublayer(playheadLayer)
    }

    // MARK: - Drawing with CALayers (not draw(_:))

    override func layout() {
        super.layout()
        updateTrackLayers()
        updatePlayhead()
        updateRuler()
    }

    private func updateTrackLayers() {
        // Reuse clip layers from pool instead of creating new ones
        clipLayerPool.returnAll()

        let trackHeight: CGFloat = 60
        let rulerHeight: CGFloat = 30

        for (trackIndex, track) in timeline.tracks.enumerated() {
            let trackY = rulerHeight + CGFloat(trackIndex) * (trackHeight + 2)

            for clip in track.clips {
                let clipX = timeToX(clip.startTime)
                let clipWidth = timeToX(clip.startTime + clip.duration) - clipX

                // Only create layers for visible clips
                let visibleRect = visibleRect
                let clipFrame = CGRect(x: clipX, y: trackY, width: clipWidth, height: trackHeight)
                guard clipFrame.intersects(visibleRect) else { continue }

                let clipLayer = clipLayerPool.acquire {
                    let layer = ClipLayer()
                    self.layer?.addSublayer(layer)
                    return layer
                }

                clipLayer.frame = clipFrame
                clipLayer.configure(with: clip,
                                     isSelected: selectedClipIDs.contains(clip.id))
                clipLayer.isHidden = false
            }
        }
    }

    private func updatePlayhead() {
        let x = timeToX(playheadTime)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: bounds.height))
        playheadLayer.path = path
    }

    // MARK: - Hit Testing

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking on a clip
        if let hitClip = hitTestClip(at: point) {
            if event.modifierFlags.contains(.command) {
                // Cmd-click: toggle selection
                if selectedClipIDs.contains(hitClip.id) {
                    selectedClipIDs.remove(hitClip.id)
                } else {
                    selectedClipIDs.insert(hitClip.id)
                }
            } else {
                selectedClipIDs = [hitClip.id]
            }
            delegate?.timelineView(self, didSelectClips: selectedClipIDs)
        } else {
            // Clicked empty area: scrub playhead
            let time = xToTime(point.x)
            delegate?.timelineView(self, didScrubTo: time)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if !selectedClipIDs.isEmpty {
            // Drag selected clip(s)
            let time = xToTime(point.x)
            for clipID in selectedClipIDs {
                delegate?.timelineView(self, didMoveClip: clipID, to: time)
            }
        } else {
            // Scrub playhead
            let time = xToTime(point.x)
            delegate?.timelineView(self, didScrubTo: time)
        }
    }

    // MARK: - Coordinate Conversion

    func timeToX(_ time: CMTime) -> CGFloat {
        return CGFloat(CMTimeGetSeconds(time)) * zoomScale * 100.0
    }

    func xToTime(_ x: CGFloat) -> CMTime {
        let seconds = Double(x) / (zoomScale * 100.0)
        return CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    }

    private func hitTestClip(at point: CGPoint) -> ClipModel? {
        for track in timeline.tracks {
            for clip in track.clips {
                let clipX = timeToX(clip.startTime)
                let clipWidth = timeToX(clip.startTime + clip.duration) - clipX
                let trackY = CGFloat(track.index) * 62.0 + 30.0
                let rect = CGRect(x: clipX, y: trackY, width: clipWidth, height: 60)
                if rect.contains(point) { return clip }
            }
        }
        return nil
    }
}

// MARK: - Clip Layer (CALayer subclass)

class ClipLayer: CALayer {
    private let nameLabel = CATextLayer()
    private let thumbnailLayer = CALayer()
    private let waveformLayer = CAShapeLayer()

    override init() {
        super.init()
        cornerRadius = 4
        masksToBounds = true
        addSublayer(thumbnailLayer)
        addSublayer(waveformLayer)
        addSublayer(nameLabel)
        nameLabel.fontSize = 11
        nameLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with clip: ClipModel, isSelected: Bool) {
        backgroundColor = isSelected
            ? NSColor.selectedControlColor.cgColor
            : clip.color.cgColor
        borderWidth = isSelected ? 2 : 0
        borderColor = NSColor.controlAccentColor.cgColor
        nameLabel.string = clip.name
        nameLabel.frame = CGRect(x: 4, y: 2, width: bounds.width - 8, height: 16)
    }
}

// MARK: - Layer Pool for Reuse

class LayerPool<T: CALayer> {
    private var available: [T] = []
    private var inUse: [T] = []

    func acquire(create: () -> T) -> T {
        let layer: T
        if let reused = available.popLast() {
            layer = reused
        } else {
            layer = create()
        }
        inUse.append(layer)
        return layer
    }

    func returnAll() {
        for layer in inUse {
            layer.isHidden = true
        }
        available.append(contentsOf: inUse)
        inUse.removeAll()
    }
}
```

### 1.4 Using in SwiftUI

```swift
struct EditorView: View {
    @StateObject var project = ProjectViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Viewer (SwiftUI)
            VideoPreviewView(player: project.player)
                .frame(minHeight: 300)

            Divider()

            // Timeline (AppKit via NSViewRepresentable)
            TimelineViewRepresentable(
                timeline: $project.timeline,
                playheadTime: $project.playheadTime,
                selectedClipIDs: $project.selectedClipIDs,
                zoomScale: $project.zoomScale,
                onClipMoved: { clipID, time in
                    project.moveClip(clipID, to: time)
                }
            )
            .frame(minHeight: 200)
        }
    }
}
```

---

## 2. Split View / Panel System

### 2.1 Custom Resizable Panel Layout

```swift
struct NLEMainLayout: View {
    @State private var leftPanelWidth: CGFloat = 250
    @State private var rightPanelWidth: CGFloat = 300
    @State private var timelineHeight: CGFloat = 250
    @AppStorage("leftPanelWidth") private var savedLeftWidth: Double = 250
    @AppStorage("rightPanelWidth") private var savedRightWidth: Double = 300
    @AppStorage("timelineHeight") private var savedTimelineHeight: Double = 250

    var body: some View {
        VStack(spacing: 0) {
            // Top section: Browser | Viewer | Inspector
            HStack(spacing: 0) {
                // Left panel: Media Browser
                MediaBrowserPanel()
                    .frame(width: leftPanelWidth)

                ResizableHandle(axis: .horizontal) { delta in
                    leftPanelWidth = max(180, leftPanelWidth + delta)
                }

                // Center: Video Preview
                VideoPreviewPanel()
                    .frame(minWidth: 400)
                    .layoutPriority(1)  // gets remaining space

                ResizableHandle(axis: .horizontal) { delta in
                    rightPanelWidth = max(200, rightPanelWidth - delta)
                }

                // Right panel: Inspector
                InspectorPanel()
                    .frame(width: rightPanelWidth)
            }

            ResizableHandle(axis: .vertical) { delta in
                timelineHeight = max(150, timelineHeight - delta)
            }

            // Bottom: Timeline
            TimelinePanel()
                .frame(height: timelineHeight)
        }
        .onAppear {
            leftPanelWidth = savedLeftWidth
            rightPanelWidth = savedRightWidth
            timelineHeight = savedTimelineHeight
        }
        .onDisappear {
            savedLeftWidth = leftPanelWidth
            savedRightWidth = rightPanelWidth
            savedTimelineHeight = timelineHeight
        }
    }
}
```

### 2.2 Resizable Divider Handle

```swift
struct ResizableHandle: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    let onDrag: (CGFloat) -> Void

    @State private var isDragging = false

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                Rectangle()
                    .fill(isDragging ? Color.accentColor : Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                isDragging = true
                                onDrag(value.translation.width)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )

            case .vertical:
                Rectangle()
                    .fill(isDragging ? Color.accentColor : Color.clear)
                    .frame(height: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                isDragging = true
                                onDrag(value.translation.height)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
        .background(Color(nsColor: .separatorColor))
    }
}
```

### 2.3 Collapsible Panels

```swift
struct CollapsiblePanel<Content: View>: View {
    let title: String
    @Binding var isCollapsed: Bool
    @ViewBuilder let content: () -> Content

    @State private var panelWidth: CGFloat = 250

    var body: some View {
        if isCollapsed {
            // Collapsed sidebar button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed = false
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .frame(width: 24)
        } else {
            VStack(spacing: 0) {
                // Header with collapse button
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCollapsed = true
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                content()
            }
            .frame(width: panelWidth)
            .transition(.move(edge: .leading))
        }
    }
}
```

---

## 3. Drag and Drop

### 3.1 Transferable for Media Clips

```swift
import UniformTypeIdentifiers

struct MediaItem: Identifiable, Codable, Transferable {
    let id: UUID
    let name: String
    let filePath: String
    let duration: Double
    let mediaType: MediaType

    enum MediaType: String, Codable {
        case video, audio, image
    }

    static var transferRepresentation: some TransferRepresentation {
        // Primary: custom type for internal drag
        CodableRepresentation(for: MediaItem.self,
                               contentType: .swiftEditorMediaItem)

        // Fallback: file URL for external drag
        ProxyRepresentation(exporting: \.fileURL)
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

extension UTType {
    static let swiftEditorMediaItem = UTType(
        exportedAs: "com.swifteditor.media-item"
    )
}
```

### 3.2 Drag Source (Media Browser)

```swift
struct MediaBrowserGrid: View {
    let mediaItems: [MediaItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
            ForEach(mediaItems) { item in
                MediaThumbnailView(item: item)
                    .draggable(item) {
                        // Custom drag preview
                        DragPreview(item: item)
                    }
            }
        }
        .padding()
    }
}

struct DragPreview: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.mediaType == .video ? "film" : "music.note")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(formatDuration(item.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
```

### 3.3 Drop Delegate for Timeline

```swift
struct TimelineDropDelegate: DropDelegate {
    let track: TrackModel
    let onInsert: (MediaItem, CMTime) -> Void
    let calculateDropTime: (CGPoint) -> CMTime

    // Visual feedback when dragging over
    func dropEntered(info: DropInfo) {
        // Show insertion indicator
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .copy)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.swiftEditorMediaItem, .movie, .audio])
    }

    func performDrop(info: DropInfo) -> Bool {
        let dropTime = calculateDropTime(info.location)

        // Handle internal media items
        if let items = info.itemProviders(for: [.swiftEditorMediaItem]).first {
            items.loadObject(ofClass: MediaItem.self) { item, error in
                if let item = item as? MediaItem {
                    DispatchQueue.main.async {
                        onInsert(item, dropTime)
                    }
                }
            }
            return true
        }

        // Handle external file drops
        let providers = info.itemProviders(for: [.movie, .audio, .image])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.movie.identifier) { item, error in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        let mediaItem = MediaItem(
                            id: UUID(),
                            name: url.lastPathComponent,
                            filePath: url.path,
                            duration: 0,  // probe later
                            mediaType: .video
                        )
                        onInsert(mediaItem, dropTime)
                    }
                }
            }
        }

        return true
    }
}
```

### 3.4 Usage in Timeline

```swift
struct TimelineTrackView: View {
    let track: TrackModel
    @Binding var timeline: TimelineModel

    var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))

            // Clips
            ForEach(track.clips) { clip in
                ClipView(clip: clip)
                    .offset(x: timeToX(clip.startTime))
                    .draggable(clip) // also draggable within timeline
            }
        }
        .onDrop(of: [.swiftEditorMediaItem, .movie, .audio],
                delegate: TimelineDropDelegate(
                    track: track,
                    onInsert: { item, time in
                        timeline.insertClip(from: item, at: time, on: track)
                    },
                    calculateDropTime: { point in
                        xToTime(point.x)
                    }
                ))
    }
}
```

---

## 4. Context Menus

### 4.1 Clip Context Menu

```swift
struct ClipContextMenu: View {
    let clip: ClipModel
    let track: TrackModel
    @Binding var timeline: TimelineModel

    var body: some View {
        // Basic clip operations
        Group {
            Button("Cut") { timeline.cutClip(clip) }
                .keyboardShortcut("x")
            Button("Copy") { timeline.copyClip(clip) }
                .keyboardShortcut("c")
            Button("Delete") { timeline.deleteClip(clip, from: track) }
                .keyboardShortcut(.delete)
        }

        Divider()

        // Clip-specific operations
        Group {
            Button("Split at Playhead") {
                timeline.splitClip(clip, at: timeline.playheadTime)
            }
            Button("Disable") {
                timeline.toggleClipEnabled(clip)
            }

            // Conditional: only show for video clips
            if clip.mediaType == .video {
                Menu("Speed") {
                    Button("50%") { timeline.setSpeed(clip, speed: 0.5) }
                    Button("100%") { timeline.setSpeed(clip, speed: 1.0) }
                    Button("200%") { timeline.setSpeed(clip, speed: 2.0) }
                    Button("Custom...") { showSpeedDialog(for: clip) }
                }

                Menu("Transform") {
                    Button("Fit to Frame") { timeline.fitToFrame(clip) }
                    Button("Fill Frame") { timeline.fillFrame(clip) }
                    Button("Reset Transform") { timeline.resetTransform(clip) }
                }
            }

            // Conditional: only show for audio clips
            if clip.mediaType == .audio || clip.hasAudio {
                Menu("Audio") {
                    Button("Detach Audio") { timeline.detachAudio(clip) }
                    Button("Normalize Volume") { timeline.normalizeAudio(clip) }
                    Button("Fade In") { timeline.addAudioFade(clip, type: .fadeIn) }
                    Button("Fade Out") { timeline.addAudioFade(clip, type: .fadeOut) }
                }
            }
        }

        Divider()

        // Effects submenu
        Menu("Add Effect") {
            Section("Color") {
                Button("Color Wheels") { timeline.addEffect(clip, .colorWheels) }
                Button("Curves") { timeline.addEffect(clip, .curves) }
                Button("LUT") { timeline.addEffect(clip, .lut) }
            }
            Section("Stylize") {
                Button("Gaussian Blur") { timeline.addEffect(clip, .gaussianBlur) }
                Button("Sharpen") { timeline.addEffect(clip, .sharpen) }
                Button("Glow") { timeline.addEffect(clip, .glow) }
            }
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: clip.filePath)]
            )
        }

        Button("Properties...") {
            showClipProperties(clip)
        }
    }
}
```

### 4.2 Applying Context Menus

```swift
struct TimelineClipView: View {
    let clip: ClipModel
    let track: TrackModel
    @Binding var timeline: TimelineModel

    var body: some View {
        ClipContentView(clip: clip)
            .contextMenu {
                ClipContextMenu(clip: clip, track: track, timeline: $timeline)
            }
    }
}
```

### 4.3 Track Context Menu

```swift
struct TrackContextMenu: View {
    let track: TrackModel
    @Binding var timeline: TimelineModel

    var body: some View {
        Button("Add Track Above") {
            timeline.addTrack(above: track)
        }
        Button("Add Track Below") {
            timeline.addTrack(below: track)
        }
        Divider()
        Button("Rename Track...") {
            // show rename dialog
        }
        Button("Set Track Color...") {
            // show color picker
        }
        Divider()
        Toggle("Mute Track", isOn: trackBinding(\.isMuted))
        Toggle("Lock Track", isOn: trackBinding(\.isLocked))
        Divider()
        Button("Delete Track", role: .destructive) {
            timeline.deleteTrack(track)
        }
        .disabled(timeline.tracks.count <= 1)
    }
}
```

---

## 5. Custom Controls

### 5.1 Color Wheel Control

```swift
struct ColorWheelView: View {
    @Binding var hue: Double        // 0...1
    @Binding var saturation: Double // 0...1
    @Binding var brightness: Double // 0...1

    let size: CGFloat = 200

    var body: some View {
        ZStack {
            // Color wheel background
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0/360.0)
                            .map { Color(hue: $0, saturation: 1, brightness: brightness) }),
                        center: .center
                    )
                )
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // Selection indicator
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 16, height: 16)
                .shadow(radius: 2)
                .offset(thumbOffset)
        }
        .frame(width: size, height: size)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateColor(from: value.location)
                }
        )
    }

    private var thumbOffset: CGSize {
        let radius = saturation * size / 2
        let angle = hue * 2 * .pi - .pi / 2
        return CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius
        )
    }

    private func updateColor(from point: CGPoint) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        saturation = min(1.0, distance / (size / 2))
        hue = (atan2(dy, dx) / (2 * .pi) + 0.75).truncatingRemainder(dividingBy: 1.0)
    }
}
```

### 5.2 Audio Fader / Vertical Slider

```swift
struct VerticalFader: View {
    @Binding var value: Double   // 0...1
    let range: ClosedRange<Double>
    let label: String

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            // dB readout
            Text(String(format: "%.1f dB", valueToDB(value)))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            // Fader track
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)

                    // Level meter (green -> yellow -> red)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(faderGradient)
                        .frame(width: 4, height: geometry.size.height * value)

                    // Thumb
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isDragging ? Color.accentColor : Color.white)
                        .frame(width: 24, height: 8)
                        .shadow(radius: 1)
                        .offset(y: -geometry.size.height * value + geometry.size.height / 2)
                }
                .frame(maxWidth: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            let normalized = 1.0 - (drag.location.y / geometry.size.height)
                            value = max(range.lowerBound, min(range.upperBound, normalized))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(width: 30)

            Text(label)
                .font(.caption2)
        }
    }

    private var faderGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func valueToDB(_ val: Double) -> Double {
        if val <= 0 { return -100 }
        return 20 * log10(val)
    }
}
```

### 5.3 Keyframe Bezier Curve Editor

```swift
struct KeyframeCurveEditor: View {
    @Binding var controlPoint1: CGPoint  // 0...1 space
    @Binding var controlPoint2: CGPoint  // 0...1 space
    let size: CGFloat = 200

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)

            // Grid
            drawGrid(context: context, rect: rect)

            // Bezier curve
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: rect.height))
                p.addCurve(
                    to: CGPoint(x: rect.width, y: 0),
                    control1: CGPoint(
                        x: controlPoint1.x * rect.width,
                        y: (1 - controlPoint1.y) * rect.height
                    ),
                    control2: CGPoint(
                        x: controlPoint2.x * rect.width,
                        y: (1 - controlPoint2.y) * rect.height
                    )
                )
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)

            // Control point handles
            drawHandle(context: context, point: controlPoint1,
                       anchor: CGPoint(x: 0, y: 1), rect: rect)
            drawHandle(context: context, point: controlPoint2,
                       anchor: CGPoint(x: 1, y: 0), rect: rect)
        }
        .frame(width: size, height: size)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            // Draggable control point 1
            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(
                    x: controlPoint1.x * size,
                    y: (1 - controlPoint1.y) * size
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            controlPoint1 = CGPoint(
                                x: max(0, min(1, value.location.x / size)),
                                y: max(0, min(1, 1 - value.location.y / size))
                            )
                        }
                )
        )
        .overlay(
            // Draggable control point 2
            Circle()
                .fill(Color.orange)
                .frame(width: 12, height: 12)
                .position(
                    x: controlPoint2.x * size,
                    y: (1 - controlPoint2.y) * size
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            controlPoint2 = CGPoint(
                                x: max(0, min(1, value.location.x / size)),
                                y: max(0, min(1, 1 - value.location.y / size))
                            )
                        }
                )
        )
    }

    private func drawGrid(context: GraphicsContext, rect: CGRect) {
        let gridColor = Color(nsColor: .separatorColor)
        for i in 1..<4 {
            let x = rect.width * CGFloat(i) / 4
            let y = rect.height * CGFloat(i) / 4
            context.stroke(
                Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)) },
                with: .color(gridColor), lineWidth: 0.5
            )
            context.stroke(
                Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)) },
                with: .color(gridColor), lineWidth: 0.5
            )
        }
    }

    private func drawHandle(context: GraphicsContext, point: CGPoint,
                             anchor: CGPoint, rect: CGRect) {
        let from = CGPoint(x: anchor.x * rect.width, y: (1 - anchor.y) * rect.height)
        let to = CGPoint(x: point.x * rect.width, y: (1 - point.y) * rect.height)
        context.stroke(
            Path { p in p.move(to: from); p.addLine(to: to) },
            with: .color(.secondary), lineWidth: 1
        )
    }
}
```

### 5.4 Rotary Knob

```swift
struct RotaryKnob: View {
    @Binding var value: Double   // 0...1
    let label: String
    let range: ClosedRange<Double> = 0...1
    let sensitivity: Double = 0.005

    @State private var lastDragValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Knob track
                Circle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 3)
                    .frame(width: 40, height: 40)

                // Value arc
                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * value)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(0))
                    .frame(width: 40, height: 40)

                // Indicator dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .offset(y: -16)
                    .rotationEffect(.degrees(-135 + 270 * value))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let delta = -gesture.translation.height * sensitivity
                        value = max(range.lowerBound,
                                    min(range.upperBound, lastDragValue + delta))
                    }
                    .onEnded { _ in
                        lastDragValue = value
                    }
            )
            .onAppear { lastDragValue = value }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## 6. Performance

### 6.1 @Observable vs @ObservedObject

```swift
import Observation

// Modern approach: @Observable (macOS 14+ / iOS 17+)
@Observable
class TimelineModel {
    var tracks: [TrackModel] = []
    var playheadTime: CMTime = .zero
    var duration: CMTime = .zero
    var zoomScale: Double = 1.0

    // Only views that READ a specific property re-render when it changes
    // e.g., changing zoomScale won't re-render views that only read tracks
}

// Usage in view -- no wrapper needed
struct TimelineHeaderView: View {
    var timeline: TimelineModel

    var body: some View {
        // Only re-renders when zoomScale or duration changes
        HStack {
            Text("Duration: \(formatTime(timeline.duration))")
            Spacer()
            Slider(value: Binding(
                get: { timeline.zoomScale },
                set: { timeline.zoomScale = $0 }
            ), in: 0.1...10.0)
            .frame(width: 150)
        }
    }
}
```

### 6.2 Preventing Unnecessary Re-renders

```swift
// Extract sub-views that observe different properties
// BAD: entire view re-renders when any property changes
struct BadTimelineView: View {
    @State var model: TimelineModel

    var body: some View {
        VStack {
            Text("Time: \(model.playheadTime.seconds)")  // changes 30+ fps
            TrackListView(tracks: model.tracks)           // re-renders every frame!
        }
    }
}

// GOOD: split into sub-views with focused observation
struct GoodTimelineView: View {
    var model: TimelineModel

    var body: some View {
        VStack {
            PlayheadDisplay(model: model)   // only re-renders on time change
            TrackListView(model: model)     // only re-renders on track change
        }
    }
}

struct PlayheadDisplay: View {
    var model: TimelineModel

    var body: some View {
        // Only subscribes to playheadTime
        Text("Time: \(model.playheadTime.seconds)")
    }
}

struct TrackListView: View {
    var model: TimelineModel

    var body: some View {
        // Only subscribes to tracks
        ForEach(model.tracks) { track in
            TrackRowView(track: track)
        }
    }
}
```

### 6.3 Lazy Containers for Long Timelines

```swift
struct MediaBrowserList: View {
    let items: [MediaItem]
    @State private var selection: Set<UUID> = []

    var body: some View {
        // Use List for large datasets (view recycling)
        // NOT LazyVStack (no recycling, memory grows with scroll)
        List(items, selection: $selection) { item in
            MediaItemRow(item: item)
                .tag(item.id)
        }
    }
}

// For grid layouts, LazyVGrid is acceptable with reasonable item counts
struct ThumbnailGrid: View {
    let items: [MediaItem]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(items) { item in
                    MediaThumbnailView(item: item)
                        .id(item.id)  // stable identity for diffing
                }
            }
            .padding()
        }
    }
}
```

### 6.4 Equatable Views

```swift
// For value-type view data, use EquatableView to skip re-renders
struct WaveformView: View, Equatable {
    let waveformData: [Float]  // value type, Equatable
    let color: Color

    static func == (lhs: WaveformView, rhs: WaveformView) -> Bool {
        lhs.waveformData == rhs.waveformData && lhs.color == rhs.color
    }

    var body: some View {
        Canvas { context, size in
            drawWaveform(context: context, size: size)
        }
    }
}

// Use .equatable() modifier
struct ParentView: View {
    let waveformData: [Float]

    var body: some View {
        WaveformView(waveformData: waveformData, color: .green)
            .equatable()  // only re-render if == returns false
    }
}
```

### 6.5 TimelineView for Animations

```swift
// Use TimelineView for playhead animation, not a Timer
struct PlayheadOverlay: View {
    @Binding var isPlaying: Bool
    @Binding var playheadTime: CMTime
    let pixelsPerSecond: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: !isPlaying)) { context in
            Canvas { ctx, size in
                let x = CMTimeGetSeconds(playheadTime) * pixelsPerSecond
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.red),
                    lineWidth: 2
                )
            }
        }
    }
}
```

---

## 7. Focus and Keyboard

### 7.1 FocusState for Panel Navigation

```swift
enum EditorFocus: Hashable {
    case mediaBrowser
    case viewer
    case inspector
    case timeline
    case effectStack
}

struct EditorView: View {
    @FocusState private var focus: EditorFocus?

    var body: some View {
        VStack {
            HStack {
                MediaBrowserPanel()
                    .focused($focus, equals: .mediaBrowser)

                VideoPreviewPanel()
                    .focused($focus, equals: .viewer)

                InspectorPanel()
                    .focused($focus, equals: .inspector)
            }

            TimelinePanel()
                .focused($focus, equals: .timeline)
        }
        .onAppear {
            focus = .timeline  // default focus
        }
    }
}
```

### 7.2 Keyboard Shortcuts

```swift
struct EditorView: View {
    @StateObject var project: ProjectViewModel

    var body: some View {
        mainContent
            .commands {
                // Transport
                CommandGroup(after: .pasteboard) {
                    Section {
                        Button("Play / Pause") {
                            project.togglePlayback()
                        }
                        .keyboardShortcut(.space, modifiers: [])

                        Button("Play Reverse") {
                            project.playReverse()
                        }
                        .keyboardShortcut("j", modifiers: [])

                        Button("Stop") {
                            project.stop()
                        }
                        .keyboardShortcut("k", modifiers: [])

                        Button("Play Forward") {
                            project.playForward()
                        }
                        .keyboardShortcut("l", modifiers: [])
                    }

                    Section {
                        Button("Previous Frame") {
                            project.stepBackward()
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Button("Next Frame") {
                            project.stepForward()
                        }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                }

                // Edit operations
                CommandGroup(after: .undoRedo) {
                    Button("Blade at Playhead") {
                        project.blade()
                    }
                    .keyboardShortcut("b", modifiers: [])

                    Button("Select All") {
                        project.selectAll()
                    }
                    .keyboardShortcut("a")

                    Button("Deselect All") {
                        project.deselectAll()
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                }

                // View
                CommandGroup(after: .toolbar) {
                    Button("Toggle Media Browser") {
                        project.showMediaBrowser.toggle()
                    }
                    .keyboardShortcut("1", modifiers: .command)

                    Button("Toggle Inspector") {
                        project.showInspector.toggle()
                    }
                    .keyboardShortcut("4", modifiers: .command)

                    Button("Zoom In") {
                        project.zoomIn()
                    }
                    .keyboardShortcut("=")

                    Button("Zoom Out") {
                        project.zoomOut()
                    }
                    .keyboardShortcut("-")

                    Button("Fit Timeline") {
                        project.zoomToFit()
                    }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                }
            }
    }
}
```

### 7.3 focusedSceneValue for Cross-Window Commands

```swift
// Define focused values
struct FocusedProjectKey: FocusedValueKey {
    typealias Value = ProjectViewModel
}

extension FocusedValues {
    var project: ProjectViewModel? {
        get { self[FocusedProjectKey.self] }
        set { self[FocusedProjectKey.self] = newValue }
    }
}

// Set in content view
struct ProjectContentView: View {
    @StateObject var project: ProjectViewModel

    var body: some View {
        EditorView(project: project)
            .focusedSceneValue(\.project, project)
    }
}

// Use in menu commands
struct AppCommands: Commands {
    @FocusedValue(\.project) var project

    var body: some Commands {
        CommandMenu("Mark") {
            Button("Set In Point") {
                project?.setInPoint()
            }
            .keyboardShortcut("i", modifiers: [])
            .disabled(project == nil)

            Button("Set Out Point") {
                project?.setOutPoint()
            }
            .keyboardShortcut("o", modifiers: [])
            .disabled(project == nil)
        }
    }
}
```

---

## 8. Window Management

### 8.1 Multiple Window Types

```swift
@main
struct SwiftEditorApp: App {
    var body: some Scene {
        // Main editor window (document-based)
        DocumentGroup(newDocument: SwiftEditorDocument()) { file in
            EditorView(document: file.$document)
        }
        .commands {
            AppCommands()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1400, height: 900)

        // Floating viewer window
        Window("Viewer", id: "viewer") {
            FloatingViewerWindow()
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Media browser window
        Window("Media Browser", id: "mediaBrowser") {
            MediaBrowserWindow()
        }
        .defaultSize(width: 600, height: 800)

        // Effect editor window
        WindowGroup("Effect Editor", id: "effectEditor", for: UUID.self) { $effectID in
            if let effectID {
                EffectEditorView(effectID: effectID)
            }
        }
        .defaultSize(width: 500, height: 400)

        // Settings
        Settings {
            SettingsView()
        }
    }
}
```

### 8.2 Opening Windows Programmatically

```swift
struct EditorView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItem {
                    Button {
                        openWindow(id: "viewer")
                    } label: {
                        Label("Floating Viewer", systemImage: "rectangle.on.rectangle")
                    }
                }

                ToolbarItem {
                    Button {
                        openWindow(id: "mediaBrowser")
                    } label: {
                        Label("Media Browser", systemImage: "photo.on.rectangle")
                    }
                }
            }
    }

    // Open effect editor for a specific effect
    func editEffect(_ effectID: UUID) {
        openWindow(id: "effectEditor", value: effectID)
    }
}
```

### 8.3 Toolbar Customization

```swift
struct EditorToolbar: ToolbarContent {
    @Binding var isPlaying: Bool
    @Binding var showBrowser: Bool
    @Binding var showInspector: Bool

    var body: some ToolbarContent {
        // Leading: panel toggles
        ToolbarItem(placement: .navigation) {
            Button {
                showBrowser.toggle()
            } label: {
                Label("Browser", systemImage: "sidebar.left")
            }
        }

        // Center: transport controls
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 16) {
                Button(action: { /* go to start */ }) {
                    Image(systemName: "backward.end.fill")
                }

                Button(action: { /* step back */ }) {
                    Image(systemName: "backward.frame.fill")
                }

                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 20)
                }

                Button(action: { /* step forward */ }) {
                    Image(systemName: "forward.frame.fill")
                }

                Button(action: { /* go to end */ }) {
                    Image(systemName: "forward.end.fill")
                }
            }
        }

        // Trailing: inspector toggle
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

// Usage
struct EditorView: View {
    @State private var isPlaying = false
    @State private var showBrowser = true
    @State private var showInspector = true

    var body: some View {
        mainContent
            .toolbar {
                EditorToolbar(
                    isPlaying: $isPlaying,
                    showBrowser: $showBrowser,
                    showInspector: $showInspector
                )
            }
            .windowToolbarStyle(.unified(showsTitle: false))
    }
}
```

---

## 9. AppKit Interop

### 9.1 NSHostingView: Embed SwiftUI in AppKit

```swift
import AppKit
import SwiftUI

class InspectorPanelController: NSViewController {
    private var hostingView: NSHostingView<InspectorView>?
    private let viewModel = InspectorViewModel()

    override func loadView() {
        let swiftUIView = InspectorView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: swiftUIView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view = NSView()
        self.view.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingView = hosting
    }

    // Update SwiftUI from AppKit
    func updateForClip(_ clip: ClipModel) {
        viewModel.selectedClip = clip
        // SwiftUI view auto-updates via @Observable
    }
}
```

### 9.2 NSViewRepresentable with Coordinator

```swift
struct MetalPreviewView: NSViewRepresentable {
    let renderer: MetalRenderer

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.drawableSize = mtkView.bounds.size
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }

    func updateNSView(_ mtkView: MTKView, context: Context) {
        // Update if renderer settings change
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetalRenderer

        init(renderer: MetalRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.resize(to: size)
        }

        func draw(in view: MTKView) {
            renderer.draw(in: view)
        }
    }
}
```

### 9.3 Sharing State Between SwiftUI and AppKit

```swift
// Use @Observable for shared state
@Observable
class SharedEditorState {
    var selectedClipIDs: Set<UUID> = []
    var playheadTime: CMTime = .zero
    var zoomScale: Double = 1.0
    var currentTool: EditingTool = .select

    enum EditingTool {
        case select, blade, trim, slip
    }
}

// SwiftUI reads/writes via @Observable
struct SwiftUIInspector: View {
    var state: SharedEditorState

    var body: some View {
        Text("Selected: \(state.selectedClipIDs.count) clips")
    }
}

// AppKit reads/writes the same object
class AppKitTimelineView: NSView {
    var state: SharedEditorState? {
        didSet {
            // Use Combine or withObservationTracking to react to changes
            observeState()
        }
    }

    private func observeState() {
        // Observation framework integration for AppKit
        withObservationTracking {
            _ = state?.selectedClipIDs
            _ = state?.playheadTime
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.needsDisplay = true
                self?.observeState()  // re-register
            }
        }
    }
}
```

---

## 10. Table / Outline Views

### 10.1 Media Browser Table

```swift
struct MediaBrowserTable: View {
    @State private var items: [MediaItem] = []
    @State private var selection: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<MediaItem>] = [
        .init(\.name, order: .forward)
    ]

    var body: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.mediaType == .video ? "film" : "music.note")
                        .foregroundStyle(.secondary)
                    Text(item.name)
                }
            }
            .width(min: 100, ideal: 200)

            TableColumn("Duration") { item in
                Text(formatDuration(item.duration))
                    .monospacedDigit()
            }
            .width(80)

            TableColumn("Resolution") { item in
                Text("\(item.width) x \(item.height)")
                    .monospacedDigit()
            }
            .width(100)

            TableColumn("Codec", value: \.codecName)
                .width(80)

            TableColumn("Size") { item in
                Text(ByteCountFormatter.string(
                    fromByteCount: item.fileSize,
                    countStyle: .file
                ))
            }
            .width(70)

            TableColumn("Frame Rate") { item in
                Text(String(format: "%.2f", item.frameRate))
                    .monospacedDigit()
            }
            .width(70)
        }
        .onChange(of: sortOrder) { _, newOrder in
            items.sort(using: newOrder)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            Button("Add to Timeline") {
                addToTimeline(selectedIDs)
            }
            Button("Reveal in Finder") {
                revealInFinder(selectedIDs)
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteItems(selectedIDs)
            }
        } primaryAction: { selectedIDs in
            // Double-click: add to timeline
            addToTimeline(selectedIDs)
        }
    }
}
```

### 10.2 Bin Hierarchy with OutlineGroup

```swift
struct BinItem: Identifiable {
    let id: UUID
    let name: String
    let type: BinType
    var children: [BinItem]?

    enum BinType {
        case folder, video, audio, image
    }
}

struct BinOutlineView: View {
    let rootBins: [BinItem]
    @State private var selection: Set<UUID> = []

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(rootBins, children: \.children) { bin in
                HStack(spacing: 8) {
                    Image(systemName: iconForType(bin.type))
                        .foregroundStyle(colorForType(bin.type))
                    Text(bin.name)
                    Spacer()
                    if let children = bin.children {
                        Text("\(children.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func iconForType(_ type: BinItem.BinType) -> String {
        switch type {
        case .folder: return "folder.fill"
        case .video: return "film"
        case .audio: return "music.note"
        case .image: return "photo"
        }
    }

    private func colorForType(_ type: BinItem.BinType) -> Color {
        switch type {
        case .folder: return .blue
        case .video: return .purple
        case .audio: return .green
        case .image: return .orange
        }
    }
}
```

### 10.3 NSOutlineView Wrapper (Better Performance)

For large hierarchies, wrap NSOutlineView for proper view recycling:

```swift
struct HighPerformanceOutlineView: NSViewRepresentable {
    let rootItems: [BinItem]
    @Binding var selection: Set<UUID>

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Name"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = true

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true

        context.coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.rootItems = rootItems
        (scrollView.documentView as? NSOutlineView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outlineView: NSOutlineView?
        var rootItems: [BinItem] = []
        @Binding var selection: Set<UUID>

        init(selection: Binding<Set<UUID>>) {
            _selection = selection
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return rootItems.count }
            return (item as? BinItem)?.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return rootItems[index] }
            return (item as! BinItem).children![index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            return (item as? BinItem)?.children != nil
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?,
                          item: Any) -> NSView? {
            guard let bin = item as? BinItem else { return nil }
            let cell = NSTextField(labelWithString: bin.name)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView else { return }
            var newSelection: Set<UUID> = []
            for index in outlineView.selectedRowIndexes {
                if let item = outlineView.item(atRow: index) as? BinItem {
                    newSelection.insert(item.id)
                }
            }
            selection = newSelection
        }
    }
}
```

---

## Architecture Summary

```
SwiftEditor macOS App
├── App Shell (SwiftUI)
│   ├── WindowGroup / DocumentGroup
│   ├── Menu commands (.commands)
│   ├── Toolbar (SwiftUI)
│   └── Window management (openWindow)
│
├── Panels (SwiftUI)
│   ├── Media Browser (Table + OutlineGroup)
│   ├── Inspector (Form, custom controls)
│   ├── Effects Stack (List, drag reorder)
│   └── Audio Mixer (custom faders)
│
├── Custom Controls (SwiftUI)
│   ├── Color Wheel
│   ├── Bezier Curve Editor
│   ├── Rotary Knobs
│   └── Audio Faders
│
├── Timeline (AppKit via NSViewRepresentable)
│   ├── CALayer-backed clip rendering
│   ├── Custom hit testing
│   ├── Layer pool for performance
│   └── Direct Core Animation
│
├── Video Preview (Metal via NSViewRepresentable)
│   ├── MTKView + MetalRenderer
│   └── CAMetalLayer
│
└── Shared State (@Observable)
    ├── ProjectViewModel
    ├── TimelineModel
    └── SelectionState
```

**Key Principles:**
- SwiftUI for panels, menus, inspectors, dialogs
- AppKit (NSViewRepresentable) for timeline (performance-critical custom drawing)
- Metal (MTKView) for video preview
- @Observable for shared state between SwiftUI and AppKit layers
- List over LazyVStack for large datasets (view recycling)
- Split views into focused sub-views to minimize re-renders
- focusedSceneValue for cross-window menu commands
