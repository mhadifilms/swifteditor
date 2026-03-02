# Editing Paradigm & UX Research

> Deep-dive into NLE editing paradigms and UX models to inform the editing model for our Swift NLE.

---

## 1. DaVinci Resolve Edit Page

### Edit Modes

DaVinci Resolve's Edit page provides four primary tool modes, each activated by a single key:

| Mode | Shortcut | Behavior |
|------|----------|----------|
| **Selection** | A | Default pointer. Click to select clips, drag to reposition. |
| **Trim** | T | Context-sensitive smart trimming. Cursor changes automatically based on hover position (edge = ripple/roll, body top = slip, body bottom = slide). |
| **Dynamic Trim** | W | Trim during JKL playback. Jumps back on each loop so you can evaluate the transition in real time. |
| **Blade** | B | Click anywhere on a clip to split it at that frame into two segments. |

#### Trim Mode Context Sensitivity

The Trim tool (T) is Resolve's crown jewel for efficiency. Rather than requiring separate tool selections, it detects intent from cursor position:

| Cursor Position | Operation | Effect |
|----------------|-----------|--------|
| Left edge of clip | **Ripple Trim** (head) | Shorten/extend clip start; downstream clips shift to fill/make room |
| Right edge of clip | **Ripple Trim** (tail) | Shorten/extend clip end; downstream clips shift |
| Directly on edit point (between two clips) | **Roll Trim** | Move edit point; one clip shortens while the other extends by the same amount. Timeline duration unchanged. |
| Body of clip (upper region / thumbnails) | **Slip** | Changes the clip's in/out window within its source media without moving the clip or changing duration. |
| Body of clip (lower region / title bar) | **Slide** | Moves the clip between its neighbors; neighbors' durations adjust to compensate. Overall timeline duration unchanged. |

**Asymmetric Trimming**: Hold Alt while trimming to trim in different directions on different tracks simultaneously -- perfect for opening or closing gaps.

**Multi-point Trimming**: Select and trim multiple edit points on the same or different tracks at once.

### Edit Types (Source-to-Timeline)

Resolve exposes seven edit types, accessible via the Edit Overlay (drag source to timeline viewer), toolbar buttons, or keyboard shortcuts:

| Edit Type | Shortcut | Behavior |
|-----------|----------|----------|
| **Insert** | F9 | Splits timeline at playhead, pushes everything downstream to make room. Ripples all unlocked tracks. |
| **Overwrite** | F10 | Replaces content at playhead position. No timeline duration change. |
| **Replace** | F11 | Replaces the existing clip at the playhead with source content, matching at the playhead frame. |
| **Fit to Fill** | Shift+F11 | Applies automatic speed change to source clip so it exactly fills the marked timeline duration. |
| **Place on Top** | F12 | Places source clip on the next available track above at the playhead position. Ideal for B-roll, titles, PIP. |
| **Append at End** | Shift+F12 | Places source clip after the last edit in the timeline, regardless of playhead position. |
| **Ripple Overwrite** | Shift+F10 | Replaces a clip AND adjusts timeline duration. If new clip is longer, timeline extends; if shorter, gap is removed. Combines overwrite + ripple delete. |

#### Ripple Behavior

When an operation "ripples," all clips to the **right** of the edit on all **unlocked** tracks shift to compensate. Clips to the left remain in place. Locked tracks are immune to ripple operations. This is critical for maintaining audio/video sync across multiple tracks.

### Timeline Organization Features

#### Markers
- **Standard markers**: Single-frame markers (M key) on clips or the timeline ruler. Color-coded, named, with notes and keywords.
- **Duration markers**: Range-based markers spanning multiple frames. Act like named sub-regions. Can be converted to/from In/Out points. Filterable in Smart Bins.
- **Chapter markers**: Standard markers that serve as chapter points for export. Named via the marker editor.
- Markers can be clip-level or timeline-level (above all tracks vs. on a specific clip).
- Copy/paste multiple markers between clips, timelines, or compound clips.

#### Compound Clips
- Group multiple clips into a single compound clip that behaves as one unit on the timeline.
- Double-click to open and edit contents in a nested timeline.
- Changes to the compound clip propagate to all instances.
- Useful for complex effects stacks, repeated segments, or reducing visual clutter.

#### Multi-Timeline Tabs
- Open multiple timelines simultaneously as tabs in the Edit page.
- Useful for: alternative versions of an edit, managing separate sections (intro/main/outro), referencing footage from another timeline.
- Drag clips between timeline tabs.

#### Smart Bins
- Rule-based bins that automatically filter clips using metadata (codec, resolution, frame rate, usage count, keywords, etc.).
- Dynamic -- continuously update as metadata changes.
- Can filter by marker content, usage > 0 (used clips), etc.
- Duration markers appear as filterable thumbnails in smart bins.

### In/Out Point Workflow
Standard source/record monitor workflow:
1. Load clip into Source Viewer.
2. Mark In (I) and Out (O) on source.
3. Optionally mark In/Out on timeline.
4. Execute edit type (Insert, Overwrite, etc.).

Three-point editing: any combination of 3 points across source and timeline determines the edit. Four-point editing (all 4 set) triggers Fit to Fill or user choice for mismatch resolution.

---

## 2. DaVinci Resolve Cut Page

### Philosophy: "The Fastest Way to Edit"

The Cut page was introduced in DaVinci Resolve 16 as a fundamentally different editing environment. It is not a simplified version of the Edit page -- it represents a new paradigm designed for speed, with the goal that every action completes in a single click.

Key design principles:
- **No tool switching**: The Cut page has no separate tool modes.
- **Single viewer**: Source and timeline viewing are merged into one viewer.
- **Automatic behavior**: The timeline adapts to context.
- **Keyboard/hardware optimized**: Designed for the DaVinci Resolve Editor Keyboard and Speed Editor.

