import SwiftUI

/// A reference sheet displaying all keyboard shortcuts grouped by category.
/// Opened from the Help menu or via Cmd+/.
struct KeyboardShortcutsHelpView: View {
    private let manager = KeyboardShortcutManager.shared

    private var groupedActions: [(category: String, actions: [ActionID])] {
        let categories = ["File", "Edit", "Playback", "Tools", "Mark", "Clip", "Timeline", "Workspace", "View"]
        return categories.compactMap { category in
            let actions = ActionID.allCases.filter { $0.category == category }
            guard !actions.isEmpty else { return nil }
            return (category: category, actions: actions)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())
                Spacer()
                Text("Preset: \(manager.activePreset.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Shortcuts grid
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedActions, id: \.category) { group in
                        ShortcutCategorySection(
                            category: group.category,
                            actions: group.actions,
                            manager: manager
                        )
                    }
                }
                .padding()
            }
        }
    }
}

/// A section showing all shortcuts for one category.
private struct ShortcutCategorySection: View {
    let category: String
    let actions: [ActionID]
    let manager: KeyboardShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category)
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 160), alignment: .leading),
                GridItem(.fixed(120), alignment: .trailing),
            ], spacing: 4) {
                ForEach(actions) { action in
                    Text(action.displayName)
                        .font(.subheadline)

                    Text(manager.displayString(for: action))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(category) shortcuts")
    }
}
