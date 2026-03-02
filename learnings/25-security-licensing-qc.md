# Security, Licensing & Quality Control for Swift NLE

## 1. FairPlay Streaming & DRM-Protected Source Media

### Overview
FairPlay Streaming (FPS) is Apple's DRM technology for securely delivering encrypted content through HTTP Live Streaming (HLS) using the CBCS encryption scheme. While FPS is designed primarily for content *playback* rather than editing, an NLE may need to handle DRM-protected source media (e.g., stock footage libraries, archived broadcast content).

### AVContentKeySession Architecture
AVContentKeySession (introduced WWDC 2017) decouples key loading from the media playback lifecycle, providing more control over content decryption keys independently of AVPlayer.

```swift
import AVFoundation

/// Manages FairPlay content key requests for DRM-protected media
class DRMKeyManager: NSObject, AVContentKeySessionDelegate {
    private let keySession: AVContentKeySession
    private let keyServerURL: URL

    init(keyServerURL: URL) {
        self.keyServerURL = keyServerURL
        self.keySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        super.init()
        keySession.setDelegate(self, queue: DispatchQueue(label: "com.editor.drm"))
    }

    /// Attach DRM key session to an AVURLAsset for editing
    func attachToAsset(_ asset: AVURLAsset) {
        keySession.addContentKeyRecipient(asset)
    }

    /// Preload keys before editing session begins (reduces latency)
    func preloadKeys(for identifiers: [String]) {
        keySession.processContentKeyRequest(
            withIdentifier: identifiers.first as Any,
            initializationData: nil,
            options: nil
        )
    }

    // MARK: - AVContentKeySessionDelegate

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        shouldRetry keyRequest: AVContentKeyRequest,
        reason retryReason: AVContentKeyRequest.RetryReason
    ) -> Bool {
        switch retryReason {
        case .timedOut, .receivedResponseWithExpiredLease:
            return true
        case .receivedObsoleteContentKey:
            return false
        @unknown default:
            return false
        }
    }

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) {
        guard let contentIdentifier = keyRequest.identifier as? String,
              let assetIDData = contentIdentifier.data(using: .utf8) else {
            keyRequest.processContentKeyResponseError(DRMError.invalidIdentifier)
            return
        }

        keyRequest.makeStreamingContentKeyRequestData(
            forApp: loadApplicationCertificate(),
            contentIdentifier: assetIDData
        ) { [weak self] spcData, error in
            guard let spcData = spcData else {
                keyRequest.processContentKeyResponseError(error ?? DRMError.spcGenerationFailed)
                return
            }

            Task {
                do {
                    let ckcData = try await self?.requestCKC(spc: spcData)
                    let response = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData!)
                    keyRequest.processContentKeyResponse(response)
                } catch {
                    keyRequest.processContentKeyResponseError(error)
                }
            }
        }
    }

    /// Request Content Key Context from license server
    private func requestCKC(spc: Data) async throws -> Data {
        var request = URLRequest(url: keyServerURL)
        request.httpMethod = "POST"
        request.httpBody = spc
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DRMError.licenseServerError
        }
        return data
    }

    private func loadApplicationCertificate() -> Data {
        // Load FPS application certificate from bundle
        guard let certURL = Bundle.main.url(forResource: "FairPlayCert", withExtension: "cer"),
              let certData = try? Data(contentsOf: certURL) else {
            fatalError("FairPlay application certificate not found")
        }
        return certData
    }

    /// Offline key management — persist keys for offline editing
    func requestPersistableKey(for identifier: String) {
        keySession.processContentKeyRequest(
            withIdentifier: identifier as Any,
            initializationData: nil,
            options: [
                AVContentKeyRequestProtocolVersionsKey: [1]
            ]
        )
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVPersistableContentKeyRequest
    ) {
        keyRequest.makeStreamingContentKeyRequestData(
            forApp: loadApplicationCertificate(),
            contentIdentifier: (keyRequest.identifier as! String).data(using: .utf8)!
        ) { [weak self] spcData, error in
            guard let spcData = spcData else { return }
            Task {
                let ckcData = try await self?.requestCKC(spc: spcData)
                let persistableData = try keyRequest.persistableContentKey(
                    fromKeyVendorResponse: ckcData!
                )
                // Store in Keychain for offline access
                try self?.storePersistableKey(persistableData, identifier: keyRequest.identifier as! String)
            }
        }
    }

    private func storePersistableKey(_ keyData: Data, identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.editor.drm.keys",
            kSecAttrAccount as String: identifier,
            kSecValueData as String: keyData
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DRMError.keychainStoreFailed
        }
    }
}

enum DRMError: Error {
    case invalidIdentifier
    case spcGenerationFailed
    case licenseServerError
    case keychainStoreFailed
}
```

### NLE Considerations for DRM Content
- **DRM content is not directly editable** — FPS is designed for secure playback, not frame-level editorial access. NLEs typically work with *mezzanine* (unencrypted) copies.
- **Proxy workflow**: Ingest DRM content, decrypt for authorized editors, create edit-friendly proxies.
- **AVContentKeySession key preloading**: Pre-fetch keys before timeline scrubbing to minimize latency.
- **Offline keys**: Use `AVPersistableContentKeyRequest` for editing sessions without network access.
- **2026 update**: FairPlay SDK v4.5.4 is deprecated; migrate to SDK v26 (Swift and Python SDKs only).

---

## 2. Watermarking

### Invisible Forensic Watermarking

Forensic watermarks use spread-spectrum techniques to distribute identifier data across video frames. They survive re-encoding, resolution changes, compression, and format conversion. The global digital watermarking market was estimated at $1.6B in 2025, projected to reach $3.8B by 2033.

```swift
import Metal
import MetalKit
import simd

/// GPU-accelerated invisible forensic watermark embedding using Metal
class ForensicWatermarkEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let embedPipeline: MTLComputePipelineState
    private let extractPipeline: MTLComputePipelineState

    init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        let library = try device.makeDefaultLibrary(bundle: .main)
        let embedFunction = library.makeFunction(name: "embedForensicWatermark")!
        let extractFunction = library.makeFunction(name: "extractForensicWatermark")!

        self.embedPipeline = try device.makeComputePipelineState(function: embedFunction)
        self.extractPipeline = try device.makeComputePipelineState(function: extractFunction)
    }

    /// Embed a unique identifier into a video frame using spread-spectrum
    func embedWatermark(
        frame: MTLTexture,
        output: MTLTexture,
        identifier: UInt64,
        strength: Float = 0.003 // Imperceptible but detectable
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(embedPipeline)
        encoder.setTexture(frame, index: 0)        // Input frame
        encoder.setTexture(output, index: 1)        // Output with watermark

        var params = WatermarkParams(
            identifier: identifier,
            strength: strength,
            frameWidth: UInt32(frame.width),
            frameHeight: UInt32(frame.height),
            seed: UInt32(arc4random()) // Per-frame randomization
        )
        encoder.setBytes(&params, length: MemoryLayout<WatermarkParams>.size, index: 0)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (frame.width + 15) / 16,
            height: (frame.height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
    }

    /// Extract watermark identifier from a potentially leaked frame
    func extractWatermark(
        frame: MTLTexture,
        completion: @escaping (UInt64?) -> Void
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(nil)
            return
        }

        let resultBuffer = device.makeBuffer(
            length: MemoryLayout<UInt64>.size * 64, // Correlation results
            options: .storageModeShared
        )!

        encoder.setComputePipelineState(extractPipeline)
        encoder.setTexture(frame, index: 0)
        encoder.setBuffer(resultBuffer, offset: 0, index: 0)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (frame.width + 15) / 16,
            height: (frame.height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            let results = resultBuffer.contents().bindMemory(
                to: UInt64.self, capacity: 64
            )
            // Majority vote across correlation bins
            var votes: [UInt64: Int] = [:]
            for i in 0..<64 {
                votes[results[i], default: 0] += 1
            }
            let detected = votes.max(by: { $0.value < $1.value })?.key
            completion(detected)
        }
        commandBuffer.commit()
    }
}

struct WatermarkParams {
    var identifier: UInt64
    var strength: Float
    var frameWidth: UInt32
    var frameHeight: UInt32
    var seed: UInt32
}
```

