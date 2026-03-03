import Testing
import Foundation
@testable import AudioEngine

@Suite("AudioMixer Tests")
struct AudioMixerTests {
    @Test("Create mixer and add/remove tracks")
    func addAndRemoveTracks() {
        let mixer = AudioMixer()
        let trackID = UUID()

        let node = mixer.addTrack(id: trackID)
        #expect(node.volume == 1.0)

        mixer.removeTrack(id: trackID)
        // Removing again should be a no-op
        mixer.removeTrack(id: trackID)
    }

    @Test("Set volume clamps to player node")
    func setVolume() {
        let mixer = AudioMixer()
        let trackID = UUID()
        let node = mixer.addTrack(id: trackID)

        mixer.setVolume(0.5, for: trackID)
        #expect(node.volume == 0.5)

        mixer.setVolume(0.0, for: trackID)
        #expect(node.volume == 0.0)
    }

    @Test("Set pan on track")
    func setPan() {
        let mixer = AudioMixer()
        let trackID = UUID()
        let node = mixer.addTrack(id: trackID)

        mixer.setPan(-1.0, for: trackID)
        #expect(node.pan == -1.0)

        mixer.setPan(0.5, for: trackID)
        #expect(node.pan == 0.5)
    }

    @Test("Set volume for nonexistent track is no-op")
    func setVolumeNonexistent() {
        let mixer = AudioMixer()
        mixer.setVolume(0.5, for: UUID())
        // Should not crash
    }

    @Test("Set pan for nonexistent track is no-op")
    func setPanNonexistent() {
        let mixer = AudioMixer()
        mixer.setPan(0.5, for: UUID())
        // Should not crash
    }
}
