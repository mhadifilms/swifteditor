# 08 - macOS NLE UI/UX Design & Panel System

Comprehensive research on professional NLE (Non-Linear Editor) user interface design, panel layout architecture, workspace systems, keyboard shortcuts, video scopes, and Liquid Glass integration for building a world-class native macOS video editor in SwiftUI + AppKit.

---

## Table of Contents

1. [Panel Layout Architecture](#1-panel-layout-architecture)
2. [Workspace Presets (Pages)](#2-workspace-presets-pages)
3. [Viewer Controls & Transport Bar](#3-viewer-controls--transport-bar)
4. [Inspector Panel](#4-inspector-panel)
5. [Effects Browser](#5-effects-browser)
6. [Video Scopes Implementation](#6-video-scopes-implementation)
7. [Complete Keyboard Shortcut Map](#7-complete-keyboard-shortcut-map)
8. [macOS Menu Bar Structure](#8-macos-menu-bar-structure)
9. [Resizable Panel Implementation in SwiftUI/AppKit](#9-resizable-panel-implementation-in-swiftuiappkit)
10. [Liquid Glass Integration for NLE Chrome](#10-liquid-glass-integration-for-nle-chrome)
11. [SwiftUI Code for Panel System](#11-swiftui-code-for-panel-system)
12. [Workspace Switching Architecture](#12-workspace-switching-architecture)

---

## 1. Panel Layout Architecture

### Reference: DaVinci Resolve Edit Page Layout

The industry standard for NLE panel layout follows a modular approach with these core zones:

```
+-------------------------------------------------------------------+
|  Menu Bar                                                          |
+----------+----------------------------+---------------------------+
| Media    |   Source Viewer   |   Timeline Viewer   |  Inspector    |
| Pool     |                  |                     |  Panel        |
| / Effects|                  |                     |               |
| Browser  |                  |                     |               |
+----------+------------------+---------------------+---------------+
|                          Timeline                                  |
|  [Track Headers] [Clip Track 1 --------------------------------]  |
|                  [Audio Track 1 --------------------------------]  |
|                  [Audio Track 2 --------------------------------]  |
+-------------------------------------------------------------------+
|  Transport Bar  |  Timecode  |  Zoom Controls  |  Workspace Tabs  |
+-------------------------------------------------------------------+
```

### Core Panel Zones

| Zone | Position | Purpose |
|------|----------|---------|
| **Media Browser** | Top-left | Import, organize, browse project media assets in hierarchical bins |
| **Source Viewer** | Top-center-left | Preview individual clips before adding to timeline, set in/out points |
| **Timeline Viewer** (Program Monitor) | Top-center-right | Display timeline output at the current playhead position |
| **Inspector** | Top-right | Detailed control over selected clip/effect properties |
| **Timeline** | Bottom-center | Heart of editing -- assemble video/audio tracks, trim, arrange clips |
| **Effects Library** | Toggled panel, typically left | Browse transitions, effects, titles, generators, filters |
| **Toolbar** | Above timeline | Editing tools: selection, trim, blade, dynamic trim, etc. |

### Panel Visibility Rules

- Panels should be independently togglable (show/hide)
- When Inspector opens, Source + Timeline viewers may switch to single-viewer mode
- Media Pool and Effects Library can share the same panel slot (tabbed)
- Inspector can be collapsed to give more viewer space
- Timeline always visible -- it is the anchor panel

### Panel Sizing Guidelines

| Panel | Min Width | Default Width | Collapsible |
|-------|-----------|---------------|-------------|
| Media Browser / Effects | 200pt | 300pt | Yes |
| Source Viewer | 320pt | Flexible | Yes (single-viewer mode) |
| Timeline Viewer | 320pt | Flexible | No |
| Inspector | 250pt | 300pt | Yes |
| Timeline | Full width | Full width, 40% height | Resizable vertically |

---

## 2. Workspace Presets (Pages)

### DaVinci Resolve Page Model

DaVinci Resolve organizes its entire UI into 7 specialized workspace **pages**, each tailored for a stage of post-production:

| Page | Purpose | Key Panels |
|------|---------|------------|
| **Media** | Import, organize, manage all project media | Media Storage browser, metadata editor, viewer |
| **Cut** | Fast assembly editing for quick turnarounds | Dual timeline (overview + detail), source tape, sync bin |
| **Edit** | Full-featured editing with dual viewers | Media Pool, Source Viewer, Timeline Viewer, Inspector, Effects Library, Timeline |
| **Fusion** | Node-based visual effects & compositing | Node editor, viewer, spline editor, keyframes |
| **Color** | Professional color grading | Color Wheels, Curves, Node Editor, Scopes, Gallery, Qualifier |
| **Fairlight** | Professional audio post-production | Mixer, Waveform editor, EQ, Effects, Meters, Monitoring |
| **Deliver** | Encoding, export, render queue | Render Settings, Format/Codec selector, Output queue, Timeline preview |

### Recommended Workspace Pages for Our NLE

For a modern macOS NLE, implement these workspace pages:

1. **Edit** -- Primary editing workspace (dual viewers, timeline, media pool, inspector)
2. **Color** -- Color correction/grading (scopes, wheels, curves, node editor)
3. **Audio** -- Audio mixing and sweetening (mixer, EQ, meters, waveform editing)
4. **Effects** -- Motion graphics, compositing, text (node/layer-based effects editor)
5. **Deliver** -- Export and render queue (format/codec settings, batch rendering)

### Workspace Switching Design

- Page tabs at bottom of window (like DaVinci Resolve) or in toolbar
- Each page stores its own panel layout state independently
- Switching pages animates panel transitions smoothly
- Page state persists across switches (timeline position, selections, etc.)
- Keyboard shortcut for each page: Shift+1 through Shift+5
- Liquid Glass styling for workspace tab bar (see Section 10)

---

## 3. Viewer Controls & Transport Bar

### Dual Viewer Architecture

The **Source Viewer** and **Timeline Viewer** (Program Monitor) are the two primary viewing surfaces:

**Source Viewer:**
- Previews individual clips from the media pool
- Allows setting In (I) and Out (O) points before editing to timeline
- Shows clip name, duration, and timecode
- Can display audio waveforms for audio-only clips

**Timeline Viewer (Program Monitor):**
- Shows the composite output of the timeline at the playhead position
- Displays all layers, effects, and transitions as rendered
- Primary output for monitoring final result

### Viewer Overlay Controls

| Overlay | Purpose |
|---------|---------|
| **Timecode** | Current frame timecode display (HH:MM:SS:FF) |
| **Title Safe / Action Safe** | 80% / 90% guides for broadcast compliance |
| **Grid** | Rule of thirds, center crosshair |
| **Zoom Controls** | Fit, 25%, 50%, 100%, 200% |
| **Audio Meters** | Mini audio level meters overlaid |
| **Clip Name** | Current clip name at bottom |

### Transport Bar Controls

Standard transport bar positioned below the viewer:

```
[<<] [<] [Stop] [Play/Pause] [>] [>>]  |  [Mark In] [Mark Out]  |  [Timecode Display]
 |    |     |       |          |    |
 Go   Step  Stop   Play      Step  Go
 Start Back         /Pause   Fwd   End
```

**Standard Transport Controls:**

| Control | Icon | Key | Function |
|---------|------|-----|----------|
| Go to Start | `<<` | Home | Jump to beginning of timeline/clip |
| Step Back | `<` | Left Arrow | Move one frame backward |
| Stop | Square | K | Stop playback |
| Play/Pause | Triangle/Bars | Space | Toggle playback |
| Step Forward | `>` | Right Arrow | Move one frame forward |
| Go to End | `>>` | End | Jump to end of timeline/clip |
| Loop | Circular arrow | Cmd+/ | Toggle loop playback |
| Mark In | `[` bracket | I | Set in point |
| Mark Out | `]` bracket | O | Set out point |
| Play In to Out | Play icon with brackets | / (slash) | Play between in/out points |

### JKL Playback System

The JKL system is the industry-standard for variable-speed playback:

| Key | Action |
|-----|--------|
| **J** | Play reverse at 1x. Press again: 2x, 4x, 8x reverse |
| **K** | Pause/Stop playback |
| **L** | Play forward at 1x. Press again: 2x, 4x, 8x forward |
| **K+J** | Slow reverse (1/4 speed or frame-by-frame) |
| **K+L** | Slow forward (1/4 speed or frame-by-frame) |
| **Shift+J** | Step back while holding |
| **Shift+L** | Step forward while holding |

---

## 4. Inspector Panel

### Inspector Tab Structure

The Inspector provides detailed property editing for the selected clip or effect. Organized into tabs:

#### Video Tab
| Property | Type | Range | Keyframeable |
|----------|------|-------|-------------|
| **Transform** | | | |
| Position X | Float | -infinity to +infinity | Yes |
| Position Y | Float | -infinity to +infinity | Yes |
| Scale / Zoom X | Float | 0% to 1000%+ | Yes |
| Scale / Zoom Y | Float | 0% to 1000%+ | Yes |
| Rotation | Float | -360 to 360 (continuous) | Yes |
| Anchor Point X | Float | Relative to clip | Yes |
| Anchor Point Y | Float | Relative to clip | Yes |
| **Cropping** | | | |
| Crop Left | Float | 0 to 100% | Yes |
| Crop Right | Float | 0 to 100% | Yes |
| Crop Top | Float | 0 to 100% | Yes |
| Crop Bottom | Float | 0 to 100% | Yes |
| **Compositing** | | | |
| Opacity | Float | 0% to 100% | Yes |
| Blend Mode | Enum | Normal, Add, Multiply, Screen, Overlay, etc. | No |
| **Speed** | | | |
| Speed | Float | -1000% to 1000% | No |
| Reverse | Bool | On/Off | No |
| Frame Blending | Enum | None, Frame Blend, Optical Flow | No |

#### Audio Tab
| Property | Type | Range | Keyframeable |
|----------|------|-------|-------------|
| Volume | Float | -infinity dB to +12 dB | Yes |
| Pan | Float | -100 (L) to +100 (R) | Yes |
| Pitch | Float | Semitones | Yes |
| EQ | Multi-band | Per-band controls | Yes |
| Channel Config | Enum | Stereo, Mono, 5.1, 7.1 | No |

#### Effects Tab
- Lists all applied effects on the selected clip
- Each effect expandable to show its parameters
- Drag to reorder effects (processing order matters)
- Enable/disable toggle per effect
- Keyframe button per parameter

#### Metadata Tab
- Clip name, file path, codec, resolution, frame rate, duration
- Color space, HDR metadata
- Audio format, sample rate, channels
- Custom user metadata fields

### Inspector UI Design

```
+----------------------------------+
| Inspector                    [x] |
+----------------------------------+
| [Video] [Audio] [Effects] [Meta] |
+----------------------------------+
| Transform           [Keyframe]   |
|   Position X  [====|====]  0.0   |
|   Position Y  [====|====]  0.0   |
|   Scale       [=======|=]  100%  |
|   Rotation    [====|====]  0.0   |
|   Anchor Pt   [====|====]  0.0   |
+----------------------------------+
| Cropping              [Keyframe] |
|   Left        [|===========]  0  |
|   Right       [|===========]  0  |
|   Top         [|===========]  0  |
|   Bottom      [|===========]  0  |
+----------------------------------+
| Compositing                      |
|   Opacity     [========|=] 100%  |
|   Blend Mode  [Normal      v]   |
+----------------------------------+
```

---

## 5. Effects Browser

### Effect Categories

Organize effects in a hierarchical browser with search:

```
Effects Browser
+----------------------------------+
| [Search...                     ] |
+----------------------------------+
| > Video Transitions              |
|   > Dissolve (Cross Dissolve,    |
|     Additive Dissolve, Dip to    |
|     Color...)                    |
|   > Wipe (Barn Door, Checker,    |
|     Clock, Edge, Inset...)       |
|   > Slide (Push, Slide, Split)   |
|   > 3D (Cube Spin, Page Curl...) |
| > Video Effects                  |
|   > Color Correction             |
|   > Blur (Gaussian, Directional, |
|     Radial, Zoom)                |
|   > Sharpen                      |
|   > Stylize (Glow, Emboss,       |
|     Posterize, Halftone)         |
|   > Distortion (Lens, Ripple,    |
|     Spherize, Twirl)             |
|   > Keying (Chroma Key, Luma     |
|     Key, Difference Matte)       |
| > Audio Transitions              |
|   > Crossfade (+3dB, -3dB, 0dB)  |
| > Audio Effects                  |
|   > EQ, Compressor, Reverb,      |
|     Delay, Noise Reduction       |
| > Titles                         |
|   > Lower Thirds                 |
|   > Full Screen                  |
|   > Scrolling                    |
|   > 3D Titles                    |
| > Generators                     |
|   > Solid Color, Gradient,       |
|     Noise, Bars & Tone,          |
|     Countdown                    |
+----------------------------------+
```

### Effects Browser Features

- **Search**: Real-time filtering by name across all categories
- **Favorites**: Star/bookmark frequently used effects
- **Preview**: Hover to see animated thumbnail preview
- **Drag-and-drop**: Drag effect to timeline clip or between clips (for transitions)
- **Info panel**: Description, parameter count, GPU/CPU requirements
- **Recently used**: Quick access section at top
- **Third-party**: Support for plugin effects (OFX, FxPlug)

---

## 6. Video Scopes Implementation

### Scope Types

#### Waveform Monitor
- **What it shows**: Brightness (luminance) distribution across the image horizontally
- **Y-axis**: 0 (black) at bottom to 100 IRE / 1023 (white) at top
- **X-axis**: Left-to-right corresponds to the image left-to-right
- **Usage**: Check exposure, ensure no clipping above 100 or below 0
- **Display modes**: Luma only, RGB overlay, RGB parade

#### RGB Parade
- **What it shows**: Separate waveform for Red, Green, and Blue channels side-by-side
- **Layout**: Three columns (R, G, B) each showing that channel's waveform
- **Usage**: Color balance correction -- matching R/G/B levels means neutral balance
- **Key indicators**: If blacks are off-center in one channel, there's a color cast

#### Vectorscope
- **What it shows**: Color saturation and hue on a circular display
- **Center**: Zero saturation (grayscale)
- **Edges**: Maximum saturation
- **Targets**: SMPTE color bar targets at R, Mg, B, Cy, G, Yl positions
- **Usage**: White balance verification, skin tone line (roughly between R and Yl)
- **Display modes**: Normal, zoom (2x, 4x for fine adjustment)

#### Histogram
- **What it shows**: Pixel distribution from dark (left) to bright (right)
- **Height**: Number of pixels at each brightness level
- **Modes**: Luma, RGB overlay, individual R/G/B channels
- **Usage**: Quick exposure check, identify clipping, verify contrast range

### GPU Implementation Strategy (Metal Compute Shaders)

Scopes should be rendered on the GPU using Metal compute shaders for real-time performance:

```
Input Video Frame (MTLTexture)
        |
        v
[Metal Compute Shader: Scope Calculation]
        |
        +--- Waveform: For each pixel column, scatter Y-position based on luma
        +--- Parade: Same as waveform but per R/G/B channel in separate columns
        +--- Vectorscope: Convert each pixel to polar coords on color wheel
        +--- Histogram: Atomic increment bins based on luminance/channel
        |
        v
[Accumulation Buffer (MTLBuffer or MTLTexture)]
        |
        v
[Metal Render Pass: Scope Visualization]
        |
        +--- Map accumulation to color (log scale for density)
        +--- Apply scope graticule overlay
        +--- Render to scope view
```

#### Key Technical Considerations

1. **Atomic Operations**: Use `atomic_fetch_add_explicit` in compute shaders for histogram/waveform accumulation
2. **Two-pass approach**:
   - Pass 1: Compute shader accumulates pixel data into bins
   - Pass 2: Render shader visualizes the accumulated data with color mapping
3. **Non-linear alpha mapping**: Apply logarithmic or sqrt mapping to accumulated values for better visual density representation
4. **Performance on Apple GPUs**:
   - Avoid rendering millions of single-pixel points with alpha blending (tile capacity overflow)
   - Prefer compute shader accumulation into a buffer, then render the buffer
   - Apple GPUs rasterize in 2x2 quads -- single pixel points waste 75% of shader invocations
5. **Resolution**: Scope display at 256x256 or 512x512 is sufficient
6. **Update rate**: Match viewer frame rate, or allow user to set scope update rate (every frame, every 2nd frame, etc.)

### Scope Layout in Color Workspace

```
+----------------------------------------+
|  Viewer (large)    |  Scopes           |
|                    |  [Waveform   ]    |
|                    |  [Vectorscope]    |
|                    |  [Histogram  ]    |
+--------------------+-------------------+
|  Color Wheels / Curves / Node Editor   |
+----------------------------------------+
```

---

## 7. Complete Keyboard Shortcut Map

### Global / Application-Wide

| Shortcut | Action |
|----------|--------|
| Cmd+N | New Project |
| Cmd+O | Open Project |
| Cmd+S | Save Project |
| Cmd+Shift+S | Save Project As |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+C | Copy |
| Cmd+V | Paste |
| Cmd+X | Cut |
| Cmd+A | Select All |
| Cmd+, | Settings / Preferences |
| Cmd+Q | Quit Application |
| Cmd+W | Close Window |
| Delete/Backspace | Delete Selected |

### Workspace / Page Switching

| Shortcut | Action |
|----------|--------|
| Shift+1 | Switch to Edit workspace |
| Shift+2 | Switch to Color workspace |
| Shift+3 | Switch to Audio workspace |
| Shift+4 | Switch to Effects workspace |
| Shift+5 | Switch to Deliver workspace |

### Playback & Transport (JKL System)

| Shortcut | Action |
|----------|--------|
| Space | Play / Pause |
| J | Play Reverse (1x, 2x, 4x, 8x with repeated presses) |
| K | Stop / Pause |
| L | Play Forward (1x, 2x, 4x, 8x with repeated presses) |
| K+J | Slow Reverse / Frame step reverse |
| K+L | Slow Forward / Frame step forward |
| Left Arrow | Step 1 frame back |
| Right Arrow | Step 1 frame forward |
| Shift+Left | Step back 1 second (or user-defined multi-frame) |
| Shift+Right | Step forward 1 second |
| Home / Fn+Left | Go to Start |
| End / Fn+Right | Go to End |
| Up Arrow | Go to Previous Edit Point |
| Down Arrow | Go to Next Edit Point |
| / (Slash) | Play In to Out |
| Cmd+/ | Toggle Loop Playback |

### Marking

| Shortcut | Action |
|----------|--------|
| I | Set In Point |
| O | Set Out Point |
| Option+I | Clear In Point |
| Option+O | Clear Out Point |
| Option+X | Clear Both In and Out |
| X | Mark Clip (auto In/Out around selected clip) |
| Shift+I | Go to In Point |
| Shift+O | Go to Out Point |
| M | Add Marker |
| Shift+M | Add Marker and open editor |
| Cmd+M | Modify Marker |

### Editing Operations (Following Final Cut Pro / DaVinci Resolve Conventions)

| Shortcut | Action | Description |
|----------|--------|-------------|
| W | Insert Edit | Insert at playhead, pushing downstream clips |
| D | Overwrite Edit | Overwrite at playhead, replacing existing |
| E | Append to End | Add clip to end of timeline |
| Q | Connect Edit | Place clip above primary storyline (connected) |
| Shift+D | Backtime Overwrite | Overwrite ending at playhead position |
| Shift+Q | Backtime Connect | Connect ending at playhead position |
| Option+W | Insert Gap | Insert empty gap at playhead |
| Cmd+B | Blade / Razor Cut | Split clip at playhead |
| Cmd+Shift+B | Blade All | Split all tracks at playhead |

### Timeline Navigation & Selection

| Shortcut | Action |
|----------|--------|
| A | Selection Tool (Arrow) |
| T | Trim Tool |
| B | Blade Tool |
| P | Position Tool |
| R | Range Selection |
| Z | Zoom Tool |
| H | Hand / Scroll Tool |
| N | Toggle Snapping |
| V | Toggle Clip Enable/Disable |
| Cmd+= | Zoom In (Timeline) |
| Cmd+- | Zoom Out (Timeline) |
| Shift+Z | Zoom to Fit (show entire timeline) |
| Option+Cmd+Up | Move selected clip up one track |
| Option+Cmd+Down | Move selected clip down one track |
| Cmd+] | Nudge clip right (1 frame) |
| Cmd+[ | Nudge clip left (1 frame) |

### Trimming

| Shortcut | Action |
|----------|--------|
| , (Comma) | Trim left 1 frame (ripple/roll depending on mode) |
| . (Period) | Trim right 1 frame |
| Shift+, | Trim left multi-frame (5 or 10 frames) |
| Shift+. | Trim right multi-frame |
| Shift+[ | Trim Start (trim clip start to playhead) |
| Shift+] | Trim End (trim clip end to playhead) |
| U | Toggle Trim mode (Ripple / Roll / Slip / Slide) |
| S | Toggle Slip/Slide |

### Panel Visibility

| Shortcut | Action |
|----------|--------|
| Cmd+1 | Toggle Media Browser |
| Cmd+2 | Toggle Effects Browser |
| Cmd+3 | Toggle Inspector |
| Cmd+4 | Toggle Audio Meters |
| Cmd+5 | Toggle Video Scopes |
| Cmd+6 | Toggle Mixer |
| Option+Cmd+1 | Single Viewer Mode |
| Option+Cmd+2 | Dual Viewer Mode |
| Cmd+Shift+F | Toggle Full Screen Viewer |

### Color Workspace

| Shortcut | Action |
|----------|--------|
| Option+S | Enable/Disable Selected Node |
| Option+D | Add Serial Node |
| Option+P | Add Parallel Node |
| Option+L | Add Layer Node |
| Cmd+D | Copy Grade to Next Clip |
| Option+Shift+C | Copy Color Grade |
| Option+Shift+V | Paste Color Grade |
| Ctrl+Shift+W | Toggle Waveform Scope |
| Ctrl+Shift+V | Toggle Vectorscope |
| Ctrl+Shift+H | Toggle Histogram |
| Ctrl+Shift+P | Toggle Parade |

### Audio Workspace

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+A | Select All Audio Tracks |
| Option+S | Solo Selected Track |
| Option+M | Mute Selected Track |
| Cmd+L | Link/Unlink Audio and Video |

---

## 8. macOS Menu Bar Structure

### Recommended Menu Structure for a Professional NLE

Following Apple's macOS conventions and professional NLE standards:

```
[App Name] | File | Edit | Mark | Clip | Timeline | View | Window | Help
```

#### App Menu (Application Name)
- About [App Name]
- Settings... (Cmd+,)
- Keyboard Customization... (Option+Cmd+K)
- ---
- Services >
- Hide [App Name] (Cmd+H)
- Hide Others (Option+Cmd+H)
- Show All
- ---
- Quit [App Name] (Cmd+Q)

#### File Menu
- New Project (Cmd+N)
- Open Project... (Cmd+O)
- Open Recent >
- ---
- Close Window (Cmd+W)
- Save (Cmd+S)
- Save As... (Cmd+Shift+S)
- Revert to Saved
- ---
- Import Media... (Cmd+I)
- Import Timeline... (Cmd+Shift+I)
- ---
- Export > (submenu: Final Cut XML, AAF, EDL)
- ---
- Project Settings... (Cmd+Shift+,)

#### Edit Menu
- Undo (Cmd+Z)
- Redo (Cmd+Shift+Z)
- ---
- Cut (Cmd+X)
- Copy (Cmd+C)
- Paste (Cmd+V)
- Paste Attributes... (Option+Cmd+V)
- ---
- Select All (Cmd+A)
- Deselect All (Cmd+Shift+A)
- ---
- Delete (Delete)
- Ripple Delete (Shift+Delete)
- ---
- Find... (Cmd+F)

#### Mark Menu
- Set In Point (I)
- Set Out Point (O)
- Clear In Point (Option+I)
- Clear Out Point (Option+O)
- Clear In and Out (Option+X)
- Mark Clip (X)
- ---
- Add Marker (M)
- Add and Edit Marker (Shift+M)
- Delete Marker
- Delete All Markers
- Modify Marker... (Cmd+M)
- ---
- Go to In Point (Shift+I)
- Go to Out Point (Shift+O)
- Go to Next Marker (Ctrl+')
- Go to Previous Marker (Ctrl+;)

#### Clip Menu
- Solo (Option+S)
- Enable/Disable (V)
- ---
- Speed > (Normal, Fast, Slow, Reverse, Custom...)
- Retime Controls (Cmd+R)
- ---
- Blade (Cmd+B)
- Blade All (Cmd+Shift+B)
- ---
- Detach Audio (Cmd+Shift+S)
- Expand Audio
- ---
- Apply Effect >
- Reset All Effects
- ---
- Open in Viewer

#### Timeline Menu
- Insert Edit (W)
- Overwrite Edit (D)
- Append to End (E)
- Connect Edit (Q)
- ---
- Add Track > (Video Track, Audio Track, Subtitle Track)
- Delete Track >
- ---
- Toggle Snapping (N)
- ---
- Render > (Render Selection, Render All, Background Render)

#### View Menu
- Zoom In (Cmd+=)
- Zoom Out (Cmd+-)
- Zoom to Fit (Shift+Z)
- ---
- Show/Hide Media Browser (Cmd+1)
- Show/Hide Effects Browser (Cmd+2)
- Show/Hide Inspector (Cmd+3)
- Show/Hide Audio Meters (Cmd+4)
- Show/Hide Video Scopes (Cmd+5)
- ---
- Viewer Display >
  - Title Safe
  - Action Safe
  - Grid Overlay
  - Timecode Overlay
- ---
- Single Viewer (Option+Cmd+1)
- Dual Viewer (Option+Cmd+2)
- ---
- Workspaces >
  - Edit (Shift+1)
  - Color (Shift+2)
  - Audio (Shift+3)
  - Effects (Shift+4)
  - Deliver (Shift+5)
  - ---
  - Save Workspace Layout...
  - Reset Workspace Layout

#### Window Menu
- Minimize (Cmd+M)
- Zoom
- ---
- Full Screen Viewer (Cmd+Shift+F)
- Enter Full Screen (Ctrl+Cmd+F)
- ---
- Bring All to Front

#### Help Menu
- [App Name] Help
- Keyboard Shortcuts Reference
- What's New
- ---
- Release Notes

---

## 9. Resizable Panel Implementation in SwiftUI/AppKit

### Architecture: Hybrid SwiftUI + AppKit Approach

For a professional NLE, a hybrid approach is recommended:

- **AppKit** (`NSSplitViewController`) for the outer frame and panel management -- provides precise control over resizing, collapsing, minimum sizes, and auto-save of layout state
- **SwiftUI** for individual panel content -- provides modern declarative UI, easy state management, and Liquid Glass integration

### Why Not Pure SwiftUI?

- `HSplitView` and `VSplitView` have limited control over divider appearance and behavior
- `NavigationSplitView` supports max 3 columns, not sufficient for 4+ panel NLE layout
- No built-in support for panel collapsing with animation in SwiftUI split views
- No programmatic control over split positions in SwiftUI
- AppKit `NSSplitViewController` auto-saves layout state, has full delegate API

### Panel Architecture

```swift
// Top-level window structure using NSSplitViewController

// Vertical split: [Top Panels] / [Timeline]
//   Top Panels = Horizontal split: [Browser | Viewers | Inspector]
//     Viewers = Vertical or Horizontal split: [Source | Program]

MainSplitViewController (vertical)
├── TopRegionSplitViewController (horizontal)
│   ├── BrowserPanel (NSSplitViewItem, sidebar behavior)
│   │   └── TabView: [Media Pool, Effects Browser]
│   ├── ViewerRegionSplitViewController (horizontal)
│   │   ├── SourceViewerPanel
│   │   └── ProgramViewerPanel
│   └── InspectorPanel (NSSplitViewItem, inspector behavior)
│       └── TabView: [Video, Audio, Effects, Metadata]
└── TimelinePanel (NSSplitViewItem)
    └── TimelineView (custom AppKit/SwiftUI)
```

### NSSplitViewController with SwiftUI Hosting

```swift
import AppKit
import SwiftUI

class NLEMainSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure the main vertical split: top panels | timeline
        let topRegion = NLETopRegionSplitViewController()
        let timelinePanel = NSHostingController(rootView: TimelinePanelView())

        let topItem = NSSplitViewItem(viewController: topRegion)
        topItem.minimumThickness = 300
        topItem.canCollapse = false

        let timelineItem = NSSplitViewItem(viewController: timelinePanel)
        timelineItem.minimumThickness = 200
        timelineItem.canCollapse = false

        splitView.isVertical = false // vertical stacking (top/bottom)
        splitView.dividerStyle = .thin

        addSplitViewItem(topItem)
        addSplitViewItem(timelineItem)

        // Auto-save layout
        splitView.autosaveName = "NLEMainSplit"
    }
}

class NLETopRegionSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Browser (sidebar behavior -- collapsible from left)
        let browserVC = NSHostingController(rootView: MediaBrowserView())
        let browserItem = NSSplitViewItem(sidebarWithViewController: browserVC)
        browserItem.minimumThickness = 200
        browserItem.maximumThickness = 400
        browserItem.canCollapse = true
        browserItem.allowsFullHeightLayout = true

        // Viewers region
        let viewersVC = NLEViewersSplitViewController()
        let viewersItem = NSSplitViewItem(viewController: viewersVC)
        viewersItem.minimumThickness = 500
        viewersItem.canCollapse = false

        // Inspector (collapsible from right)
        let inspectorVC = NSHostingController(rootView: InspectorPanelView())
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorVC)
        inspectorItem.minimumThickness = 250
        inspectorItem.maximumThickness = 450
        inspectorItem.canCollapse = true
        inspectorItem.isCollapsed = false

        splitView.isVertical = true // horizontal layout (side by side)
        splitView.dividerStyle = .thin

        addSplitViewItem(browserItem)
        addSplitViewItem(viewersItem)
        addSplitViewItem(inspectorItem)

        splitView.autosaveName = "NLETopRegionSplit"
    }
}

class NLEViewersSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let sourceVC = NSHostingController(rootView: SourceViewerView())
        let sourceItem = NSSplitViewItem(viewController: sourceVC)
        sourceItem.minimumThickness = 320
        sourceItem.canCollapse = true

        let programVC = NSHostingController(rootView: ProgramViewerView())
        let programItem = NSSplitViewItem(viewController: programVC)
        programItem.minimumThickness = 320
        programItem.canCollapse = false

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        addSplitViewItem(sourceItem)
        addSplitViewItem(programItem)

        splitView.autosaveName = "NLEViewersSplit"
    }
}
```

### Third-Party Library: stevengharris/SplitView

For simpler panel arrangements or SwiftUI-only panels, the [SplitView](https://github.com/stevengharris/SplitView) library (v3.5.3) provides:

- Horizontal or vertical splits with draggable splitter
- Min/max fraction constraints per side
- Drag-to-hide (collapse) behavior
- macOS cursor changes on hover over splitter
- Nested split view composition
- Programmatic show/hide

```swift
import SplitView

struct EditWorkspaceView: View {
    var body: some View {
        // Vertical: top panels over timeline
        VSplit(top: {
            // Horizontal: browser | viewers | inspector
            HSplit(left: {
                MediaBrowserView()
            }, right: {
                HSplit(left: {
                    ViewersRegionView()
                }, right: {
                    InspectorPanelView()
                })
                .fraction(0.75) // viewers get 75%, inspector 25%
            })
            .fraction(0.2) // browser gets 20%, rest 80%
        }, bottom: {
            TimelineView()
        })
        .fraction(0.55) // top panels 55%, timeline 45%
    }
}
```

---

## 10. Liquid Glass Integration for NLE Chrome

### Design Principles for NLE + Liquid Glass

Following Apple's Liquid Glass guidelines (macOS Tahoe 26+), here is how to apply the design system to a professional NLE:

#### Where to Use Liquid Glass in an NLE

| Element | Glass Treatment | Notes |
|---------|----------------|-------|
| **Toolbar** | Automatic (system) | Editing tools, workspace switcher. Recompile with Xcode 26 |
| **Sidebar** (Media Browser) | Automatic (system) | Translucent sidebar with ambient reflection |
| **Inspector panel header** | `.glassEffect(.regular)` | Tab bar for Video/Audio/Effects/Metadata |
| **Transport bar** | `.glassEffect(.regular)` | Play/stop/JKL controls floating over viewer |
| **Workspace page tabs** | `GlassEffectContainer` | Tab strip at bottom with morphing on switch |
| **Floating tool palettes** | `.glassEffect(.regular)` | Any detachable tool windows |
| **Panel headers/tabs** | `.glassEffect(.regular)` | Panel title bars with close/collapse buttons |
| **Scope overlays** (graticule) | `.glassEffect(.clear)` | Over video content, needs bold foreground |
| **Timeline ruler** | Subtle glass | Timecode ruler at top of timeline |
| **Audio meters** | No glass | Content -- show raw data |

#### Where NOT to Use Liquid Glass in an NLE

| Element | Reason |
|---------|--------|
| **Timeline tracks/clips** | Content layer -- clips are content, not navigation |
| **Viewer (video display)** | Content -- never obscure the video frame |
| **Waveform/Scope displays** | Content -- precision data visualization |
| **Effects parameter sliders** | Content controls -- glass adds visual noise to dense parameter UI |
| **Color wheels/curves** | Content controls -- precision tools need clear visibility |

### Liquid Glass Implementation Patterns

#### Workspace Tab Bar with Morphing

```swift
struct WorkspaceTabBar: View {
    @Binding var selectedWorkspace: Workspace
    @Namespace private var tabNamespace

    enum Workspace: String, CaseIterable {
        case edit = "Edit"
        case color = "Color"
        case audio = "Audio"
        case effects = "Effects"
        case deliver = "Deliver"

        var icon: String {
            switch self {
            case .edit: return "film"
            case .color: return "paintpalette"
            case .audio: return "speaker.wave.3"
            case .effects: return "sparkles"
            case .deliver: return "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Workspace.allCases, id: \.self) { workspace in
                    Button {
                        withAnimation(.bouncy(duration: 0.3)) {
                            selectedWorkspace = workspace
                        }
                    } label: {
                        Label(workspace.rawValue, systemImage: workspace.icon)
                            .font(.callout.weight(
                                selectedWorkspace == workspace ? .semibold : .regular
                            ))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID(workspace.rawValue, in: tabNamespace)
                }
            }
        }
    }
}
```

#### Transport Bar with Glass

```swift
struct TransportBar: View {
    @Namespace private var transportNamespace
    @ObservedObject var playbackState: PlaybackState

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                // Transport controls group
                HStack(spacing: 4) {
                    Button(action: { playbackState.goToStart() }) {
                        Image(systemName: "backward.end.fill")
                    }
                    .buttonStyle(.glass)

                    Button(action: { playbackState.stepBack() }) {
                        Image(systemName: "backward.frame.fill")
                    }
                    .buttonStyle(.glass)

                    Button(action: { playbackState.togglePlayPause() }) {
                        Image(systemName: playbackState.isPlaying
                              ? "pause.fill" : "play.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .glassEffectID("play", in: transportNamespace)

                    Button(action: { playbackState.stepForward() }) {
                        Image(systemName: "forward.frame.fill")
                    }
                    .buttonStyle(.glass)

                    Button(action: { playbackState.goToEnd() }) {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(.glass)
                }

                // Timecode display
                Text(playbackState.timecodeString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
```

#### Inspector Panel Header with Glass Tabs

```swift
struct InspectorHeader: View {
    @Binding var selectedTab: InspectorTab
    @Namespace private var inspectorNamespace

    enum InspectorTab: String, CaseIterable {
        case video = "Video"
        case audio = "Audio"
        case effects = "Effects"
        case metadata = "Info"

        var icon: String {
            switch self {
            case .video: return "video"
            case .audio: return "speaker.wave.2"
            case .effects: return "wand.and.stars"
            case .metadata: return "info.circle"
            }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.bouncy(duration: 0.25)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(selectedTab == tab ? .glassProminent : .glass)
                    .glassEffectID(tab.rawValue, in: inspectorNamespace)
                }
            }
        }
    }
}
```

---

## 11. SwiftUI Code for Panel System

### Complete Panel System Architecture

```swift
import SwiftUI

// MARK: - App Entry Point

@main
struct NLEApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            NLECommands()
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var currentWorkspace: Workspace = .edit
    @Published var panelVisibility = PanelVisibility()
    @Published var playbackState = PlaybackState()

    enum Workspace: String, CaseIterable, Identifiable {
        case edit, color, audio, effects, deliver
        var id: String { rawValue }
    }

    struct PanelVisibility {
        var mediaBrowser: Bool = true
        var inspector: Bool = true
        var sourceViewer: Bool = true  // false = single viewer mode
        var effectsBrowser: Bool = false
        var audioMeters: Bool = false
        var videoScopes: Bool = false
    }
}

class PlaybackState: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0

    var timecodeString: String {
        let totalFrames = Int(currentTime * 30) // assuming 30fps
        let hours = totalFrames / (30 * 60 * 60)
        let minutes = (totalFrames / (30 * 60)) % 60
        let seconds = (totalFrames / 30) % 60
        let frames = totalFrames % 30
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    func togglePlayPause() { isPlaying.toggle() }
    func goToStart() { currentTime = 0 }
    func goToEnd() { currentTime = duration }
    func stepBack() { currentTime = max(0, currentTime - 1.0/30.0) }
    func stepForward() { currentTime = min(duration, currentTime + 1.0/30.0) }
}

// MARK: - Content View (Workspace Router)

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Workspace content
            switch appState.currentWorkspace {
            case .edit:
                EditWorkspaceView()
            case .color:
                ColorWorkspaceView()
            case .audio:
                AudioWorkspaceView()
            case .effects:
                EffectsWorkspaceView()
            case .deliver:
                DeliverWorkspaceView()
            }

            // Workspace tab bar at bottom
            WorkspaceTabBar(selectedWorkspace: $appState.currentWorkspace)
                .padding(.vertical, 4)
        }
        .frame(minWidth: 1280, minHeight: 720)
    }
}

// MARK: - Edit Workspace (Primary Editing View)

struct EditWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VSplitView {
            // Top region: Browser | Viewers | Inspector
            HSplitView {
                // Left: Media Browser / Effects Browser
                if appState.panelVisibility.mediaBrowser {
                    MediaBrowserPanel()
                        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                }

                // Center: Viewer(s)
                ViewerRegion(
                    showSourceViewer: appState.panelVisibility.sourceViewer
                )
                .frame(minWidth: 500)

                // Right: Inspector
                if appState.panelVisibility.inspector {
                    InspectorPanel()
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 450)
                }
            }
            .frame(minHeight: 300)

            // Bottom: Timeline
            TimelinePanel()
                .frame(minHeight: 200)
        }
    }
}

// MARK: - Media Browser Panel

struct MediaBrowserPanel: View {
    @State private var selectedTab: BrowserTab = .media
    @State private var searchText = ""

    enum BrowserTab: String, CaseIterable {
        case media = "Media Pool"
        case effects = "Effects"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(BrowserTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            // Search bar
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            Divider()

            // Content
            switch selectedTab {
            case .media:
                MediaPoolView(searchText: searchText)
            case .effects:
                EffectsBrowserView(searchText: searchText)
            }
        }
        .background(.background)
    }
}

// MARK: - Viewer Region

struct ViewerRegion: View {
    let showSourceViewer: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if showSourceViewer {
                // Dual viewer mode
                HSplitView {
                    SourceViewerView()
                        .frame(minWidth: 320)
                    ProgramViewerView()
                        .frame(minWidth: 320)
                }
            } else {
                // Single viewer mode (program only)
                ProgramViewerView()
            }

            // Transport bar
            TransportBar(playbackState: appState.playbackState)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Source Viewer

struct SourceViewerView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Viewer header
            HStack {
                Text("Source")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // Viewer controls: fit, zoom, overlay toggles
                HStack(spacing: 4) {
                    Button(action: {}) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Video display area
            ZStack {
                Rectangle()
                    .fill(.black)
                    .aspectRatio(16/9, contentMode: .fit)

                // Timecode overlay
                VStack {
                    Spacer()
                    HStack {
                        Text("00:00:00:00")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        Spacer()
                    }
                    .padding(8)
                }
            }

            // Source scrubber
            Slider(value: .constant(0.0))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Program Viewer

struct ProgramViewerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Program")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ZStack {
                Rectangle()
                    .fill(.black)
                    .aspectRatio(16/9, contentMode: .fit)

                VStack {
                    Spacer()
                    HStack {
                        Text(appState.playbackState.timecodeString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
    }
}

// MARK: - Inspector Panel

struct InspectorPanel: View {
    @State private var selectedTab: InspectorTab = .video

    enum InspectorTab: String, CaseIterable {
        case video, audio, effects, info
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue.capitalized).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Content
            ScrollView {
                switch selectedTab {
                case .video:
                    VideoInspectorContent()
                case .audio:
                    AudioInspectorContent()
                case .effects:
                    EffectsInspectorContent()
                case .info:
                    MetadataInspectorContent()
                }
            }
        }
        .background(.background)
    }
}

struct VideoInspectorContent: View {
    @State private var positionX: Double = 0
    @State private var positionY: Double = 0
    @State private var scale: Double = 100
    @State private var rotation: Double = 0
    @State private var opacity: Double = 100
    @State private var blendMode: String = "Normal"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSection(title: "Transform") {
                InspectorSlider(label: "Position X", value: $positionX, range: -1920...1920)
                InspectorSlider(label: "Position Y", value: $positionY, range: -1080...1080)
                InspectorSlider(label: "Scale", value: $scale, range: 0...400, unit: "%")
                InspectorSlider(label: "Rotation", value: $rotation, range: -360...360, unit: "deg")
            }

            InspectorSection(title: "Compositing") {
                InspectorSlider(label: "Opacity", value: $opacity, range: 0...100, unit: "%")
                HStack {
                    Text("Blend Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $blendMode) {
                        Text("Normal").tag("Normal")
                        Text("Add").tag("Add")
                        Text("Multiply").tag("Multiply")
                        Text("Screen").tag("Screen")
                        Text("Overlay").tag("Overlay")
                    }
                    .frame(width: 120)
                }
            }
        }
        .padding(8)
    }
}

// MARK: - Inspector Reusable Components

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    // Keyframe button
                    Button(action: {}) {
                        Image(systemName: "diamond")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 4)
            }
        }
    }
}

struct InspectorSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    var unit: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Slider(value: $value, in: range)
                .controlSize(.small)

            TextField("", value: $value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .frame(width: 50)

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Timeline Panel

struct TimelinePanel: View {
    var body: some View {
        VStack(spacing: 0) {
            // Timeline toolbar
            HStack(spacing: 12) {
                // Tool selector
                HStack(spacing: 2) {
                    ToolButton(icon: "arrow.uturn.left", tooltip: "Selection (A)")
                    ToolButton(icon: "scissors", tooltip: "Blade (B)")
                    ToolButton(icon: "arrow.left.and.right", tooltip: "Trim (T)")
                }

                Spacer()

                // Snapping toggle
                Toggle(isOn: .constant(true)) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .toggleStyle(.button)
                .controlSize(.small)

                // Zoom controls
                HStack(spacing: 4) {
                    Button(action: {}) { Image(systemName: "minus.magnifyingglass") }
                    Slider(value: .constant(0.5))
                        .frame(width: 100)
                    Button(action: {}) { Image(systemName: "plus.magnifyingglass") }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Timeline ruler + tracks
            VStack(spacing: 0) {
                // Ruler
                TimelineRulerView()
                    .frame(height: 24)

                // Tracks area
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 1) {
                        TimelineTrackView(name: "V1", type: .video)
                        TimelineTrackView(name: "V2", type: .video)
                        TimelineTrackView(name: "A1", type: .audio)
                        TimelineTrackView(name: "A2", type: .audio)
                    }
                }
            }
        }
        .background(.background)
    }
}

struct ToolButton: View {
    let icon: String
    let tooltip: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(tooltip)
    }
}

struct TimelineRulerView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.bar)
                // Tick marks and timecodes would be drawn here
                // using Canvas or custom drawing
            }
        }
    }
}

struct TimelineTrackView: View {
    let name: String
    let type: TrackType

    enum TrackType {
        case video, audio
    }

    var body: some View {
        HStack(spacing: 0) {
            // Track header
            HStack {
                Text(name)
                    .font(.caption.weight(.medium))
                Spacer()
                // Track controls: mute, solo, lock
                HStack(spacing: 2) {
                    Button(action: {}) { Image(systemName: "speaker.wave.2") }
                    Button(action: {}) { Image(systemName: "lock.open") }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
            .frame(width: 120)
            .padding(.horizontal, 4)
            .background(.bar)

            // Track content area
            Rectangle()
                .fill(type == .video
                      ? Color.blue.opacity(0.1)
                      : Color.green.opacity(0.1))
        }
        .frame(height: type == .video ? 60 : 40)
    }
}

// MARK: - Placeholder Panel Views

struct MediaPoolView: View {
    let searchText: String
    var body: some View {
        List {
            Label("Project Media", systemImage: "folder")
            Label("Footage", systemImage: "film")
            Label("Audio", systemImage: "music.note")
            Label("Graphics", systemImage: "photo")
        }
        .listStyle(.sidebar)
    }
}

struct EffectsBrowserView: View {
    let searchText: String
    var body: some View {
        List {
            Section("Video Transitions") {
                Label("Cross Dissolve", systemImage: "rectangle.on.rectangle")
                Label("Wipe", systemImage: "arrow.right.square")
            }
            Section("Video Effects") {
                Label("Blur", systemImage: "aqi.medium")
                Label("Color Correction", systemImage: "paintpalette")
            }
            Section("Titles") {
                Label("Basic Title", systemImage: "textformat")
                Label("Lower Third", systemImage: "text.below.photo")
            }
        }
        .listStyle(.sidebar)
    }
}

struct AudioInspectorContent: View {
    @State private var volume: Double = 0
    @State private var pan: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSection(title: "Audio") {
                InspectorSlider(label: "Volume", value: $volume, range: -96...12, unit: "dB")
                InspectorSlider(label: "Pan", value: $pan, range: -100...100)
            }
        }
        .padding(8)
    }
}

struct EffectsInspectorContent: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("No effects applied")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}

struct MetadataInspectorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                MetadataRow(label: "Name", value: "Clip_001.mov")
                MetadataRow(label: "Resolution", value: "3840 x 2160")
                MetadataRow(label: "Frame Rate", value: "30 fps")
                MetadataRow(label: "Codec", value: "H.265")
                MetadataRow(label: "Duration", value: "00:02:30:15")
                MetadataRow(label: "Color Space", value: "Rec. 709")
            }
        }
        .padding(8)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Color Workspace (Placeholder)

struct ColorWorkspaceView: View {
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Viewer
                Rectangle()
                    .fill(.black)
                    .overlay(Text("Color Viewer").foregroundStyle(.white))

                // Scopes
                VStack {
                    Text("Video Scopes")
                        .font(.caption.weight(.semibold))
                    Rectangle()
                        .fill(.black)
                        .overlay(Text("Waveform").foregroundStyle(.green))
                    Rectangle()
                        .fill(.black)
                        .overlay(Text("Vectorscope").foregroundStyle(.green))
                }
                .frame(minWidth: 250)
            }

            // Color controls (wheels, curves, node editor)
            HSplitView {
                // Color Wheels
                HStack(spacing: 20) {
                    ColorWheelPlaceholder(title: "Lift")
                    ColorWheelPlaceholder(title: "Gamma")
                    ColorWheelPlaceholder(title: "Gain")
                    ColorWheelPlaceholder(title: "Offset")
                }
                .padding()

                // Node Editor
                VStack {
                    Text("Node Editor")
                        .font(.caption.weight(.semibold))
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .frame(minWidth: 300)
            }
            .frame(height: 250)
        }
    }
}

struct ColorWheelPlaceholder: View {
    let title: String
    var body: some View {
        VStack {
            Text(title)
                .font(.caption2.weight(.medium))
            Circle()
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 100, height: 100)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                )
            Slider(value: .constant(0.5))
                .frame(width: 100)
        }
    }
}

// MARK: - Audio Workspace (Placeholder)

struct AudioWorkspaceView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Timeline with waveforms
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Text("Audio Timeline with Waveforms"))

            // Mixer
            HStack(spacing: 1) {
                ForEach(1...8, id: \.self) { channel in
                    VStack(spacing: 4) {
                        Text("Ch \(channel)")
                            .font(.caption2)
                        Rectangle()
                            .fill(.green.opacity(0.3))
                            .frame(width: 8, height: 100)
                        Slider(value: .constant(0.75))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 60, height: 20)
                        Text("0 dB")
                            .font(.caption2)
                    }
                    .frame(width: 60)
                    .padding(.vertical, 8)
                }

                Spacer()

                // Master
                VStack(spacing: 4) {
                    Text("Master")
                        .font(.caption2.weight(.semibold))
                    Rectangle()
                        .fill(.green.opacity(0.3))
                        .frame(width: 16, height: 100)
                    Slider(value: .constant(0.75))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 60, height: 20)
                    Text("0 dB")
                        .font(.caption2)
                }
                .frame(width: 80)
                .padding(.vertical, 8)
            }
            .frame(height: 200)
            .background(.bar)
        }
    }
}

// MARK: - Effects Workspace (Placeholder)

struct EffectsWorkspaceView: View {
    var body: some View {
        HSplitView {
            // Effects list
            List {
                Section("Applied Effects") {
                    Text("No clip selected")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Preview
            Rectangle()
                .fill(.black)
                .overlay(Text("Effects Preview").foregroundStyle(.white))

            // Parameters
            VStack {
                Text("Effect Parameters")
                    .font(.caption.weight(.semibold))
                Text("Select an effect to edit parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 250, maxWidth: 350)
        }
    }
}

// MARK: - Deliver Workspace (Placeholder)

struct DeliverWorkspaceView: View {
    var body: some View {
        HSplitView {
            // Render settings
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Render Settings")
                        .font(.headline)

                    GroupBox("Format") {
                        VStack(alignment: .leading) {
                            Picker("Format", selection: .constant("MP4")) {
                                Text("MP4").tag("MP4")
                                Text("QuickTime").tag("MOV")
                                Text("MXF").tag("MXF")
                            }
                            Picker("Codec", selection: .constant("H.265")) {
                                Text("H.264").tag("H.264")
                                Text("H.265").tag("H.265")
                                Text("ProRes 422").tag("ProRes422")
                                Text("ProRes 4444").tag("ProRes4444")
                            }
                        }
                    }

                    GroupBox("Resolution") {
                        Picker("", selection: .constant("3840x2160")) {
                            Text("1920 x 1080").tag("1920x1080")
                            Text("3840 x 2160").tag("3840x2160")
                            Text("Custom...").tag("custom")
                        }
                    }

                    Button("Add to Render Queue") {}
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(minWidth: 300, maxWidth: 400)

            // Preview + Render Queue
            VStack(spacing: 0) {
                // Preview
                Rectangle()
                    .fill(.black)
                    .overlay(Text("Preview").foregroundStyle(.white))

                // Render queue
                VStack(alignment: .leading) {
                    Text("Render Queue")
                        .font(.caption.weight(.semibold))
                    List {
                        Text("Queue is empty")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 150)
            }
        }
    }
}

// MARK: - Menu Commands

struct NLECommands: Commands {
    var body: some Commands {
        // Replace default New Item
        CommandGroup(replacing: .newItem) {
            Button("New Project") { }
                .keyboardShortcut("n")
            Button("Open Project...") { }
                .keyboardShortcut("o")
        }

        // Import
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Media...") { }
                .keyboardShortcut("i")
        }

        // Mark menu
        CommandMenu("Mark") {
            Button("Set In Point") { }
                .keyboardShortcut("i", modifiers: [])
            Button("Set Out Point") { }
                .keyboardShortcut("o", modifiers: [])
            Button("Clear In Point") { }
                .keyboardShortcut("i", modifiers: .option)
            Button("Clear Out Point") { }
                .keyboardShortcut("o", modifiers: .option)
            Divider()
            Button("Add Marker") { }
                .keyboardShortcut("m", modifiers: [])
        }

        // Clip menu
        CommandMenu("Clip") {
            Button("Blade") { }
                .keyboardShortcut("b")
            Button("Blade All") { }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Button("Enable/Disable") { }
                .keyboardShortcut("v", modifiers: [])
        }

        // Timeline menu
        CommandMenu("Timeline") {
            Button("Insert Edit") { }
                .keyboardShortcut("w", modifiers: [])
            Button("Overwrite Edit") { }
                .keyboardShortcut("d", modifiers: [])
            Button("Append to End") { }
                .keyboardShortcut("e", modifiers: [])
            Divider()
            Button("Toggle Snapping") { }
                .keyboardShortcut("n", modifiers: [])
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Show Media Browser") { }
                .keyboardShortcut("1")
            Button("Show Effects Browser") { }
                .keyboardShortcut("2")
            Button("Show Inspector") { }
                .keyboardShortcut("3")
            Divider()
            Button("Zoom to Fit") { }
                .keyboardShortcut("z", modifiers: .shift)
        }
    }
}
```

---

## 12. Workspace Switching Architecture

### State Management

Each workspace page maintains independent state:

```swift
// Workspace state preserved during switches
class WorkspaceStateManager: ObservableObject {
    // Each workspace stores its own panel configuration
    var editState = EditWorkspaceState()
    var colorState = ColorWorkspaceState()
    var audioState = AudioWorkspaceState()
    var effectsState = EffectsWorkspaceState()
    var deliverState = DeliverWorkspaceState()

    // Shared state (timeline position, selection) spans all workspaces
    @Published var timelinePosition: Double = 0
    @Published var selectedClips: Set<UUID> = []
}

class EditWorkspaceState: ObservableObject {
    @Published var panelSizes: PanelSizes = .default
    @Published var browserTab: BrowserTab = .media
    @Published var inspectorTab: InspectorTab = .video
    @Published var viewerMode: ViewerMode = .dual
}
```

### Workspace Transition Animation

```swift
struct WorkspaceTransition: View {
    @Binding var workspace: AppState.Workspace

    var body: some View {
        ZStack {
            // Workspace views
            ForEach(AppState.Workspace.allCases) { ws in
                if workspace == ws {
                    workspaceView(for: ws)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: workspace)
    }

    @ViewBuilder
    func workspaceView(for ws: AppState.Workspace) -> some View {
        switch ws {
        case .edit: EditWorkspaceView()
        case .color: ColorWorkspaceView()
        case .audio: AudioWorkspaceView()
        case .effects: EffectsWorkspaceView()
        case .deliver: DeliverWorkspaceView()
        }
    }
}
```

### Saving/Restoring Layout

```swift
// Use UserDefaults + NSSplitView.autosaveName for panel sizes
// Use Codable for workspace-specific state

struct WorkspaceLayout: Codable {
    var browserWidth: CGFloat
    var inspectorWidth: CGFloat
    var timelineHeight: CGFloat
    var viewerSplit: CGFloat // 0.5 = equal source/program
    var browserVisible: Bool
    var inspectorVisible: Bool
    var sourceViewerVisible: Bool
}

extension WorkspaceLayout {
    static let defaultEdit = WorkspaceLayout(
        browserWidth: 280,
        inspectorWidth: 300,
        timelineHeight: 300,
        viewerSplit: 0.5,
        browserVisible: true,
        inspectorVisible: true,
        sourceViewerVisible: true
    )

    static let defaultColor = WorkspaceLayout(
        browserWidth: 0,
        inspectorWidth: 0,
        timelineHeight: 120,
        viewerSplit: 0.7,
        browserVisible: false,
        inspectorVisible: false,
        sourceViewerVisible: false
    )
}
```

---

## Summary of Key Design Decisions

1. **Hybrid AppKit + SwiftUI**: Use `NSSplitViewController` for the outer panel framework (precise resize control, auto-save, delegate API), SwiftUI for panel content (declarative UI, state management)

2. **Liquid Glass for navigation only**: Toolbar, workspace tabs, transport bar, and panel headers get glass treatment. Timeline clips, viewer, scopes, and parameter controls remain content-layer with no glass.

3. **Workspace pages**: 5 pages (Edit, Color, Audio, Effects, Deliver) following the DaVinci Resolve model, each with independent panel layouts and state. Switching via bottom tab bar or keyboard shortcuts (Shift+1-5).

4. **Standard NLE shortcuts**: Follow industry conventions (JKL, I/O, W/D/E/Q) so editors can transition from other NLEs. Customizable keyboard mapping via Cmd+Option+K.

5. **Video scopes via Metal compute shaders**: Two-pass GPU approach (accumulate in compute shader, visualize in render pass) for real-time waveform, vectorscope, histogram, and RGB parade.

6. **Panel system**: 5 core panels (Browser, Source Viewer, Program Viewer, Inspector, Timeline) with independent collapse/resize. `NSSplitViewItem` sidebar/inspector behaviors for proper macOS integration.

7. **Menu bar**: Full macOS menu structure with app-specific menus (Mark, Clip, Timeline) following both Apple guidelines and NLE conventions. Every command accessible via menu and keyboard shortcut.

---

## Sources

- [DaVinci Resolve Edit Page Layout](https://www.motionvfx.com/know-how/davinci-resolve-edit-page-layout-and-purpose/)
- [DaVinci Resolve Interface and Pages](https://2pop.calarts.edu/technicalsupport/davinci-resolve-interface/)
- [DaVinci Resolve Color Page](https://www.blackmagicdesign.com/products/davinciresolve/color)
- [DaVinci Resolve Fairlight](https://www.blackmagicdesign.com/products/davinciresolve/fairlight)
- [Final Cut Pro Keyboard Shortcuts - Apple Support](https://support.apple.com/guide/final-cut-pro/keyboard-shortcuts-ver90ba5929/mac)
- [FCPX Full Access Shortcuts Reference](https://fcpxfullaccess.com/blogs/blog/every-final-cut-pro-keyboard-shortcut-quick-reference-guide)
- [JKL Playback Shortcuts](https://www.premiumbeat.com/blog/video-editing-j-k-l-shortcuts/)
- [Frame.io FCP Shortcuts](https://blog.frame.io/2018/09/17/fcpx-final-cut-pro-shortcuts/)
- [DaVinci Resolve Keyboard Shortcuts](https://motionarray.com/learn/davinci-resolve/davinci-resolve-keyboard-shortcuts/)
- [Video Scopes Introduction](https://blog.frame.io/2017/09/27/introduction-to-video-scopes/)
- [GPU Video Scopes (Blender/Aras)](https://aras-p.info/blog/2025/08/24/This-many-points-is-surely-out-of-scope/)
- [Premiere Pro Menus](https://www.schoolofmotion.com/blog/exploring-the-menus-of-adobe-premiere-pro-sequence)
- [SplitView SwiftUI Library](https://github.com/stevengharris/SplitView)
- [NSSplitViewController with SwiftUI](https://gist.github.com/HashNuke/f8895192fff1f275e66c30340f304d80)
- [Liquid Glass Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [Apple Newsroom - Liquid Glass Design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [macOS Tahoe Liquid Glass Review](https://eshop.macsales.com/blog/97650-blurry-or-beautiful-the-tweaks-and-tenets-of-apples-controversial-liquid-glass-design-in-macos-tahoe/)
- [SwiftUI for Mac 2025](https://troz.net/post/2025/swiftui-mac-2025/)
- [HSplitView Apple Documentation](https://developer.apple.com/documentation/swiftui/hsplitview)
- [NavigationSplitView Apple Documentation](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Monitor Overlays in Premiere Pro](https://helpx.adobe.com/premiere-pro/using/monitor-overlays.html)
- [Final Cut Pro Viewer Overlays](https://support.apple.com/guide/final-cut-pro/use-overlays-in-the-viewer-verded6d49d7/mac)
- [DaVinci Resolve Inspector Guide](https://cromostudio.it/cromo-tips/a-comprehensive-guide-to-the-inspector-tab-in-davinci-resolve)
- [Lift Gamma Gain Color Wheels](https://www.videosoftdev.com/how-to-use-lift-gamma-gain-in-vsdc)
- [Adobe Media Encoder Export Settings](https://helpx.adobe.com/media-encoder/using/export-settings-reference.html)
