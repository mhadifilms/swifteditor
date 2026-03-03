# macOS App Distribution, Testing & Shipping for NLE

## Table of Contents
1. [macOS Sandboxing & Entitlements](#1-macos-sandboxing--entitlements)
2. [FFmpeg in the Sandbox](#2-ffmpeg-in-the-sandbox)
3. [Distribution: App Store vs Direct](#3-distribution-app-store-vs-direct)
4. [Notarization Workflow](#4-notarization-workflow)
5. [Sparkle Auto-Updates](#5-sparkle-auto-updates)
6. [Performance Testing & Benchmarking](#6-performance-testing--benchmarking)
7. [Memory Management for Large Projects](#7-memory-management-for-large-projects)
8. [Crash Reporting & Diagnostics](#8-crash-reporting--diagnostics)
9. [Accessibility Testing for Timeline UI](#9-accessibility-testing-for-timeline-ui)
10. [Localization & RTL Support](#10-localization--rtl-support)
11. [Document-Based App with UTType](#11-document-based-app-with-uttype)

---

## 1. macOS Sandboxing & Entitlements

### 1.1 App Sandbox Overview

The App Sandbox restricts what the app can access on the system. Required for Mac App Store, strongly recommended for direct distribution. Entitlements are declared in the `.entitlements` property list file.

### 1.2 Essential Entitlements for NLE

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Enable App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- File Access: user-selected files (Open/Save dialogs) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- File Access: persist access across launches via bookmarks -->
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>

    <!-- Camera access (for capture/recording features) -->
    <key>com.apple.security.device.camera</key>
    <true/>

    <!-- Microphone / Audio input -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <!-- Network access (for asset downloads, cloud sync, updates) -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- USB devices (external drives, capture cards) -->
    <key>com.apple.security.device.usb</key>
    <true/>

    <!-- Movies folder access (common media location) -->
    <key>com.apple.security.assets.movies.read-write</key>
    <true/>

    <!-- Downloads folder (common import/export location) -->
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
</dict>
</plist>
```

### 1.3 Security-Scoped Bookmarks for Persistent File Access

Users expect to reopen projects and still access the original media files. Security-scoped bookmarks solve this:

```swift
import Foundation

class MediaFileBookmarkManager {
    private let bookmarkKey = "savedMediaBookmarks"

    // MARK: - Save bookmark when user selects a file/folder

    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Store bookmark data persistently (UserDefaults, Core Data, project file)
        var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
    }

    // MARK: - Restore access on app relaunch

    func restoreAccess(for originalPath: String) -> URL? {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey),
              let bookmarkData = bookmarks[originalPath] as? Data else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-save the bookmark if the file moved
                try saveBookmark(for: url)
            }

            return url
        } catch {
            print("Failed to restore bookmark: \(error)")
            return nil
        }
    }

    // MARK: - Access scoped resource

    func withSecurityScopedAccess<T>(to url: URL, perform work: (URL) throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try work(url)
    }
}
```

### 1.4 Managing Multiple Media Folders

NLE projects typically reference media across many folders. Store bookmarks for each:

```swift
class ProjectMediaResolver {
    let bookmarkManager = MediaFileBookmarkManager()

    /// Called when user adds media through Open dialog
    func userSelectedMedia(urls: [URL]) {
        for url in urls {
            // Bookmark the parent directory for broad access
            let parentDir = url.deletingLastPathComponent()
            try? bookmarkManager.saveBookmark(for: parentDir)
        }
    }

    /// Called when opening a saved project
    func resolveProjectMedia(mediaPaths: [String]) -> [String: URL] {
        var resolved: [String: URL] = [:]

        for path in mediaPaths {
            // Try parent directories first (fewer bookmarks to maintain)
            let parentPath = (path as NSString).deletingLastPathComponent
            if let parentURL = bookmarkManager.restoreAccess(for: parentPath) {
                let _ = parentURL.startAccessingSecurityScopedResource()
                let fileURL = parentURL.appendingPathComponent(
                    (path as NSString).lastPathComponent
                )
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    resolved[path] = fileURL
                }
            }
        }

        return resolved
    }
}
```

### 1.5 Info.plist Privacy Keys

Required alongside entitlements for camera and microphone:

```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>SwiftEditor needs camera access to record video directly into your timeline.</string>

<key>NSMicrophoneUsageDescription</key>
<string>SwiftEditor needs microphone access to record audio for your project.</string>
```

---

## 2. FFmpeg in the Sandbox

### 2.1 Approach A: Bundle as Helper Tool (Recommended)

Bundle FFmpeg as a helper binary inside the app bundle. The helper inherits the parent's sandbox.

```
SwiftEditor.app/
  Contents/
    MacOS/
      SwiftEditor          (main binary)
    Helpers/
      ffmpeg               (bundled FFmpeg binary)
      ffprobe              (bundled FFprobe binary)
    Frameworks/
      libavcodec.dylib     (or statically linked into ffmpeg)
      libavformat.dylib
      ...
```

**Entitlement for helper tools:**
```xml
<!-- FFmpeg helper entitlements (ffmpeg.entitlements) -->
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.inherit</key>
    <true/>
</dict>
```

**Important:** When using `com.apple.security.inherit`, the child process inherits the parent's sandbox. You cannot specify additional sandbox entitlements on the child -- the system will abort it.

### 2.2 Running Bundled FFmpeg

```swift
import Foundation

class FFmpegRunner {
    private let ffmpegURL: URL

    init() {
        // Locate bundled FFmpeg
        guard let url = Bundle.main.url(
            forAuxiliaryExecutable: "ffmpeg"
        ) else {
            fatalError("FFmpeg not found in app bundle")
        }
        self.ffmpegURL = url
    }

    /// Run FFmpeg with arguments, returning output
    func run(arguments: [String]) async throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Inherit sandbox from parent app
        // FFmpeg can access files the parent has access to

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: (stdout, stderr))
                } else {
                    continuation.resume(throwing: FFmpegError.exitCode(
                        Int(proc.terminationStatus), stderr
                    ))
                }
            }
        }
    }

    /// Transcode a video file
    func transcode(input: URL, output: URL, codec: String = "libx264",
                   preset: String = "medium") async throws {
        try await run(arguments: [
            "-i", input.path,
            "-c:v", codec,
            "-preset", preset,
            "-c:a", "aac",
            "-y",
            output.path
        ])
    }

    /// Get media info via ffprobe
    func probe(file: URL) async throws -> String {
        let probeURL = Bundle.main.url(forAuxiliaryExecutable: "ffprobe")!
        let process = Process()
        process.executableURL = probeURL
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format", "-show_streams",
            file.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }
}

enum FFmpegError: Error {
    case exitCode(Int, String)
}
```

### 2.3 Code Signing Bundled Binaries

All binaries must be signed with hardened runtime for notarization:

```bash
# Sign FFmpeg binary with hardened runtime
codesign --force --options runtime \
    --entitlements ffmpeg.entitlements \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    SwiftEditor.app/Contents/Helpers/ffmpeg

# Sign any bundled dylibs
codesign --force --options runtime \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    SwiftEditor.app/Contents/Frameworks/libavcodec.dylib

# Verify
codesign --verify --deep --strict SwiftEditor.app
```

### 2.4 Approach B: Link FFmpeg as a Library (No Subprocess)

For maximum sandbox compatibility, link FFmpeg libraries directly into your Swift app via a C/ObjC bridge. This avoids subprocess issues entirely but requires more integration work. See `learnings/12-ffmpeg-researcher.md` for details.

### 2.5 Approach C: XPC Service (Most Isolated)

For direct-distribution apps, use an XPC service for FFmpeg operations:

```swift
// XPC service protocol
@objc protocol FFmpegXPCProtocol {
    func transcode(inputPath: String, outputPath: String,
                   options: [String: String],
                   withReply reply: @escaping (Bool, String?) -> Void)
    func probeMedia(path: String,
                    withReply reply: @escaping (String?) -> Void)
}
```

The XPC service runs in its own process with its own sandbox profile, providing the strongest isolation.

---

## 3. Distribution: App Store vs Direct

### 3.1 Comparison

| Factor | Mac App Store | Direct (Developer ID) |
|--------|--------------|----------------------|
| **Sandbox** | Required | Recommended, not required |
| **Revenue** | Apple takes 15-30% | 100% yours (minus payment processing) |
| **Updates** | Automatic via App Store | You handle (Sparkle, etc.) |
| **Discovery** | App Store search | Your own marketing |
| **Review** | App Review process (days) | Notarization only (minutes) |
| **Payments** | Apple handles | You handle (Stripe, Paddle, etc.) |
| **Trials** | Not supported | You implement |
| **Entitlements** | Strict subset allowed | More flexibility |
| **FFmpeg** | Must inherit sandbox, strict | More options (XPC, etc.) |
| **Pricing** | Per-app or subscription | Any model |

### 3.2 Recommended: Ship Both

Many professional NLEs distribute via both channels. Ship a sandboxed App Store version with core features and a direct version with advanced features that may need broader system access.

### 3.3 Developer ID Signing

```bash
# Export from Xcode with Developer ID signing
xcodebuild archive \
    -scheme SwiftEditor \
    -archivePath build/SwiftEditor.xcarchive

xcodebuild -exportArchive \
    -archivePath build/SwiftEditor.xcarchive \
    -exportOptionsPlist ExportOptions-DirectDist.plist \
    -exportPath build/Direct
```

**ExportOptions-DirectDist.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

---

## 4. Notarization Workflow

### 4.1 Prerequisites

- Apple Developer account ($99/year)
- Developer ID Application certificate
- Hardened runtime enabled on all binaries
- App-specific password for notarytool (generate at appleid.apple.com)

### 4.2 Store Credentials in Keychain

```bash
xcrun notarytool store-credentials "SwiftEditorNotary" \
    --apple-id "developer@example.com" \
    --team-id "ABCD123456" \
    --password "app-specific-password-here"
```

### 4.3 Create DMG and Notarize

```bash
#!/bin/bash
set -e

APP_NAME="SwiftEditor"
APP_PATH="build/Direct/${APP_NAME}.app"
DMG_PATH="build/${APP_NAME}.dmg"
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"

# Step 1: Deep sign the app (including all frameworks, helpers)
codesign --force --deep --options runtime \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_PATH}"

