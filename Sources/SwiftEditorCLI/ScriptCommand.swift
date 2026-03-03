import ArgumentParser
import Foundation
import SwiftEditorAPI
import CommandBus
import CoreMediaPlus
import TimelineKit

struct ScriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "script",
        abstract: "Execute a JSON command script against a project.",
        subcommands: [RunScript.self]
    )
}

struct RunScript: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a JSON command script file."
    )

    @Argument(help: "Path to the JSON script file.")
    var scriptPath: String

    @Option(name: .shortAndLong, help: "Project file to operate on.")
    var project: String?

    @Option(name: .shortAndLong, help: "Output project file path (saves after script).")
    var output: String?

    @Flag(name: .shortAndLong, help: "Print each command as it executes.")
    var verbose = false

    func run() async throws {
        let engine = SwiftEditorEngine(projectName: project ?? "Script")

        // Load project if specified
        if let projectPath = project {
            let url = URL(filePath: projectPath)
            if FileManager.default.fileExists(atPath: url.path) {
                try await engine.projectAPI.load(from: url)
                if verbose { print("Loaded project: \(projectPath)") }
            }
        }

        // Read script file
        let scriptURL = URL(filePath: scriptPath)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            print("Error: Script file not found: \(scriptPath)")
            throw ExitCode.failure
        }

        let data = try Data(contentsOf: scriptURL)

        // Run script
        let runner = ScriptRunner(engine: engine)
        let results = try await runner.execute(scriptData: data, verbose: verbose)

        print("Script completed: \(results.commandsExecuted) command(s) executed, " +
              "\(results.errors) error(s)")

        // Save project if output specified
        if let outputPath = output {
            let url = URL(filePath: outputPath)
            try await engine.projectAPI.save(to: url)
            print("Project saved to: \(outputPath)")
        }
    }
}

// MARK: - Script Runner

/// Executes a JSON array of serialized commands through the CommandBus.
struct ScriptRunner {
    let engine: SwiftEditorEngine

    struct ScriptResult {
        var commandsExecuted: Int
        var errors: Int
    }

    /// Execute a script from JSON data.
    /// Expected format: an array of command objects, each with a "type" field
    /// and command-specific fields.
    func execute(scriptData: Data, verbose: Bool) async throws -> ScriptResult {
        let commands = try JSONDecoder().decode([ScriptEntry].self, from: scriptData)

        var executed = 0
        var errors = 0

        for (index, entry) in commands.enumerated() {
            if verbose {
                print("[\(index + 1)/\(commands.count)] \(entry.type): \(entry.description ?? "")")
            }

            do {
                try await dispatchCommand(entry)
                executed += 1
            } catch {
                errors += 1
                print("  Error at command \(index + 1) (\(entry.type)): \(error)")
            }
        }

        return ScriptResult(commandsExecuted: executed, errors: errors)
    }

    private func dispatchCommand(_ entry: ScriptEntry) async throws {
        switch entry.type {
        case "addTrack":
            let type = entry.trackType == "audio" ? TrackType.audio : TrackType.video
            let index = entry.index ?? 0
            engine.timeline.requestTrackInsert(at: index, type: type)

        case "addClip":
            guard let trackIndex = entry.trackIndex,
                  let startTime = entry.startTime,
                  let sourceIn = entry.sourceIn,
                  let sourceOut = entry.sourceOut else {
                throw ScriptError.missingField("addClip requires trackIndex, startTime, sourceIn, sourceOut")
            }
            let trackIDs = engine.timeline.videoTracks.map(\.id) + engine.timeline.audioTracks.map(\.id)
            guard trackIndex < trackIDs.count else {
                throw ScriptError.invalidIndex("Track index \(trackIndex) out of range")
            }
            let trackID = trackIDs[trackIndex]
            let assetID = entry.assetID ?? UUID()
            engine.timeline.requestAddClip(
                sourceAssetID: assetID, trackID: trackID,
                at: Rational(Int64(startTime), 1),
                sourceIn: Rational(Int64(sourceIn), 1),
                sourceOut: Rational(Int64(sourceOut), 1)
            )

        case "split":
            guard let trackIndex = entry.trackIndex, let time = entry.time else {
                throw ScriptError.missingField("split requires trackIndex and time")
            }
            let trackIDs = engine.timeline.videoTracks.map(\.id) + engine.timeline.audioTracks.map(\.id)
            guard trackIndex < trackIDs.count else {
                throw ScriptError.invalidIndex("Track index \(trackIndex) out of range")
            }
            let trackID = trackIDs[trackIndex]
            let splitTime = Rational(Int64(time), 1)
            if let clip = engine.timeline.clipAt(time: splitTime, trackID: trackID) {
                engine.timeline.requestClipSplit(clipID: clip.id, at: splitTime)
            }

        case "bladeAll":
            guard let time = entry.time else {
                throw ScriptError.missingField("bladeAll requires time")
            }
            engine.timeline.requestBladeAll(at: Rational(Int64(time), 1))

        case "undo":
            engine.timeline.undoManager.undo()

        case "redo":
            engine.timeline.undoManager.redo()

        default:
            throw ScriptError.unknownCommand(entry.type)
        }
    }
}

// MARK: - Script Types

struct ScriptEntry: Codable {
    let type: String
    var description: String?
    var trackType: String?
    var index: Int?
    var trackIndex: Int?
    var startTime: Int?
    var sourceIn: Int?
    var sourceOut: Int?
    var time: Int?
    var assetID: UUID?
}

enum ScriptError: Error, CustomStringConvertible {
    case missingField(String)
    case invalidIndex(String)
    case unknownCommand(String)

    var description: String {
        switch self {
        case .missingField(let msg): return "Missing field: \(msg)"
        case .invalidIndex(let msg): return "Invalid index: \(msg)"
        case .unknownCommand(let cmd): return "Unknown command: \(cmd)"
        }
    }
}
