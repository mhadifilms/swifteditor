import ArgumentParser

@main
struct SwiftEditorCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-editor",
        abstract: "SwiftEditor command-line tool for non-linear video editing.",
        version: "1.0.0",
        subcommands: [
            ImportCommand.self,
            ExportCommand.self,
            InfoCommand.self,
            ScriptCommand.self,
        ]
    )
}