# Step 2: Verify signing
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose "${APP_PATH}"

# Step 3: Create DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Step 4: Sign the DMG
codesign --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

# Step 5: Submit for notarization
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "SwiftEditorNotary" \
    --wait

# Step 6: Staple the notarization ticket
xcrun stapler staple "${DMG_PATH}"

# Step 7: Verify stapling
xcrun stapler validate "${DMG_PATH}"

echo "Notarized and stapled: ${DMG_PATH}"
```

### 4.4 Troubleshooting Notarization

```bash
# Check notarization status and get detailed log
xcrun notarytool info <submission-id> \
    --keychain-profile "SwiftEditorNotary"

# Get detailed log (shows exactly what failed)
xcrun notarytool log <submission-id> \
    --keychain-profile "SwiftEditorNotary"

# Common issues:
# - Unsigned binary inside the bundle
# - Missing hardened runtime
# - Linked against private frameworks
# - Contains forbidden entitlements
```

### 4.5 Hardened Runtime Entitlements

Some FFmpeg operations may need runtime exceptions:

```xml
<!-- For direct distribution only (not App Store) -->
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <!-- Needed if FFmpeg uses JIT for codec optimization -->

    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <!-- Needed if loading third-party plugins/dylibs -->
</dict>
```

---

## 5. Sparkle Auto-Updates

### 5.1 Integration via SPM

```swift
// Package.swift or Xcode: Add Sparkle
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
]
```

### 5.2 SwiftUI Integration

```swift
import SwiftUI
import Sparkle

@main
struct SwiftEditorApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Create the updater controller on launch
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

