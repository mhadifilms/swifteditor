import ArgumentParser
import Foundation
import SwiftEditorAPI
import MediaManager
import CoreMediaPlus

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import media files into a project."
    )

    @Argument(help: "Media file paths to import.")
    var files: [String]

    @Option(name: .shortAndLong, help: "Project file to import into.")
    var project: String?

    @Flag(name: .shortAndLong, help: "Print detailed asset metadata.")
    var verbose = false

    func run() async throws {
        let engine = SwiftEditorEngine(projectName: project ?? "CLI Project")

        // Load project if specified
        if let projectPath = project {
            let url = URL(filePath: projectPath)
            if FileManager.default.fileExists(atPath: url.path) {
                try await engine.projectAPI.load(from: url)
                print("Loaded project: \(projectPath)")
            }
        }

        // Import each file
        for filePath in files {
            let url = URL(filePath: filePath)

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Error: File not found: \(filePath)")
                continue
            }

            do {
                let assets = try await engine.media.importAssetsDirectly(from: [url])
                for asset in assets {
                    print("Imported: \(asset.url.lastPathComponent)")
                    if verbose {
                        print("  ID:         \(asset.id)")
                        print("  Duration:   \(formatTime(asset.duration))")
                        if let vp = asset.videoParams {
                            print("  Resolution: \(vp.width)x\(vp.height)")
                        }
                    }
                }
            } catch {
                print("Error importing \(filePath): \(error)")
            }
        }

        // Save project if path given
        if let projectPath = project {
            let url = URL(filePath: projectPath)
            try await engine.projectAPI.save(to: url)
            print("Project saved to: \(projectPath)")
        }
    }

    private func formatTime(_ time: Rational) -> String {
        let total = time.seconds
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let frames = Int((total - Double(Int(total))) * 24)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
