import Testing
import Foundation
@testable import ProjectModel
@testable import CoreMediaPlus

@Suite("ProjectModel Tests")
struct ProjectModelTests {

    @Test("Project creation")
    func projectCreation() {
        let project = Project(name: "Test Project")
        #expect(project.name == "Test Project")
        #expect(project.version == Project.currentVersion)
    }

    @Test("Project JSON round-trip")
    func jsonRoundTrip() throws {
        let project = Project(name: "Round Trip Test")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Project.self, from: data)

        #expect(restored.name == project.name)
        #expect(restored.id == project.id)
        #expect(restored.version == project.version)
    }

    @Test("ClipData duration calculation")
    func clipDuration() {
        let clip = ClipData(
            sourceAssetID: UUID(),
            startTime: Rational(0, 1),
            sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1),
            speed: Rational(2, 1) // 2x speed
        )
        #expect(clip.duration == Rational(24, 1)) // Half duration at 2x speed
    }

    @Test("Sequence creation")
    func sequenceCreation() {
        let sequence = ProjectModel.Sequence(name: "My Sequence")
        #expect(sequence.name == "My Sequence")
        #expect(sequence.tracks.isEmpty)
    }

    @Test("TrackData with clips")
    func trackWithClips() {
        let clip = ClipData(sourceAssetID: UUID(),
                            startTime: Rational(0, 1),
                            sourceIn: Rational(0, 1),
                            sourceOut: Rational(24, 1))
        let track = TrackData(name: "V1", trackType: .video, clips: [clip])
        #expect(track.clips.count == 1)
        #expect(track.trackType == .video)
    }

    @Test("MediaBinModel recursive structure")
    func mediaBin() {
        var root = MediaBinModel(name: "Root")
        let subfolder = MediaBinModel(name: "Subfolder")
        root.subfolders.append(subfolder)
        #expect(root.subfolders.count == 1)
        #expect(root.subfolders[0].name == "Subfolder")
    }

    @Test("ProjectFileManager save and load")
    func saveAndLoad() throws {
        let project = Project(name: "File Test")
        let fm = ProjectFileManager()
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_project.json")

        defer { try? FileManager.default.removeItem(at: url) }

        try fm.save(project, to: url)
        let loaded = try fm.load(from: url)
        #expect(loaded.name == "File Test")
        #expect(loaded.id == project.id)
    }

    @Test("EffectData serialization")
    func effectDataSerialization() throws {
        let effect = EffectData(effectID: "blur", name: "Gaussian Blur",
                                parameters: ["radius": .float(5.0)])
        let data = try JSONEncoder().encode(effect)
        let restored = try JSONDecoder().decode(EffectData.self, from: data)
        #expect(restored.effectID == "blur")
        #expect(restored.parameters["radius"] == .float(5.0))
    }

    @Test("Marker serialization")
    func markerSerialization() throws {
        let marker = Marker(name: "Scene Start", time: Rational(120, 1), color: .green)
        let data = try JSONEncoder().encode(marker)
        let restored = try JSONDecoder().decode(Marker.self, from: data)
        #expect(restored.name == "Scene Start")
        #expect(restored.color == .green)
    }
}