// Menu item view
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}
```

### 5.3 Sparkle Configuration (Info.plist)

```xml
<!-- Appcast URL -->
<key>SUFeedURL</key>
<string>https://yoursite.com/swifteditor/appcast.xml</string>

<!-- Enable automatic update checks -->
<key>SUEnableAutomaticChecks</key>
<true/>

<!-- Check interval (default 24 hours) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<!-- Allow automatic downloads -->
<key>SUAllowsAutomaticUpdates</key>
<true/>

<!-- Public EdDSA key for update verification -->
<key>SUPublicEDKey</key>
<string>YOUR_EDDSA_PUBLIC_KEY</string>
```

### 5.4 Sandboxed App Setup

For sandboxed apps, Sparkle uses XPC services. Add these to Info.plist:

```xml
<!-- Enable Sparkle XPC services for sandboxed apps -->
<key>SparkleInstallerLauncherEnabled</key>
<true/>
<key>SparkleDownloaderEnabled</key>
<true/>
<!-- Only needed if your app does NOT have network client entitlement -->
```

### 5.5 Generating Appcast

```bash
# Generate EdDSA key pair (one time)
./bin/generate_keys

# Sign the update DMG
./bin/sign_update SwiftEditor-2.0.dmg

# Generate appcast.xml
./bin/generate_appcast /path/to/updates/folder/
```

### 5.6 Appcast XML Format

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>SwiftEditor Updates</title>
        <item>
            <title>Version 2.0</title>
            <description><![CDATA[
                <h3>What's New</h3>
                <ul>
                    <li>Metal 4 rendering pipeline</li>
                    <li>AI-powered scene detection</li>
                    <li>ProRes RAW support</li>
                </ul>
            ]]></description>
            <pubDate>Mon, 02 Mar 2026 12:00:00 +0000</pubDate>
            <sparkle:version>200</sparkle:version>
            <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://yoursite.com/updates/SwiftEditor-2.0.dmg"
                length="85000000"
                type="application/octet-stream"
                sparkle:edSignature="EDDSA_SIGNATURE_HERE" />
        </item>
    </channel>
</rss>
```

---

## 6. Performance Testing & Benchmarking

### 6.1 XCTest Performance Metrics

```swift
import XCTest

class VideoProcessingPerformanceTests: XCTestCase {

    // MARK: - Frame Processing Throughput

    func testColorCorrectionPerformance() throws {
        let processor = ColorCorrectionProcessor()
        let testFrame = try loadTestFrame(named: "4K_ProRes")

        // Measure with multiple metrics
        let metrics: [XCTMetric] = [
            XCTClockMetric(),      // wall clock time
            XCTCPUMetric(),        // CPU time, cycles, instructions
            XCTMemoryMetric(),     // peak memory usage
        ]

        measure(metrics: metrics) {
            for _ in 0..<30 {  // 1 second of 30fps
                _ = processor.applyCorrection(to: testFrame, parameters: defaultLift)
            }
        }
    }

    // MARK: - Timeline Rendering Performance

    func testTimelineRenderWith20Layers() throws {
        let renderer = TimelineRenderer()
        let timeline = try buildTestTimeline(layerCount: 20)

        measure(metrics: [XCTClockMetric()]) {
            for frame in 0..<30 {
                _ = renderer.renderFrame(at: CMTime(value: CMTimeValue(frame),
                                                     timescale: 30),
                                          timeline: timeline)
            }
        }
    }

    // MARK: - Export Performance

    func testProResExportPerformance() throws {
        let exporter = VideoExporter()
        let project = try loadTestProject("5min_multicam")

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = self.expectation(description: "export")
            exporter.export(project: project, format: .proRes422) { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 300)
        }
    }

    // MARK: - Signpost-Based Metrics

    func testFrameRenderSignpostMetric() throws {
        let signpostMetric = XCTOSSignpostMetric(
            subsystem: "com.swifteditor.render",
            category: "FrameRender",
            name: "RenderFrame"
        )

        measure(metrics: [signpostMetric]) {
            renderTestSequence()
        }
    }

    // MARK: - Set Baselines

    func testAppLaunchPerformance() throws {
        if #available(macOS 12.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
```

### 6.2 Swift Benchmark Package (Ordo-One)

For CI-integrated performance regression detection:

```swift
// Benchmarks/VideoProcessingBenchmarks/VideoProcessingBenchmarks.swift
import Benchmark
import SwiftEditorCore

let benchmarks = {
    Benchmark("ColorCorrection-4K-Frame",
              configuration: .init(
                  metrics: [.cpuTotal, .wallClock, .peakMemoryResident,
                            .mallocCountTotal],
                  maxDuration: .seconds(10),
                  maxIterations: 1000
              )) { benchmark in
        let frame = TestFrameGenerator.generate4KFrame()
        let processor = ColorCorrectionProcessor()

        for _ in benchmark.scaledIterations {
            blackHole(processor.applyCorrection(to: frame, parameters: .default))
        }
    }

    Benchmark("YUV-to-RGB-Conversion",
              configuration: .init(
                  metrics: [.cpuTotal, .wallClock, .peakMemoryResident]
              )) { benchmark in
        let yuvFrame = TestFrameGenerator.generateYUVFrame(width: 3840, height: 2160)

        for _ in benchmark.scaledIterations {
            blackHole(ColorSpaceConverter.yuvToRGB(yuvFrame))
        }
    }

    Benchmark("Timeline-Render-10-Layers") { benchmark in
        let timeline = TestTimelineGenerator.generate(layerCount: 10, duration: 1.0)
        let renderer = TimelineRenderer()

        for _ in benchmark.scaledIterations {
            blackHole(renderer.renderFrame(at: .zero, timeline: timeline))
        }
    }
}
```

### 6.3 os_signpost for Runtime Performance Logging