### Source Tape

Instead of browsing individual clips in bins, Source Tape concatenates all clips in a bin (or the entire media pool) into one continuous virtual "tape." Editors scrub through it visually to find shots without file management overhead.

- Click a bin to view its clips as a tape.
- Navigate up to see all bins combined into a master tape.
- Eliminates the "click through individual clips" bottleneck.
- Scroll visually rather than relying on filenames.

### Sync Bin

The Sync Bin revolutionizes multicam editing:
- Select the Sync Clips icon and Resolve automatically finds all clips that sync to the current timeline position.
- Displays synced clips in a multiview grid.
- Scroll the timeline and the sync bin updates in real time.
- Click a view, set in/out, then use Source Overwrite to place it perfectly synced on the track above.
- Sync methods: timecode (default), audio waveform, or manual.
- Non-real-time multicam: works at any resolution without performance penalty.

### Smart Insert

Smart Insert places a clip at the **nearest edit point** to the playhead, rather than at the playhead itself. This eliminates the need to precisely park at an edit point before inserting. Works best on V1 and reinforces the Cut page's "rough cut first" philosophy.

### Close-Up Detection

AI-powered feature that detects faces in wide shots and can automatically generate close-up reframes, accelerating multicam and interview editing.

### Dual Timeline

The Cut page always shows two timelines:
- **Upper timeline**: Full project overview (all clips visible regardless of project length).
- **Lower timeline**: Detail/precision view of the area around the playhead.
- No manual zoom controls -- the system manages scale automatically.
- Designed for hardware controllers and search dials.
- Navigate the overview for big jumps; use the detail view for precise edits.

### Why Some Editors Love It

- Eliminates the "zoom in, zoom out" cycle that dominates traditional editing.
- Extremely fast for assembly edits, social media content, and news/event work.
- Source Tape removes bin-browsing friction.
- Sync Bin is faster than traditional multicam for cutaway selection.
- Everything is "live" -- changes happen with single clicks.

### Limitations

- Not suited for complex multi-layer compositing or detailed effects work.
- No manual zoom control can frustrate precision editors.
- Single viewer means no simultaneous source/record comparison.
- Best thought of as a complement to, not replacement for, the Edit page.

---

## 3. Final Cut Pro Magnetic Timeline

### Core Concept: Relationship-Based Editing

FCP abandoned the track-based paradigm entirely in favor of a **relationship-based** model. Instead of placing clips at specific track/timecode positions, editors define how clips relate to each other.

### Primary Storyline

- The horizontal spine of the timeline (dark gray bar).
- Clips placed here snap together magnetically with no gaps.
- Removing a clip causes all subsequent clips to ripple left.
- Designed to prevent accidental black frames (flashes of black between edits).
- Clips cannot overlap on the primary storyline -- they push each other.

### Connected Clips

- Secondary clips (B-roll, SFX, music, titles) attach to primary storyline clips via a connection point (thin line).
- When a primary clip moves, all connected clips move with it, preserving sync relationships.
- Shortcut: Q (connect to primary storyline).
- The timeline "knows" what is B-roll over an interview because of these connections.

### Roles System

Roles replace tracks as an organizational mechanism:

| Default Role | Purpose |
|-------------|---------|
| Video | Standard video content |
| Titles | Text and graphic overlays |
| Dialogue | Spoken word audio |
| Effects | Sound effects |
| Music | Musical score/soundtrack |

- Custom roles and sub-roles can be created.
- Clips are tagged with roles for identification and organization.
- **Audio Lanes**: Toggle on to visually separate audio by role, creating a "pseudo-tracks" view.
- Roles enable batch operations on all clips of a type.
- Export stems by role for broadcast delivery.

### Gap Clips

Placeholder clips that maintain timing. Used when you want to remove a clip but preserve its duration (equivalent to a Lift edit in track-based NLEs).

### Compound Clips

- Group clips together (Option+G) into a single unit.
- Editable by double-clicking to enter the compound clip's internal timeline.
- Useful for reducing connected clip clutter (e.g., grouping all music/SFX into one compound clip with a single connection point).

### Auditions

- A unique FCP feature for trying alternative clips.
- Create an audition containing multiple clip options.
- Cycle through options with arrow keys.
- Set a "pick" -- the active clip that plays in the timeline.
- Non-destructive: all alternatives remain available.
- Limitation: Does not work with multicam clips.

### Multicam Clips

- Created from multiple source clips synced by timecode, audio waveform, content creation date, first marker, or start of first clip.
- Opened in the Angle Editor for sync adjustment and angle management.
- Live switching: watch all angles simultaneously in the Angle Viewer while cutting or switching in real time.
- Changes to the parent multicam clip propagate to all child instances.

### Synchronized Clips

- Combine separate video and audio recordings into a single synchronized clip.
- Largely superseded by multicam clips for most workflows, since multicam clips now export cleanly via FCPXML.

### Why Pros Complain

| Complaint | Detail |
|-----------|--------|
| **Unpredictable clip movement** | Clips automatically shuffle when you don't expect it, especially during insert/delete operations near connected clips. |
| **No manual track control** | Cannot place a clip at an exact track position. Layers are automatic. |
| **Accidental connected clip deletion** | Deleting a primary clip removes all connected clips unless you first detach them. |
| **Inability to leave gaps** | The magnetic behavior closes gaps automatically -- editors who use gaps intentionally find this infuriating. |
| **Multi-layer compositing friction** | Complex compositing with many layers requires extensive use of secondary storylines and compound clips as workarounds. |
| **One-frame alignment errors** | Duration markers can appear aligned visually but be off by one frame. |
| **Paradigm switch pain** | Editors from track-based NLEs report weeks of adjustment, with muscle memory conflicts. |