**Metal Shader for Spread-Spectrum Embedding:**

```metal
#include <metal_stdlib>
using namespace metal;

struct WatermarkParams {
    uint64_t identifier;
    float strength;
    uint32_t frameWidth;
    uint32_t frameHeight;
    uint32_t seed;
};

/// Pseudo-random number generator for spread-spectrum sequence
inline float prng(uint2 pos, uint seed, uint bit) {
    uint h = pos.x * 374761393u + pos.y * 668265263u + seed * 1274126177u + bit * 982451653u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h = h ^ (h >> 16);
    return float(h & 1) * 2.0 - 1.0; // -1.0 or +1.0
}

kernel void embedForensicWatermark(
    texture2d<float, access::read>  input  [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant WatermarkParams &params       [[buffer(0)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= params.frameWidth || gid.y >= params.frameHeight) return;

    float4 pixel = input.read(gid);

    // Embed each bit of the identifier using spread-spectrum
    float watermarkSignal = 0.0;
    for (uint bit = 0; bit < 64; bit++) {
        float chipValue = prng(gid, params.seed, bit);
        float bitValue = float((params.identifier >> bit) & 1) * 2.0 - 1.0;
        watermarkSignal += chipValue * bitValue;
    }
    watermarkSignal /= 64.0; // Normalize

    // Add to luminance channel (perceptually weighted)
    float luminanceOffset = watermarkSignal * params.strength;
    pixel.rgb += luminanceOffset;

    output.write(pixel, gid);
}

kernel void extractForensicWatermark(
    texture2d<float, access::read> input [[texture(0)]],
    device uint64_t *results             [[buffer(0)]],
    uint2 gid                            [[thread_position_in_grid]]
) {
    // Correlation-based extraction would accumulate across all pixels
    // This is a simplified per-threadgroup extraction
    // Full implementation requires reduction across the entire image
}
```

### Visible Burn-In Watermarks

```swift
import AVFoundation
import CoreImage

/// Burn-in watermark overlay for review copies
class BurnInWatermarkRenderer {

    enum WatermarkType {
        case timecode          // Running timecode display
        case clientName(String) // "CONFIDENTIAL - Client Name"
        case draft             // "DRAFT" diagonal
        case custom(String)    // Custom text
    }

    /// Create a video composition with burn-in watermark
    func applyWatermark(
        to asset: AVAsset,
        type: WatermarkType,
        opacity: Float = 0.4
    ) async throws -> AVMutableVideoComposition {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw WatermarkError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let composition = AVMutableVideoComposition()
        composition.renderSize = naturalSize
        composition.frameDuration = CMTime(value: 1, timescale: 24)

        composition.customVideoCompositorClass = WatermarkCompositor.self

        let instruction = WatermarkInstruction(
            timeRange: CMTimeRange(start: .zero, duration: try await asset.load(.duration)),
            watermarkType: type,
            opacity: opacity,
            renderSize: naturalSize
        )
        composition.instructions = [instruction]

        return composition
    }

    /// Render timecode burn-in text for a specific frame
    static func renderTimecodeString(
        time: CMTime,
        frameRate: Float64
    ) -> String {
        let totalFrames = Int(CMTimeGetSeconds(time) * frameRate)
        let fps = Int(frameRate)
        let frames = totalFrames % fps
        let seconds = (totalFrames / fps) % 60
        let minutes = (totalFrames / (fps * 60)) % 60
        let hours = totalFrames / (fps * 3600)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Generate diagonal "DRAFT" watermark using Core Image
    static func generateDraftOverlay(size: CGSize, opacity: Float) -> CIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(CGColor(gray: 1.0, alpha: CGFloat(opacity)))

            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size.height * 0.15, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: CGColor(gray: 1.0, alpha: CGFloat(opacity))
            ]

            let text = "DRAFT" as NSString
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: -.pi / 4) // 45-degree diagonal

            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                withAttributes: attributes
            )
            ctx.restoreGState()
        }
        return CIImage(image: image)
    }
}

enum WatermarkError: Error {
    case noVideoTrack
}
```

### Industry Landscape
- **Moxion** provides forensic watermarking for dailies review in film production
- **NAGRA** serves 95% of digital cinemas globally with forensic watermarking
- **Steg.AI** offers invisible, tamper-proof forensic watermarks that survive screenshots
- **Frame.io** added forensic watermarking and DRM in their V4 update (IBC 2025)

---

## 3. Secure Preview & Client Review

### Watermarked Low-Res Preview Exports

```swift
import AVFoundation

/// Generate watermarked low-resolution preview for client review
class SecurePreviewExporter {

    struct PreviewSettings {
        var maxWidth: Int = 1280         // 720p for reviews
        var maxHeight: Int = 720
        var videoBitrate: Int = 2_000_000 // 2 Mbps — watchable but not final quality
        var watermarkText: String = "REVIEW COPY"
        var includeTimecode: Bool = true
        var clientName: String?
    }

    func exportPreview(
        composition: AVComposition,
        videoComposition: AVVideoComposition?,
        settings: PreviewSettings,
        outputURL: URL,
        progress: @escaping (Float) -> Void
    ) async throws {
        // Scale down to review resolution
        let scaledComposition = AVMutableVideoComposition()
        scaledComposition.renderSize = CGSize(
            width: settings.maxWidth,
            height: settings.maxHeight
        )
        scaledComposition.frameDuration = CMTime(value: 1, timescale: 24)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            throw PreviewError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = scaledComposition
        exportSession.fileLengthLimit = 500 * 1024 * 1024 // 500 MB cap

        // Monitor progress
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(exportSession.progress)
        }

        await exportSession.export()
        timer.invalidate()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? PreviewError.exportFailed
        }
    }
}

enum PreviewError: Error {
    case exportSessionCreationFailed
    case exportFailed
}
```

### Expiring Review Links Architecture

For secure client review, integrate with services like **Frame.io** or build a custom solution:

