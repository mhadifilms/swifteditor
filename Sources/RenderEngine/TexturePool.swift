import Metal
import CoreMediaPlus

/// Thread-safe reusable texture pool. Reduces allocation churn during playback.
public actor TexturePool {
    private let device: any MTLDevice
    private var available: [TextureKey: [any MTLTexture]] = [:]
    private var maxPoolSize: Int = 32

    private struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }

    public init(device: any MTLDevice) {
        self.device = device
    }

    public func checkout(width: Int, height: Int,
                         pixelFormat: MTLPixelFormat = .bgra8Unorm) -> (any MTLTexture)? {
        let key = TextureKey(width: width, height: height, pixelFormat: pixelFormat)

        if var textures = available[key], let texture = textures.popLast() {
            available[key] = textures
            return texture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    public func returnTexture(_ texture: any MTLTexture) {
        let key = TextureKey(width: texture.width, height: texture.height,
                             pixelFormat: texture.pixelFormat)
        var textures = available[key] ?? []
        guard textures.count < maxPoolSize else { return }
        textures.append(texture)
        available[key] = textures
    }

    public func drain() {
        available.removeAll()
    }
}
