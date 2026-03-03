@preconcurrency import AVFoundation
import Metal
import CoreVideo
import CoreMediaPlus

/// Custom AVVideoCompositing implementation using Metal.
/// Pull-based: AVFoundation calls startRequest() when it needs a frame.
public final class MetalCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    public var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var supportsHDRSourceFrames: Bool { true }
    public var supportsWideColorSourceFrames: Bool { true }

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private let renderQueue = DispatchQueue(label: "com.swifteditor.compositor",
                                            qos: .userInteractive)
    private var isCancelled = false

    override public init() {
        let renderDevice = MetalRenderingDevice.shared
        self.device = renderDevice.device
        self.commandQueue = renderDevice.commandQueue
        super.init()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [self] in
            guard !isCancelled else {
                request.finishCancelledRequest()
                return
            }

            autoreleasepool {
                let sourceTrackIDs = request.sourceTrackIDs
                guard !sourceTrackIDs.isEmpty else {
                    request.finish(with: NSError(domain: "MetalCompositor",
                                                  code: -1, userInfo: nil))
                    return
                }

                // For MVP: pass through the first source frame
                if let firstTrackID = sourceTrackIDs.first?.int32Value,
                   let sourceBuffer = request.sourceFrame(byTrackID: firstTrackID) {
                    request.finish(withComposedVideoFrame: sourceBuffer)
                } else {
                    request.finish(with: NSError(domain: "MetalCompositor",
                                                  code: -2, userInfo: nil))
                }
            }
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        isCancelled = true
        renderQueue.async { [self] in
            isCancelled = false
        }
    }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Resize texture pool if needed
    }
}