```swift
import Foundation
import CryptoKit

/// Generate time-limited, signed review URLs
struct ReviewLinkGenerator {
    private let signingKey: SymmetricKey
    private let baseURL: URL

    init(signingKey: SymmetricKey, baseURL: URL) {
        self.signingKey = signingKey
        self.baseURL = baseURL
    }

    /// Create a signed, expiring review link
    func generateLink(
        projectID: String,
        reviewerEmail: String,
        expiresIn: TimeInterval = 7 * 24 * 3600, // 7 days default
        permissions: ReviewPermissions = .viewAndComment
    ) -> URL {
        let expiry = Int(Date().timeIntervalSince1970 + expiresIn)
        let payload = "\(projectID):\(reviewerEmail):\(expiry):\(permissions.rawValue)"

        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: signingKey
        )
        let signatureHex = Data(signature).map { String(format: "%02x", $0) }.joined()

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/review/\(projectID)"
        components.queryItems = [
            URLQueryItem(name: "reviewer", value: reviewerEmail),
            URLQueryItem(name: "expires", value: String(expiry)),
            URLQueryItem(name: "permissions", value: permissions.rawValue),
            URLQueryItem(name: "sig", value: signatureHex)
        ]
        return components.url!
    }

    /// Validate a review link on the server side
    func validateLink(url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return false }

        let reviewer = items.first(where: { $0.name == "reviewer" })?.value ?? ""
        let expiryStr = items.first(where: { $0.name == "expires" })?.value ?? "0"
        let permissions = items.first(where: { $0.name == "permissions" })?.value ?? ""
        let receivedSig = items.first(where: { $0.name == "sig" })?.value ?? ""

        let projectID = components.path.replacingOccurrences(of: "/review/", with: "")
        let expiry = Int(expiryStr) ?? 0

        // Check expiry
        guard expiry > Int(Date().timeIntervalSince1970) else { return false }

        // Verify signature
        let payload = "\(projectID):\(reviewer):\(expiry):\(permissions)"
        let expectedSig = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: signingKey
        )
        let expectedHex = Data(expectedSig).map { String(format: "%02x", $0) }.joined()

        return receivedSig == expectedHex
    }
}

enum ReviewPermissions: String {
    case viewOnly = "view"
    case viewAndComment = "comment"
    case viewCommentApprove = "approve"
}
```

### Frame.io Integration Notes (2025)
- **V4 API** with DRM, forensic watermarking, and speaker-aware transcripts
- **Quick Share** modal for faster review link creation
- **NLP search** across all assets on paid plans
- **Firefly Actions**: Reframe, Dub (17 languages), Remove Background built-in
- Enterprise security: SSO, 2FA, dynamic watermarking, embed code expiration

---

## 4. Media Encryption at Rest

### FileVault — Whole-Disk Encryption
On Macs with Apple silicon or T2 chips, all data on the internal SSD is encrypted automatically using AES-XTS with hardware acceleration. FileVault adds password-gated access to this encryption. Enabling FileVault is essentially instant on modern Macs since the volume is already encrypted — it just wraps the volume key with the user password.

**Key facts:**
- Algorithm: AES-XTS (hardware-accelerated via Secure Enclave)
- Performance impact: Minimal on SSDs; hardware encryption engine operates at line speed
- Compliance: FIPS-validated cryptographic modules
- Limitation: Data is accessible once logged in — FileVault protects only data at rest (powered off / locked)

### Application-Level Media Encryption with CryptoKit

```swift
import CryptoKit
import Foundation

/// Encrypt/decrypt project media files at the application level
class MediaEncryptionManager {
    private let masterKey: SymmetricKey

    init(masterKey: SymmetricKey) {
        self.masterKey = masterKey
    }

    /// Generate a new master key and store in Keychain
    static func generateAndStoreKey(
        service: String = "com.editor.media-encryption"
    ) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)

        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "master-key",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary) // Remove old key if exists
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed
        }
        return key
    }

    /// Encrypt a small-to-medium file (fits in memory)
    func encryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let sealedBox = try AES.GCM.seal(data, using: masterKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealingFailed
        }
        try combined.write(to: destinationURL)
    }

    /// Decrypt a small-to-medium file
    func decryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        let combined = try Data(contentsOf: sourceURL)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(sealedBox, using: masterKey)
        try decryptedData.write(to: destinationURL)
    }

    /// Stream-encrypt a large video file using chunked AES-GCM
    /// CryptoKit requires the entire plaintext in memory for seal().
    /// For multi-GB video files, process in chunks with per-chunk authentication.
    func encryptLargeFile(
        at sourceURL: URL,
        to destinationURL: URL,
        chunkSize: Int = 16 * 1024 * 1024 // 16 MB chunks
    ) throws {
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { inputHandle.closeFile() }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer { outputHandle.closeFile() }

        // Write file header with version and chunk size
        var header = EncryptedFileHeader(
            magic: 0x454E4352, // "ENCR"
            version: 1,
            chunkSize: UInt32(chunkSize),
            originalSize: try FileManager.default.attributesOfItem(
                atPath: sourceURL.path
            )[.size] as! UInt64
        )
        let headerData = withUnsafeBytes(of: &header) { Data($0) }
        outputHandle.write(headerData)

        var chunkIndex: UInt64 = 0
        while true {
            let chunk = inputHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            // Use chunk index as nonce component for deterministic nonce
            let sealedBox = try AES.GCM.seal(chunk, using: masterKey)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.sealingFailed
            }

            // Write chunk length + encrypted data
            var length = UInt32(combined.count)
            outputHandle.write(Data(bytes: &length, count: 4))
            outputHandle.write(combined)

            chunkIndex += 1
        }
    }

    /// Stream-decrypt a large video file
    func decryptLargeFile(
        at sourceURL: URL,
        to destinationURL: URL
    ) throws {
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { inputHandle.closeFile() }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        defer { outputHandle.closeFile() }

        // Read header
        let headerData = inputHandle.readData(ofLength: MemoryLayout<EncryptedFileHeader>.size)
        let header = headerData.withUnsafeBytes { $0.load(as: EncryptedFileHeader.self) }
        guard header.magic == 0x454E4352 else {
            throw EncryptionError.invalidFileFormat
        }

        while true {
            let lengthData = inputHandle.readData(ofLength: 4)
            if lengthData.count < 4 { break }

            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let combined = inputHandle.readData(ofLength: Int(length))

            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decryptedChunk = try AES.GCM.open(sealedBox, using: masterKey)
            outputHandle.write(decryptedChunk)
        }
    }
}

struct EncryptedFileHeader {
    var magic: UInt32       // "ENCR" identifier
    var version: UInt32
    var chunkSize: UInt32
    var originalSize: UInt64
}

enum EncryptionError: Error {
    case keychainStoreFailed
    case sealingFailed
    case invalidFileFormat
}
```

### Secure Temporary Files

```swift
import Foundation

/// Manage secure temporary files for editing sessions
class SecureTempFileManager {
    private let tempDirectory: URL
    private var trackedFiles: [URL] = []

    init() throws {
        // Use app sandbox temporary directory
        let baseTemp = FileManager.default.temporaryDirectory
        self.tempDirectory = baseTemp.appendingPathComponent(
            "com.editor.secure-temp-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Create a secure temporary file
    func createTempFile(extension ext: String) -> URL {
        let url = tempDirectory.appendingPathComponent(
            "\(UUID().uuidString).\(ext)"
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
        trackedFiles.append(url)

        // Set restrictive permissions (owner read/write only)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Securely delete all temporary files (overwrite before deletion)
    func cleanupAll() {
        for fileURL in trackedFiles {
            secureDelete(at: fileURL)
        }
        try? FileManager.default.removeItem(at: tempDirectory)
        trackedFiles.removeAll()
    }

    /// Overwrite file contents before deletion
    private func secureDelete(at url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        let size = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? Int) ?? 0

        // Overwrite with random data
        let chunkSize = 1024 * 1024 // 1 MB
        var remaining = size
        while remaining > 0 {
            let writeSize = min(chunkSize, remaining)
            var randomData = Data(count: writeSize)
            randomData.withUnsafeMutableBytes { buffer in
                _ = SecRandomCopyBytes(kSecRandomDefault, writeSize, buffer.baseAddress!)
            }
            handle.write(randomData)
            remaining -= writeSize
        }
        handle.closeFile()
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        cleanupAll()
    }
}
```

---

## 5. Licensing System

### StoreKit 2 for Mac App Store Distribution

StoreKit 2 provides modern async/await APIs with automatic transaction verification via JWS (JSON Web Signature). Transactions are cryptographically signed by the App Store, eliminating the need for manual receipt parsing.