### Workarounds

- **Position Tool (P)**: Disables magnetic behavior. Clips can be placed freely, gaps can be left, clips can overwrite each other. Makes FCP behave like a track-based NLE.
- **Secondary Storylines**: Create grouped clip sequences above the primary storyline.
- **Command+Option+Up Arrow**: Move clips out of the primary storyline.
- **Command+Shift+G**: Break apart secondary storyline grouping.

---

## 4. Adobe Premiere Pro

### Track-Based Model

Premiere Pro uses the traditional, industry-standard track-based timeline:
- Named video tracks (V1, V2, V3...) and audio tracks (A1, A2, A3...).
- Clips are placed at specific track + timecode positions.
- Clips stay where you put them -- no automatic movement.
- Higher video tracks have compositing priority (V3 renders on top of V2, etc.).
- Unlimited tracks.

### Source/Program Monitor Workflow

Premiere Pro uses the classic dual-monitor paradigm inherited from linear tape editing:
- **Source Monitor** (left): Preview and mark source clips (In/Out).
- **Program Monitor** (right): View the timeline output. Mark timeline In/Out.
- Buttons below the Source Monitor execute edits: Insert (,) and Overwrite (.).

### Three-Point Editing

The foundational NLE editing technique:
- Define 3 of the 4 possible points (Source In, Source Out, Timeline In, Timeline Out).
- The fourth point is calculated automatically.

| Points Set | Result |
|-----------|--------|
| Source In + Source Out + Timeline In | Clip placed at timeline In, duration determined by source marks |
| Source In + Source Out + Timeline Out | Clip placed ending at timeline Out |
| Source In + Timeline In + Timeline Out | Source In used, duration from timeline marks, source Out calculated |
| Source Out + Timeline In + Timeline Out | Source Out used, duration from timeline marks, source In calculated |

### Four-Point Editing

All 4 points set. If source duration != timeline duration, Premiere presents options:
- **Change Clip Speed (Fit to Fill)**: Speed up/slow down source to fit timeline duration.
- **Ignore Source In/Out Point**: Trim source to match timeline duration.
- **Ignore Sequence In/Out Point**: Use full source duration, ignoring timeline marks.

### Track Targeting

Premiere Pro's track system has three layers of control:

| Control | Purpose |
|---------|---------|
| **Source Patching** (V1/A1 indicators, left side) | Routes source video/audio to specific timeline tracks for Insert/Overwrite edits. On = receives media, Off = receives nothing, Silent (Alt-click) = receives gap of same duration. |
| **Track Targeting** (track name highlight) | Determines which tracks are affected by paste, match frame, and keyboard navigation (Up/Down arrow keys snap to edits on targeted tracks). |
| **Sync Lock** (lock icon) | When enabled, tracks shift together during insert/ripple edits to maintain sync. |

### Pancake Timeline Technique

Open multiple sequences (timelines) simultaneously, stacked vertically:
- Top timeline: raw/source sequence (organized footage).
- Bottom timeline: main edit/program sequence.
- Drag clips from source sequence directly to program sequence.
- Non-destructive: source timeline remains intact.
- Excellent for long-form editing, string-outs, and selects sequences.
- Pro tip: Load source sequences in the Source Monitor for three-point editing from sequence to sequence.

### Nested Sequences

- Place one sequence inside another as a single clip.
- The nested instance reflects the current state of the source sequence (dynamic updating).
- Trimming a nested instance does not affect the source sequence length.
- Use the "Insert And Overwrite Sequences As Nest Or Individual Clips" toggle to control nesting behavior.
- Wrench icon in Source Monitor > "Open Sequence in Timeline" to edit the nested source.
- Useful for: applying effects to groups of clips, reusing edited segments, managing complex audio (merged clips with 8+ audio tracks).
- Caveat: One-to-many relationship. Changing the nest changes all instances. Duplicate the nest in the Project panel for independent instances.

### Through Edits

- An edit point where both sides contain the same continuous media (created by razor/blade tool or Add Edit command).
- Visually indicated by a dashed line through the edit point.
- Can be removed: right-click > "Join Through Edit" to merge the segments back into one clip.
- Through edits are common when applying different effects or color grades to different sections of the same clip.

---

## 5. Avid Media Composer

### The Original Professional Editing Paradigm

Media Composer established many conventions that became industry standards. Its editing model is built around two fundamental modes:

### Segment Mode vs. Trim Mode

#### Segment Mode (Moving Clips)

Two types, color-coded:
- **Red Arrow (Lift/Overwrite)**: Grab and move a clip. The clip is **lifted** from its position (leaving filler/black) and **overwrites** at its destination.
- **Yellow Arrow (Extract/Splice-In)**: Grab and move a clip. The clip is **extracted** from its position (gap closes) and **spliced in** at its destination (downstream clips shift right).

Mnemonic: **Red = others don't move. Yellow = others move.**

#### Trim Mode (Adjusting Edit Points)

Two types, also color-coded:
- **Red Roller (Overwrite Trim)**: Extend or shorten a clip without moving other clips. If extended, it overwrites the adjacent clip. Equivalent to a Roll trim.
- **Yellow Roller (Ripple Trim)**: Extend or shorten a clip, pushing or pulling all subsequent clips. Timeline duration changes.

### SmartTools

Introduced in Media Composer 5, SmartTools merge Segment Mode and Trim Mode into a single, always-on palette with context-sensitive behavior:

