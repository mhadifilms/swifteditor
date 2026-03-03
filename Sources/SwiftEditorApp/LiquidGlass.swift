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

    /// Apply glass effect for the timeline ruler.
    @ViewBuilder
    func liquidGlassRuler() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 0))
        } else {
            self.background(.thinMaterial)
        }
    }
}
