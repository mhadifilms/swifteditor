@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import MetalKit
import SwiftUI
import SwiftEditorAPI
import ViewerKit
import RenderEngine
import CoreMediaPlus

// MARK: - ViewerMode

/// Controls whether the viewer shows a single program monitor or dual source/program.
enum ViewerMode: String, CaseIterable {
    case program = "Program"
    case dual = "Source/Program"
}

/// Controls A/B comparison display mode.
enum ComparisonMode: String, CaseIterable {
    case off = "Off"
    case splitScreen = "Split"
    case wipe = "Wipe"
}

// MARK: - ViewerView

/// Video viewer panel showing the timeline output at the current playhead position.
/// Supports single-viewer and dual source/program modes.
struct ViewerView: View {
    let engine: SwiftEditorEngine

    @State private var viewerMode: ViewerMode = .program
    @State private var comparisonMode: ComparisonMode = .off
    @State private var wipePosition: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // Viewer toolbar
            viewerToolbar

            Divider()

            // Viewer content
            if viewerMode == .dual {
                HSplitView {
                    sourceViewerPanel
                    programViewerPanel
                }
            } else {
                programViewerPanel
            }
        }
    }

    // MARK: - Viewer Toolbar

    private var viewerToolbar: some View {
        HStack(spacing: 8) {
            // Viewer mode toggle
            Picker("Mode", selection: $viewerMode) {
                ForEach(ViewerMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .accessibilityLabel("Viewer mode")

            Spacer()

            // A/B Comparison controls (program viewer only)
            if viewerMode == .program {
                Picker("Compare", selection: $comparisonMode) {
                    ForEach(ComparisonMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .accessibilityLabel("Comparison mode")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Program Viewer

    private var programViewerPanel: some View {
        ZStack {
            Color.black

            if engine.timeline.duration > .zero {
                switch comparisonMode {
                case .off:
                    MetalViewerView(engine: engine)
                case .splitScreen:
                    ABComparisonView(engine: engine, mode: .splitScreen, wipePosition: $wipePosition)
                case .wipe:
                    ABComparisonView(engine: engine, mode: .wipe, wipePosition: $wipePosition)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray.opacity(0.4))
                        .accessibilityHidden(true)
                    Text("No Media")
                        .foregroundStyle(.gray.opacity(0.6))
                        .font(.title3)
                }
            }

            // Timecode overlay
            VStack {
                HStack {
                    if viewerMode == .dual {
                        Text("Program")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                            .padding(6)
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    TimecodeDisplay(time: engine.transport.currentTime)
                        .padding(8)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Program viewer")
        .accessibilityHint("Displays the current frame at the playhead position")
    }

    // MARK: - Source Viewer

    private var sourceViewerPanel: some View {
        ZStack {
            Color.black

            if engine.viewer.isSourceVisible,
               let url = engine.viewer.sourceAssetURL {
                SourceMetalViewerView(sourceURL: url, engine: engine)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray.opacity(0.4))
                        .accessibilityHidden(true)
                    Text("No Source")
                        .foregroundStyle(.gray.opacity(0.6))
                        .font(.title3)
                    Text("Select a clip in the Media Browser")
                        .foregroundStyle(.gray.opacity(0.4))
                        .font(.caption)
                }
            }

            // Source label + in/out overlay
            VStack {
                HStack {
                    Text("Source")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                        .padding(6)
                    Spacer()
                }
                Spacer()
                // In/Out point indicators
                sourceInOutBar
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source viewer")
        .accessibilityHint("Displays the selected source clip for setting in and out points")
    }

    private var sourceInOutBar: some View {
        HStack(spacing: 8) {
            // In point button
            Button {
                engine.viewer.setSourceInPoint(engine.transport.currentTime)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                    Text(inPointText)
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set in point")
            .accessibilityHint("Set the source in point to the current timecode")
            .accessibilityValue(inPointText)

            Spacer()

            // Out point button
            Button {
                engine.viewer.setSourceOutPoint(engine.transport.currentTime)
            } label: {
                HStack(spacing: 2) {
                    Text(outPointText)
                        .font(.system(.caption2, design: .monospaced))
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set out point")
            .accessibilityHint("Set the source out point to the current timecode")
            .accessibilityValue(outPointText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6))
    }

    private var inPointText: String {
        if let inPt = engine.viewer.sourceInPoint {
            return formatTimecode(inPt)
        }
        return "--:--:--:--"
    }

    private var outPointText: String {
        if let outPt = engine.viewer.sourceOutPoint {
            return formatTimecode(outPt)
        }
        return "--:--:--:--"
    }

    private func formatTimecode(_ time: Rational) -> String {
        let totalSeconds = time.seconds
        guard totalSeconds >= 0 else { return "00:00:00:00" }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds - Double(Int(totalSeconds))) * 24.0)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

// MARK: - MetalViewerView

/// Wraps an MTKView in NSViewRepresentable to display video frames from AVPlayer.
struct MetalViewerView: NSViewRepresentable {
    let engine: SwiftEditorEngine

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.layer?.isOpaque = true

        // Configure pixel format based on HDR settings
        let hdrConfig = engine.renderConfig.currentHDRConfiguration
        if hdrConfig.isHDR {
            mtkView.colorPixelFormat = .rgba16Float
            if let wideColorSpace = hdrConfig.cgColorSpace {
                mtkView.colorspace = wideColorSpace
            }
        } else {
            mtkView.colorPixelFormat = .bgra8Unorm
        }

        context.coordinator.setup(mtkView: mtkView, engine: engine)
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updatePlayer(from: engine)

        // Update HDR pixel format if changed
        let hdrConfig = engine.renderConfig.currentHDRConfiguration
        let expectedFormat: MTLPixelFormat = hdrConfig.isHDR ? .rgba16Float : .bgra8Unorm
        if nsView.colorPixelFormat != expectedFormat {
            nsView.colorPixelFormat = expectedFormat
            if hdrConfig.isHDR, let wideColorSpace = hdrConfig.cgColorSpace {
                nsView.colorspace = wideColorSpace
            } else {
                nsView.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            }
        }
    }

    func makeCoordinator() -> ViewerCoordinator {
        ViewerCoordinator()
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: ViewerCoordinator) {
        coordinator.tearDown()
    }
}

// MARK: - SourceMetalViewerView

/// A separate MTKView-based viewer for the source monitor.
/// Has its own AVPlayer instance to play source clips independently.
struct SourceMetalViewerView: NSViewRepresentable {
    let sourceURL: URL
    let engine: SwiftEditorEngine

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.layer?.isOpaque = true
        context.coordinator.setup(mtkView: mtkView, sourceURL: sourceURL)
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateSource(url: sourceURL)
    }

    func makeCoordinator() -> SourceViewerCoordinator {
        SourceViewerCoordinator()
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: SourceViewerCoordinator) {
        coordinator.tearDown()
    }
}

// MARK: - ABComparisonView

/// Shows A/B comparison: before effects (left) vs after effects (right).
/// In split mode, the division is fixed at 50%. In wipe mode, a draggable divider.
struct ABComparisonView: View {
    let engine: SwiftEditorEngine
    let mode: ComparisonMode
    @Binding var wipePosition: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full "after" frame behind
                MetalViewerView(engine: engine)

                // "Before" label overlay
                VStack {
                    HStack {
                        Text("Before")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
                            .padding(4)
                        Spacer()
                        Text("After")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
                            .padding(4)
                    }
                    Spacer()
                }

                // Wipe divider line
                if mode == .wipe {
                    let xPos = wipePosition * geo.size.width
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2)
                        .position(x: xPos, y: geo.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    wipePosition = max(0, min(1, value.location.x / geo.size.width))
                                }
                        )

                    // Wipe handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .position(x: xPos, y: geo.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    wipePosition = max(0, min(1, value.location.x / geo.size.width))
                                }
                        )
                        .accessibilityLabel("Wipe divider")
                        .accessibilityHint("Drag to adjust the before/after comparison split position")
                } else {
                    // Split screen fixed divider
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 1)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
    }
}

// MARK: - ViewerCoordinator

/// Manages the AVPlayerItemVideoOutput -> display refresh -> MTKView pipeline.
@MainActor
final class ViewerCoordinator: NSObject, MTKViewDelegate, @unchecked Sendable {

    private var videoOutput: AVPlayerItemVideoOutput?
    private var refreshTimer: Timer?
    private var ciContext: CIContext?
    private var commandQueue: (any MTLCommandQueue)?
    private weak var mtkView: MTKView?
    private weak var currentPlayer: AVPlayer?
    private var playerItemObservation: NSKeyValueObservation?
    private weak var engineRef: SwiftEditorEngine?
    private var renderColorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()

    override init() {
        super.init()
    }

    // MARK: - Setup

    func setup(mtkView: MTKView, engine: SwiftEditorEngine) {
        self.mtkView = mtkView
        self.engineRef = engine
        mtkView.delegate = self

        guard let device = mtkView.device else { return }
        commandQueue = device.makeCommandQueue()

        // Use HDR-aware color space for CIContext if HDR is active
        let hdrConfig = engine.renderConfig.currentHDRConfiguration
        let workingColorSpace: CGColorSpace
        if hdrConfig.isHDR, let hdrSpace = hdrConfig.cgColorSpace {
            workingColorSpace = hdrSpace
            renderColorSpace = hdrSpace
        } else {
            workingColorSpace = CGColorSpaceCreateDeviceRGB()
            renderColorSpace = CGColorSpaceCreateDeviceRGB()
        }

        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: workingColorSpace,
            .cacheIntermediates: false,
        ])

        // Use HDR pixel format for video output if HDR is active
        let pixelFormat = hdrConfig.isHDR ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        videoOutput = output

        startRefreshTimer()
        updatePlayer(from: engine)
    }

    // MARK: - Player Attachment

    func updatePlayer(from engine: SwiftEditorEngine) {
        let player = engine.transport.currentPlayer
        guard player !== currentPlayer else { return }
        currentPlayer = player
        attachVideoOutput(to: player)
    }

    private func attachVideoOutput(to player: AVPlayer?) {
        guard let player, videoOutput != nil else { return }

        playerItemObservation?.invalidate()
        playerItemObservation = nil

        if let item = player.currentItem {
            addOutputToItem(item)
        }

        playerItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            guard let item = change.newValue ?? nil else { return }
            MainActor.assumeIsolated {
                self?.addOutputToItem(item)
            }
        }
    }

    private func addOutputToItem(_ item: AVPlayerItem) {
        guard let videoOutput else { return }
        if !item.outputs.contains(where: { $0 === videoOutput }) {
            item.add(videoOutput)
        }
    }

    // MARK: - Display Refresh

    private func startRefreshTimer() {
        let interval = 1.0 / 120.0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let view = self.mtkView else { return }
                view.setNeedsDisplay(view.bounds)
            }
        }
    }

    // MARK: - Tear Down

    func tearDown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        playerItemObservation?.invalidate()
        playerItemObservation = nil
        videoOutput = nil
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        guard let videoOutput,
              let commandQueue,
              let ciContext,
              let drawable = view.currentDrawable else { return }

        // Check frame cache first for pre-rendered frames
        if let engine = engineRef {
            let currentTime = engine.transport.currentTime
            let frameHash = FrameHash(clipID: UUID(), sourceTime: currentTime)
            // Attempt to use cached frame from BackgroundRenderer
            Task { @MainActor in
                if let cached = await engine.renderConfig.frameCache.hit(for: frameHash),
                   case .pixelBuffer(let cachedBuffer) = cached {
                    let cachedImage = CIImage(cvPixelBuffer: cachedBuffer)
                    self.renderCIImage(cachedImage, in: view, drawable: drawable,
                                       commandQueue: commandQueue, ciContext: ciContext)
                    return
                }
            }
        }

        let hostTime = CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)

        guard itemTime.isValid, itemTime.isNumeric else { return }
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime, itemTimeForDisplay: nil
        ) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        renderCIImage(ciImage, in: view, drawable: drawable,
                      commandQueue: commandQueue, ciContext: ciContext)
    }

    private func renderCIImage(_ ciImage: CIImage, in view: MTKView,
                                drawable: any CAMetalDrawable,
                                commandQueue: any MTLCommandQueue,
                                ciContext: CIContext) {
        let drawableSize = view.drawableSize

        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        guard imageWidth > 0, imageHeight > 0 else { return }

        let scaleX = drawableSize.width / imageWidth
        let scaleY = drawableSize.height / imageHeight
        let scale = min(scaleX, scaleY)

        let scaledWidth = imageWidth * scale
        let scaledHeight = imageHeight * scale
        let offsetX = (drawableSize.width - scaledWidth) / 2
        let offsetY = (drawableSize.height - scaledHeight) / 2

        let scaledImage = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let bounds = CGRect(origin: .zero, size: drawableSize)

        ciContext.render(
            scaledImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: renderColorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - SourceViewerCoordinator

/// Coordinator for the source viewer with its own AVPlayer.
@MainActor
final class SourceViewerCoordinator: NSObject, MTKViewDelegate, @unchecked Sendable {

    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var refreshTimer: Timer?
    private var ciContext: CIContext?
    private var commandQueue: (any MTLCommandQueue)?
    private weak var mtkView: MTKView?
    private var currentURL: URL?
    private var playerItemObservation: NSKeyValueObservation?

    override init() {
        super.init()
    }

    func setup(mtkView: MTKView, sourceURL: URL) {
        self.mtkView = mtkView
        mtkView.delegate = self

        guard let device = mtkView.device else { return }
        commandQueue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .cacheIntermediates: false,
        ])

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)

        loadSource(url: sourceURL)
        startRefreshTimer()
    }

    func updateSource(url: URL) {
        guard url != currentURL else { return }
        loadSource(url: url)
    }

    private func loadSource(url: URL) {
        currentURL = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        if let videoOutput {
            item.add(videoOutput)
        }

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        // Pause by default -- source viewer is for scrubbing, not auto-play
        player?.pause()
    }

    private func startRefreshTimer() {
        let interval = 1.0 / 60.0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let view = self.mtkView else { return }
                view.setNeedsDisplay(view.bounds)
            }
        }
    }

    func tearDown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        playerItemObservation?.invalidate()
        playerItemObservation = nil
        player?.pause()
        player = nil
        videoOutput = nil
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        guard let videoOutput,
              let commandQueue,
              let ciContext,
              let drawable = view.currentDrawable else { return }

        let hostTime = CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)

        guard itemTime.isValid, itemTime.isNumeric else { return }
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime, itemTimeForDisplay: nil
        ) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let drawableSize = view.drawableSize

        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        guard imageWidth > 0, imageHeight > 0 else { return }

        let scaleX = drawableSize.width / imageWidth
        let scaleY = drawableSize.height / imageHeight
        let scale = min(scaleX, scaleY)

        let scaledWidth = imageWidth * scale
        let scaledHeight = imageHeight * scale
        let offsetX = (drawableSize.width - scaledWidth) / 2
        let offsetY = (drawableSize.height - scaledHeight) / 2

        let scaledImage = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(origin: .zero, size: drawableSize)

        ciContext.render(
            scaledImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: colorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - TimecodeDisplay

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
            .accessibilityValue(formattedTimecode)
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
