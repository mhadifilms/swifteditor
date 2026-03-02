# Community Insights: Building Video Editors in Swift

## Table of Contents
1. [AVFoundation Development Experience](#avfoundation-development-experience)
2. [Timeline UI Implementation Insights](#timeline-ui-implementation-insights)
3. [Metal & GPU Processing Community Wisdom](#metal--gpu-processing-community-wisdom)
4. [Open Source Video Editor Architecture](#open-source-video-editor-architecture)
5. [DaVinci Resolve Free Tier Analysis](#davinci-resolve-free-tier-analysis)
6. [State of the NLE 2025](#state-of-the-nle-2025)
7. [What Professional Editors Want](#what-professional-editors-want)
8. [Common Pitfalls & Performance Bottlenecks](#common-pitfalls--performance-bottlenecks)
9. [AI-Assisted Editing Trends](#ai-assisted-editing-trends)
10. [Recommended WWDC Sessions](#recommended-wwdc-sessions)
11. [Key Open Source Swift Frameworks](#key-open-source-swift-frameworks)
12. [Hacker News Developer Discussions](#hacker-news-developer-discussions)
13. [Proxy Workflow Architecture](#proxy-workflow-architecture)
14. [Undo/Redo Patterns in Swift](#undoredo-patterns-in-swift)
15. [Lessons Learned Summary](#lessons-learned-summary)

---

## AVFoundation Development Experience

### Core Architecture Understanding

The community consensus is clear: **for a basic Swift video editor, Core Image and AVFoundation are sufficient.** However, **Metal becomes essential when you need real-time, low-latency processing that maintains 30/60 FPS** while users edit, overlay heavy effects, or apply complex filters.

**Source**: [Banuba Swift Video Editor Guide (2025)](https://www.banuba.com/blog/how-to-integrate-a-swift-video-editor-in-your-ios-app)

### Key AVFoundation Components

- **AVMutableComposition**: An editable timeline where you can cut and stitch, trim clips to ranges, place them at exact timestamps, and merge multiple video and audio elements into a single clip
- **AVVideoComposition**: Time-based instructions that tell AVFoundation which pixels to render and how to combine tracks at each moment of playback -- used for cropping, rotating, layering tracks, and applying transitions/effects
- **AVAsynchronousCIImageFilteringRequest**: Suitable when the task pertains to a single video (cropping, resizing, applying filters, adding captions)

**Source**: [VideoWithSwift - Frame-by-frame Pipeline (March 2024)](https://videowithswift.com/frame-by-frame-video-editing-pipeline-with-swift/)

### Pain Points Reported by Developers

1. **Swift Concurrency Integration**: AVFoundation relies on GCD, which does not play nicely with Swift Concurrency. The most difficult refactoring challenge for Swift 6 is camera/video logic that uses AVFoundation heavily.

2. **Unpredictable Async Hangs**: Developers report "execution randomly stops and is completely unpredictable with no crash or error thrown, leaving the thread in a suspended state indefinitely" when using new Swift Concurrency APIs with AVFoundation.

3. **SwiftUI Camera Integration Complexity**: Using the camera in SwiftUI requires AVFoundation for the device camera, UIKit to deal with views, then UIViewRepresentable to bridge -- meaning you need UIKit knowledge even in a SwiftUI-first project.

4. **Custom Compositor Real-Time Updates**: A common forum issue -- when using a custom AVVideoCompositing compositor, filter property changes (like intensity via slider) are slow because the videoComposition prepares frames ahead of time. To get real-time updates, the composition must be reset every change, but then slider changes come faster than the CPU can handle.

5. **iOS Version Regressions**: After iOS 18.5, AVCaptureSessionInterruptionReason errors increased 5x. On iOS 26 (beta), video/audio sync issues appear after seeking during playback (2-3 second offset), not present on iOS 18.

**Sources**: [Apple Developer Forums - AVFoundation](https://developer.apple.com/forums/tags/avfoundation), [Swift 6 Camera Refactoring Blog](https://fatbobman.com/en/posts/swift6-refactoring-in-a-camera-app/)

### Custom Compositor Implementation

The community approach for professional-grade compositing:

- Implement **AVVideoCompositing** and **AVVideoCompositionInstruction** protocols
- Source frames are returned as **CVPixelBuffer** objects via `startRequest`
- Use **CVMetalTextureCache** to convert CVPixelBuffers to Metal textures
- Apple's **AVCustomEdit** sample project demonstrates this pattern
- **WWDC22 "Display HDR video in EDR with AVFoundation and Metal"** is the canonical reference

Key gotcha from forums: `anticipateRenderingUsingHint` is called every frame duration to pre-load compositor resources -- failure to implement this efficiently causes frame drops.

**Source**: [Apple AVVideoCompositing Documentation](https://developer.apple.com/documentation/avfoundation/avvideocompositing), [Metal by Example - HDR Video](https://metalbyexample.com/hdr-video/)

---

## Timeline UI Implementation Insights

### IMG.LY's SwiftUI Timeline (2025) -- Definitive Community Resource

IMG.LY built their CE.SDK video editor timeline entirely in SwiftUI and documented their process extensively. This is the most detailed public account of building a video editing timeline in Swift.

**Key Architecture Decisions:**

1. **SwiftUI for rapid prototyping** between design and development, but needed UIKit fallbacks
2. **Left-to-right always**: "Editor timelines in software are universally left-to-right" even in RTL languages
3. **Adaptive height**: Timeline adjusts height based on content rather than consuming fixed space, maximizing canvas visibility
4. **Precision labeling**: Duration labels show fractional seconds below 10s (e.g. "4.2s"), ruler uses short format below 1 minute

**Five Gesture Layers Requiring Coordination:**
1. Horizontal scrolling (time navigation)
2. Vertical scrolling (track accommodation)
3. Clip movement (horizontal dragging)
4. Duration adjustment (trim handle dragging)
5. Pinch-to-zoom (timeline magnification)

**Critical Quote:** "We found it unexpectedly difficult to fine-tune and harmonize these interactions with pure SwiftUI, so we used some proven legacy iOS techniques to get it right." -- They used **SwiftUIIntrospect** and **UIGestureRecognizers** for proper gesture prioritization.

**Trim Handle UX Insights:**
- Trim handles have hit areas "more than twice as wide as the visual appearance suggests"
- Finite-duration clips show "marching ants" ghost outlines during resize
- A temporary overlay with independent playback time shows exact trim position, solving the conflict between preview visibility and clip manipulation during trimming
- Snapping uses animated dotted lines + iPhone haptic feedback
- Snapping respects only visible viewport positions -- offscreen snap points ignored

**Source**: [IMG.LY - Designing a Timeline for Mobile Video Editing](https://img.ly/blog/designing-a-timeline-for-mobile-video-editing/)

### Apple Developer Forums -- SwiftUI ScrollView Performance

- SwiftUI ScrollView performance on macOS is significantly worse than iOS
- On macOS 15.2, 85% of execution time in flame graph is "_hitTestForEvent" method
- Apple acknowledged this as "Potential fix identified - For a future OS update"
- For thousands of elements, LazyVStack in ScrollView shows definite slowdown
- **Recommendation**: For a macOS NLE timeline, consider AppKit NSScrollView wrapped in NSViewRepresentable for the core scrolling, with SwiftUI for overlay controls

**Source**: [Apple Developer Forums - SwiftUI ScrollView Performance](https://developer.apple.com/forums/thread/764264)

---

## Metal & GPU Processing Community Wisdom

### When to Use Metal vs. Core Image

**Community Consensus:**
- Start with Core Image/CIFilters for prototyping -- it works and is simple
- Switch to Metal when preview drops frames below 30 FPS with effects applied
- "A more intuitive and better performing way is to implement a Metal rendering pipeline with custom written shaders" vs. Core Image
- Metal has "a very steep learning curve, especially for those without GPU experience"
- Apple should "rewrite all the Metal examples in Swift instead of Objective-C" -- documentation quality remains a concern

### Metal Shader Optimization Tips

From developer blogs and Apple resources:
- Choose optimal **threadgroup sizes** to maximize GPU occupancy
- Efficiently manage textures and buffers to prevent memory bottlenecks
- **Reuse pipeline states** and other Metal objects to reduce overhead
- Use **indirect command buffers** to reduce CPU overhead for repeated rendering
- MetalPetal framework demonstrates: programmable blending, memoryless render targets, resource heaps

**Source**: [Apple - Metal for Pro Apps (WWDC19)](https://developer.apple.com/videos/play/wwdc2019/608/), [MetalPetal GitHub](https://github.com/MetalPetal/MetalPetal)

### WWDC18 Metal Game Performance Optimization

Community-recommended session for understanding GPU profiling, even though it is game-focused. Concepts transfer directly to video processing: command buffer scheduling, render pass optimization, texture management.

**Source**: [Apple WWDC18 Session 612](https://developer.apple.com/videos/play/wwdc2018/612/)

---

## Open Source Video Editor Architecture

### VideoLab Framework (AVFoundation + Metal)

An Adobe After Effects-inspired architecture in Swift:

- **RenderLayer**: The most basic unit -- individual media elements (video, images, audio, effects)
- **RenderComposition**: Container setting resolution, frame rate, holding multiple layers
- **VideoLab**: Parser that generates AVFoundation objects (AVPlayerItem, AVAssetExportSession, AVAssetImageGenerator) from RenderComposition

Key insight: Think in terms of layers and composition, not tracks. This AE-like approach maps better to AVFoundation's compositing model.

**Source**: [VideoLab GitHub](https://github.com/ruanjx/VideoLab) -- MIT License, iOS 11.0+

### Vulcan -- SwiftUI + Composable Architecture

A macOS video editor built with SwiftUI and The Composable Architecture (TCA). Demonstrates:
- State management via TCA reducers
- Unidirectional data flow for complex editor state
- SwiftUI-first approach for macOS desktop editing

**Source**: [Vulcan GitHub](https://github.com/hadiidbouk/Vulcan)

### MLT-Based Editors (Kdenlive, Shotcut)

From Hacker News discussions: "Kdenlive and Shotcut both use the MLT video editing framework under the hood, so their capabilities and constraints are very close to each other's."

The main architectural division in open-source editors is **MLT-based vs. non-MLT**. MLT provides a unified multimedia processing framework but constrains your architecture. Building from scratch (like Olive editor) gives more flexibility but requires solving every problem yourself.

**Source**: [Hacker News Discussion](https://news.ycombinator.com/item?id=39675531)

### Olive Editor Community Insight

Olive was notable for running on "a 10-year-old notebook with just 2GBs of RAM" when other editors couldn't function. Community valued its resource efficiency. Development velocity was impressive -- "only 1 hour" to fix reported issues. However, the project struggled with sustainable development.

**Source**: [Hacker News - Olive NLE](https://news.ycombinator.com/item?id=18838227)

---

## DaVinci Resolve Free Tier Analysis

### Why DaVinci Resolve's Free Tier Wins

DaVinci Resolve's free version is arguably the most successful free creative software tier. Key factors:

1. **Comprehensive Feature Set**: Free version includes editing, visual effects (Fusion), audio post-production (Fairlight DAW), and professional color grading -- more features than most paid software
2. **Professional-Grade Color Grading**: Vast majority of color tools available free, and color is what Resolve is best known for
3. **No Watermarks**: Unlike many free alternatives
4. **Pay-Once Studio Version**: $295 one-time vs. subscription competitors. DaVinci Resolve 20 introduced optional license rentals
5. **Lifetime Free Updates**: Free version receives continuous feature additions
6. **UHD Support**: Edit and finish up to 60fps at Ultra HD 3840x2160 in free version
7. **Hardware Ecosystem**: Blackmagic offers cameras, storage, control surfaces, displays -- complete vertical integration
8. **Node-Based Effects**: "A far more advanced and complete feature set" with native Fusion compositing vs. layer-based approaches

**Free vs. Studio Differences:**
- Studio adds: Multi-GPU, 8K+ resolution, Neural Engine AI features, HDR tools, stereoscopic 3D, immersive audio, advanced noise reduction
- Free limitation: Maximum UHD output, single GPU
- DaVinci Resolve 20 introduced "more than 100 new features including powerful AI tools"

**Lesson for our project**: The free tier works because it doesn't cripple the core editing/grading experience. Users upgrade for performance (multi-GPU) and AI features, not basic functionality.

**Sources**: [Blackmagic Design](https://www.blackmagicdesign.com/products/davinciresolve), [Toolfarm Comparison](https://www.toolfarm.com/tutorial/in-depth-davinci-resolve-studio-vs-the-free-version/), [SimonSays Comparison](https://www.simonsaysai.com/blog/davinci-resolve-free-vs-resolve-studio)

---

## State of the NLE 2025

### Market Landscape

Seven professional NLEs: Avid Media Composer, Adobe Premiere Pro, Apple Final Cut Pro, Blackmagic DaVinci Resolve, Magix Vegas Pro, Grass Valley Edius, Lightworks.

**Market Positioning:**
- **Avid + Adobe**: Dominate professional facilities. "Media Composer and Premiere Pro are the main contenders" for top-tier users
- **DaVinci Resolve**: "The newest challenger" gaining traction as editing alternative. Leads in AI innovation
- **Final Cut Pro**: Repositioned from high-end post houses to "content creators" and social media work
- **Vegas Pro, Edius, Lightworks**: Niche pockets -- Vegas for enthusiasts, Edius for broadcast news, Lightworks declining

**Licensing Models:**
- Adobe: Subscription required (projects locked if cancelled)
- Avid: Subscription + optional perpetual license
- Apple FCP: Pay-once ($299), subscription for iPad
- Blackmagic: Free + pay-once Studio ($295), new optional rental starting Resolve 20

**Key Differentiators:**
- All four major editors handle basic editing similarly
- DaVinci Resolve integrates most advanced feature set (Fusion + Fairlight natively)
- Final Cut Pro relies on third-party plugins but has "far larger" plugin marketplace
- FCP lacks native remote collaboration (depends on third-party PostLab)

**Usage Recommendations from Industry:**
- TV/film in major markets: Avid
- Commercials/corporate: Premiere Pro
- Social media/casual: Final Cut Pro
- "Ultimate power" users: DaVinci Resolve Studio

**Source**: [digitalfilms - State of the NLE 2025](https://digitalfilms.wordpress.com/2025/07/19/the-state-of-the-nle-2025/)

---

## What Professional Editors Want

### Features Most Demanded (2024-2025)

1. **AI-Powered Automation**: Tools that "respect their creative process and remove bottlenecks that slow it down, rather than replacing creativity"
   - Filler word detection and removal
   - Auto reframe for different social platforms
   - Scene edit detection
   - Intelligent transcription and captioning
   - Dialogue enhancement / noise reduction

2. **Multi-Camera Editing**: "Revamped workflow that allows editors to sync, switch, and edit multiple camera angles with ease"

3. **Cloud Collaboration**: Teams working on same project simultaneously from different locations with real-time updates and version control

4. **Advanced Audio**: Support for Dolby Atmos immersive audio, improved mixing/mastering interfaces

5. **Performance on Apple Silicon**: Editors expect native ARM optimization. Apple gave Blackmagic significant support optimizing Resolve for Apple Silicon

6. **Proxy Workflow**: Seamless proxy creation and management, especially for remote work. Editing with proxies ensures smooth playback and stability for 4K+ footage

7. **Color Management**: Professional color grading tools, HDR support, ACES workflows

**Source**: [RedShark News - AI Tools for Video Editing 2025](https://www.redsharknews.com/ai-tools-for-video-editing-that-are-actually-useful-in-2025), [TechRadar - Best Video Editing Software 2026](https://www.techradar.com/best/best-video-editing-software)

---

## Common Pitfalls & Performance Bottlenecks

### Memory Management

- **RAM is the biggest constraint**: Video clips are copied into RAM uncompressed for pixel processing. When RAM runs out, system swaps to disk causing extreme lag, dropped frames, crashes
- **VRAM exhaustion**: When GPU VRAM is full, driver offloads to system RAM (much slower but prevents crashes)
- **Buffer management**: Using a line buffer instead of frame buffer for processing significantly improves throughput and reduces memory requirements
- **Compression trade-off**: More compression = more CPU work to decompress for viewing, creating bottlenecks

### GPU Acceleration Challenges

- "A powerful GPU alone is not enough -- insufficient RAM, a slow CPU, or inadequate storage can create bottlenecks that limit GPU acceleration benefits"
- "The real-world implementation of GPU acceleration is unfortunately spotty, as programs need to hand data back and forth with the GPU very quickly and without errors"
- Outdated drivers or incompatible APIs lead to crashes
- **Bottleneck cascade**: Fast GPU means nothing if CPU can't feed it data fast enough

### Storage Performance

- NVMe SSDs with 3000+ MB/s read/write for local editing
- Traditional HDD editing "will feel incredibly sluggish"
- For collaboration: NAS with 10GbE networking minimum

### SwiftUI-Specific Performance Issues

- ScrollView performance on macOS is significantly worse than iOS
- Hit testing consumes 85% of execution time in some scenarios
- LazyVStack with thousands of elements shows definite slowdown
- **SwiftUI drawingGroup()** can help with Metal-accelerated rendering but "should only be used when you have an actual performance problem"

### AVFoundation-Specific Pitfalls

- Custom compositor + real-time slider updates = lag (composition reset required per change)
- Frame skipping with custom compositors even at declared 60 FPS frameDuration
- videoComposition breaks export in some iOS versions
- Audio-video sync issues after seeking (observed in recent iOS versions)

**Sources**: [DIY Video Editor](https://diyvideoeditor.com/why-is-video-editing-so-computer-resource-intensive/), [Apple Developer Forums](https://developer.apple.com/forums/tags/avfoundation)

---

## AI-Assisted Editing Trends

### Current State (2025)

**Automatic Scene Detection**: AI identifies key moments and scene boundaries. Final Cut Pro automatically tags different scenes and recommends tone/style-relevant transitions for each scene.

**Object Tracking**: AI algorithms track moving objects for targeted effects, automatic keyframing of text/graphics on subjects. Final Cut Pro's Magic Mask selects people or objects automatically.

**Smart Audio**: Automatic transcription for subtitles, filler word detection, dialogue enhancement, noise reduction. Premiere Pro offers automatic caption translation into 27 languages.

**DaVinci Resolve AI Leadership**:
- AI Voice Convert: Applies voice models while retaining inflection
- AI Set Extender: Extends frame edges via text prompts
- Neural Engine for upscaling, noise reduction, face detection (Studio only)

**Emerging Trends**:
- Chat-based editing interfaces where creators describe intent in natural language
- Real-time AI during live recording (captioning, background replacement, visual effects)
- AI-driven automatic color grading and matching
- Prompt-based workflows: "analyze footage and generate smart cuts in seconds"

**Source**: [Adobe Blog - AI Video Editing Tools (Jan 2026)](https://blog.adobe.com/en/publish/2026/01/20/new-ai-powered-video-editing-tools-premiere-major-motion-design-upgrades-after-effects), [HeyGen AI Video Trends](https://www.heygen.com/blog/top-ai-video-trends)

---

## Recommended WWDC Sessions

### Essential for Video Editor Development

| Session | Year | Topic | Why Watch |
|---------|------|-------|-----------|
| **Editing Media with AV Foundation** | 2010 | Foundation concepts | Original composition/editing API introduction |
| **Advanced Editing with AV Foundation** (612) | 2013 | Custom compositing, debugging | Deep dive into custom video compositors |
| **Editing Movies in AV Foundation** (506) | 2015 | AVMovie, AVMutableMovie | Movie file editing classes |
| **Metal for Pro Apps** (608) | 2019 | Pro app Metal patterns | Video/photo app-specific Metal optimization |
| **Edit and play back HDR video with AVFoundation** | 2020 | HDR editing pipeline | AVVideoComposition with CIFilter handler for HDR |
| **Decode ProRes with AVFoundation and VideoToolbox** | 2020 | ProRes decode pipeline | Optimal graphics pipeline with Metal display |
| **What's new in AVFoundation** | 2021 | API updates | Latest AVFoundation capabilities |
| **Create a more responsive media app** | 2022 | Async patterns | Avoiding synchronous blocking in media apps |
| **Display HDR video in EDR with AVFoundation and Metal** | 2022 | EDR pipeline | Building AVFoundation + Metal EDR pipeline |
| **Demystify SwiftUI performance** | 2023 | SwiftUI optimization | Understanding hitches and animation issues |
| **Discover media performance metrics in AVFoundation** | 2024 | AVMetrics API | New unified metrics gathering for media playback |
| **SwiftUI essentials** | 2024 | SwiftUI fundamentals | Modern SwiftUI patterns for complex apps |
| **Optimize SwiftUI performance with Instruments** | 2025 | SwiftUI profiling | GPU and CPU profiling for SwiftUI views |

**Sources**: [Apple Developer Videos](https://developer.apple.com/videos/), [ASCIIwwdc.com](https://asciiwwdc.com/)

---

## Key Open Source Swift Frameworks

### Video Processing Frameworks Comparison

| Framework | Approach | Best For | Status |
|-----------|----------|----------|--------|
| **VideoLab** | AVFoundation + Metal, AE-like layers | Full editing pipeline | MIT, iOS 11+ |
| **MetalPetal** | Metal-based, render graph optimization | Real-time image/video filters | Active, SPM support |
| **GPUImage3** | Metal-based, pipeline chains | Simple filter chains | Stable, less active |
| **PixelSDK** | Full editing UI framework | Drop-in editor component | Commercial |
| **Vulcan** | SwiftUI + TCA, macOS editor | Architecture reference | Demo/learning |

### MetalPetal Architecture (Community Recommended)

MetalPetal is highlighted by the community for its thoughtful architecture:

- **MTIImage**: Immutable representation with recipe (MTIImagePromise) + caching info. Thread-safe sharing
- **MTIContext**: Evaluation context storing caches and state. Reuse for efficiency
- **MTIKernel**: Image processing routine creating pipeline states for filters
- **Render graph optimization**: Analyzes graph to determine minimal intermediate textures, eliminates redundant render passes
- **Metal feature utilization**: Programmable blending, memoryless render targets, resource heaps, MPS

**Source**: [MetalPetal GitHub](https://github.com/MetalPetal/MetalPetal), [GPUImage3 GitHub](https://github.com/BradLarson/GPUImage3)

---

## Hacker News Developer Discussions

### Browser-Based Video SDK Insights (Rendley)

Key technical challenges documented from building a video editing SDK:

- **FFmpeg memory safety**: "A lot of the FFmpeg code is not memory safe" and "out-of-bounds read or write will bring down the entire wasm subsystem"
- **Codec complexity**: ".avi file just shows a spinner... hevc .mp4 loads, but the exported video is all black" -- format support testing is crucial
- **Fallback strategy**: Implemented "a rendering mechanism based on FFmpeg" for environments without WebCodecs -- slower but functional

**Source**: [Hacker News - Rendley SDK](https://news.ycombinator.com/item?id=41108843)

### Twick Video Editor Discussion

- Browser-based editors face 16GB per-tab memory limits
- Tested only "with videos up to 5 minutes in length"
- Strategy: Offload "compute-heavy tasks like rendering and AI-driven edits to cloud functions"
- "Pushing browser-based tech to handle native-level video editing is definitely ambitious"

**Source**: [Hacker News - Twick](https://news.ycombinator.com/item?id=44108410)

### Replit Video Rendering Engine

Insight into time-based rendering: "Browsers are real-time systems that render frames when they can, skip frames under load, and tie animations to wall-clock time. If a screenshot takes 200ms but an animation expects 16ms frames, you get a stuttery, unwatchable result."

Solution: Time virtualization and BeginFrame capture -- useful concepts for any programmatic video system.

**Source**: [Replit Blog](https://blog.replit.com/browsers-dont-want-to-be-cameras)

---

## Proxy Workflow Architecture

### Community Best Practices

Proxy workflows are considered essential for any serious video editor:

- **Proxies**: Lower-resolution copies of high-res raw files serving as "placeholder" video files
- **Benefits**: Smooth playback, quicker editing response, overall stability for 4K+ footage
- **MAM systems**: Automatically generate proxy copies during ingest, store centrally for remote access
- **Storage**: NVMe SSDs (3000+ MB/s) for local, NAS with 10GbE for collaborative
- **FCP limitation**: No option to move/copy only proxy media separately from original camera media

### Architecture Recommendations

1. Automatic proxy generation on import (background task)
2. Seamless toggle between proxy and full-res in timeline
3. Final render always uses full-res source
4. Proxy format: H.264 at 1/4 or 1/2 resolution is standard
5. Proxy files linked by metadata to original assets

**Source**: [Frame.io Workflow Guide](https://workflow.frame.io/guide/fcpx-proxies), [Evolphin Proxy Editing](https://blog.evolphin.com/proxy-video-editing/)

---

## Undo/Redo Patterns in Swift

### Community-Recommended Approaches

For a video editor, the community recommends combining these patterns:

1. **UndoManager (Apple Native)**: Foundation framework class for general-purpose undo/redo recording. Integrates with SwiftUI via `@Environment(\.undoManager)`.

2. **Command Pattern**: Encapsulate each editing action as an object with execute/undo methods. "Allows execution of actions to be treated the same way as other objects, making it possible to store actions in a history list and revert by executing in reverse order."

3. **State-Based (Memento Pattern)**: Record state before/after each action, undo switches between states. Two approaches: counteraction-based vs. state snapshot-based.

**Best practice for NLE**: Use Command Pattern for editing operations (cut, trim, move) with state snapshots at key intervals as recovery points. UndoManager integrates well with SwiftUI but the Command pattern gives more control for complex multi-step operations.

**Sources**: [Medium - Undo/Redo with Command Pattern in Swift](https://heydavethedev.medium.com/implementing-undo-and-redo-with-the-command-design-pattern-in-swift-e9b1d22307e3), [Apple UndoManager Documentation](https://developer.apple.com/documentation/foundation/undomanager)

---

## Lessons Learned Summary

### Architecture Lessons

1. **Start with AVFoundation, graduate to Metal**: Don't over-engineer early. Core Image + AVFoundation handles basic editing. Add Metal when profiling shows frame drops.

2. **Layer-based > Track-based for AVFoundation**: VideoLab's AE-inspired layer model maps better to AVFoundation's compositing primitives than traditional NLE track-based thinking.

3. **SwiftUI + UIKit/AppKit hybrid is necessary**: Pure SwiftUI cannot handle complex gesture coordination in a timeline. Use SwiftUIIntrospect and native gesture recognizers for precision interactions.

4. **Command Pattern for undo/redo**: Essential for any serious editor. State snapshots at intervals as recovery points.

5. **TCA or similar unidirectional architecture**: Vulcan demonstrates that The Composable Architecture works for video editor state management, providing testability and predictable state transitions.

### Performance Lessons

6. **RAM is king**: Video clips uncompressed in RAM. Memory management is the primary constraint, not GPU speed.

7. **Custom compositor gotchas**: Real-time parameter updates (slider changes) fight against videoComposition's pre-rendering. Need composition reset strategy that doesn't overwhelm CPU.

8. **ScrollView performance on macOS is poor**: For timeline scrolling with many elements, consider AppKit NSScrollView with SwiftUI overlays instead of pure SwiftUI ScrollView.

9. **Proxy workflow from day one**: Design the media pipeline to support proxy files from the start. Retrofitting proxy support is painful.

10. **Profile before optimizing**: Use Instruments with Metal System Trace. Don't add drawingGroup() or Metal rendering preemptively.

### Product/Market Lessons

11. **DaVinci Resolve sets the bar**: A free NLE must offer genuine, un-crippled core functionality. Users upgrade for performance and AI, not basic editing.

12. **Plugin ecosystem matters**: FCP's success despite fewer built-in features is partly due to its "far larger" plugin marketplace.

13. **Collaboration is table stakes**: FCP's lack of native collaboration is seen as a significant gap. Cloud-based workflows are expected.

14. **AI features are differentiators**: Transcription, scene detection, object tracking, and smart audio processing are expected features in 2025+.

15. **Content creator market growing**: FCP's repositioning toward "content creators" reflects market reality. The explosion of YouTube/TikTok/social creates demand for prosumer tools.

### Developer Experience Lessons

16. **AVFoundation + Swift Concurrency is painful**: GCD-based AVFoundation and Swift's structured concurrency don't mix well. Plan for this friction.

17. **Metal documentation needs work**: Community complains about Objective-C examples and insufficient Swift coverage. Expect to spend significant time on Metal learning curve.

18. **Test on real devices early**: "The only way to experience an experience is to experience it" -- simulators don't reveal real performance characteristics for video processing.

19. **FFmpeg integration has risks**: Memory safety issues in FFmpeg code can crash entire subsystems. Need careful isolation and error handling.

20. **Ship simple first**: "When in doubt, ship the simplest thing -- the simplest version is simply better." Build trimming and basic cuts before effects and AI.

---

## Additional Resources

### Developer Blogs and Tutorials
- [VideoWithSwift.com](https://videowithswift.com/) -- Programmatic video editing with Swift tutorials
- [IMG.LY Blog](https://img.ly/blog/) -- Professional video SDK development insights
- [Metal by Example](https://metalbyexample.com/) -- Metal programming tutorials including HDR video
- [SwiftUI Lab](https://swiftui-lab.com/) -- Advanced SwiftUI animation and performance

### GitHub Repositories Worth Studying
- [VideoLab](https://github.com/ruanjx/VideoLab) -- AE-inspired editing framework (AVFoundation + Metal)
- [MetalPetal](https://github.com/MetalPetal/MetalPetal) -- GPU image/video processing framework
- [GPUImage3](https://github.com/BradLarson/GPUImage3) -- Metal-based video processing
- [Vulcan](https://github.com/hadiidbouk/Vulcan) -- SwiftUI + TCA video editor
- [AVCustomEdit](https://developer.apple.com/library/archive/samplecode/AVCustomEdit/) -- Apple sample for custom compositing

### Community Forums
- [Apple Developer Forums - AVFoundation](https://developer.apple.com/forums/tags/avfoundation)
- [Apple Developer Forums - Metal](https://developer.apple.com/forums/tags/metal)
- [Blackmagic Design Forum](https://forum.blackmagicdesign.com/)
- r/swift, r/iOSProgramming, r/VideoEditing on Reddit
