import SwiftUI
import SwiftEditorAPI
import EffectsEngine
import CoreMediaPlus

/// Panel for browsing and adding effects to clips.
struct EffectsBrowserView: View {
    let engine: SwiftEditorEngine

    @State private var searchText = ""
    @State private var selectedCategory: BuiltInEffectCategory?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Effects")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Effects", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityHint("Clear the effects search field")
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

            Divider()

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    CategoryPill(name: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(BuiltInEffectCategory.allCases, id: \.rawValue) { category in
                        CategoryPill(name: category.displayName, isSelected: selectedCategory == category) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider()

            // Effects list
            List(filteredEffects, id: \.id) { descriptor in
                EffectRow(descriptor: descriptor, engine: engine)
            }
            .listStyle(.plain)
        }
    }

    private var filteredEffects: [BuiltInEffectDescriptor] {
        var effects = engine.effects.builtInEffects
        if let category = selectedCategory {
            effects = effects.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            effects = effects.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return effects
    }
}

struct CategoryPill: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) category")
        .accessibilityHint("Filter effects to the \(name) category")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EffectRow: View {
    let descriptor: BuiltInEffectDescriptor
    let engine: SwiftEditorEngine

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .font(.subheadline)
                Text(descriptor.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Add to selected clip
            Button {
                addToSelectedClip()
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .disabled(engine.timeline.selection.selectedClipIDs.isEmpty)
            .help("Add to selected clip")
            .accessibilityLabel("Add \(descriptor.name)")
            .accessibilityHint("Apply this effect to the currently selected clip")
        }
        .padding(.vertical, 2)
    }

    private func addToSelectedClip() {
        guard let clipID = engine.timeline.selection.selectedClipIDs.first else { return }
        Task {
            try? await engine.effects.addEffect(clipID: clipID, pluginID: descriptor.id, name: descriptor.name)
        }
    }
}

extension BuiltInEffectCategory {
    var displayName: String {
        switch self {
        case .colorCorrection: return "Color"
        case .blur: return "Blur"
        case .sharpen: return "Sharpen"
        case .stylize: return "Stylize"
        case .distortion: return "Distortion"
        }
    }
}