```swift
import os.signpost

extension OSLog {
    static let render = OSLog(subsystem: "com.swifteditor", category: "Render")
    static let decode = OSLog(subsystem: "com.swifteditor", category: "Decode")
    static let effects = OSLog(subsystem: "com.swifteditor", category: "Effects")
    static let export = OSLog(subsystem: "com.swifteditor", category: "Export")
}

class InstrumentedRenderer {
    private let signpostLog = OSLog.render

    func renderFrame(at time: CMTime, timeline: Timeline) -> CVPixelBuffer? {
        let signpostID = OSSignpostID(log: signpostLog)

        // Interval signpost: measure full frame render
        os_signpost(.begin, log: signpostLog, name: "RenderFrame",
                    signpostID: signpostID,
                    "time=%{public}.3f layers=%d",
                    time.seconds, timeline.layers.count)

        // Decode phase
        os_signpost(.begin, log: OSLog.decode, name: "DecodeFrames", signpostID: signpostID)
        let decodedFrames = decodeFrames(for: timeline, at: time)
        os_signpost(.end, log: OSLog.decode, name: "DecodeFrames", signpostID: signpostID,
                    "frames=%d", decodedFrames.count)

        // Effects phase
        os_signpost(.begin, log: OSLog.effects, name: "ApplyEffects", signpostID: signpostID)
        let processedFrames = applyEffects(to: decodedFrames, timeline: timeline)
        os_signpost(.end, log: OSLog.effects, name: "ApplyEffects", signpostID: signpostID)

        // Composite phase
        os_signpost(.begin, log: signpostLog, name: "Composite", signpostID: signpostID)
        let result = composite(frames: processedFrames)
        os_signpost(.end, log: signpostLog, name: "Composite", signpostID: signpostID)

        os_signpost(.end, log: signpostLog, name: "RenderFrame", signpostID: signpostID,
                    "success=%d", result != nil ? 1 : 0)

        return result
    }

    /// Point of interest: marks dropped frames for easy identification in Instruments
    func reportDroppedFrame(at time: CMTime) {
        os_signpost(.event, log: OSLog(subsystem: "com.swifteditor",
                                        category: .pointsOfInterest),
                    name: "DroppedFrame",
                    "time=%{public}.3f", time.seconds)
    }
}
```

### 6.4 Instruments Templates for NLE

| Template | Purpose |
|----------|---------|
| **Metal System Trace** | GPU encoder timing, shader costs, dropped frames |
| **Game Performance** | Frame rate, GPU counters, hitches |
| **Time Profiler** | CPU hotspots in rendering pipeline |
| **Allocations** | Memory growth during playback, leak detection |
| **Leaks** | Retain cycle detection |
| **File Activity** | I/O bottlenecks during media read/write |
| **Network** | Cloud sync and asset download performance |
| **os_signpost** | Custom signpost visualization for decode/render/composite phases |
| **Animation Hitches** | UI responsiveness during timeline scrubbing |

### 6.5 Custom Instruments Package

Create a custom Instruments package to visualize your NLE's render pipeline:

```xml
<!-- SwiftEditorInstruments.instrpkg -->
<?xml version="1.0" encoding="UTF-8" ?>
<package>
    <id>com.swifteditor.instruments</id>
    <title>SwiftEditor</title>

    <import-schema>os-signpost</import-schema>

    <!-- Frame Render Timeline -->
    <instrument>
        <id>com.swifteditor.frame-render</id>
        <title>Frame Render</title>
        <category>Video Processing</category>
        <purpose>Visualize video frame rendering phases</purpose>
        <icon>Generic</icon>

        <create-table>
            <id>render-intervals</id>
            <schema-ref>os-signpost</schema-ref>
            <attribute>
                <name>subsystem</name>
                <string>com.swifteditor</string>
            </attribute>
        </create-table>

        <graph>
            <title>Frame Render Timeline</title>
            <lane>
                <title>Render</title>
                <table-ref>render-intervals</table-ref>
            </lane>
        </graph>
    </instrument>
</package>
```

---

## 7. Memory Management for Large Projects

### 7.1 Memory Pressure Monitoring

```swift
import Dispatch

class MemoryPressureMonitor {
    private var source: DispatchSourceMemoryPressure?

    func startMonitoring(onPressure: @escaping (MemoryPressureLevel) -> Void) {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            guard let source = self?.source else { return }
            let event = source.data

            if event.contains(.critical) {
                onPressure(.critical)
            } else if event.contains(.warning) {
                onPressure(.warning)
            }
        }

        source?.resume()
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
}

enum MemoryPressureLevel {
    case warning, critical
}
```

### 7.2 Adaptive Cache Manager

```swift
class AdaptiveCacheManager {
    private let memoryMonitor = MemoryPressureMonitor()

    /// Frame cache with configurable capacity
    private var frameCache = NSCache<NSNumber, CVPixelBufferWrapper>()
    private var thumbnailCache = NSCache<NSString, NSImage>()
    private var waveformCache = NSCache<NSString, WaveformData>()

    private var currentCacheLevel: CacheLevel = .full

    enum CacheLevel: Int {
        case full = 3       // all caches active, generous limits
        case reduced = 2    // reduced frame cache
        case minimal = 1    // thumbnails only
        case emergency = 0  // flush everything
    }

    init() {
        configureForLevel(.full)

        memoryMonitor.startMonitoring { [weak self] level in
            switch level {
            case .warning:
                self?.reduceCacheLevel()
            case .critical:
                self?.emergencyFlush()
            }
        }
    }

    private func configureForLevel(_ level: CacheLevel) {
        currentCacheLevel = level

        switch level {
        case .full:
            frameCache.countLimit = 60        // ~2 seconds at 30fps
            frameCache.totalCostLimit = 1024 * 1024 * 1024  // 1 GB
            thumbnailCache.countLimit = 500
            waveformCache.countLimit = 100

        case .reduced:
            frameCache.countLimit = 15        // ~0.5 seconds
            frameCache.totalCostLimit = 256 * 1024 * 1024   // 256 MB
            thumbnailCache.countLimit = 200
            waveformCache.countLimit = 50

        case .minimal:
            frameCache.removeAllObjects()
            frameCache.countLimit = 5
            frameCache.totalCostLimit = 64 * 1024 * 1024    // 64 MB
            thumbnailCache.countLimit = 100
            waveformCache.countLimit = 20

        case .emergency:
            frameCache.removeAllObjects()
            thumbnailCache.removeAllObjects()
            waveformCache.removeAllObjects()
        }
    }

    private func reduceCacheLevel() {
        let newLevel = CacheLevel(rawValue: max(currentCacheLevel.rawValue - 1, 0))!
        configureForLevel(newLevel)
    }

    private func emergencyFlush() {
        configureForLevel(.emergency)
        // Also tell Metal to release unused resources
        autoreleasepool {
            // Force ARC cleanup
        }
    }

    /// Restore caches when pressure subsides
    func memoryPressureNormalized() {
        configureForLevel(.full)
    }
}

/// Wrapper to store CVPixelBuffer in NSCache
class CVPixelBufferWrapper: NSObject {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}
```

