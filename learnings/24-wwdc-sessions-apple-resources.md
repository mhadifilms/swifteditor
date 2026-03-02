# WWDC Sessions & Apple Resources for NLE Video Editor Development

> Comprehensive catalog of every relevant WWDC session, sample code project, documentation page, and HIG section for building a professional video editing (NLE) application on Apple platforms.

---

## Table of Contents

1. [AVFoundation / Video Composition / Editing](#1-avfoundation--video-composition--editing)
2. [Metal for Media / Video Processing / GPU](#2-metal-for-media--video-processing--gpu)
3. [Core Image / Core Video](#3-core-image--core-video)
4. [Vision Framework for Video Analysis](#4-vision-framework-for-video-analysis)
5. [Audio (AVAudioEngine, Spatial Audio)](#5-audio-avaudioengine-spatial-audio)
6. [SwiftUI for Pro / Complex Apps](#6-swiftui-for-pro--complex-apps)
7. [Performance / Instruments / Debugging](#7-performance--instruments--debugging)
8. [Accessibility for Pro Apps](#8-accessibility-for-pro-apps)
9. [App Lifecycle / Document-Based / Window Management](#9-app-lifecycle--document-based--window-management)
10. [Design System / Liquid Glass / HIG](#10-design-system--liquid-glass--hig)
11. [Swift Concurrency / Swift 6](#11-swift-concurrency--swift-6)
12. [Distribution / TestFlight / Notarization](#12-distribution--testflight--notarization)
13. [Color Management / HDR / EDR](#13-color-management--hdr--edr)
14. [Camera Capture](#14-camera-capture)
15. [VideoToolbox / Codecs / Hardware Encoding](#15-videotoolbox--codecs--hardware-encoding)
16. [Drag & Drop / Undo-Redo / Menus / Keyboard Shortcuts](#16-drag--drop--undo-redo--menus--keyboard-shortcuts)
17. [Supplementary Frameworks (Transferable, SharePlay, Charts)](#17-supplementary-frameworks)
18. [Apple Sample Code Projects](#18-apple-sample-code-projects)
19. [Key Apple Documentation Pages](#19-key-apple-documentation-pages)
20. [Human Interface Guidelines for NLE](#20-human-interface-guidelines-for-nle)

---

## 1. AVFoundation / Video Composition / Editing

### WWDC 2013
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 612 | **Advanced Editing with AV Foundation** | Covers custom compositors for transitions and effects, plus audio mix integration. Foundational for understanding how AVVideoCompositing protocol enables custom GPU-driven compositing. |

### WWDC 2015
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 506 | **Editing Movies in AV Foundation** | Introduces AVMutableMovie for segment-based editing tied to QuickTime file format. Essential for understanding non-destructive editing workflows where you open, edit, and write back movie files without full re-encoding. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10009 | **Edit and Play Back HDR Video with AVFoundation** | Demonstrates HDR editing with AVMutableVideoComposition using built-in compositor, Core Image filters, and custom compositors. Shows the core NLE pipeline: asset -> AVComposition (temporal) + AVVideoComposition (spatial) -> playback/export. |
| 10010 | **Export HDR Media in Your App with AVFoundation** | Covers AVAssetExportSession and AVAssetWriter for HDR export with HEVC and ProRes codecs. Critical for understanding how to export edited compositions preserving HDR metadata and wide color. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10146 | **What's New in AVFoundation** | Async asset inspection, video compositing with timed metadata, and caption file authoring (.itt, .scc). Enables subtitle/caption workflows in NLE timelines with programmatic authoring and runtime preview. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 110379 | **Create a More Responsive Media App** | New async APIs for AVMutableVideoComposition and AVMutableComposition. Essential for keeping timeline UI responsive while performing I/O-heavy composition operations on background threads. |
| 110565 | **Display HDR Video in EDR with AVFoundation and Metal** | Building an efficient EDR pipeline using AVPlayer + Metal rendering + Core Image/Metal shaders for real-time video effects. Core architecture pattern for an NLE preview/viewer panel. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10137 | **Support Cinematic Mode Videos in Your App** | Custom video compositor for Cinematic assets with multi-track handling and depth-based rendering. Relevant for supporting iPhone Cinematic footage in the NLE with user-adjustable focus. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10166 | **Build Compelling Spatial Photo and Video Experiences** | Spatial video integration using existing AVFoundation/PhotoKit APIs. Relevant for future-proofing the NLE to handle stereoscopic media from Vision Pro and iPhone 15 Pro. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 319 | **Capture Cinematic Video in Your App** | Cinematic capture API producing non-destructive depth-enhanced video. The output movie format enables post-capture editing of bokeh/focus using the Cinematic Framework. |

---

## 2. Metal for Media / Video Processing / GPU

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 601 | **Modern Rendering with Metal** | GPU-driven rendering, deferred/tiled-forward rendering, and GPU Families for cross-platform scaling. Foundational understanding for building GPU-accelerated compositing and effects pipelines. |
| 608 | **Metal for Pro Apps** | **The single most relevant Metal session for NLE development.** Covers video editing pipeline optimization for 8K content, multi-GPU support, HDR display via CAMetalLayer + EDR APIs, and CPU/GPU parallelism. Apple partnered with Blackmagic on DaVinci Resolve optimization. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10602 | **Harness Apple GPUs with Metal** | Apple GPU TBDR architecture deep-dive. Understanding tile-based deferred rendering is critical for optimizing real-time video compositing and effects rendering on Apple silicon. |
| 10603 | **Optimize Metal Apps and Games with GPU Counters** | GPU performance counter profiling. Essential for finding bottlenecks in shader-heavy video processing pipelines using Metal System Trace. |
| 10632 | **Optimize Metal Performance for Apple Silicon Macs** | TBDR optimization for Apple silicon, scheduling workloads for maximum throughput. Directly applicable to building efficient rendering pipelines on M-series chips. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10066 | **Discover Metal 3** | Fast resource loading, offline compilation, MetalFX upscaling, mesh shaders, and ML acceleration. MetalFX can enable real-time preview of high-res timelines. Blackmagic DaVinci Resolve showcased dramatic ML-based editing improvements. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10218 | **Accelerate Machine Learning with Metal** | ML inference optimization for image/video processing on Apple silicon. Enables AI-powered effects like style transfer, noise reduction, and super-resolution in real-time. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 205 | **Discover Metal 4** | New command structure, explicit memory management, tensor resources, ML encoder, and Shader ML for embedding neural networks in shaders. MetalFX Frame Interpolation for optical flow and frame generation. Game-changing for AI-enhanced NLE effects. |
| 262 | **Combine Metal 4 Machine Learning and Graphics** | Tensor resources and ML encoder on the GPU timeline. Enables running inference networks alongside rendering for real-time AI effects like intelligent upscaling, denoising, and object removal. |
| 254 | **Explore Metal 4 Games** | Advanced Metal 4 rendering techniques. Applicable to complex multi-pass compositing pipelines. |

---

## 3. Core Image / Core Video

### WWDC 2017
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 510 | **Advances in Core Image: Filters, Metal, Vision, and More** | Custom CIKernels in Metal Shading Language, depth data processing, barcode handling. Foundation for writing custom video filters/effects that run in the Core Image pipeline. |
| 508 | **Image Editing with Depth** | Core Image filters applied to depth data from dual cameras. Relevant for depth-aware effects in NLE like selective focus, background replacement. |

### WWDC 2018
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 719 | **Core Image: Performance, Prototyping, and Python** | Filter chain performance optimization and custom CIKernel techniques. Critical for ensuring video effects chains maintain real-time playback performance. |
| 219 | **Image and Graphics Best Practices** | CPU/GPU image handling optimization, memory footprint minimization. Important for thumbnail generation and proxy workflow performance. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 260 | **Introducing Photo Segmentation Mattes** | Core Image with semantic segmentation mattes (hair, skin, teeth). Enables intelligent masking effects in the NLE without manual rotoscoping. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10008 | **Optimize the Core Image Pipeline for Your Video App** | **Essential for NLE.** Best practices for CIContext creation, custom CI Kernels in Metal, and optimal rendering to MTKView/AVPlayerView. Shows the complete real-time video effects pipeline. |
| 10021 | **Build Metal-Based Core Image Kernels with Xcode** | Step-by-step guide for writing CIKernels in Metal Shading Language with build-time compilation. Eliminates runtime shader compilation for custom NLE effects. |
| 10089 | **Discover Core Image Debugging Techniques** | CI_PRINT_TREE and other debugging tools. Essential for diagnosing performance issues in complex filter chains used for video effects. |
| 10673 | **Explore Computer Vision APIs** | Combining Core Image preprocessing with Vision framework analysis. Enables intelligent auto-effects like auto color correction and content-aware adjustments. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10159 | **Explore Core Image Kernel Improvements** | Enhanced Metal CIKernel integration. Enables more sophisticated custom video effects with better performance characteristics. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10114 | **Display EDR Content with Core Image, Metal, and SwiftUI** | **Key architecture reference.** Shows complete sample project for Core Image + MTKView + SwiftUI multiplatform app with EDR support. Over 150 built-in CIFilters support EDR. Directly applicable to NLE viewer architecture. |
| 10113 | **Explore EDR on iOS** | Reference Mode for color-critical workflows (color grading, editing, content review). Fixed brightness mapping essential for professional color work in the NLE. |

---

## 4. Vision Framework for Video Analysis

### WWDC 2017
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 506 | **Vision Framework: Building on Core ML** | Introduction of Vision: face detection, landmarks, object tracking. Foundation for smart NLE features like auto-framing, face tracking, and object-following effects. |

### WWDC 2018
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 716 | **Object Tracking in Vision** | Object tracking in video streams. Directly applicable to motion tracking for effects, stabilization, and following objects across timeline frames. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 222 | **Understanding Images in Vision Framework** | Image classification, saliency analysis. Enables auto-scene detection and smart thumbnail selection in the NLE media browser. |
| 234 | **Text Recognition in Vision Framework** | OCR for video frames. Useful for auto-generating captions/subtitles and searchable timeline markers. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10653 | **Detect Body and Hand Pose with Vision** | Body and hand pose detection in video. Enables motion-driven effects, gesture-based editing triggers, and action classification for auto-tagging clips. |
| 10099 | **Explore the Action & Vision App** | Complete sample combining Create ML + Core ML + Vision for real-time video analysis. Architecture reference for building AI-assisted editing features. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10040 | **Detect People, Faces, and Poses Using Vision** | Person segmentation API returning a single mask for all people. Directly useful for background removal/replacement effects in the NLE without manual masking. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10024 | **What's New in Vision** | Optical flow for video, updated text recognition, face detection improvements. Optical flow is directly applicable to frame interpolation, motion estimation, and temporal effects. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10176 | **Lift Subjects from Images in Your App** | Class-agnostic subject lifting (not just people). Enables one-click subject isolation for compositing in the NLE timeline. |
| 111241 | **Explore 3D Body Pose and Person Segmentation in Vision** | 3D body pose (17 joints) and individual person instance masks (up to 4 people). Enables per-person effects and 3D-aware compositing. |
| 10045 | **Detect Animal Poses in Vision** | Animal pose detection with individual joints. Extends NLE tracking capabilities to animals in wildlife/nature content. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10163 | **Discover Swift Enhancements in the Vision Framework** | Swift concurrency redesign, holistic body pose (body + hands together), image aesthetics scoring. Aesthetics scoring can power smart clip selection and auto-highlight features. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 272 | **Read Documents Using the Vision Framework** | Improved hand pose detection (21 joints), structured document understanding. Enhanced hand tracking enables gesture-driven editing in future spatial computing workflows. |

---

## 5. Audio (AVAudioEngine, Spatial Audio)

### WWDC 2015
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 507 | **What's New in Core Audio** | AVAudioEngine enhancements: compressed formats, flexible connections, AVAudioSequencer. Foundation for NLE audio processing pipeline. |
| 508 | **Audio Unit Extensions** | Audio Unit extension architecture. Enables third-party audio plugin support in the NLE (VST-equivalent). |

### WWDC 2016
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 507 | **Delivering an Exceptional Audio Experience** | AVAudioEngine real-time processing, multichannel 5.1/7.1 surround rendering. Essential for NLE multichannel audio mixing and surround panning. |

### WWDC 2017
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 501 | **What's New in Audio** | Manual Rendering Mode for AVAudioEngine, Auto Shutdown Mode, high-order ambisonics support. Manual rendering enables offline audio processing for NLE export/bounce. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 510 | **What's New in AVAudioEngine** | Voice processing, AVAudioSourceNode/AVAudioSinkNode, spatial rendering mode selection, multichannel spatialization. Directly applicable to NLE audio effects and spatial audio mixing. |
| 508 | **Modernizing Your Audio App** | AUGraph/Inter-App Audio/OpenAL deprecated; migrate to AVAudioEngine. Important migration guidance for audio architecture decisions. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10265 | **Immerse Your App in Spatial Audio** | Spatial audio delivery via AVFoundation, automatic listening experience adaptation. Enables spatial audio playback in the NLE preview and export to spatial formats. |
| 10079 | **Discover Geometry-Aware Audio with PHASE** | Physical Audio Spatialization Engine for geometry-aware spatial soundscapes. Future-relevant for spatial audio editing in 3D/AR video projects. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10271 | **Explore Immersive Sound Design** | Spatial audio design principles for visionOS. Relevant for creating spatial audio editing workflows targeting Apple Vision Pro content. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 251 | **Enhance Your App's Audio Recording Capabilities** | Spatial audio recording to First Order Ambisonics via AVAssetWriter, simultaneous MovieFileOutput + AudioDataOutput. Enables spatial audio capture and real-time audio visualization in the NLE. |

---

## 6. SwiftUI for Pro / Complex Apps

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 216 | **SwiftUI Essentials** | Composition of small, single-purpose views. Core architecture principle for building complex NLE UI from composable components. |
| 226 | **Data Flow Through SwiftUI** | @State, @Binding, @ObservableObject data flow. Essential for managing NLE state (timeline position, selection, tool state) across the view hierarchy. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10037 | **App Essentials in SwiftUI** | App/Scene/View lifecycle, WindowGroup, commands modifier. Foundation for multi-window NLE app architecture with menu bar commands. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10018 | **What's New in SwiftUI (2021)** | Canvas view, materials, multi-column tables on macOS, search API, AttributedString. Canvas is essential for high-performance timeline rendering; tables for media browser. |
| 10022 | **Demystify SwiftUI** | Identity, Lifetime, Dependencies core principles. Critical for understanding view update performance in complex NLE interfaces with many simultaneously updating views. |
| 10062 | **SwiftUI on the Mac: Build the Fundamentals** | Sidebar/detail patterns, .searchable, toolbar, multiple windows, menu bar support. **Directly applicable** to NLE layout with sidebar media browser, inspector, and multi-window support. |
| 10021 | **Add Rich Graphics to Your SwiftUI App** | Canvas view for immediate-mode drawing, TimelineView for time-based updates. **Essential for NLE timeline rendering** -- Canvas provides the low-overhead drawing needed for waveforms, thumbnails, and timeline tracks. TimelineView drives playback-synchronized UI updates. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10052 | **What's New in SwiftUI (2022)** | NavigationSplitView, NavigationStack, adaptive layouts. Foundation for NLE layout that adapts between compact (single pane) and full (multi-pane) configurations. |
| 10056 | **Compose Custom Layouts with SwiftUI** | Grid container, Layout protocol, animated layout transitions. Layout protocol enables custom NLE-specific layouts (e.g., tracks area, effects rack, mixer). |
| 10054 | **The SwiftUI Cookbook for Navigation** | Navigation patterns, deep linking, state restoration. Important for NLE project navigation, recent projects, and workspace restoration. |
| 10061 | **Bring Multiple Windows to Your SwiftUI App** | MenuBarExtra, window modifiers, newDocument/openDocument actions. Enables multi-window NLE workflows (viewer, timeline, effects, scopes in separate windows). |
| 10072 | **Use SwiftUI with UIKit** | Hosting SwiftUI in UIKit and vice versa. Critical for incremental adoption -- Metal views and timeline in UIKit/AppKit, panels in SwiftUI. |
| 10075 | **Use SwiftUI with AppKit** | Hosting SwiftUI in AppKit, responder chain, navigational focus. Essential for macOS NLE development combining SwiftUI panels with AppKit infrastructure. |
| 10062 | **Meet Transferable** | Swift-first drag-and-drop, copy/paste protocol. Enables drag-and-drop of clips, effects, and media between NLE panels and from Finder. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10160 | **Demystify SwiftUI Performance** | Performance mental model, identifying bottlenecks in complex views. Critical for maintaining 60fps responsiveness in the NLE interface during playback and editing. |
| 10115 | **Design with SwiftUI** | Design-to-code workflow, non-programmer accessibility of SwiftUI. Relevant for rapid prototyping of NLE interface designs. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10150 | **SwiftUI Essentials (2024)** | Updated best practices, tabs/documents on iPadOS, windowing APIs. Latest guidance for NLE app structure on iPad and Mac. |
| 10151 | **Create Custom Visual Effects with SwiftUI** | Custom visual effects using GraphicsContext (same as Canvas). Enables sophisticated NLE UI effects like glass morphism on panels, visualizers. |
| 10144 | **What's New in SwiftUI (2024)** | Function plotting in Swift Charts, mesh gradients, new controls. Mesh gradients for waveform visualization, Charts for audio level meters. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 256 | **What's New in SwiftUI (2025)** | Lists 6x faster for 100K+ items (16x faster updates), scene bridging for UIKit/AppKit lifecycle apps, web content, rich text editing. Massive performance gains directly benefit media browser lists. Scene bridging enables gradual NLE migration. |

---

## 7. Performance / Instruments / Debugging

### WWDC 2018
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 407 | **Practical Approaches to Great App Performance** | Strategies from tuning Apple's own apps (Xcode, Photos). Directly applicable patterns for profiling NLE rendering and I/O bottlenecks. |
| 405 | **Measuring Performance Using Logging** | Signposts, Points of Interest instrument, custom instruments. Essential for adding tracing to NLE pipeline stages (decode, composite, render, encode). |
| 612 | **Metal Game Performance Optimization** | GPU profiling with Metal System Trace. Critical for optimizing real-time video compositing shader performance. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 411 | **Getting Started with Instruments** | Time Profiler, Points of Interest. Foundation for profiling NLE responsiveness and identifying CPU bottlenecks. |
| 414 | **Developing a Great Profiling Experience** | Adding tracing to frameworks, building custom instruments. Enables building NLE-specific profiling instruments for pipeline stages. |
| 421 | **Modeling in Custom Instruments** | Custom modeler from signpost output. Build custom instruments that visualize NLE-specific metrics (frames decoded/s, render queue depth). |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10106 | **Profile and Optimize Your Game's Memory** | Game Memory template, memory graphs, heap analysis. Directly applicable to profiling memory usage of video frame buffers and texture caches. |
| 110350 | **Visualize and Optimize Swift Concurrency** | Swift Concurrency template in Instruments. Essential for diagnosing task scheduling issues in async NLE pipeline code. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10248 | **Analyze Hangs with Instruments** | Hang detection and analysis. Critical for ensuring the NLE never freezes during editing operations. |
| 10160 | **Demystify SwiftUI Performance** | SwiftUI-specific performance analysis. Ensures the NLE interface remains responsive with complex view hierarchies. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 306 | **Optimize SwiftUI Performance with Instruments** | New SwiftUI instrument with View Body Updates tracking. Shows exactly which NLE views are causing unnecessary redraws during timeline scrubbing. |
| 226 | **How Senior iOS Devs Profile and Solve Performance Issues** | Time Profiler, Power Profiler best practices. Practical profiling methodology applicable to NLE development workflow. |

---

## 8. Accessibility for Pro Apps

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 238 | **Accessibility in SwiftUI** | SwiftUI accessibility fundamentals. Foundation for making NLE panels, controls, and timeline accessible. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10020 | **Make Your App Visually Accessible** | Adaptive interface, color accessibility, readable text. Critical for NLE where dense information displays must remain readable at all settings. |
| 10117 | **Accessibility Design for Mac Catalyst** | Mouse/keyboard accessibility, element grouping. Relevant for Mac NLE accessibility patterns. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10119 | **SwiftUI Accessibility: Beyond the Basics** | Advanced accessibility APIs, Xcode preview accessibility audit. Essential for complex NLE interfaces with custom controls (sliders, knobs, timeline). |
| 10121 | **Tailor the VoiceOver Experience in Data-Rich Apps** | accessibilityCustomContent for complex data. Directly applicable to NLE timelines with many tracks, clips, and properties that need VoiceOver navigation. |
| 10120 | **Support Full Keyboard Access in Your iOS App** | Full keyboard navigation, accessibilityUserInputLabels. Critical for NLE where keyboard-driven editing is a core workflow. |
| 10260 | **Focus on iPad Keyboard Navigation** | Focusable content, focus appearance customization. Enables keyboard-driven navigation through NLE timeline and inspector panels on iPad. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10036 | **SwiftUI Accessibility: Beyond the Basics (Revisited)** | Updated accessibility techniques for rich interfaces. Latest patterns for making complex NLE controls accessible. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10073 | **Catch Up on Accessibility in SwiftUI** | Comprehensive SwiftUI accessibility overview. Current best practices for NLE accessibility implementation. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 229 | **Make Your Mac App More Accessible to Everyone** | Accessibility containers for VoiceOver navigation, keyboard shortcuts as accessibility features, accessibility default focus. **Directly applicable** to NLE with deep view hierarchies. Container grouping enables efficient VoiceOver navigation through timeline tracks. |

---

## 9. App Lifecycle / Document-Based / Window Management

### WWDC 2018
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 216 | **Managing Documents in Your iOS Apps** | Document Browser vs Document Picker, document lifecycle. Foundation for NLE project file management. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 212 | **Introducing Multiple Windows on iPad** | Scene-based lifecycle, state restoration via NSUserActivity. Essential for NLE supporting multiple windows (viewer + timeline split). |
| 246 | **Window Management in Your Multitasking App** | requestSceneSessionActivation for auxiliary windows. Enables opening separate viewer/scopes windows from NLE. |
| 258 | **Architecting Your App for Multiple Windows** | UIScene delegate, per-scene state management. Core architecture for managing NLE workspace state across multiple windows. |
| 235 | **Taking iPad Apps for Mac to the Next Level** | Mac Catalyst refinements, per-scene state handling on macOS. Cross-platform NLE lifecycle management. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10037 | **App Essentials in SwiftUI** | App protocol, WindowGroup, commands modifier. Declarative NLE app structure with automatic multi-window support. |
| 10039 | **Build Document-Based Apps in SwiftUI** | DocumentGroup scene, FileDocument/ReferenceFileDocument protocols. **Directly applicable** to NLE project file architecture with automatic document browsing and standard save/open commands. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10061 | **Bring Multiple Windows to Your SwiftUI App** | MenuBarExtra, newDocument/openDocument actions, window customization. Enables NLE workflows like detachable panels and utility windows. |

---

## 10. Design System / Liquid Glass / HIG

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 219 | **Meet Liquid Glass** | Design principles behind Liquid Glass material. Defines the new visual language the NLE should adopt for toolbars, tabs, and navigation elements. |
| 356 | **Get to Know the New Design System** | Visual design changes, information architecture, core system components. **Essential** for understanding how NLE sidebars, split views, and toolbars should evolve. Sidebars are now inset with glass, content flows behind. |
| 310 | **Adopt the New Design System in AppKit** | Tab views, split views, bars updated for Liquid Glass in AppKit. Direct implementation guidance for macOS NLE UI. |
| 284 | **Build a UIKit App with the New Design** | Navigation bars, toolbars, tab bars with Liquid Glass in UIKit/iPad. Implementation guidance for iPad NLE UI. |

### Apple Tech Talk
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 208 | **Showcase: Learn How Apps Are Integrating Liquid Glass** | Real-world adoption patterns. Shows how pro apps are integrating Liquid Glass while keeping content as the focus -- directly relevant to NLE design. |

---

## 11. Swift Concurrency / Swift 6

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10132 | **Meet async/await in Swift** | Foundation of Swift concurrency. Essential for async media loading, decoding, and I/O in the NLE pipeline. |
| 10134 | **Explore Structured Concurrency in Swift** | Task groups, cancellation, child tasks. Enables parallel thumbnail generation, batch export, and cancellable operations. |
| 10194 | **Swift Concurrency: Update a Sample App** | Practical migration from callbacks to async/await. Guide for migrating existing AVFoundation callback-based code. |
| 10254 | **Swift Concurrency: Behind the Scenes** | Cooperative threading model internals. Understanding this prevents thread explosion in media-heavy NLE workloads. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 110350 | **Visualize and Optimize Swift Concurrency** | Instruments concurrency template. Essential for diagnosing pipeline stalls and actor contention in the NLE. |
| 110351 | **Eliminate Data Races Using Swift Concurrency** | Sendable, actor isolation. Critical for ensuring thread-safe access to shared NLE state (timeline, playback position). |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10170 | **Beyond the Basics of Structured Concurrency** | Task hierarchy, automatic cancellation, task-local values. Enables clean cancellation of NLE preview rendering when user scrubs timeline. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10169 | **Migrate Your App to Swift 6** | Incremental module-by-module migration, data-race safety. Essential for adopting Swift 6 strict concurrency in the NLE codebase. |
| 10136 | **What's New in Swift (2024)** | Swift 6 language mode, data-race safety, Embedded Swift. Understanding the new safety model for NLE architecture. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 268 | **Embracing Swift Concurrency** | @concurrent attribute, nonisolated flexibility. New patterns for controlling where NLE processing work runs. |
| 266 | **Explore Concurrency in SwiftUI** | MainActor by default in Swift 6.2, async task management with SwiftUI event loop. **Critical** for NLE UI architecture -- understanding when work runs on MainActor vs background. |
| 270 | **Code-Along: Elevate an App with Swift Concurrency** | Practical guide from single-threaded to concurrent. Step-by-step pattern applicable to NLE pipeline parallelization. |
| 250 | **Use Structured Concurrency with Network Framework** | Network framework with structured concurrency. Relevant for collaborative NLE features and cloud media access. |

---

## 12. Distribution / TestFlight / Notarization

### WWDC 2018
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 702 | **Your Apps and the Future of macOS Security** | Introduction of notarization. Foundation for distributing the NLE outside the Mac App Store via Developer ID. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 703 | **All About Notarization** | Detailed notarization process. Essential for macOS NLE distribution via direct download. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10261 | **Faster and Simpler Notarization for Mac Apps** | notarytool introduction, faster processing. Streamlines NLE CI/CD pipeline for macOS builds. |
| 10204 | **Distribute Apps in Xcode with Cloud Signing** | Cloud signing, distribution options (TestFlight, Developer ID, ad hoc). Complete distribution workflow for NLE beta testing and release. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10109 | **What's New in Notarization for Mac Apps** | Notary REST API. Enables automated notarization in NLE CI/CD pipeline. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10224 | **Simplify Distribution in Xcode and Xcode Cloud** | One-click TestFlight submission, TestFlight Internal Only builds, auto-notarization in Xcode Cloud. **Highly practical** for NLE development -- Internal Only builds for team testing, Xcode Cloud for automated distribution. |

---

## 13. Color Management / HDR / EDR

### WWDC 2016
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 712 | **Working with Wide Color** | ColorSync, P3 color space, wide color pipeline. Foundation for understanding color management in the NLE -- essential for professional color grading. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 608 | **Metal for Pro Apps** (EDR section) | CAMetalLayer + EDR APIs, HDR tone mapping, color management for content creation. Core architecture for NLE HDR viewer. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10009 | **Edit and Play Back HDR Video with AVFoundation** | HDR editing pipeline. See AVFoundation section above. |
| 10010 | **Export HDR Media in Your App** | HDR export with HEVC/ProRes, HLG/PQ transfer functions, BT.2020 color primaries. Essential for NLE export settings and format support. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10161 | **Explore HDR Rendering with EDR** | **Key session.** EDR as Apple's HDR pipeline, native EDR APIs on macOS, Pro Display XDR support. Provides the complete HDR rendering architecture for NLE color-accurate preview. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10113 | **Explore EDR on iOS** | Reference Mode (100 nits SDR / 1000 nits HDR, 10x headroom). **Essential for pro NLE** -- Reference Mode enables on-device color grading and review on iPad. |
| 10114 | **Display EDR Content with Core Image, Metal, and SwiftUI** | Complete EDR rendering sample. See Core Image section. |
| 110565 | **Display HDR Video in EDR with AVFoundation and Metal** | Complete HDR video pipeline. See AVFoundation section. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10181 | **Support HDR Images in Your App** | ISO HDR standards, UIImage HDR write support, EDR headroom APIs. Relevant for NLE thumbnail and still export with HDR preservation. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10177 | **Use HDR for Dynamic Image Experiences** | CGImageGetContentHeadroom, extended range CGContext with EDR target headroom. Enables precise HDR handling in NLE UI elements like scopes and waveform displays. |
| 10088 | **Capture HDR Content with ScreenCaptureKit** | HDR screen capture. Relevant for screen recording features and tutorial creation from within the NLE. |

### Apple Tech Talks
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10023 | **Support Apple Pro Display XDR in Your Apps** | P3 wide gamut, 10-bit color, 1600 nits peak, reference modes. Configuration guide for NLE on professional displays. |
| 110337 | **Discover Reference Mode** | Fixed brightness mapping (SDR=100 nits, HDR=1000 nits). Professional color grading display configuration for NLE. |

---

## 14. Camera Capture

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 225 | **Advances in Camera Capture & Photo Segmentation** | Multi-camera capture, semantic segmentation. Enables multi-angle recording features in the NLE. |
| 249 | **Introducing Multi-Camera Capture for iOS** | AVCaptureMultiCamSession deep dive. Enables simultaneous multi-cam recording in NLE companion capture app. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10047 | **What's New in Camera Capture** | 10-bit HDR capture, IOSurface compression, performance best practices. Ensures NLE capture integration supports latest formats. |
| 10247 | **Capture High-Quality Photos Using Video Formats** | Quality prioritization API. Relevant for frame grab/still extraction from NLE timeline. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 110429 | **Discover Advancements in iOS Camera Capture** | LiDAR depth capture, multitasking with camera, multiple simultaneous VideoDataOutputs. Depth capture enables NLE depth-based effects on new footage. |
| 10018 | **Bring Continuity Camera to Your macOS App** | iPhone as Mac camera via Continuity Camera. Enables using iPhone as a live camera source in the Mac NLE. |

### WWDC 2023
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10105 | **Create a More Responsive Camera Experience** | Zero shutter lag, deferred photo processing, responsive capture pipeline. Relevant for NLE integrated recording features. |

### WWDC 2024
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10166 | **Build Compelling Spatial Photo and Video Experiences** | Spatial video capture on iPhone 15 Pro. Ensures NLE can ingest and edit spatial video content. |

### WWDC 2025
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 253 | **Enhancing Your Camera Experience with Capture Controls** | Capture Controls API, remote camera control with AirPods. Future NLE integration for direct-to-timeline recording. |
| 319 | **Capture Cinematic Video in Your App** | Cinematic capture API, 1080p/4K at 30fps, SDR/EDR/HDR formats. Enables NLE to directly capture cinema-quality depth-enhanced footage. |

---

## 15. VideoToolbox / Codecs / Hardware Encoding

### WWDC 2014
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 513 | **Direct Access to Video Encoding and Decoding** | VideoToolbox fundamentals, hardware encoder/decoder access. Foundation for NLE's custom decode/encode pipeline when AVFoundation's high-level APIs are insufficient. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10090 | **Decode ProRes with AVFoundation and VideoToolbox** | **Essential for NLE.** Optimal ProRes decode pipeline with Metal integration, Afterburner card support, CVPixelBuffer-to-Metal-texture via CVMetalTextureCache. Core architecture for NLE decode-to-GPU rendering pipeline. |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10158 | **Explore Low-Latency Video Encoding with VideoToolbox** | Hardware-accelerated low-latency H.264 encoding. Useful for NLE real-time recording and proxy generation. |

### Hardware Announcements (Keynotes)
| Year | Topic | NLE Relevance |
|------|-------|---------------|
| 2022 | M2 Media Engine | ProRes hardware encode/decode, 8K H.264/HEVC decoder. Enables NLE to handle 8K ProRes workflows natively. |
| 2023 | M2 Ultra Media Engine | 22 streams of 8K ProRes, 24 simultaneous 4K ProRes encode. Professional multi-stream editing performance for NLE. |
| 2024 | M3/M4 | AV1 hardware decode, continued ProRes/ProRes RAW support. NLE codec support roadmap should include AV1 decode. |

---

## 16. Drag & Drop / Undo-Redo / Menus / Keyboard Shortcuts

### WWDC 2017
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 203 | **Introducing Drag and Drop** | iOS drag and drop architecture. Foundation for NLE clip/effect drag-and-drop between browser, timeline, and inspector. |

### WWDC 2019
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 235 | **Taking iPad Apps for Mac to the Next Level** | UIContextMenuInteraction, menu bar customization with UICommands. Enables context menus on timeline clips and comprehensive NLE menu bar. |
| 103 | **Platforms State of the Union (2019)** | Three-finger undo/redo gestures via NSUndoManager, menu commands via storyboard. NLE gets free undo/redo gestures on iPad by using NSUndoManager. |

### WWDC 2020
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10109 | **Support Hardware Keyboards in Your App** | UIKeyCommands, UIResponderStandardEditActions, command builder API. **Essential** for NLE keyboard shortcut system (J/K/L, I/O, spacebar, etc.). |

### WWDC 2021
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10057 | **Take Your iPad Apps to the Next Level** | iPadOS 15 main menu system, UIMenuBuilder, keyboard shortcut overlay. Enables full NLE menu bar with discoverable shortcuts on iPad. |

### WWDC 2022
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10062 | **Meet Transferable** | Declarative drag-and-drop and copy/paste. Modern approach for NLE media transfer between panels and external apps. |

---

## 17. Supplementary Frameworks

### Transferable (WWDC 2022)
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10062 | **Meet Transferable** | Swift-first drag-and-drop/copy-paste. Enables type-safe media transfer in NLE. |

### SharePlay / Group Activities (WWDC 2021+)
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10183 | **Meet Group Activities** (2021) | SharePlay foundation. Future collaborative editing via FaceTime. |

### StoreKit 2 (WWDC 2021+)
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10114 | **Meet StoreKit 2** (2021) | Modern in-app purchase APIs. For NLE monetization (effects packs, pro features). |
| 10013 | **Meet StoreKit for SwiftUI** (2023) | SwiftUI in-app purchase views. Streamlined NLE upgrade/purchase UI. |

### Swift Charts (WWDC 2022+)
| Session | Title | NLE Relevance |
|---------|-------|---------------|
| 10136 | **Hello Swift Charts** (2022) | Declarative charting framework. Could be used for audio level meters, histogram displays, and scope visualizations. |

---

## 18. Apple Sample Code Projects

### Video Editing / Composition
| Sample | Description | URL |
|--------|-------------|-----|
| **AVCustomEdit** | Custom compositors with transitions using AVVideoCompositing protocol. Metal/OpenGL off-screen rendering for transitions. | [developer.apple.com/library/archive/samplecode/AVCustomEdit](https://developer.apple.com/library/archive/samplecode/AVCustomEdit/Introduction/Intro.html) |
| **AVCustomEditOSX** | macOS version of AVCustomEdit with custom video compositors. | [developer.apple.com/library/archive/samplecode/AVCustomEditOSX](https://developer.apple.com/library/archive/samplecode/AVCustomEditOSX/Introduction/Intro.html) |
| **AVCompositionDebugView** | Visual debugging tool for AVComposition, AVVideoComposition, and AVAudioMix. Shows temporal alignment and composition structure. | Referenced in [TN2447](https://developer.apple.com/library/archive/technotes/tn2447/_index.html) |

### Metal Rendering
| Sample | Description | URL |
|--------|-------------|-----|
| **Metal Sample Code Library** | Comprehensive collection: lightweight rendering views, multistage image filters with heaps/fences, multi-threaded rendering. | [developer.apple.com/metal/sample-code](https://developer.apple.com/metal/sample-code/) |
| **Metal Sample Code Library (Docs)** | Full indexed sample library with downloadable projects. | [developer.apple.com/documentation/metal/metal-sample-code-library](https://developer.apple.com/documentation/metal/metal-sample-code-library) |

### Core Image
| Sample | Description | URL |
|--------|-------------|-----|
| **Generating an Animation with Core Image Render Destination** | Animated filtered image to Metal view in SwiftUI using CIRenderDestination. | [developer.apple.com/documentation/coreimage/generating-an-animation-with-a-core-image-render-destination](https://developer.apple.com/documentation/coreimage/generating-an-animation-with-a-core-image-render-destination) |
| **Display EDR Content (WWDC22 Sample)** | Complete multiplatform SwiftUI app with Core Image + MTKView + EDR support via ViewRepresentable. | Accompanying [WWDC22 Session 10114](https://developer.apple.com/videos/play/wwdc2022/10114/) |

### SwiftUI Pro App
| Sample | Description | URL |
|--------|-------------|-----|
| **Fruta: Building a Feature-Rich App with SwiftUI** | Multiplatform SwiftUI app with widgets, App Clip. Architecture reference for complex SwiftUI apps. | [developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui](https://developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui) |
| **SwiftUI Sample Apps (Tutorials)** | Collection of SwiftUI tutorial apps demonstrating various patterns. | [developer.apple.com/tutorials/sample-apps](https://developer.apple.com/tutorials/sample-apps) |

### Vision / ML
| Sample | Description | URL |
|--------|-------------|-----|
| **Action & Vision App** | Complete sample combining Create ML + Core ML + Vision for real-time video analysis with feedback loop. | Accompanying [WWDC20 Session 10099](https://developer.apple.com/videos/play/wwdc2020/10099/) |

---

## 19. Key Apple Documentation Pages

### AVFoundation Editing
| Document | Description | URL |
|----------|-------------|-----|
| **AVFoundation Editing Guide** | Core editing API: AVMutableComposition, AVVideoComposition, AVAudioMix, instructions, layer instructions. | [developer.apple.com/library/archive/.../03_Editing.html](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html) |
| **AVMutableComposition** | API reference for creating compositions from existing assets. | [developer.apple.com/documentation/avfoundation/avmutablecomposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition) |
| **AVMutableVideoComposition** | API reference for mutable video composition. | [developer.apple.com/documentation/avfoundation/avmutablevideocomposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition) |
| **AVVideoComposition** | API reference for composing video frames at time points. | [developer.apple.com/documentation/avfoundation/avvideocomposition](https://developer.apple.com/documentation/avfoundation/avvideocomposition) |
| **TN2447: Debugging Compositions** | Debug AVComposition/AVVideoComposition/AVAudioMix with visual tools. | [developer.apple.com/library/archive/technotes/tn2447](https://developer.apple.com/library/archive/technotes/tn2447/_index.html) |
| **AVFoundation Overview** | Framework landing page with architecture diagrams. | [developer.apple.com/av-foundation](https://developer.apple.com/av-foundation/) |
| **AVFoundation Framework** | Complete API documentation. | [developer.apple.com/documentation/avfoundation](https://developer.apple.com/documentation/avfoundation) |

### Metal
| Document | Description | URL |
|----------|-------------|-----|
| **Metal Best Practices Guide** | Persistent objects, resource options, command buffers, functions/libraries, load/store actions, indirect buffers, screen scale. | [developer.apple.com/library/archive/.../MTLBestPracticesGuide](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/) |
| **Metal Programming Guide** | Complete Metal API concepts, GPU architecture, command submission. | [developer.apple.com/library/archive/.../MetalProgrammingGuide](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Introduction/Introduction.html) |
| **Metal Framework Documentation** | Full API reference for Metal. | [developer.apple.com/documentation/metal](https://developer.apple.com/documentation/metal) |
| **Metal Overview** | Framework landing page. | [developer.apple.com/metal](https://developer.apple.com/metal/) |
| **Metal Shading Language for Core Image Kernels** | Reference for writing CIKernels in Metal Shading Language. | [developer.apple.com/metal/MetalCIKLReference6.pdf](https://developer.apple.com/metal/MetalCIKLReference6.pdf) |

### Core Image
| Document | Description | URL |
|----------|-------------|-----|
| **Core Image Programming Guide: Processing Images** | CIContext creation, filter chaining, Metal integration, rendering to views. | [developer.apple.com/library/archive/.../CoreImaging/ci_tasks](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_tasks/ci_tasks.html) |
| **Core Image Kernel Language Reference** | CIKernel language specification. | [developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf](https://developer.apple.com/metal/CoreImageKernelLanguageReference11.pdf) |

### VideoToolbox
| Document | Description | URL |
|----------|-------------|-----|
| **VideoToolbox Framework** | API reference for hardware-accelerated video encoding/decoding. | [developer.apple.com/documentation/videotoolbox](https://developer.apple.com/documentation/videotoolbox) |

### Swift Concurrency
| Document | Description | URL |
|----------|-------------|-----|
| **Swift Concurrency Documentation** | Official Swift concurrency guide. | [developer.apple.com/documentation/swift/concurrency](https://developer.apple.com/documentation/swift/concurrency) |
| **Adopting Strict Concurrency in Swift 6 Apps** | Migration guide for Swift 6 data-race safety. | [developer.apple.com/documentation/swift/adoptingswift6](https://developer.apple.com/documentation/swift/adoptingswift6) |

### Liquid Glass
| Document | Description | URL |
|----------|-------------|-----|
| **Liquid Glass Overview** | Design and development guide for Liquid Glass material. | [developer.apple.com/documentation/TechnologyOverviews/liquid-glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) |
| **Adopting Liquid Glass** | Implementation guide for bringing Liquid Glass to your app. | [developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) |

### Audio
| Document | Description | URL |
|----------|-------------|-----|
| **AVAudioEngine Documentation** | API reference for real-time audio processing engine. | [developer.apple.com/documentation/avfaudio/avaudioengine](https://developer.apple.com/documentation/avfaudio/avaudioengine) |
| **Audio Overview** | Apple audio technologies landing page. | [developer.apple.com/audio](https://developer.apple.com/audio/) |

### Accessibility
| Document | Description | URL |
|----------|-------------|-----|
| **Accessibility Overview** | Apple accessibility technologies landing page. | [developer.apple.com/accessibility](https://developer.apple.com/accessibility/) |
| **Undo and Redo HIG** | Guidelines for undo/redo implementation. | [developer.apple.com/design/human-interface-guidelines/undo-and-redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) |

---

## 20. Human Interface Guidelines for NLE

### Core Layout Patterns
| HIG Section | URL | NLE Application |
|-------------|-----|-----------------|
| **Toolbars** | [developer.apple.com/design/human-interface-guidelines/toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | NLE main toolbar with transport controls, tool selection, zoom, and timeline controls. With Liquid Glass, toolbars float above content. |
| **Sidebars** | [developer.apple.com/design/human-interface-guidelines/sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) | NLE media browser, effects browser, and project navigator. Now inset with Liquid Glass, content flows behind. |
| **Split Views** | [developer.apple.com/design/human-interface-guidelines/split-views](https://developer.apple.com/design/human-interface-guidelines/split-views) | Core NLE layout: sidebar (browser) | center (viewer + timeline) | trailing (inspector). Each pane can have its own scroll edge effect. |
| **Navigation and Search** | [developer.apple.com/design/human-interface-guidelines/navigation-and-search](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search) | NLE project navigation, media search, and filter functionality. On iPad, search appears at trailing edge of navigation bar. |
| **Layout** | [developer.apple.com/design/human-interface-guidelines/layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Adaptive NLE layout across screen sizes and platforms. Safe areas, margins, and content-to-edge relationships. |

### Controls and Interactions
| HIG Section | URL | NLE Application |
|-------------|-----|-----------------|
| **Undo and Redo** | [developer.apple.com/design/human-interface-guidelines/undo-and-redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) | Multi-level undo for all editing operations. Essential for non-destructive editing workflow. |
| **Drag and Drop** | [developer.apple.com/design/human-interface-guidelines/drag-and-drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) | Clip placement on timeline, effect application, media import from Finder/Files. |
| **Menus** | [developer.apple.com/design/human-interface-guidelines/menus](https://developer.apple.com/design/human-interface-guidelines/menus) | NLE menu bar with File, Edit, View, Mark, Clip, Sequence, Effects, Window menus. Context menus on timeline clips. |
| **Keyboard** | [developer.apple.com/design/human-interface-guidelines/keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) | Keyboard shortcut system for professional editing workflow (J/K/L, I/O, etc.). |

### Pro App Patterns
| Pattern | Description | NLE Application |
|---------|-------------|-----------------|
| **Dense Information Display** | Pro apps show more information simultaneously than consumer apps. Use smaller text, tighter spacing, and more controls visible at once. | Timeline with many tracks, scopes, meters, and inspector properties all visible. |
| **Multi-Window** | Pro apps benefit from multiple windows for different functions. | Separate viewer, timeline, effects, audio mixer, and scopes windows. |
| **Customizable Interface** | Allow users to arrange panels and save workspace layouts. | Workspace presets (Color, Edit, Audio) with drag-to-arrange panels. |
| **Keyboard-First** | Pro users expect comprehensive keyboard shortcuts for speed. | Every editing action should have a keyboard shortcut. Support custom shortcut sets. |
| **Contextual Tools** | Tool behavior changes based on context and modifier keys. | Arrow tool behavior differs when over clip edges (trim) vs clip body (move) vs track header (select all). |

### Liquid Glass Considerations for NLE
| Guideline | Implementation |
|-----------|---------------|
| Remove background colors from custom toolbars/tab bars | Let Liquid Glass material provide the surface treatment. |
| Use tinting for primary actions | NLE primary actions (play, record) should use tint to stand out in glass surfaces. |
| Organize bar items by function and frequency | Group transport controls together, editing tools together, view options together. |
| Content should take center stage | NLE viewer and timeline should fill available space; glass chrome should be minimal and transparent. |
| Consistent scroll edge effects across split view panes | Align glass effects between browser, viewer, and inspector panes. |

---

## Cross-Reference: Sessions by Priority for NLE Development

### Must-Watch (Core Architecture)
1. **Metal for Pro Apps** (WWDC19-608) -- NLE GPU pipeline architecture
2. **Optimize the Core Image Pipeline for Your Video App** (WWDC20-10008) -- Real-time effects pipeline
3. **Edit and Play Back HDR Video with AVFoundation** (WWDC20-10009) -- Composition architecture
4. **Display HDR Video in EDR with AVFoundation and Metal** (WWDC22-110565) -- HDR viewer pipeline
5. **Create a More Responsive Media App** (WWDC22-110379) -- Async composition APIs
6. **Decode ProRes with AVFoundation and VideoToolbox** (WWDC20-10090) -- Decode pipeline
7. **SwiftUI on the Mac: Build the Fundamentals** (WWDC21-10062) -- Mac app layout
8. **Add Rich Graphics to Your SwiftUI App** (WWDC21-10021) -- Canvas + TimelineView
9. **Explore HDR Rendering with EDR** (WWDC21-10161) -- HDR architecture
10. **Get to Know the New Design System** (WWDC25-356) -- Liquid Glass adoption

### Important (Feature Implementation)
11. **What's New in AVFoundation** (WWDC21-10146) -- Captions, async APIs
12. **Support Cinematic Mode Videos** (WWDC23-10137) -- Cinematic editing
13. **What's New in AVAudioEngine** (WWDC19-510) -- Audio processing
14. **Detect People, Faces, and Poses** (WWDC21-10040) -- Person segmentation
15. **Lift Subjects from Images** (WWDC23-10176) -- Subject isolation
16. **Build Document-Based Apps in SwiftUI** (WWDC20-10039) -- Project management
17. **Compose Custom Layouts with SwiftUI** (WWDC22-10056) -- Custom layout
18. **Demystify SwiftUI Performance** (WWDC23-10160) -- UI performance
19. **Migrate Your App to Swift 6** (WWDC24-10169) -- Concurrency safety
20. **Display EDR Content with Core Image, Metal, and SwiftUI** (WWDC22-10114) -- EDR sample code

### Recommended (Best Practices & Polish)
21. **Explore Concurrency in SwiftUI** (WWDC25-266)
22. **Explore EDR on iOS** (WWDC22-10113) -- Reference Mode
23. **Make Your Mac App More Accessible** (WWDC25-229)
24. **Optimize SwiftUI Performance with Instruments** (WWDC25-306)
25. **Discover Metal 4** (WWDC25-205)
26. **Meet Transferable** (WWDC22-10062)
27. **Bring Multiple Windows to Your SwiftUI App** (WWDC22-10061)
28. **What's New in SwiftUI (2025)** (WWDC25-256)
29. **Simplify Distribution in Xcode and Xcode Cloud** (WWDC23-10224)
30. **What's New in Vision** (WWDC22-10024) -- Optical flow