```swift
import StoreKit

/// StoreKit 2 licensing manager for NLE subscription and feature unlocking
@MainActor
class LicenseManager: ObservableObject {

    // MARK: - Product Identifiers

    enum ProductID: String, CaseIterable {
        case monthlyPro = "com.editor.pro.monthly"
        case yearlyPro = "com.editor.pro.yearly"
        case colorGradingPack = "com.editor.addon.colorgrading"
        case effectsPack = "com.editor.addon.effects"
        case studioUpgrade = "com.editor.studio.lifetime"
    }

    enum LicenseTier: Comparable {
        case free
        case pro
        case studio
    }

    // MARK: - Published State

    @Published private(set) var currentTier: LicenseTier = .free
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []

    private var transactionListener: Task<Void, Error>?

    // MARK: - Initialization

    init() {
        // Listen for transaction updates (renewals, revocations, etc.)
        transactionListener = Task.detached {
            for await result in Transaction.updates {
                await self.handleTransactionUpdate(result)
            }
        }

        // Check current entitlements on launch
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            let productIDs = ProductID.allCases.map(\.rawValue)
            availableProducts = try await Product.products(for: Set(productIDs))
                .sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerification(verification)
            await transaction.finish()
            await refreshEntitlements()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Transaction requires approval (Ask to Buy, etc.)
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Entitlement Checking

    func refreshEntitlements() async {
        var purchased = Set<String>()

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerification(result) {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
        updateTier()
    }

    private func updateTier() {
        if purchasedProductIDs.contains(ProductID.studioUpgrade.rawValue) {
            currentTier = .studio
        } else if purchasedProductIDs.contains(ProductID.monthlyPro.rawValue) ||
                    purchasedProductIDs.contains(ProductID.yearlyPro.rawValue) {
            currentTier = .pro
        } else {
            currentTier = .free
        }
    }

    // MARK: - Feature Gating

    func isFeatureAvailable(_ feature: EditorFeature) -> Bool {
        switch feature {
        case .basicEditing, .basicTransitions, .export720p:
            return true // Always available (free tier)

        case .multitrackTimeline, .export1080p, .basicColorCorrection:
            return currentTier >= .pro

        case .colorGrading:
            return currentTier >= .pro ||
                   purchasedProductIDs.contains(ProductID.colorGradingPack.rawValue)

        case .advancedEffects:
            return currentTier >= .pro ||
                   purchasedProductIDs.contains(ProductID.effectsPack.rawValue)

        case .export4K, .hdrGrading, .multiGPU, .collaborativeEditing:
            return currentTier >= .studio
        }
    }

    /// Restore purchases (user-initiated)
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Verification

    private func checkVerification<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw LicenseError.verificationFailed(error)
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerification(result) else { return }

        if transaction.revocationDate != nil {
            // Subscription was revoked — remove entitlement
            purchasedProductIDs.remove(transaction.productID)
        } else {
            purchasedProductIDs.insert(transaction.productID)
        }

        await transaction.finish()
        updateTier()
    }
}

enum EditorFeature {
    case basicEditing, basicTransitions, export720p
    case multitrackTimeline, export1080p, basicColorCorrection
    case colorGrading, advancedEffects
    case export4K, hdrGrading, multiGPU, collaborativeEditing
}

enum LicenseError: Error {
    case verificationFailed(Error)
}
```

### License Key System for Direct Distribution

For distribution outside the Mac App Store (direct download, Paddle, etc.):

```swift
import Foundation
import CryptoKit

/// License key validation for direct (non-App Store) distribution
class DirectLicenseManager {

    struct License: Codable {
        let key: String
        let email: String
        let tier: String
        let issuedAt: Date
        let expiresAt: Date?
        let machineLimit: Int
        let signature: String
    }

    private let publicKeyData: Data // Ed25519 public key for signature verification

    init(publicKeyPEM: String) {
        // Extract raw key data from PEM
        let stripped = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        self.publicKeyData = Data(base64Encoded: stripped)!
    }

    /// Validate a license key (offline-capable with online activation check)
    func validateLicense(_ licenseKey: String) async throws -> License {
        // 1. Decode the license
        guard let licenseData = Data(base64Encoded: licenseKey) else {
            throw LicenseKeyError.invalidFormat
        }

        let license = try JSONDecoder().decode(License.self, from: licenseData)

        // 2. Verify cryptographic signature
        let signable = "\(license.key):\(license.email):\(license.tier):\(license.issuedAt.timeIntervalSince1970)"
        let signatureData = Data(base64Encoded: license.signature)!
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)

        guard publicKey.isValidSignature(signatureData, for: Data(signable.utf8)) else {
            throw LicenseKeyError.invalidSignature
        }

        // 3. Check expiry
        if let expiry = license.expiresAt, expiry < Date() {
            throw LicenseKeyError.expired
        }

        // 4. Machine binding check
        let machineID = try getMachineIdentifier()
        let activated = try await activateOnServer(
            license: license,
            machineID: machineID
        )
        guard activated else {
            throw LicenseKeyError.machineLimitExceeded
        }

        // 5. Cache validated license locally
        try cacheLicense(license)

        return license
    }

    /// Get a stable machine identifier (hardware UUID)
    private func getMachineIdentifier() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else {
            throw LicenseKeyError.machineIDUnavailable
        }

        // Hash the UUID for privacy
        let hash = SHA256.hash(data: Data(uuid.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Activate license on server (returns false if machine limit exceeded)
    private func activateOnServer(
        license: License,
        machineID: String
    ) async throws -> Bool {
        var request = URLRequest(
            url: URL(string: "https://api.youreditor.com/activate")!
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "key": license.key,
            "machine": machineID
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        switch http.statusCode {
        case 200: return true
        case 409: return false // Machine limit exceeded
        default: throw LicenseKeyError.serverError
        }
    }

    /// Cache license in Keychain for offline validation
    private func cacheLicense(_ license: License) throws {
        let data = try JSONEncoder().encode(license)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.editor.license",
            kSecAttrAccount as String: "active-license",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Load cached license for offline use
    func loadCachedLicense() -> License? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.editor.license",
            kSecAttrAccount as String: "active-license",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(License.self, from: data)
    }
}

enum LicenseKeyError: Error {
    case invalidFormat
    case invalidSignature
    case expired
    case machineLimitExceeded
    case machineIDUnavailable
    case serverError
}
```

### Freemium Model: Feature Gating Implementation

```swift
import SwiftUI

/// Feature gate overlay that prompts upgrade
struct FeatureGateView<Content: View>: View {
    let feature: EditorFeature
    let content: Content
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var showUpgradeSheet = false

    init(feature: EditorFeature, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.content = content()
    }

    var body: some View {
        if licenseManager.isFeatureAvailable(feature) {
            content
        } else {
            content
                .disabled(true)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title)
                        Text("Pro Feature")
                            .font(.headline)
                        Text("Upgrade to unlock \(feature)")
                            .font(.caption)
                        Button("Upgrade") {
                            showUpgradeSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
                .sheet(isPresented: $showUpgradeSheet) {
                    UpgradeView()
                }
        }
    }
}
```

---

## 6. Pricing Models — Competitive Analysis & Recommendation

### Market Landscape (2025-2026)