### 7.3 Lazy Resource Loading

```swift
class LazyMediaLoader {
    /// Only load what's needed for the current viewport + small lookahead
    func loadVisibleRange(timeline: Timeline, viewportRange: CMTimeRange,
                          lookahead: CMTime = CMTime(seconds: 5, preferredTimescale: 600)) {
        let extendedRange = CMTimeRange(
            start: viewportRange.start,
            duration: viewportRange.duration + lookahead
        )

        for layer in timeline.layers {
            for clip in layer.clips {
                if extendedRange.intersection(clip.timeRange).duration > .zero {
                    clip.ensureLoaded()     // load thumbnail, waveform
                } else {
                    clip.unloadResources()  // free memory for off-screen clips
                }
            }
        }
    }
}
```

### 7.4 Memory Reporting

```swift
import os

func reportMemoryUsage() {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    if result == KERN_SUCCESS {
        let usedMB = Double(info.resident_size) / 1_048_576.0
        os_log(.info, log: .default,
               "Memory: %.1f MB resident", usedMB)
    }
}
```

---

## 8. Crash Reporting & Diagnostics

### 8.1 MetricKit Integration

```swift
import MetricKit

class DiagnosticsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsManager()

    func startCollecting() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - Receive periodic metric reports (daily)
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // CPU metrics
            if let cpuMetrics = payload.cpuMetrics {
                logMetric("CPU cumulative time",
                          value: cpuMetrics.cumulativeCPUTime)
            }

            // GPU metrics
            if let gpuMetrics = payload.gpuMetrics {
                logMetric("GPU cumulative time",
                          value: gpuMetrics.cumulativeGPUTime)
            }

            // Memory metrics
            if let memoryMetrics = payload.memoryMetrics {
                logMetric("Peak memory",
                          value: memoryMetrics.peakMemoryUsage)
            }

            // Disk I/O
            if let diskMetrics = payload.diskIOMetrics {
                logMetric("Cumulative writes",
                          value: diskMetrics.cumulativeLogicalWrites)
            }

            // Application hang rate
            if let hangMetrics = payload.applicationResponsivenessMetrics {
                logMetric("Hang time",
                          value: hangMetrics.applicationHangTime)
            }

            // Send to your analytics backend
            sendToAnalytics(payload.jsonRepresentation())
        }
    }

    // MARK: - Receive crash/diagnostic reports (immediate)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Crash diagnostics
            if let crashes = payload.crashDiagnostics {
                for crash in crashes {
                    handleCrash(crash)
                }
            }

            // CPU exceptions (excessive CPU usage)
            if let cpuExceptions = payload.cpuExceptionDiagnostics {
                for exception in cpuExceptions {
                    os_log(.error, "CPU exception: %{public}@",
                           exception.callStackTree.debugDescription)
                }
            }

            // Disk write exceptions
            if let diskExceptions = payload.diskWriteExceptionDiagnostics {
                for exception in diskExceptions {
                    os_log(.error, "Disk write exception: %{public}@",
                           exception.callStackTree.debugDescription)
                }
            }

            // Hang diagnostics
            if let hangs = payload.hangDiagnostics {
                for hang in hangs {
                    os_log(.error, "App hang: duration=%{public}@",
                           hang.hangDuration.description)
                }
            }
        }
    }

    private func handleCrash(_ crash: MXCrashDiagnostic) {
        let exceptionType = crash.exceptionType?.intValue ?? -1
        let signal = crash.signal?.intValue ?? -1

        os_log(.fault, "CRASH: type=%d signal=%d reason=%{public}@",
               exceptionType, signal,
               crash.terminationReason ?? "unknown")

        // Send to crash reporting service
        CrashReporter.shared.report(
            exceptionType: exceptionType,
            signal: signal,
            callStack: crash.callStackTree,
            metadata: crash.metaData
        )
    }

    private func logMetric(_ name: String, value: Measurement<Unit>) {
        os_log(.info, "Metric %{public}@: %{public}@",
               name, value.description)
    }

    private func sendToAnalytics(_ json: Data) {
        // Send JSON payload to your analytics backend
    }
}
```

### 8.2 os_signpost for Performance Diagnostics

```swift
import os

// Use mxSignpost for MetricKit-compatible signposting
func renderFrameWithDiagnostics(at time: CMTime) {
    let log = MXMetricManager.makeLogHandle(category: "Render")

    mxSignpost(.begin, log: log, name: "FrameRender")

    // ... render frame ...

    mxSignpost(.end, log: log, name: "FrameRender")
    // MetricKit captures CPU time, memory, and disk writes during this interval
}
```

### 8.3 Third-Party Crash Reporting (Complementary)

MetricKit is limited to 24-hour delivery (except crashes on macOS 12+). For immediate crash reporting, consider integrating a third-party service alongside MetricKit:

```swift
// Sentry example (works alongside MetricKit)
import Sentry

func setupCrashReporting() {
    SentrySDK.start { options in
        options.dsn = "https://examplePublicKey@o0.ingest.sentry.io/0"
        options.tracesSampleRate = 0.1  // 10% of transactions for performance
        options.enableMetricKit = true  // Sentry can ingest MetricKit payloads
        options.attachScreenshot = true
        options.environment = isDebug ? "development" : "production"
    }
}
```