| Cursor Position | Smart Tool Active | Result |
|----------------|-------------------|--------|
| Top half of clip body | Red Segment Arrow (Lift/Overwrite) | Drag to overwrite-move |
| Bottom half of clip body | Yellow Segment Arrow (Extract/Splice) | Drag to splice-move |
| Left side of edit point | Trim (type depends on roller enabled) | Trim outgoing clip |
| Right side of edit point | Trim (type depends on roller enabled) | Trim incoming clip |
| Directly on edit point | Dual-roller trim (Roll) | Adjust edit point between both clips |

SmartTool toggles: Shift+A (Lift/Overwrite segment), Shift+S (Extract/Splice segment), Shift+D (Overwrite trim), Shift+F (Ripple trim).

### Match Frame

- **Match Frame** (record -> source): Park on any frame in the timeline, press Match Frame key, and Resolve loads the original source clip in the Source Monitor at that exact frame with an In point. Direction: Timeline to Source.
- **Reverse Match Frame** (source -> record): With a source clip loaded, Ctrl+click Match Frame to find where that frame appears in the timeline. Direction: Source to Timeline.
- **Match Frame Track**: Match frame without needing a specific track active -- searches all enabled track selectors.

These form a powerful navigation system for moving fluidly between timeline and source without manual bin browsing.

### Slip and Slide

Built into dual-roller trimming:
- **Slip**: Changes the clip's content window without changing position or duration. Two transitions are trimmed simultaneously (In moves forward, Out moves forward by same amount).
- **Slide**: Moves the clip between its neighbors; adjacent clips' durations change to compensate.

### Add Edit (Avid's Blade)