| App | Model | Price | Free Tier | Platform |
|-----|-------|-------|-----------|----------|
| **DaVinci Resolve** | Free + perpetual | $0 / $295 Studio | Full editor (no watermark) | Mac/Win/Linux |
| **Final Cut Pro** | Perpetual | $299 (90-day trial) | No | macOS only |
| **Premiere Pro** | Subscription | $22.99/mo ($239.88/yr) | 7-day trial | Mac/Win |
| **CapCut** | Freemium + sub | $0 / $9.99-19.99/mo Pro | Full basic editor | All platforms |
| **Filmora** | Perpetual + sub | $49.99/yr or $79.99 perpetual | Watermarked exports | Mac/Win |

### Key Observations
- **DaVinci Resolve's free tier** is the industry disruptor — a genuinely capable editor with no watermarks or time limits. Studio adds HDR, AI masking, multi-GPU, noise reduction.
- **Final Cut Pro** at $299 one-time pays for itself within 13 months vs Premiere's subscription.
- **Premiere Pro** subscription model faces growing user dissatisfaction, but retains dominance in team/enterprise workflows.
- **CapCut** proves free-to-use with optional paid unlocks works for casual/prosumer market (1B+ downloads).

### Recommended Pricing Strategy for Our NLE

**Hybrid Freemium + Perpetual model** (inspired by DaVinci Resolve + CapCut's best elements):

| Tier | Price | Target | Includes |
|------|-------|--------|----------|
| **Free** | $0 | Students, hobbyists | Full timeline editing, basic transitions/effects, 1080p export, basic color correction, single GPU |
| **Pro** (subscription) | $9.99/mo or $99/yr | Content creators, freelancers | 4K export, advanced effects, multi-track audio, basic color grading, LUT import |
| **Studio** (perpetual) | $249 one-time | Professionals | Everything in Pro + HDR grading, multi-GPU, noise reduction, team collaboration, broadcast delivery |
| **Add-on packs** | $29-49 each | A-la-carte | Color grading pack, effects pack, audio mastering pack |

**Rationale:**
- Free tier must be genuinely useful (no watermarks on exports) to compete with DaVinci Resolve free
- Subscription for mid-tier provides recurring revenue
- Perpetual option for professionals who resist subscriptions
- Add-on packs enable targeted upselling without forcing full upgrade
- Price Studio below FCP ($299) and Resolve Studio ($295) to be competitive

---

## 7. Anti-Piracy

### What Actually Works vs Security Theater

**Effective measures (raise the bar meaningfully):**
1. StoreKit 2 transaction verification (JWS-signed, tamper-evident)
2. Server-side activation with machine binding
3. Receipt validation with obfuscated code paths
4. Code signing integrity checks at runtime
5. Combination of multiple lightweight checks

**Security theater (easily bypassed, not worth heavy investment):**
1. Complex local-only license checks (patched out in minutes)
2. Heavy obfuscation (slows legitimate users, determined crackers still bypass)
3. Anti-debugging measures alone (trivially defeated)
4. Hardware dongles for software-only products

### Runtime Code Signing Verification

```swift
import Foundation
import Security

/// Verify the app's code signature hasn't been tampered with at runtime
class IntegrityChecker {

    /// Check that the running binary has a valid Apple code signature
    static func verifyCodeSignature() -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [], &staticCode
        ) == errSecSuccess, let code = staticCode else {
            return false
        }

        // Verify against designated requirement (embedded in the binary)
        let status = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil // Uses designated requirement
        )
        return status == errSecSuccess
    }

    /// Verify the app was signed by our specific team
    static func verifyTeamIdentifier(expected: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [], &staticCode
        ) == errSecSuccess, let code = staticCode else {
            return false
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            code, SecCSFlags(rawValue: kSecCSSigningInformation), &info
        ) == errSecSuccess, let signingInfo = info as? [String: Any] else {
            return false
        }

        let teamID = signingInfo["teamid"] as? String
        return teamID == expected
    }

    /// Check that the App Store receipt is present and valid (basic check)
    static func verifyReceiptPresence() -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }

    /// Verify bundle identifier matches (detects re-signing)
    static func verifyBundleIdentifier(expected: String) -> Bool {
        return Bundle.main.bundleIdentifier == expected
    }

    /// Combined integrity check — call from multiple places in the app
    static func performIntegrityCheck(
        teamID: String,
        bundleID: String
    ) -> Bool {
        // Scatter these checks throughout the codebase, not just at launch
        let checks = [
            verifyCodeSignature(),
            verifyTeamIdentifier(expected: teamID),
            verifyBundleIdentifier(expected: bundleID)
        ]
        return checks.allSatisfy { $0 }
    }
}
```

### Obfuscation Tools for macOS Swift
- **Secretly** (secretly.dev): Obfuscates each release build, prevents recurring ASM patterns. Covers receipt validation, integrity checking, SSL pinning, debugger detection.
- **Receigen**: Auto-generates receipt validation code with obfuscation.
- **Compiler flags**: `-Osize` or `-O` optimization already makes reverse engineering harder. Strip debug symbols (`STRIP_INSTALLED_PRODUCT = YES`).

### Practical Anti-Piracy Philosophy
- **Accept that determined pirates will crack any protection**. The goal is to make casual piracy inconvenient, not to stop all piracy.
- **Focus on making purchasing easy** rather than making piracy hard. A frictionless purchase flow with fair pricing converts more users than aggressive DRM.
- **Don't punish paying customers** with overly aggressive checks (e.g., requiring constant internet, frequent re-activation).
- **Monitor, don't block**: Log integrity check results to analytics rather than immediately killing the app. This data helps understand piracy scope.

### 2025 SHA-256 Receipt Update
As of January 24, 2025, App Store receipt signing uses SHA-256. Any local receipt validation code using the older SHA-1 intermediate certificate must be updated.

---

## 8. Broadcast Safe

### IRE Limits and Color Legality
For broadcast delivery (SD/HD Rec. 601/709):
- **Luminance**: Must not exceed 100 IRE
- **Chroma**: Must stay within -20 to 120 IRE
- **Black level**: 7.5 IRE (NTSC), 0 IRE (PAL/NTSC-J)
- **Modern standard**: EBU R103 for file-based delivery (not IRE-based)
- **Web-only content**: No IRE restrictions apply

### Gamut Warning Overlay (Metal Shader)

```metal
#include <metal_stdlib>
using namespace metal;

/// Convert RGB to YCbCr (BT.709) and check broadcast legality
kernel void broadcastSafeOverlay(
    texture2d<float, access::read>  input    [[texture(0)]],
    texture2d<float, access::write> output   [[texture(1)]],
    constant float &maxIRE                   [[buffer(0)]],  // Typically 100.0
    constant float &minIRE                   [[buffer(1)]],  // Typically 0.0 or 7.5
    constant uint  &mode                     [[buffer(2)]],  // 0=overlay, 1=clamp, 2=soft-clip
    uint2 gid                                [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;

    float4 pixel = input.read(gid);

    // BT.709 RGB to Y (luminance)
    float Y = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;

    // Convert to IRE scale (0.0 = 0 IRE, 1.0 = 100 IRE for full range)
    float ire = Y * 100.0;

    // BT.709 chroma (simplified)
    float Cb = -0.1146 * pixel.r - 0.3854 * pixel.g + 0.5 * pixel.b;
    float Cr =  0.5 * pixel.r - 0.4542 * pixel.g - 0.0458 * pixel.b;
    float chromaIRE = sqrt(Cb * Cb + Cr * Cr) * 200.0;

    bool lumaViolation = ire > maxIRE || ire < minIRE;
    bool chromaViolation = chromaIRE > 120.0;

    if (mode == 0) {
        // Overlay mode: show violations as colored zebra stripes
        if (lumaViolation) {
            // Red overlay for luma violations
            float stripe = step(0.5, fract(float(gid.x + gid.y) * 0.1));
            pixel.rgb = mix(pixel.rgb, float3(1.0, 0.0, 0.0), 0.5 * stripe);
        }
        if (chromaViolation) {
            // Magenta overlay for chroma violations
            float stripe = step(0.5, fract(float(gid.x - gid.y) * 0.1));
            pixel.rgb = mix(pixel.rgb, float3(1.0, 0.0, 1.0), 0.5 * stripe);
        }
    } else if (mode == 1) {
        // Hard clamp mode
        float maxY = maxIRE / 100.0;
        float minY = minIRE / 100.0;
        if (Y > maxY) {
            float scale = maxY / Y;
            pixel.rgb *= scale;
        } else if (Y < minY) {
            float scale = minY / max(Y, 0.001);
            pixel.rgb *= scale;
        }
    } else if (mode == 2) {
        // Soft-clip mode (preserves some highlight detail)
        float maxY = maxIRE / 100.0;
        float knee = maxY * 0.9; // Start compression at 90% of max
        if (Y > knee) {
            float compressed = knee + (maxY - knee) * tanh((Y - knee) / (maxY - knee));
            float scale = compressed / max(Y, 0.001);
            pixel.rgb *= scale;
        }
    }

    output.write(pixel, gid);
}
```

### Swift Broadcast Safe Manager

```swift
import Metal
import AVFoundation

/// Broadcast safe analysis and correction for the NLE
class BroadcastSafeManager {

    enum Standard {
        case rec601NTSC  // 7.5 - 100 IRE
        case rec601PAL   // 0 - 100 IRE
        case rec709      // 0 - 100 IRE (HD)
        case rec2020     // HDR — different handling
    }

    enum CorrectionMode: UInt32 {
        case overlayOnly = 0   // Visual warning only
        case hardClamp = 1     // Clamp to legal range
        case softClip = 2      // Knee compression
    }

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState

    init(device: MTLDevice) throws {
        self.device = device
        let library = try device.makeDefaultLibrary(bundle: .main)
        let function = library.makeFunction(name: "broadcastSafeOverlay")!
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    /// Analyze a frame for broadcast safety violations
    func analyzeFrame(_ texture: MTLTexture) -> BroadcastSafeReport {
        // Read back texture data and analyze (simplified)
        // In production, use a Metal reduction kernel for GPU-side analysis
        return BroadcastSafeReport(
            maxLumaIRE: 0, minLumaIRE: 0,
            maxChromaIRE: 0,
            lumaViolationPercentage: 0,
            chromaViolationPercentage: 0,
            isBroadcastSafe: true
        )
    }

    struct BroadcastSafeReport {
        let maxLumaIRE: Float
        let minLumaIRE: Float
        let maxChromaIRE: Float
        let lumaViolationPercentage: Float
        let chromaViolationPercentage: Float
        let isBroadcastSafe: Bool
    }
}
```

### Clamping vs Soft-Clip vs Manual Correction
- **Hard clamp**: Resets all values above 100 IRE to exactly 100. Simple but destroys highlight detail (e.g., white wedding dress detail is lost).
- **Soft-clip (knee compression)**: Gradually compresses highlights approaching the limit. Preserves more detail but subtly changes the look.
- **Manual correction**: Using Lumetri/color wheels to bring whites down. Best results but time-consuming. Recommended for final grading.
- **Best practice**: Use gamut warning overlays during editing, apply soft-clip as a safety net on the master output, but grade manually for critical content.

---

## 9. Quality Control

### EBU R128 Audio Loudness Measurement

EBU R128 specifies:
- **Integrated loudness**: -23 LUFS (+/- 0.5 LU, or +/- 1.0 LU for live)
- **Maximum true peak**: -1 dBTP
- **Measurement modes**: Momentary (400ms window), Short-term (3s window), Integrated (full program)
- **Gating**: Absolute threshold at -70 LUFS, relative gate at -10 LU below ungated level

```swift
import AVFoundation
import Accelerate

/// EBU R128 loudness measurement using AVFoundation + Accelerate
class LoudnessMeter {

    struct LoudnessResult {
        let integratedLUFS: Float    // Target: -23 LUFS
        let truePeakDBTP: Float      // Must be <= -1 dBTP
        let loudnessRange: Float     // LRA in LU
        let shortTermMax: Float      // Maximum short-term loudness
        let isCompliant: Bool
    }

    /// Measure integrated loudness of an audio file per EBU R128
    func measureLoudness(url: URL) async throws -> LoudnessResult {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw QCError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48000
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var allSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &dataPointer)
            guard let data = dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            let floatBuffer = UnsafeBufferPointer(
                start: data.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 },
                count: floatCount
            )
            allSamples.append(contentsOf: floatBuffer)
        }

        // Apply K-weighting filter (ITU-R BS.1770)
        let kWeighted = applyKWeighting(samples: allSamples, sampleRate: 48000)

        // Calculate integrated loudness with gating
        let integrated = calculateIntegratedLoudness(kWeighted, sampleRate: 48000)

        // Calculate true peak (4x oversampled)
        let truePeak = calculateTruePeak(allSamples)

        // Calculate loudness range
        let lra = calculateLoudnessRange(kWeighted, sampleRate: 48000)

        let isCompliant = integrated >= -23.5 && integrated <= -22.5 && truePeak <= -1.0

        return LoudnessResult(
            integratedLUFS: integrated,
            truePeakDBTP: truePeak,
            loudnessRange: lra,
            shortTermMax: 0, // Would compute from 3s windows
            isCompliant: isCompliant
        )
    }

    /// K-weighting filter: pre-filter (high-shelf) + RLB weighting
    /// Per ITU-R BS.1770-5
    private func applyKWeighting(samples: [Float], sampleRate: Int) -> [Float] {
        var filtered = samples

        // Stage 1: Pre-filter (shelving) — boosts high frequencies
        // Coefficients for 48kHz (from ITU-R BS.1770)
        let preB: [Double] = [1.53512485958697, -2.69169618940638, 1.19839281085285]
        let preA: [Double] = [1.0, -1.69065929318241, 0.73248077421585]
        filtered = applyBiquad(filtered, b: preB, a: preA)

        // Stage 2: RLB weighting (high-pass, revised low-frequency B-curve)
        let rlbB: [Double] = [1.0, -2.0, 1.0]
        let rlbA: [Double] = [1.0, -1.99004745483398, 0.99007225036621]
        filtered = applyBiquad(filtered, b: rlbB, a: rlbA)

        return filtered
    }

    private func applyBiquad(_ input: [Float], b: [Double], a: [Double]) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        var z1: Double = 0, z2: Double = 0

        for i in 0..<input.count {
            let x = Double(input[i])
            let y = b[0] * x + z1
            z1 = b[1] * x - a[1] * y + z2
            z2 = b[2] * x - a[2] * y
            output[i] = Float(y)
        }
        return output
    }

    /// Integrated loudness with absolute and relative gating
    private func calculateIntegratedLoudness(
        _ kWeighted: [Float],
        sampleRate: Int
    ) -> Float {
        let blockSize = sampleRate * 400 / 1000 // 400ms blocks
        let hopSize = blockSize / 4 // 75% overlap

        var blockLoudnesses: [Float] = []
        var i = 0
        while i + blockSize <= kWeighted.count {
            let block = Array(kWeighted[i..<i+blockSize])
            var sumSquares: Float = 0
            vDSP_svesq(block, 1, &sumSquares, vDSP_Length(block.count))
            let meanSquare = sumSquares / Float(block.count)
            let loudness = -0.691 + 10 * log10(max(meanSquare, 1e-10))
            blockLoudnesses.append(loudness)
            i += hopSize
        }

        // Absolute gate at -70 LUFS
        let absoluteGated = blockLoudnesses.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }

        let ungatedMean = absoluteGated.reduce(0, +) / Float(absoluteGated.count)

        // Relative gate at -10 LU below ungated mean
        let relativeThreshold = ungatedMean - 10
        let relativeGated = absoluteGated.filter { $0 > relativeThreshold }
        guard !relativeGated.isEmpty else { return ungatedMean }

        return relativeGated.reduce(0, +) / Float(relativeGated.count)
    }

    /// True peak measurement with 4x oversampling
    private func calculateTruePeak(_ samples: [Float]) -> Float {
        // 4x oversample using vDSP interpolation
        let oversampleFactor = 4
        var oversampled = [Float](repeating: 0, count: samples.count * oversampleFactor)

        // Simple linear interpolation (production should use polyphase FIR)
        for i in 0..<samples.count - 1 {
            for j in 0..<oversampleFactor {
                let t = Float(j) / Float(oversampleFactor)
                oversampled[i * oversampleFactor + j] = samples[i] * (1 - t) + samples[i + 1] * t
            }
        }

        var peak: Float = 0
        vDSP_maxmgv(oversampled, 1, &peak, vDSP_Length(oversampled.count))

        return 20 * log10(max(peak, 1e-10)) // Convert to dBTP
    }

    /// Loudness Range (LRA) per EBU R128
    private func calculateLoudnessRange(
        _ kWeighted: [Float],
        sampleRate: Int
    ) -> Float {
        // Compute short-term (3s) loudness values, gate, then find
        // 10th and 95th percentiles. LRA = difference.
        let blockSize = sampleRate * 3 // 3-second blocks
        let hopSize = blockSize / 3

        var stLoudnesses: [Float] = []
        var i = 0
        while i + blockSize <= kWeighted.count {
            let block = Array(kWeighted[i..<i+blockSize])
            var sumSquares: Float = 0
            vDSP_svesq(block, 1, &sumSquares, vDSP_Length(block.count))
            let meanSquare = sumSquares / Float(block.count)
            let loudness = -0.691 + 10 * log10(max(meanSquare, 1e-10))
            stLoudnesses.append(loudness)
            i += hopSize
        }

        let gated = stLoudnesses.filter { $0 > -70 }.sorted()
        guard gated.count >= 2 else { return 0 }

        let low = gated[Int(Float(gated.count) * 0.1)]
        let high = gated[Int(Float(gated.count) * 0.95)]
        return high - low
    }
}

enum QCError: Error {
    case noAudioTrack
    case noVideoTrack
    case analysisFailure
}
```

### Automated QC Pipeline

```swift
import AVFoundation

/// Comprehensive automated quality control checks for broadcast delivery
class AutomatedQCPipeline {

    struct QCReport {
        var loudnessResult: LoudnessMeter.LoudnessResult?
        var blackFrames: [CMTimeRange] = []
        var colorSpaceVerified: Bool = false
        var safeAreaViolations: Int = 0
        var pseRiskDetected: Bool = false
        var overallPass: Bool = false
        var issues: [QCIssue] = []
    }

    struct QCIssue {
        let severity: Severity
        let category: Category
        let description: String
        let timeRange: CMTimeRange?

        enum Severity { case error, warning, info }
        enum Category { case audio, video, metadata, compliance }
    }

    private let loudnessMeter = LoudnessMeter()

    /// Run full QC pipeline on an exported file
    func runFullQC(
        url: URL,
        standard: BroadcastStandard = .ebuR128,
        progress: @escaping (String, Float) -> Void
    ) async throws -> QCReport {
        var report = QCReport()

        let asset = AVURLAsset(url: url)

        // 1. Audio loudness check
        progress("Measuring audio loudness...", 0.1)
        do {
            let loudness = try await loudnessMeter.measureLoudness(url: url)
            report.loudnessResult = loudness

            if !loudness.isCompliant {
                if loudness.integratedLUFS < -24 || loudness.integratedLUFS > -22 {
                    report.issues.append(QCIssue(
                        severity: .error,
                        category: .audio,
                        description: "Integrated loudness \(String(format: "%.1f", loudness.integratedLUFS)) LUFS (target: -23 LUFS +/- 0.5)",
                        timeRange: nil
                    ))
                }
                if loudness.truePeakDBTP > -1.0 {
                    report.issues.append(QCIssue(
                        severity: .error,
                        category: .audio,
                        description: "True peak \(String(format: "%.1f", loudness.truePeakDBTP)) dBTP exceeds -1.0 dBTP limit",
                        timeRange: nil
                    ))
                }
            }
        } catch {
            report.issues.append(QCIssue(
                severity: .warning, category: .audio,
                description: "Audio loudness measurement failed: \(error)",
                timeRange: nil
            ))
        }

        // 2. Black frame detection
        progress("Detecting black frames...", 0.3)
        report.blackFrames = try await detectBlackFrames(asset: asset)
        for range in report.blackFrames {
            let start = CMTimeGetSeconds(range.start)
            let duration = CMTimeGetSeconds(range.duration)
            report.issues.append(QCIssue(
                severity: duration > 1.0 ? .error : .warning,
                category: .video,
                description: String(format: "Black frames detected at %.2fs (duration: %.2fs)", start, duration),
                timeRange: range
            ))
        }

        // 3. Color space verification
        progress("Verifying color space...", 0.5)
        report.colorSpaceVerified = try await verifyColorSpace(asset: asset)
        if !report.colorSpaceVerified {
            report.issues.append(QCIssue(
                severity: .warning, category: .video,
                description: "Color space metadata missing or inconsistent",
                timeRange: nil
            ))
        }

        // 4. Safe area check (title safe / action safe)
        progress("Checking safe areas...", 0.7)
        report.safeAreaViolations = try await checkSafeAreas(asset: asset)
        if report.safeAreaViolations > 0 {
            report.issues.append(QCIssue(
                severity: .warning, category: .video,
                description: "\(report.safeAreaViolations) frames with content outside title-safe area",
                timeRange: nil
            ))
        }

        // 5. PSE (Photosensitive Epilepsy) flash detection
        progress("PSE flash analysis...", 0.85)
        report.pseRiskDetected = try await detectPSERisk(asset: asset)
        if report.pseRiskDetected {
            report.issues.append(QCIssue(
                severity: .error, category: .compliance,
                description: "Potential PSE risk: rapid luminance changes exceed Ofcom/ITU BT.1702 thresholds",
                timeRange: nil
            ))
        }

        // Overall result
        progress("Complete", 1.0)
        report.overallPass = report.issues.filter { $0.severity == .error }.isEmpty

        return report
    }

    // MARK: - Individual QC Checks

    /// Detect sequences of black frames
    private func detectBlackFrames(
        asset: AVAsset,
        threshold: Float = 0.01, // Nearly-black threshold
        minDuration: Double = 0.5 // Minimum duration to flag
    ) async throws -> [CMTimeRange] {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw QCError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var blackRanges: [CMTimeRange] = []
        var blackStart: CMTime?

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let isBlack = analyzeFrameBrightness(pixelBuffer) < threshold

            if isBlack && blackStart == nil {
                blackStart = pts
            } else if !isBlack, let start = blackStart {
                let duration = CMTimeSubtract(pts, start)
                if CMTimeGetSeconds(duration) >= minDuration {
                    blackRanges.append(CMTimeRange(start: start, duration: duration))
                }
                blackStart = nil
            }
        }

        return blackRanges
    }

    private func analyzeFrameBrightness(_ pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Sample every 8th pixel for speed
        var totalBrightness: Float = 0
        var sampleCount: Float = 0

        for y in stride(from: 0, to: height, by: 8) {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width * 4, by: 32) {
                let b = Float(rowPtr[x]) / 255.0
                let g = Float(rowPtr[x + 1]) / 255.0
                let r = Float(rowPtr[x + 2]) / 255.0
                totalBrightness += 0.2126 * r + 0.7152 * g + 0.0722 * b
                sampleCount += 1
            }
        }

        return sampleCount > 0 ? totalBrightness / sampleCount : 0
    }

    /// Verify color space metadata matches expected standard
    private func verifyColorSpace(asset: AVAsset) async throws -> Bool {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else { return false }

        // Check for color space extensions
        let colorPrimaries = CMFormatDescriptionGetExtension(
            formatDesc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        )
        let transferFunction = CMFormatDescriptionGetExtension(
            formatDesc, extensionKey: kCMFormatDescriptionExtension_TransferFunction
        )
        let ycbcrMatrix = CMFormatDescriptionGetExtension(
            formatDesc, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix
        )

        // All three should be present for proper color space identification
        return colorPrimaries != nil && transferFunction != nil && ycbcrMatrix != nil
    }

    /// Check for content outside title-safe and action-safe areas
    private func checkSafeAreas(asset: AVAsset) async throws -> Int {
        // Title safe: 80% of frame (10% margin each side)
        // Action safe: 90% of frame (5% margin each side)
        // Simplified: check if significant content exists in margins
        // Full implementation would use edge detection in margins
        return 0
    }

    /// Detect potential PSE (photosensitive epilepsy) triggers
    /// Based on ITU-R BT.1702 / Ofcom guidelines
    private func detectPSERisk(asset: AVAsset) async throws -> Bool {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        reader.startReading()

        var previousBrightness: Float?
        var flashCount = 0
        var flashesInLastSecond: [Double] = []
        let frameRate = try await videoTrack.load(.nominalFrameRate)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let brightness = analyzeFrameBrightness(pixelBuffer)

            if let prev = previousBrightness {
                let delta = abs(brightness - prev)

                // Ofcom: A flash is a luminance change > 20 cd/m2 (approx 0.1 in normalized)
                if delta > 0.1 {
                    flashesInLastSecond.append(pts)

                    // Remove flashes older than 1 second
                    flashesInLastSecond.removeAll { pts - $0 > 1.0 }

                    // Ofcom: More than 3 flashes per second is a violation
                    if flashesInLastSecond.count > 3 {
                        return true // PSE risk detected
                    }
                }
            }
            previousBrightness = brightness
        }

        return false
    }
}

enum BroadcastStandard {
    case ebuR128       // European broadcast
    case atscA85       // US broadcast (CALM Act)
    case abcAustralia  // Australia OP-59
}
```

### Industry QC Tools
- **Telestream Vidchecker**: Automated QC for broadcast standards compliance
- **Venera Pulsar**: Extensive audio/video checks including PSE, loudness, CALM Act
- **Interra BATON**: Industry-leading check coverage for file-based QC
- **Harding FPA**: The reference PSE testing tool, licensed by Netflix, required by Ofcom

### PSE Testing Requirements
- **UK (Ofcom Rule 2.12)**: Mandatory. Max 3 flashes/second, with luminance and red flash thresholds per ITU-R BT.1702.
- **Japan (NAB-J)**: Mandatory since the 1997 Pokemon incident.
- **Netflix**: Requires Harding FPA test results for animated content and high-VFX productions.
- **UK Online Safety Act 2023**: Criminal offense (up to 5 years) to deliberately send seizure-inducing content.

---

## 10. Content Rating for App Store

### Age Rating Requirements (2025 Update)

Apple introduced new age ratings (13+, 16+, 18+) in July 2025. Video editing apps must:

1. **Complete the updated age rating questionnaire** by January 31, 2026
2. **Implement age restriction** for UGC features using the Declared Age Range API
3. **Moderate user-generated content** if the app allows sharing

### UGC Moderation Checklist (Guideline 1.2)

```swift
import SwiftUI

/// Content moderation requirements for apps with user-generated content
struct ContentModerationConfig {
    /// Required moderation features per App Store Guidelines
    static let requiredFeatures: [ModerationFeature] = [
        .contentFilter,        // Filter objectionable material from being posted
        .reportContent,        // Mechanism to report offensive content
        .blockUser,            // Ability to block abusive users
        .publishedContactInfo, // Contact information for support
        .moderationQueue,      // Queue for reviewing flagged content
        .ageRestriction        // Age-based access control (new Nov 2025)
    ]

    enum ModerationFeature {
        case contentFilter
        case reportContent
        case blockUser
        case publishedContactInfo
        case moderationQueue
        case ageRestriction
    }
}

/// Age rating questionnaire categories relevant to video editing
struct AgeRatingAssessment {
    // For a video editing app, consider:
    let infrequentMildCartoonViolence = false  // If template effects include any
    let frequentIntenseRealisticViolence = false
    let matureContent = false
    let gamblingSimulations = false
    let userGeneratedContent: Bool             // TRUE if users can share creations
    let unrestrictedWebAccess = false

    /// Recommended: 4+ if no UGC sharing, 12+ if UGC sharing enabled
    var recommendedRating: String {
        if userGeneratedContent {
            return "12+" // Minimum for UGC apps
        }
        return "4+" // Pure editing tool with no sharing
    }
}

/// AI disclosure requirements (Guideline 5.1.2, Nov 2025)
struct AIFeatureDisclosure {
    /// If the app uses AI features that process user content with third-party services,
    /// explicit user consent is required before data transmission
    static func requiresDisclosure(features: [AIFeature]) -> Bool {
        return features.contains { $0.usesThirdPartyAI }
    }

    struct AIFeature {
        let name: String              // e.g., "AI Background Removal"
        let usesThirdPartyAI: Bool    // If data leaves device
        let dataTypes: [String]       // What data is sent
    }
}
```

### Key Guidelines for Video Editing Apps
- **No UGC sharing** (pure editing tool): Rate 4+, minimal compliance burden
- **With UGC sharing** (community features): Rate 12+ minimum, requires full moderation system, age-gating (Guideline 1.2.1), and content filtering
- **With AI features**: Must disclose third-party AI data sharing (Guideline 5.1.2)
- **Creator content (1.2.1)**: If the app enables creators to author and share video content, it must provide a way for users to flag content exceeding the age rating and implement age restriction based on verified or declared age

---

## Summary: Implementation Priority

| Priority | Feature | Complexity | Impact |
|----------|---------|------------|--------|
| **P0** | StoreKit 2 licensing | Medium | Revenue enablement |
| **P0** | Code signing verification | Low | Basic anti-tamper |
| **P0** | App Store age rating | Low | Store approval |
| **P1** | Broadcast safe overlay | Medium | Professional credibility |
| **P1** | EBU R128 loudness meter | High | Broadcast delivery |
| **P1** | Visible burn-in watermarks | Low | Client review workflow |
| **P2** | Direct distribution licensing | High | Non-App Store revenue |
| **P2** | Secure preview exports | Medium | Client collaboration |
| **P2** | Media encryption at rest | Medium | Enterprise/studio sales |
| **P2** | Automated QC pipeline | High | Professional differentiation |
| **P3** | Forensic watermarking | Very High | Studio/enterprise feature |
| **P3** | FairPlay DRM integration | Very High | Niche use case |
| **P3** | PSE testing | High | Broadcast compliance |