### 8.4 Custom Breadcrumbs for NLE Context

```swift
class NLEBreadcrumbs {
    static let shared = NLEBreadcrumbs()
    private let log = OSLog(subsystem: "com.swifteditor", category: "Breadcrumbs")

    func logUserAction(_ action: String, metadata: [String: String] = [:]) {
        os_log(.info, log: log, "Action: %{public}@ meta=%{public}@",
               action, metadata.description)

        // Also store for crash report context
        recentActions.append(BreadcrumbEntry(
            timestamp: Date(),
            action: action,
            metadata: metadata
        ))

        // Keep last 50 actions
        if recentActions.count > 50 {
            recentActions.removeFirst()
        }
    }

    private var recentActions: [BreadcrumbEntry] = []

    struct BreadcrumbEntry {
        let timestamp: Date
        let action: String
        let metadata: [String: String]
    }

    /// Attach to crash report
    func breadcrumbSummary() -> String {
        return recentActions.map {
            "[\($0.timestamp)] \($0.action)"
        }.joined(separator: "\n")
    }
}

// Usage throughout the app:
// NLEBreadcrumbs.shared.logUserAction("AddClipToTimeline",
//     metadata: ["codec": "ProRes422", "duration": "00:05:23"])
// NLEBreadcrumbs.shared.logUserAction("ApplyEffect",
//     metadata: ["effect": "ColorWheels", "layer": "2"])
```

---

## 9. Accessibility Testing for Timeline UI

### 9.1 NSAccessibility for Custom Timeline View

```swift
import AppKit

class TimelineTrackView: NSView {
    var clips: [ClipView] = []

    // MARK: - Accessibility Role

    override func isAccessibilityElement() -> Bool { return true }

    override func accessibilityRole() -> NSAccessibility.Role {
        return .group  // or .list for a list-like track
    }

    override func accessibilityRoleDescription() -> String? {
        return "Timeline track"
    }

    override func accessibilityLabel() -> String? {
        return "Video track \(trackIndex + 1) with \(clips.count) clips"
    }

    override func accessibilityChildren() -> [Any]? {
        return clips
    }
}

class ClipView: NSView {
    var clipName: String = ""
    var startTime: CMTime = .zero
    var duration: CMTime = .zero
    var isSelected: Bool = false

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { return true }

    override func accessibilityRole() -> NSAccessibility.Role {
        return .button  // clips are interactive
    }

    override func accessibilityLabel() -> String? {
        let timeStr = formatTime(startTime)
        let durStr = formatDuration(duration)
        return "\(clipName), starts at \(timeStr), duration \(durStr)"
    }

    override func accessibilityValue() -> Any? {
        return isSelected ? "Selected" : "Not selected"
    }

    override func accessibilityHelp() -> String? {
        return "Double-click to select, drag to move on timeline"
    }

    override func isAccessibilitySelected() -> Bool {
        return isSelected
    }

    // MARK: - Accessibility Actions

    override func accessibilityPerformPress() -> Bool {
        selectClip()
        return true
    }

    override func accessibilityPerformDelete() -> Bool {
        deleteClip()
        return true
    }

    private func formatTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let f = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, f)
    }

    private func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        }
        return String(format: "%d minutes %.0f seconds",
                      Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}
```

### 9.2 SwiftUI Accessibility

```swift
import SwiftUI

struct TimelineClipView: View {
    let clip: TimelineClip
    @State private var isSelected = false

    var body: some View {
        Rectangle()
            .fill(clip.color)
            .overlay(Text(clip.name).font(.caption))
            // Accessibility
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(clip.name)")
            .accessibilityValue(accessibilityDescription)
            .accessibilityHint("Double-tap to select, drag to reposition")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
            .accessibilityAction(.default) { isSelected.toggle() }
            .accessibilityAction(named: "Delete clip") { deleteClip() }
            .accessibilityAction(named: "Trim start") { trimClipStart() }
            .accessibilityAction(named: "Trim end") { trimClipEnd() }
    }

    private var accessibilityDescription: String {
        let start = formatTimecode(clip.startTime)
        let dur = formatDuration(clip.duration)
        return "Starts at \(start), duration \(dur), on track \(clip.trackIndex + 1)"
    }
}

// Timeline scrubber
struct PlayheadView: View {
    @Binding var currentTime: CMTime
    let duration: CMTime

    var body: some View {
        Slider(value: timeBinding, in: 0...1)
            .accessibilityLabel("Playhead position")
            .accessibilityValue(formatTimecode(currentTime))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    // Move forward 1 frame
                    currentTime = CMTimeAdd(currentTime,
                                            CMTime(value: 1, timescale: 30))
                case .decrement:
                    // Move back 1 frame
                    currentTime = CMTimeSubtract(currentTime,
                                                  CMTime(value: 1, timescale: 30))
                @unknown default: break
                }
            }
    }
}
```

### 9.3 Keyboard Navigation

```swift
class TimelineViewController: NSViewController {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            if event.modifierFlags.contains(.shift) {
                extendSelectionLeft()
            } else {
                movePlayheadLeft()
            }
        case 124: // Right arrow
            if event.modifierFlags.contains(.shift) {
                extendSelectionRight()
            } else {
                movePlayheadRight()
            }
        case 125: // Down arrow - next track
            selectNextTrack()
        case 126: // Up arrow - previous track
            selectPreviousTrack()
        case 49: // Space - play/pause
            togglePlayback()
        case 51: // Delete
            deleteSelectedClips()
        default:
            super.keyDown(with: event)
        }
    }
}
```

### 9.4 Testing with Accessibility Inspector

