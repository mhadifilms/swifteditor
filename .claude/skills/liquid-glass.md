# Liquid Glass Skill

Use when the user wants to implement iOS 26 Liquid Glass effects in Swift/SwiftUI. This includes adding glass effects to views, buttons, toolbars, tab bars, sheets, navigation, morphing transitions, and any Liquid Glass styling.

## Instructions

You are an expert in iOS 26 Liquid Glass implementation. Use the comprehensive reference below to write correct, idiomatic Liquid Glass code following Apple's design guidelines.

### Key Rules
1. Liquid Glass is ONLY for the **navigation layer** — never apply to content (lists, tables, media)
2. ALWAYS wrap multiple glass elements in `GlassEffectContainer` for performance and correct rendering
3. Glass cannot sample other glass — the container provides a shared sampling region
4. Use `.regular` variant by default; `.clear` only for media-rich backgrounds with bold foreground
5. Prefer `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` over manual `.glassEffect()` on buttons
6. Use `.bouncy` animation for morphing transitions
7. Minimum target: iOS 26.0+, Xcode 26.0+

---

## API Reference

### Core Glass Effect

```swift
// Basic (defaults: .regular variant, .capsule shape)
.glassEffect()

// Full signature
func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = DefaultGlassEffectShape,
    isEnabled: Bool = true
) -> some View
```

### Glass Types

```swift
struct Glass {
    static var regular: Glass    // Default, medium transparency, full adaptivity
    static var clear: Glass      // High transparency, for media-rich backgrounds
    static var identity: Glass   // No effect (conditional toggle)

    func tint(_ color: Color) -> Glass      // Semantic meaning, NOT decoration
    func interactive() -> Glass             // iOS only: scale, bounce, shimmer
}

// Chaining
.glassEffect(.regular.tint(.orange).interactive())
```

### Shapes

```swift
.glassEffect(.regular, in: .capsule)           // Default
.glassEffect(.regular, in: .circle)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.glassEffect(.regular, in: .rect(cornerRadius: .containerConcentric))  // Aligns with container
.glassEffect(.regular, in: .ellipse)
.glassEffect(.regular, in: CustomShape())       // Any Shape conformant
```

### GlassEffectContainer

```swift
// Groups glass elements for shared sampling and morphing
GlassEffectContainer {
    HStack(spacing: 20) {
        Button("A") { }.glassEffect(.regular.interactive())
        Button("B") { }.glassEffect(.regular.interactive())
    }
}

// With spacing (controls morphing threshold distance)
GlassEffectContainer(spacing: 40.0) {
    // Elements within 40pt morph together
}
```

### Morphing with glassEffectID

Requirements: same `GlassEffectContainer`, each view has `glassEffectID` with shared `@Namespace`, conditional show/hide, animation applied.

```swift
struct MorphingExample: View {
    @State private var isExpanded = false
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 30) {
            Button(isExpanded ? "Collapse" : "Expand") {
                withAnimation(.bouncy) { isExpanded.toggle() }
            }
            .glassEffect()
            .glassEffectID("toggle", in: namespace)

            if isExpanded {
                Button("Action 1") { }
                    .glassEffect()
                    .glassEffectID("action1", in: namespace)
            }
        }
    }
}
```

### glassEffectUnion

Manually combine distant glass effects that can't merge via spacing alone.

```swift
func glassEffectUnion<ID: Hashable>(id: ID, namespace: Namespace.ID) -> some View

// Requirements: same ID, same glass type, similar shapes
Button("Edit") { }
    .buttonStyle(.glass)
    .glassEffectUnion(id: "tools", namespace: controls)
```

### glassEffectTransition

```swift
enum GlassEffectTransition {
    case identity        // No changes
    case matchedGeometry // Default
    case materialize     // Material appearance
}

.glassEffectTransition(.materialize)
```

### Button Styles

```swift
Button("Cancel") { }.buttonStyle(.glass)            // Translucent, secondary
Button("Save") { }.buttonStyle(.glassProminent)      // Opaque, primary
    .tint(.blue)

// Sizes
.controlSize(.mini | .small | .regular | .large | .extraLarge)

// Shapes
.buttonBorderShape(.capsule | .circle | .roundedRectangle(radius: 8))

// Known issue: .glassProminent + .circle has artifacts — fix with:
.clipShape(Circle())
```

### Toolbar

```swift
NavigationStack {
    ContentView()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { }
                // .confirmationAction auto-gets .glassProminent
            }
        }
}

// Grouping with spacers
ToolbarSpacer(.fixed, spacing: 20)
ToolbarSpacer(.flexible)

// Badge
.badge(5)

// Hide glass background on specific item
.sharedBackgroundVisibility(.hidden)
```

### TabView

