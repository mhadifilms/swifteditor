import Metal
import MetalKit
import CoreMediaPlus

/// Singleton holder for the Metal device and command queue.
/// All Metal operations flow through this shared device.
public final class MetalRenderingDevice: @unchecked Sendable {
    public static let shared = MetalRenderingDevice()

    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let defaultLibrary: (any MTLLibrary)?

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.device = device
        self.commandQueue = queue
        self.defaultLibrary = device.makeDefaultLibrary()
    }
}