```swift
// XCTest UI tests for accessibility
class AccessibilityTests: XCTestCase {

    func testTimelineClipIsAccessible() {
        let app = XCUIApplication()
        app.launch()

        // Find clip by accessibility label
        let clip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Interview_01'")
        ).firstMatch

        XCTAssertTrue(clip.exists, "Clip should be accessible")
        XCTAssertTrue(clip.label.contains("starts at"), "Should include timecode")
    }

    func testPlayheadIsAdjustable() {
        let app = XCUIApplication()
        app.launch()

        let playhead = app.sliders["Playhead position"]
        XCTAssertTrue(playhead.exists)

        playhead.adjust(toNormalizedSliderPosition: 0.5)
        // Verify the timecode updated
    }

    func testVoiceOverTraversal() {
        let app = XCUIApplication()
        app.launch()

        // Verify logical VoiceOver traversal order
        let elements = app.descendants(matching: .any)
            .matching(NSPredicate(format: "isAccessibilityElement == true"))

        // At minimum: toolbar, timeline tracks, clip elements, transport controls
        XCTAssertGreaterThan(elements.count, 10)
    }
}
```

---

## 10. Localization & RTL Support

### 10.1 String Catalog Setup (Modern Approach)

Xcode 15+ supports String Catalogs (`.xcstrings`) which replace `.strings` and `.stringsdict` files:

```swift
// Localizable strings are automatically extracted from SwiftUI
Text("Export Complete")            // auto-extracted
Text("Track \(trackNumber)")      // interpolation supported
Text("\(clipCount) clips")        // pluralization via String Catalog
```

### 10.2 RTL-Aware Layout

```swift
import SwiftUI

struct TimelineView: View {
    @Environment(\.layoutDirection) var layoutDirection

    var body: some View {
        // Timeline always runs left-to-right regardless of language
        // This is a media convention -- time flows left to right
        HStack {
            ForEach(clips) { clip in
                ClipView(clip: clip)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        // Force LTR for timeline -- this is standard in all NLEs
    }
}

struct InspectorPanel: View {
    var body: some View {
        // Inspector panel SHOULD mirror for RTL languages
        Form {
            Section("Clip Properties") {
                LabeledContent("Name", value: clipName)
                LabeledContent("Duration", value: durationString)
                LabeledContent("Codec", value: codecName)
            }
        }
        // No .environment override -- inherits system direction
    }
}
```

### 10.3 What to Localize vs Not in an NLE

| Element | Localize? | Notes |
|---------|-----------|-------|
| Menu items | Yes | Standard macOS localization |
| Inspector labels | Yes | "Duration", "Frame Rate", etc. |
| Timeline direction | **No** | Always LTR (media convention) |
| Timecodes | Partial | Format numbers, keep HH:MM:SS:FF structure |
| Keyboard shortcuts | Partial | Some change per-locale, some are universal (J/K/L) |
| Effect names | Yes | "Gaussian Blur", "Color Wheels" |
| Codec names | No | "ProRes 422", "H.264" are universal |
| Error messages | Yes | All user-facing errors |
| Tooltips | Yes | All UI tooltips |

### 10.4 Number and Date Formatting

```swift
// Always use formatters for user-facing numbers
let framerate = Measurement(value: 29.97, unit: UnitFrequency.framesPerSecond)
let formatted = framerate.formatted(.measurement(width: .abbreviated))
// "29.97 fps" in English, localized in other languages

// File sizes
let fileSize = Measurement(value: 2.5, unit: UnitInformationStorage.gigabytes)
let sizeFormatted = fileSize.formatted(.measurement(width: .abbreviated))

// Duration formatting
let formatter = DateComponentsFormatter()
formatter.allowedUnits = [.hour, .minute, .second]
formatter.unitsStyle = .positional
formatter.zeroFormattingBehavior = .pad
let durationString = formatter.string(from: totalDuration)
```

### 10.5 Pluralization with String Catalog

In your `.xcstrings` file, define plural variants:

```json
{
    "stringUnit": {
        "state": "translated",
        "value": {
            "one": "%lld clip selected",
            "other": "%lld clips selected"
        }
    }
}
```

```swift
// In code, just use interpolation
Text("\(selectedCount) clips selected")
// String Catalog handles singular/plural automatically
```

### 10.6 Testing RTL Layout

```swift
// Force RTL in scheme environment variables:
// Arguments Passed On Launch: -AppleLanguages (ar)
// Or programmatically in tests:

class RTLLayoutTests: XCTestCase {
    func testInspectorMirrorsForRTL() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)"]
        app.launch()

        // Verify inspector panel layout is mirrored
        let nameLabel = app.staticTexts["Name"]
        let nameValue = app.staticTexts["Interview_01"]

        // In RTL, value should be to the left of label
        XCTAssertLessThan(nameValue.frame.origin.x, nameLabel.frame.origin.x)
    }

    func testTimelineStaysLTR() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)"]
        app.launch()

        // Timeline should remain LTR even in Arabic
        let firstClip = app.buttons["Clip 1"]
        let secondClip = app.buttons["Clip 2"]

        // First clip should be to the left of second clip
        XCTAssertLessThan(firstClip.frame.origin.x, secondClip.frame.origin.x)
    }
}
```

---

## 11. Document-Based App with UTType

### 11.1 Define Custom UTType

```swift
import UniformTypeIdentifiers

extension UTType {
    /// SwiftEditor project file (.swproj)
    static let swiftEditorProject = UTType(
        exportedAs: "com.swifteditor.project",
        conformingTo: .package  // directory package
    )

    /// SwiftEditor library file (.swlib)
    static let swiftEditorLibrary = UTType(
        exportedAs: "com.swifteditor.library",
        conformingTo: .database
    )
}
```

### 11.2 Info.plist Type Declarations

```xml
<!-- Exported Type Identifiers (types your app owns) -->
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.swifteditor.project</string>
        <key>UTTypeDescription</key>
        <string>SwiftEditor Project</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>com.apple.package</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>swproj</string>
            </array>
        </dict>
        <key>UTTypeIconFiles</key>
        <array>
            <string>swproj-icon</string>
        </array>
    </dict>
</array>

<!-- Imported Type Identifiers (types your app can open) -->
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.apple.final-cut-pro.project</string>
        <key>UTTypeDescription</key>
        <string>Final Cut Pro XML</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.xml</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>fcpxml</string>
            </array>
        </dict>
    </dict>
</array>

<!-- Document Types -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>SwiftEditor Project</string>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.swifteditor.project</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Final Cut Pro XML</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.apple.final-cut-pro.project</string>
        </array>
    </dict>
</array>
```