```swift
TabView {
    Tab("Home", systemImage: "house") { HomeView() }
    Tab("Search", systemImage: "magnifyingglass", role: .search) {
        NavigationStack { SearchView() }
    }
}
.searchable(text: $searchText)
.tabBarMinimizeBehavior(.onScrollDown)  // .automatic | .onScrollDown | .never
.tabViewBottomAccessory {
    NowPlayingBar()  // Persistent glass view above tab bar
}

// Environment
@Environment(\.tabViewBottomAccessoryPlacement) var placement  // .expanded | .collapsed
```

### Sheets

```swift
// Automatic glass background in iOS 26
.sheet(isPresented: $show) {
    SheetContent()
        .presentationDetents([.medium, .large])
}

// Morphing from toolbar button
.matchedTransitionSource(id: "info", in: transition)
.navigationTransition(.zoom(sourceID: "info", in: transition))

// Remove old custom backgrounds for glass
.scrollContentBackground(.hidden)
.containerBackground(.clear, for: .navigation)
```

### NavigationSplitView

```swift
NavigationSplitView {
    List(items) { item in NavigationLink(item.name, value: item) }
        .backgroundExtensionEffect()  // Extends beyond safe area
} detail: {
    DetailView()
}
// Sidebar auto-receives floating Liquid Glass
```

### Search

```swift
.searchable(text: $searchText)
.searchToolbarBehavior(.minimized)
DefaultToolbarItem(kind: .search, placement: .bottomBar)
```

### UIKit Integration

```swift
let glassEffect = UIGlassEffect(glass: .regular, isInteractive: true)
let effectView = UIVisualEffectView(effect: glassEffect)

let containerEffect = UIGlassContainerEffect()
let containerView = UIVisualEffectView(effect: containerEffect)
```

### Backward Compatibility

```swift
extension View {
    @ViewBuilder
    func glassedEffect(in shape: some Shape = Capsule(), interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass = interactive ? Glass.regular.interactive() : .regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(
                shape.fill(.ultraThinMaterial)
                    .overlay(LinearGradient(colors: [.white.opacity(0.3), .clear],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 1))
            )
        }
    }
}
```

### Opt-Out (temporary, expires iOS 27)

```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```

---

## Design Guidelines

### Use Glass For
- Navigation bars, toolbars, tab bars
- Floating action buttons
- Sheets, popovers, menus
- Context-sensitive controls

### Never Use Glass For
- Content layer (lists, tables, media)
- Full-screen backgrounds
- Scrollable content
- Stacked glass layers

### Readability Solutions

1. **Gradient fade** behind tab bar areas (`.deliquify()` pattern)
2. **Strategic tinting**: `.glassEffect(.regular.tint(.purple.opacity(0.8)))`
3. **Background dimming**: `.overlay(Color.black.opacity(0.3))`
4. Use `.regular` variant in most cases

### Performance
- Always use `GlassEffectContainer` for multiple elements
- Limit continuous animations — let glass rest in steady states
- Use `.identity` for conditional toggle (no layout recalc)
- Test on iPhone 11-13 for performance baseline
- Battery impact: ~13% drain vs 1% on iOS 18

### Accessibility (automatic, no code needed)
- Reduced Transparency: increases frosting
- Increased Contrast: stark colors/borders
- Reduced Motion: tones down animations
- iOS 26.1+ Tinted Mode: user-controlled opacity

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
// Let system handle — don't override unless necessary
```

### Anti-Patterns
- Glass-on-glass stacking
- Tinting everything (tint = semantic meaning only)
- Multiple glass effects without container
- Custom opacity bypassing accessibility
- Continuous rotation/animation on glass elements

---

## Complete Example: App with TabView, FAB, Morphing

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: 0) {
                HomeView()
            }
            Tab("Favorites", systemImage: "star", value: 1) {
                FavoritesView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                NavigationStack { SearchView(searchText: $searchText) }
            }
        }
        .searchable(text: $searchText)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if selectedTab == 0 { NowPlayingView() }
        }
    }
}

struct FloatingActionButton: View {
    @Binding var showActions: Bool
    var namespace: Namespace.ID
    let actions = [("photo", "Photo", Color.blue), ("video", "Video", Color.purple)]

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 12) {
                if showActions {
                    ForEach(actions, id: \.0) { action in
                        Button { } label: {
                            HStack {
                                Image(systemName: action.0)
                                Text(action.1).font(.callout.bold())
                            }
                            .frame(height: 48)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.glass)
                        .tint(action.2)
                        .glassEffectID(action.0, in: namespace)
                    }
                }

                Button {
                    withAnimation(.bouncy(duration: 0.35)) { showActions.toggle() }
                } label: {
                    Image(systemName: showActions ? "xmark" : "plus")
                        .font(.title2.bold())
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.orange)
                .glassEffectID("toggle", in: namespace)
            }
        }
    }
}
```

## Source

Reference: https://github.com/conorluddy/LiquidGlassReference
