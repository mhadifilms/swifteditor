import Foundation
import CoreMediaPlus
import AudioEngine

/// Facade for audio operations.
public final class AudioAPI: @unchecked Sendable {
    private let mixer: AudioMixer

    public init(mixer: AudioMixer) {
        self.mixer = mixer
    }

    public func setVolume(_ volume: Float, for trackID: UUID) {
        mixer.setVolume(volume, for: trackID)
    }

    public func setPan(_ pan: Float, for trackID: UUID) {
        mixer.setPan(pan, for: trackID)
    }

    public func startEngine() throws {
        try mixer.start()
    }

    public func stopEngine() {
        mixer.stop()
    }
}
