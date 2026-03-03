import SwiftUI
import SwiftEditorAPI
import ProjectModel
import CoreMediaPlus

@main
struct SwiftEditorApp: App {
    @State private var engine = SwiftEditorEngine(projectName: "Untitled")

    var body: some Scene {
        WindowGroup {
            MainWindowView(engine: engine)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .commands {
            AppMenuCommands(engine: engine)
        }
    }
}
