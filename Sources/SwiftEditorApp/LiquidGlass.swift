import SwiftUI

// MARK: - Liquid Glass View Modifiers

/// Apply Liquid Glass styling to navigation-layer surfaces.
/// Uses .glassEffect() on macOS 26+ (Tahoe) and .ultraThinMaterial on earlier versions.
/// Per Apple guidelines: ONLY for toolbar, sidebar headers, transport bar, workspace tabs, ruler.
/// NEVER for timeline clips, viewer, waveforms, scopes, color wheels.
extension View {

    /// Apply glass effect suitable for toolbar/transport bar surfaces.
    @ViewBuilder
    func liquidGlassBar() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 0))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// Apply glass effect for tab bar buttons/segments.
    @ViewBuilder
    func liquidGlassTabBar() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Apply glass effect for sidebar/inspector header sections.
    @ViewBuilder
    func liquidGlassSidebarHeader() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 0))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// Apply glass effect for the timeline ruler — uses .regular (ruler is navigation, not media).
    @ViewBuilder
    func liquidGlassRuler() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 0))
        } else {
            self.background(.thinMaterial)
        }
    }

    /// Apply glass button styling. Falls back to .borderless on pre-macOS 26.
    @ViewBuilder
    func liquidGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }

    /// Apply prominent glass button styling. Falls back to .borderedProminent on pre-macOS 26.
    @ViewBuilder
    func liquidGlassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - GlassEffectID Modifier

/// Applies .glassEffectID on macOS 26+ for morphing transitions. No-op on earlier.
struct GlassEffectIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - GlassEffectContainer Wrapper

/// Wraps content in a GlassEffectContainer on macOS 26+ for correct glass sampling
/// and morphing transitions. Falls back to a plain container on earlier versions.
struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
