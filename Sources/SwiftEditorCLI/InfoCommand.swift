import ArgumentParser
import Foundation
import SwiftEditorAPI
import CoreMediaPlus

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display information about a project."
    )

    @Argument(help: "Project file path.")
    var project: String

    @Flag(name: .shortAndLong, help: "Show detailed track and clip information.")
    var detailed = false

    func run() async throws {
        let engine = SwiftEditorEngine(projectName: "Info")

        let url = URL(filePath: project)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Error: Project file not found: \(project)")
            throw ExitCode.failure
        }

        try await engine.projectAPI.load(from: url)

        print("Project: \(engine.project.name)")
        print("Duration: \(formatTime(engine.timeline.duration))")
        print("Video Tracks: \(engine.timeline.videoTracks.count)")
        print("Audio Tracks: \(engine.timeline.audioTracks.count)")

        // Count total clips
        var totalClips = 0
        for track in engine.timeline.videoTracks {
            totalClips += engine.timeline.clipsOnTrack(track.id).count
        }
        for track in engine.timeline.audioTracks {
            totalClips += engine.timeline.clipsOnTrack(track.id).count
        }
        print("Total Clips: \(totalClips)")

        // Markers
        let markerCount = engine.timeline.markerManager.markers.count
        if markerCount > 0 {
            print("Markers: \(markerCount)")
        }

        if detailed {
            print("\n--- Tracks ---")

            for (i, track) in engine.timeline.videoTracks.enumerated() {
                let clips = engine.timeline.clipsOnTrack(track.id)
                print("  V\(i + 1): \(clips.count) clip(s)")
                for clip in clips {
                    print("    [\(formatTime(clip.startTime)) - \(formatTime(clip.startTime + clip.duration))] " +
                          "dur=\(formatTime(clip.duration)) speed=\(String(format: "%.1fx", clip.speed))" +
                          (clip.isEnabled ? "" : " [disabled]"))
                }
            }

            for (i, track) in engine.timeline.audioTracks.enumerated() {
                let clips = engine.timeline.clipsOnTrack(track.id)
                print("  A\(i + 1): \(clips.count) clip(s)")
                for clip in clips {
                    print("    [\(formatTime(clip.startTime)) - \(formatTime(clip.startTime + clip.duration))] " +
                          "dur=\(formatTime(clip.duration))")
                }
            }
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