Adds an edit point at the playhead on selected tracks. The Avid equivalent of Blade/Razor. Creates a "match frame edit" -- both sides contain the same continuous media (equivalent to Premiere's "through edit").

---

## 6. Recommended Editing Model for Our Swift NLE

### Recommendation: Track-Based with Intelligent Assistive Behaviors

We recommend a **track-based timeline** as the primary paradigm, enhanced with select intelligent behaviors inspired by the magnetic timeline and DaVinci Resolve's context-sensitive tools.

### Rationale

| Factor | Analysis |
|--------|----------|
| **Target audience** | Prosumer-to-pro. This audience predominantly uses Premiere Pro, Resolve, and Avid. Track-based editing is their muscle memory. |
| **Industry standard** | Track-based editing is the dominant paradigm in professional post-production (film, TV, broadcast, commercial). |
| **Predictability** | Clips stay where you put them. No automatic shuffling. Editors maintain full control over clip positions. |
| **Flexibility** | Unlimited tracks enable complex compositing, multi-layer effects, and precise audio mixing. |
| **Learning curve** | Editors switching from Premiere/Resolve/Avid face zero paradigm adjustment. FCP editors can use the Position tool analogy. |
| **Magnetic timeline risks** | The FCP approach is genuinely divisive. Many professional editors actively avoid FCP because of the magnetic timeline. Adopting it would alienate a large segment of our target audience. |
| **Innovation opportunity** | Instead of choosing magnetic vs. track-based, we can add optional intelligent behaviors (like Resolve's context-sensitive trim) that enhance the track-based model without compromising predictability. |

### Specific Design Decisions

1. **Fixed tracks with manual track creation/deletion**: Users explicitly create V1, V2, A1, A2, etc. Clips placed on a track stay on that track.
2. **No automatic clip repositioning**: Clips never move unless the user explicitly performs a ripple operation.
3. **Context-sensitive trim tool (a la Resolve)**: A single Trim mode (T) that automatically detects ripple, roll, slip, and slide based on cursor position.
4. **Source/Record dual monitor**: Traditional Source Monitor + Program Monitor workflow for three-point editing.
5. **Optional ripple mode toggle**: A global toggle (or per-operation modifier) to enable ripple behavior on insert/delete operations. Default: OFF (overwrite behavior).
6. **Linked selection by default**: Video and audio from the same source move together, with Option/Alt override for independent selection.
7. **Track targeting with source patching**: Premiere-style source routing for keyboard-driven editing.
8. **Sync locks**: Per-track sync lock to maintain synchronization during ripple operations.
9. **Compound clips / nested timelines**: Allow grouping clips and editing nested timelines.
10. **Marker system**: Standard, duration, and chapter markers with color coding, notes, and keywords.

### Why Not Magnetic

| Magnetic Timeline Advantage | Our Alternative |
|----------------------------|-----------------|
| Prevents accidental gaps | Ripple delete option; visual gap indicators; "close gap" command |
| Maintains clip relationships | Linked selection + sync locks + grouping |
| Automatic B-roll sync | Compound clips + linked/synced clips |
| Faster rough cuts | Cut page-inspired "quick assembly" mode (future consideration) |
| No overwrite accidents | Overwrite requires explicit action (not drag default) |

### Why Not Hybrid (Like Resolve's Cut + Edit)

For v1, maintaining a single timeline paradigm reduces implementation complexity and user confusion. A dual-page approach (Cut + Edit) could be considered for v2, but only if user research validates demand. The Edit page alone, with good keyboard shortcuts and context-sensitive tools, can be fast enough for assembly editing.

---

## 7. Edit Operations Specification

Based on the recommended track-based model, here is the exact behavioral specification for each operation:

### 7.1 Insert Edit (with Ripple)

**Trigger**: F9, or drag to Insert zone in Edit Overlay

**Behavior**:
1. Source In/Out define the clip region to insert.
2. Timeline playhead (or Timeline In point) defines the insertion point.
3. If the playhead is in the middle of a clip, that clip is **split** at the playhead.
4. The source clip is placed at the insertion point on the **source-patched** track.
5. All clips to the **right** of the insertion point on all **sync-locked** tracks shift right by the duration of the inserted clip.
6. Timeline duration **increases** by the inserted clip's duration.

**Edge cases**:
- If no source In/Out set: uses entire source clip duration.
- If timeline In AND Out set (4-point): source is trimmed or speed-changed to fit (user prompt).

### 7.2 Overwrite Edit

**Trigger**: F10, or drag to Overwrite zone in Edit Overlay

**Behavior**:
1. Source In/Out define the clip region.
2. Timeline playhead (or Timeline In point) defines the start point.
3. Source clip is placed at the start point on the source-patched track.
4. Any existing content on that track in the overwritten range is **replaced**.
5. No other clips move. No ripple. Timeline duration is **unchanged** (unless the overwrite extends past the current timeline end).

**Edge cases**:
- Partial clip overwrite: the existing clip is split; the overlapping portion is removed and replaced with the source clip.

### 7.3 Replace Edit

**Trigger**: F11

**Behavior**:
1. The source clip replaces the **entire** clip under the playhead on the targeted track.
2. The playhead position in both source and timeline are **matched** (the source frame at the playhead aligns with the timeline frame at the playhead).
3. The resulting clip duration matches the original timeline clip's duration.
4. Source content fills the timeline clip's duration, centered on the playhead match point.
5. No ripple. Timeline duration unchanged.

### 7.4 Ripple Delete

**Trigger**: Shift+Delete (or Shift+Backspace)

**Behavior**:
1. Selected clip(s) are removed from the timeline.
2. All clips to the **right** on all **sync-locked** tracks shift left to close the gap.
3. Timeline duration **decreases** by the removed clips' duration.

**Compared to Delete (non-ripple)**:
- Regular Delete removes the clip but leaves a gap (filler/black) of the same duration.

### 7.5 Ripple Trim (Extend/Shorten with Ripple)

**Trigger**: Drag clip edge in Trim mode (yellow/ripple roller), or use trim shortcuts

**Behavior (Shorten)**:
1. Dragging a clip's Out point left (or In point right) shortens the clip.
2. All clips to the right on sync-locked tracks shift left by the trimmed amount.
3. Timeline duration **decreases**.

**Behavior (Extend)**:
1. Dragging a clip's Out point right (or In point left) extends the clip into its handles (unused source media).
2. All clips to the right on sync-locked tracks shift right by the extended amount.
3. Timeline duration **increases**.
4. If no handles available (no more source media), the trim stops.

### 7.6 Roll Trim

**Trigger**: Drag directly on an edit point between two clips in Trim mode

**Behavior**:
1. Moving the edit point **left**: the outgoing clip (left) shortens, the incoming clip (right) extends.
2. Moving the edit point **right**: the outgoing clip extends, the incoming clip shortens.
3. The combined duration of both clips remains **constant**.
4. No other clips move. Timeline duration **unchanged**.
5. Both clips must have sufficient handles for the trim to proceed.

### 7.7 Slip

**Trigger**: Drag clip body (upper region) in Trim mode, or dedicated Slip shortcut

**Behavior**:
1. The clip's position and duration on the timeline remain **unchanged**.
2. The source In and Out points shift together (both move by the same offset).
3. Dragging left reveals later source material; dragging right reveals earlier source material.
4. No other clips move. Timeline duration unchanged.
5. The viewer displays a four-up view: previous clip's Out, current clip's new In, current clip's new Out, next clip's In.

### 7.8 Slide

**Trigger**: Drag clip body (lower region) in Trim mode, or dedicated Slide shortcut

**Behavior**:
1. The selected clip moves left or right on the timeline.
2. The clip's duration and source content remain **unchanged**.
3. The **adjacent clips' durations change** to compensate:
   - Sliding left: the clip to the left shortens (its Out retracts), the clip to the right extends (its In retracts).
   - Sliding right: the clip to the left extends (its Out advances), the clip to the right shortens (its In advances).
4. Overall timeline duration **unchanged**.
5. All three clips must have sufficient handles.

### 7.9 Razor / Blade

**Trigger**: B key activates Blade mode, then click on a clip; or Cmd/Ctrl+B at playhead

**Behavior**:
1. The clip under the cursor (or at the playhead) is split into two clips at the exact frame.
2. Both resulting clips retain all properties (effects, color, audio levels) of the original.
3. A "through edit" indicator (dashed line) marks the split point.
4. No clips move. No duration change.
5. **All-tracks blade**: Shift+B (or Cmd+Shift+B) splits all clips on all unlocked tracks at the playhead.

### 7.10 Lift

**Trigger**: Delete key (on selected clip), or dedicated Lift button

**Behavior**:
1. Selected clip(s) are removed from the timeline.
2. A **gap** (filler/black) of the same duration replaces the removed clip.
3. No other clips move. Timeline duration **unchanged**.
4. Equivalent to "leave a hole where the clip was."

### 7.11 Extract

**Trigger**: Shift+Delete, or dedicated Extract button

**Behavior**:
1. Selected clip(s) are removed from the timeline.
2. All clips to the right on sync-locked tracks shift left to **close the gap**.
3. Timeline duration **decreases** by the removed duration.
4. Equivalent to Ripple Delete.

### 7.12 Paste Insert

**Trigger**: Ctrl/Cmd+Shift+V (Paste Insert)

**Behavior**:
1. Clipboard content is inserted at the playhead on the targeted track.
2. If the playhead is mid-clip, that clip is split.
3. All clips to the right on sync-locked tracks shift right.
4. Timeline duration **increases**.
5. Behaves identically to Insert Edit but from clipboard instead of source monitor.

### 7.13 Paste Overwrite

**Trigger**: Ctrl/Cmd+V (standard Paste)

**Behavior**:
1. Clipboard content is placed at the playhead on the targeted track.
2. Existing content is **replaced** (overwritten).
3. No other clips move. Timeline duration unchanged (unless paste extends beyond timeline end).

### 7.14 Drag Reorder (Same Track)

**Trigger**: Drag a clip along the same track

**Behavior (Default -- Overwrite)**:
1. Clip is lifted from its position (leaving a gap on its original track).
2. Clip is placed at the drop position, overwriting any content underneath.

**Behavior (with Modifier -- Insert/Ripple)**:
1. Hold Shift (or designated modifier) while dragging.
2. Clip is extracted from its position (gap closes).
3. Clip is inserted at the drop position (clips shift right to make room).

### 7.15 Drag to Different Track

**Trigger**: Drag a clip to a different track

**Behavior**:
1. Clip moves from source track to destination track.
2. Default: the original position on the source track is left as a gap; the clip overwrites on the destination track.
3. With modifier: ripple on both source (close gap) and destination (make room).
4. If linked selection is active, linked audio/video clips move together to their corresponding tracks.

### 7.16 Speed Change

#### Constant Speed Change
**Trigger**: Right-click > Speed/Duration, or Retime Controls

**Behavior**:
1. User specifies new speed percentage (e.g., 50% = half speed, 200% = double speed).
2. Clip duration changes: `new_duration = original_duration / (speed / 100)`.
3. **No ripple by default**: a gap is left (if clip shortens) or clip overwrites adjacent content (if clip lengthens).
4. Optional "Ripple sequence" checkbox: enables ripple to adjust timeline.
5. Frame interpolation method selectable: Nearest, Frame Blending, Optical Flow.

#### Speed Ramp (Variable Speed)
**Trigger**: Retime Controls > Add Speed Point, or Retime Curve editor

**Behavior**:
1. Speed points are added at specific frames within the clip.
2. Each segment between speed points has an independent speed value.
3. Transitions between speeds can be: **Cut** (instant change) or **Curve** (smooth ramp with bezier handles).
4. The clip's total duration changes based on the combined effect of all speed segments.
5. Retime curve editor shows a graph of speed over time for precise control.
6. Reverse speed (negative values) supported for reverse playback segments.

---

## 8. Selection Model

### Selection Types

| Selection Type | Behavior | Shortcut/Method |
|---------------|----------|-----------------|
| **Single Clip** | Click a clip to select it. Deselects all others. | Click |
| **Multiple Clips (additive)** | Add clips to selection one at a time. | Cmd/Ctrl+Click |
| **Multiple Clips (contiguous)** | Select a range of clips on the same track. | Click first, Shift+Click last |
| **Lasso/Marquee** | Drag a rectangle to select all clips it touches (even partially). | Drag on empty area |
| **Range Selection** | Select a time range across one or more tracks (not tied to clip boundaries). | R tool, or mark In/Out |
| **Track Selection** | Select all clips on a track from the playhead forward (or all). | Select All on Track command |
| **All Tracks Selection** | Select all clips on all tracks from playhead forward (or entire timeline). | Cmd/Ctrl+A (all), or Cmd/Ctrl+Shift+A from playhead |
| **Linked Selection** | When active, selecting a video clip also selects its linked audio (and vice versa). | Toggle button in toolbar |

### Linked Selection Details

- **Default state**: ON. Video and audio from the same source act as one unit.
- **Override**: Hold Option/Alt while clicking to temporarily select only the video or audio portion.
- **Unlink permanently**: Select clip > right-click > Unlink. Clips become independent.
- **Re-link**: Select both clips > right-click > Link. Establishes a new link.
- **Linked clips and trimming**: Trimming one side of a linked pair trims the other to maintain sync (unless link is overridden).
- **Visual indicator**: Linked clips share a highlighted color or a link icon.

### Selection Behaviors Across Operations

| Operation | Affects | Linked Clips |
|-----------|---------|--------------|
| Move (drag) | Selected clips only | Both video and audio move together |
| Delete/Lift | Selected clips only | Both removed together |
| Trim | Selected edge/clip | Both trimmed together |
| Copy/Cut | Selected clips | Both copied together |
| Effects | Applied to selected | Applied independently to video/audio |
| Speed Change | Selected clip | Applied to video; audio pitch may be affected |

### Range Selection Specifics

- Range selection defines a time region (In to Out) that can span multiple tracks.
- Operations on a range: Lift (remove, leave gap), Extract (remove, close gap), Copy, Apply effect.
- Range selection respects track targeting: only targeted tracks are affected.
- Useful for: removing a section across all tracks, applying effects to a time region, exporting a section.

---

## 9. Keyboard Shortcut Philosophy

### Guiding Principles

1. **JKL is sacred**: J (reverse), K (stop), L (forward) transport controls must be identical to every other NLE. This is non-negotiable muscle memory.
2. **Single-key tool activation**: A (selection), T (trim), B (blade) -- one key to switch tools, no modifiers.
3. **Function keys for edit types**: F9 (Insert), F10 (Overwrite), F11 (Replace), F12 (Place on Top) -- following the DaVinci Resolve convention which itself follows Avid heritage.
4. **Modifier keys add ripple**: Shift+action = ripple variant (e.g., Shift+Delete = Ripple Delete).
5. **Fully customizable**: Users must be able to remap every shortcut.
6. **NLE presets**: Ship with built-in keyboard layouts for DaVinci Resolve, Premiere Pro, Avid Media Composer, and Final Cut Pro.

### Default Keyboard Mapping (DaVinci Resolve-based)

This is our recommended default, as Resolve's layout is the most modern synthesis of the Avid/Premiere heritage:

#### Transport

| Key | Function |
|-----|----------|
| J | Play Reverse (press multiple times to increase speed) |
| K | Stop |
| L | Play Forward (press multiple times to increase speed) |
| K+J | Slow motion reverse / frame step backward |
| K+L | Slow motion forward / frame step forward |
| Space | Play/Stop toggle |
| Home | Go to timeline start |
| End | Go to timeline end |
| Up Arrow | Previous edit point (on targeted tracks) |
| Down Arrow | Next edit point (on targeted tracks) |

#### Marking

| Key | Function |
|-----|----------|
| I | Mark In |
| O | Mark Out |
| Alt+I | Clear In |
| Alt+O | Clear Out |
| Alt+X | Clear both In and Out |
| M | Add Marker |
| Shift+M | Add Marker with duration |

#### Edit Types

| Key | Function |
|-----|----------|
| F9 | Insert |
| F10 | Overwrite |
| F11 | Replace |
| Shift+F10 | Ripple Overwrite |
| Shift+F11 | Fit to Fill |
| F12 | Place on Top |
| Shift+F12 | Append at End |

#### Tool Modes

| Key | Function |
|-----|----------|
| A | Selection (pointer) |
| T | Trim (context-sensitive) |
| B | Blade |
| Z | Zoom |
| H | Hand / Pan |

#### Timeline Operations

| Key | Function |
|-----|----------|
| Delete | Lift (remove, leave gap) |
| Shift+Delete | Extract / Ripple Delete (remove, close gap) |
| Cmd/Ctrl+C | Copy |
| Cmd/Ctrl+X | Cut |
| Cmd/Ctrl+V | Paste (overwrite) |
| Cmd/Ctrl+Shift+V | Paste Insert (ripple) |
| Cmd/Ctrl+Z | Undo |
| Cmd/Ctrl+Shift+Z | Redo |
| Cmd/Ctrl+B | Blade at playhead (all targeted tracks) |
| Cmd/Ctrl+Shift+B | Blade all tracks at playhead |
| Cmd/Ctrl+G | Group clips |
| Cmd/Ctrl+Shift+G | Ungroup clips |
| Cmd/Ctrl+L | Link/Unlink selection |

#### Navigation

| Key | Function |
|-----|----------|
| Cmd/Ctrl+= | Zoom In |
| Cmd/Ctrl+- | Zoom Out |
| Shift+Z | Zoom to Fit (entire timeline visible) |
| F | Match Frame (load source of current frame) |
| Shift+F | Reverse Match Frame |

### Cross-NLE Shortcut Comparison

| Operation | DaVinci Resolve | Premiere Pro | Final Cut Pro | Avid MC |
|-----------|----------------|--------------|---------------|---------|
| Selection Tool | A | V | A | (Smart Tool) |
| Trim Tool | T | T | T | (Smart Tool) |
| Blade/Razor | B | C | B | Add Edit btn |
| Insert | F9 | , (comma) | W | V |
| Overwrite | F10 | . (period) | D | B |
| Ripple Delete | Shift+Del | Shift+Del | Shift+Del | Z |
| Mark In | I | I | I | I |
| Mark Out | O | O | O | O |
| Play Forward | L | L | L | L |
| Stop | K | K | K | K |
| Play Reverse | J | J | J | J |
| Undo | Cmd+Z | Cmd+Z | Cmd+Z | Cmd+Z |
| Match Frame | (unassigned) | F | -- | (mapped) |
| Zoom to Fit | Shift+Z | \ | Shift+Z | Cmd+J |

### Customization Approach

1. **Keyboard customization panel**: Visual keyboard layout showing current mappings.
2. **Search by command**: Find a command by name and assign a key.
3. **Search by key**: Click a key to see what's assigned.
4. **Conflict detection**: Warn when a shortcut is already assigned, offer to swap or cancel.
5. **Import/Export**: Save and load keyboard preset files (.json).
6. **Built-in presets**: DaVinci Resolve (default), Adobe Premiere Pro, Avid Media Composer, Final Cut Pro.
7. **Reset to default**: One-click restore for any preset.

---

## 10. Tool Modes

### Overview

Tool modes determine what happens when the user clicks and drags on the timeline. Only one mode is active at a time.

### Mode Specifications

#### Selection / Pointer (A)

| Action | Behavior |
|--------|----------|
| **Click clip** | Select clip (deselect others). With Cmd: additive. With Shift: contiguous range. |
| **Click empty space** | Deselect all. |
| **Drag clip** | Move clip (overwrite at destination, gap at source). With Shift modifier: insert-move (ripple). |
| **Drag clip edge** | Basic trim (non-ripple). Shorten/extend clip without affecting other clips. Overwrites adjacent if extended. |
| **Drag on empty space** | Marquee/lasso selection. |
| **Double-click clip** | Open clip in Source Monitor. |
| **Double-click compound clip** | Enter compound clip timeline. |

#### Trim (T) -- Context-Sensitive

| Cursor Position | Visual Indicator | Drag Behavior |
|----------------|------------------|---------------|
| **Near left edge of clip** | Ripple-left icon | Ripple trim clip's In point. Other clips shift. |
| **Near right edge of clip** | Ripple-right icon | Ripple trim clip's Out point. Other clips shift. |
| **On edit point (between two clips)** | Roll icon (double arrows) | Roll edit: adjust edit point, both clips change, total duration constant. |
| **Body of clip (upper half)** | Slip icon | Slip: shift source in/out window within the clip. |
| **Body of clip (lower half)** | Slide icon | Slide: move clip between neighbors, neighbors adjust. |

**Modifier overrides in Trim mode**:
- Option/Alt + drag edge: switches between Ripple and Roll.
- Numeric entry: type frame count to trim by exact amount after clicking an edit point.
- JKL dynamic trim: enter trim mode, then use J/K/L to trim while playing. Resolve-style.

#### Blade (B)

| Action | Behavior |
|--------|----------|
| **Click on clip** | Split clip at clicked frame. |
| **Click on empty space** | No effect. |
| **Shift+Click** | Split all clips on all unlocked tracks at that frame. |
| **Drag** | No drag behavior (single-click operation). |

After a blade operation, the tool optionally returns to Selection mode (configurable preference: "Auto-return to Selection after Blade").

#### Zoom (Z)

| Action | Behavior |
|--------|----------|
| **Click** | Zoom in at clicked position. |
| **Option/Alt+Click** | Zoom out at clicked position. |
| **Drag** | Zoom to fit the dragged region in the timeline viewport. |

#### Hand / Pan (H)

| Action | Behavior |
|--------|----------|
| **Drag** | Scroll/pan the timeline view. No clips are affected. |
| **Scroll wheel** | Horizontal scroll. |
| **Ctrl+Scroll** | Vertical scroll (if multiple tracks). |

**Temporary tool activation**:
- Hold Space: temporarily activates Hand tool; release returns to previous tool.
- Hold Z: temporarily activates Zoom; release returns to previous tool.
- Hold Cmd/Ctrl: temporarily activates Zoom In while in any mode.
- Hold Cmd/Ctrl+Option/Alt: temporarily activates Zoom Out.

### Tool Mode Summary Table

| Mode | Key | Click Behavior | Drag Behavior | Modifier Behavior |
|------|-----|---------------|---------------|-------------------|
| **Selection** | A | Select | Move/Marquee | Cmd=additive, Shift=range, Alt=unlinked |
| **Trim** | T | Enter trim at edit point | Context-sensitive trim | Alt=toggle ripple/roll, numeric=precise |
| **Blade** | B | Split clip | -- | Shift=all tracks |
| **Zoom** | Z | Zoom in | Zoom to region | Alt=zoom out |
| **Hand** | H | -- | Pan timeline | -- |

### Cursor Feedback

The cursor icon must change dynamically to communicate the current tool's behavior:
- **Selection**: Standard arrow cursor.
- **Trim (ripple)**: Single bracket icon pointing in trim direction ([ or ]).
- **Trim (roll)**: Double bracket icon (][).
- **Trim (slip)**: Double horizontal arrows with vertical bars.
- **Trim (slide)**: Horizontal arrows with clip icon between.
- **Blade**: Razor blade / scissors icon.
- **Zoom in**: Magnifying glass with +.
- **Zoom out**: Magnifying glass with -.
- **Hand**: Open hand; grabbing hand while dragging.

---

## Appendix A: Comparison Summary Table

| Feature | DaVinci Resolve | Premiere Pro | Final Cut Pro | Avid MC | **Our NLE** |
|---------|----------------|--------------|---------------|---------|-------------|
| Timeline model | Track-based | Track-based | Magnetic/trackless | Track-based | **Track-based** |
| Trim approach | Context-sensitive | Separate tools | Magnetic + Position | SmartTools | **Context-sensitive** |
| Source/Record | Dual monitor | Dual monitor | Single viewer | Dual monitor | **Dual monitor** |
| Three-point editing | Yes | Yes | Limited | Yes | **Yes** |
| Edit overlay | 7 types | 2 (Insert/Overwrite) | N/A | 3 types | **7 types** |
| Ripple behavior | Per-operation | Per-operation | Always (magnetic) | Color-coded modes | **Per-operation + modifier** |
| Markers | Standard/Duration/Chapter | Standard/Comment | To-Do/Chapter/Standard | Locators/Markers | **Standard/Duration/Chapter** |
| Compound/Nested | Compound clips | Nested sequences | Compound clips | Subsequences | **Compound clips** |
| Multicam | Multicam clip | Multi-camera | Multicam clip + Angle viewer | GroupClip | **Multicam clip** |
| Keyboard presets | Multiple NLE presets | Single + custom | Single + custom | Single + custom | **Multiple NLE presets** |
| Linked selection | Yes | Yes | Connected clips | Linked clips | **Yes** |
| Sync mechanism | Track locks | Sync locks | Magnetic connections | Sync locks | **Sync locks** |

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| **Ripple** | An edit that shifts all subsequent clips to compensate for added or removed duration. |
| **Roll** | Adjusting the edit point between two clips; one shortens as the other extends. Total duration unchanged. |
| **Slip** | Changing which portion of source media is visible within a fixed-duration, fixed-position clip. |
| **Slide** | Moving a clip's position on the timeline while adjusting its neighbors' durations. |
| **Lift** | Removing a clip and leaving a gap of the same duration. |
| **Extract** | Removing a clip and closing the gap (ripple delete). |
| **Through Edit** | An edit point where both sides contain the same continuous media (result of a blade cut). |
| **Handle** | Unused source media beyond a clip's current In/Out points, available for extending trims. |
| **Source Patching** | Routing source clip tracks to specific timeline tracks for editing. |
| **Sync Lock** | A per-track setting that ensures the track shifts during ripple operations on other tracks. |
| **Three-Point Edit** | Defining 3 of 4 possible In/Out points (source and timeline) to execute an edit. |
| **Match Frame** | Loading the source clip of the frame currently at the playhead in the timeline. |
| **Compound Clip** | A group of clips that behaves as a single clip, with an editable internal timeline. |
| **Smart Bin** | A metadata-driven bin that automatically filters and displays clips matching user-defined rules. |

---

*Research compiled from analysis of DaVinci Resolve, Adobe Premiere Pro, Final Cut Pro, and Avid Media Composer documentation and community resources.*
