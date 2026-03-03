import ArgumentParser
import Foundation
import SwiftEditorAPI
import CoreMediaPlus

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export/render a timeline to a video file."
    )

    @Option(name: .shortAndLong, help: "Project file to export.")
    var project: String

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String

    @Option(name: .long, help: "Export preset (h264_1080p, h264_4k, h265_1080p, h265_4k, prores422, prores4444, proresProxy).")
    var preset: String = "h264_1080p"

    func run() async throws {
        let engine = SwiftEditorEngine(projectName: "Export")

        // Load project
        let projectURL = URL(filePath: project)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            print("Error: Project file not found: \(project)")
            throw ExitCode.failure
        }

        try await engine.projectAPI.load(from: projectURL)
        print("Loaded project: \(project)")
        print("Timeline duration: \(formatTime(engine.timeline.duration))")

        guard engine.timeline.duration > .zero else {
            print("Error: Timeline is empty, nothing to export.")
            throw ExitCode.failure
        }

        let outputURL = URL(filePath: output)
        let exportPreset = parsePreset(preset)

        print("Exporting to: \(output)")
        print("  Preset: \(preset)")

        try await engine.export.export(to: outputURL, preset: exportPreset)

        print("Export complete: \(output)")
    }

    private func parsePreset(_ name: String) -> ExportPreset {
        switch name.lowercased() {
        case "h264_4k": return .h264_4k
        case "h265_1080p": return .h265_1080p
        case "h265_4k": return .h265_4k
        case "prores422", "prores": return .prores422
        case "prores4444": return .prores4444
        case "proresproxy": return .proresProxy
        default: return .h264_1080p
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