### 11.3 NSDocument Subclass

```swift
import AppKit
import UniformTypeIdentifiers

class ProjectDocument: NSDocument {

    var project: NLEProject = NLEProject()

    // MARK: - Supported Types

    override class var readableContentTypes: [UTType] {
        [.swiftEditorProject, UTType("com.apple.final-cut-pro.project")!]
    }

    override class var writableContentTypes: [UTType] {
        [.swiftEditorProject]
    }

    // MARK: - Autosave

    override class var autosavesInPlace: Bool { true }

    override class var autosavesDrafts: Bool { true }

    // MARK: - Read

    override func read(from url: URL, ofType typeName: String) throws {
        if typeName == UTType.swiftEditorProject.identifier {
            // Read package directory
            let dataURL = url.appendingPathComponent("project.json")
            let data = try Data(contentsOf: dataURL)
            project = try JSONDecoder().decode(NLEProject.self, from: data)
        } else if typeName == "com.apple.final-cut-pro.project" {
            // Import FCPXML
            let data = try Data(contentsOf: url)
            project = try FCPXMLImporter.import(data: data)
        }
    }

    // MARK: - Write

    override func write(to url: URL, ofType typeName: String) throws {
        // Create package directory
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        // Write project data
        let data = try JSONEncoder().encode(project)
        let dataURL = url.appendingPathComponent("project.json")
        try data.write(to: dataURL)

        // Write render cache manifest
        let cacheManifest = project.renderCacheManifest()
        let cacheURL = url.appendingPathComponent("cache-manifest.json")
        try JSONEncoder().encode(cacheManifest).write(to: cacheURL)
    }

    // MARK: - Undo Support

    func addClip(_ clip: TimelineClip, to track: Track) {
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.removeClip(clip, from: track)
        }
        undoManager?.setActionName("Add Clip")

        track.clips.append(clip)
        updateChangeCount(.changeDone)
    }

    func removeClip(_ clip: TimelineClip, from track: Track) {
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addClip(clip, to: track)
        }
        undoManager?.setActionName("Remove Clip")

        track.clips.removeAll { $0.id == clip.id }
        updateChangeCount(.changeDone)
    }

    func moveClip(_ clip: TimelineClip, from oldTime: CMTime, to newTime: CMTime) {
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.moveClip(clip, from: newTime, to: oldTime)
        }
        undoManager?.setActionName("Move Clip")

        clip.startTime = newTime
        updateChangeCount(.changeDone)
    }

    // MARK: - Window Controller

    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        if let wc = storyboard.instantiateController(
            withIdentifier: "ProjectWindowController"
        ) as? NSWindowController {
            addWindowController(wc)
        }
    }
}
```

### 11.4 SwiftUI Document-Based App (Alternative)

```swift
import SwiftUI
import UniformTypeIdentifiers

@main
struct SwiftEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SwiftEditorDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}

struct SwiftEditorDocument: FileDocument {
    var project: NLEProject

    static var readableContentTypes: [UTType] { [.swiftEditorProject] }
    static var writableContentTypes: [UTType] { [.swiftEditorProject] }

    init() {
        project = NLEProject()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try JSONDecoder().decode(NLEProject.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
```

### 11.5 Package-Based Project Format

For a professional NLE, a package (directory bundle) format is better than a single file:

```
MyProject.swproj/           (directory, appears as single file in Finder)
  project.json              (timeline, tracks, clips, effects)
  media-manifest.json       (references to original media + bookmarks)
  thumbnails/               (generated preview thumbnails)
    clip_001.jpg
    clip_002.jpg
  render-cache/             (optional: cached rendered frames)
    segment_001.mov
  waveforms/                (audio waveform data)
    audio_001.waveform
  presets/                  (saved effect presets)
    grade_warm.json
```

```swift
struct NLEProject: Codable {
    var version: Int = 1
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var frameRate: Double = 30.0
    var resolution: CGSize = CGSize(width: 1920, height: 1080)
    var timeline: TimelineData
    var mediaReferences: [MediaReference]
}

struct MediaReference: Codable {
    let id: UUID
    let originalPath: String        // original file path
    let bookmarkData: Data?         // security-scoped bookmark
    let fileName: String
    let fileSize: Int64
    let duration: Double
    let codecName: String
    let width: Int
    let height: Int
}
```

---

## Build & Release Checklist

### Pre-Release

- [ ] All performance tests pass with acceptable baselines
- [ ] Accessibility audit with Accessibility Inspector (no warnings)
- [ ] VoiceOver testing on timeline, inspector, transport controls
- [ ] RTL layout testing (Arabic, Hebrew)
- [ ] Memory profiling with Instruments -- no leaks, stable under pressure
- [ ] GPU capture review -- no unnecessary passes, correct formats
- [ ] Localization complete for target languages
- [ ] Security-scoped bookmarks persist across relaunch

### Signing & Distribution

- [ ] All binaries signed with hardened runtime
- [ ] Bundled FFmpeg signed with inherit entitlement
- [ ] `codesign --verify --deep --strict` passes
- [ ] `spctl --assess --type execute` passes
- [ ] Notarization succeeds
- [ ] Stapler stapled
- [ ] DMG tested on clean macOS install

### App Store Specific

- [ ] Sandbox entitlements minimal and justified
- [ ] No temporary exception entitlements (App Review rejects these)
- [ ] Privacy manifest present
- [ ] App Store screenshots for all required sizes
- [ ] App Review notes explain camera/mic/file access

### Post-Release

- [ ] Sparkle appcast updated (direct distribution)
- [ ] MetricKit subscriber active
- [ ] Crash reporting verified with test crash
- [ ] Analytics baseline established
- [ ] os_signpost logging active for key code paths
