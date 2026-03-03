@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import MetalKit
import SwiftUI
import SwiftEditorAPI
import ViewerKit
import CoreMediaPlus

// MARK: - ViewerView

/// Video viewer panel showing the timeline output at the current playhead position.
struct ViewerView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        ZStack {
            Color.black

            if engine.timeline.duration > .zero {
                MetalViewerView(engine: engine)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video viewer")
        .accessibilityHint("Displays the current frame at the playhead position")
    }
}

// MARK: - MetalViewerView

/// Wraps an MTKView in NSViewRepresentable to display video frames from AVPlayer.
struct MetalViewerView: NSViewRepresentable {
    let engine: SwiftEditorEngine

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.layer?.isOpaque = true
        context.coordinator.setup(mtkView: mtkView, engine: engine)
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updatePlayer(from: engine)
    }

    func makeCoordinator() -> ViewerCoordinator {
        ViewerCoordinator()
    }

    static func dismantleNSView(_ nsView: MTKView, coordinator: ViewerCoordinator) {
        coordinator.tearDown()
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

    override init() {
        super.init()
    }

    // MARK: - Setup

    func setup(mtkView: MTKView, engine: SwiftEditorEngine) {
        self.mtkView = mtkView
        mtkView.delegate = self

        guard let device = mtkView.device else { return }
        commandQueue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .cacheIntermediates: false,
        ])

        // Create video output with Metal-compatible pixel buffers
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
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

        // Remove from previous item
        playerItemObservation?.invalidate()
        playerItemObservation = nil

        // Attach to current item if available
        if let item = player.currentItem {
            addOutputToItem(item)
        }

        // Observe currentItem changes so we re-attach when it changes
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

    /// Uses a 120 Hz timer on the main run loop to drive frame display.
    /// The actual frame rate is gated by AVPlayerItemVideoOutput.hasNewPixelBuffer,
    /// so this only redraws when a new frame is available.
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

        let hostTime = CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)

        guard itemTime.isValid, itemTime.isNumeric else { return }
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime, itemTimeForDisplay: nil
        ) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let drawableSize = view.drawableSize

        // Compute aspect-fit scaling
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
