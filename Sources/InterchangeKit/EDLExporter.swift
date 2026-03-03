// InterchangeKit — CMX3600 EDL Export
import Foundation
import CoreMediaPlus
import ProjectModel

/// Exports a project to CMX3600 Edit Decision List format.
///
/// CMX3600 EDL is a line-based plain-text format used universally across NLEs.
/// Each line represents an edit event with format:
/// `EVENT# REEL TRACK TYPE DURATION SRC_IN SRC_OUT REC_IN REC_OUT`
///
/// Timecodes are in HH:MM:SS:FF format.
public struct EDLExporter: Sendable {

    /// Frame rate for timecode conversion. Defaults to 24 fps.
    public var frameRate: Rational

    /// Whether to use drop-frame timecode (for 29.97 fps).
    public var dropFrame: Bool

    public init(frameRate: Rational = Rational(24, 1), dropFrame: Bool = false) {
        self.frameRate = frameRate
        self.dropFrame = dropFrame
    }

    /// Export a project to CMX3600 EDL format.
    /// Since EDL only supports a single track, this exports the first video track.
    public func export(_ project: Project, title: String? = nil) -> String {
        let edlTitle = title ?? project.name
        guard let sequence = project.sequences.first else {
            return formatHeader(title: edlTitle)
        }
        return exportSequence(sequence, title: edlTitle, bin: project.bin)
    }

    /// Export a single sequence.
    public func exportSequence(_ sequence: ProjectModel.Sequence,
                               title: String? = nil,
                               bin: MediaBinModel = MediaBinModel()) -> String {
        let edlTitle = title ?? sequence.name

        // Pick the first video track for EDL export
        let videoTrack = sequence.tracks.first(where: { $0.trackType == .video })
        let audioTrack = sequence.tracks.first(where: { $0.trackType == .audio })

        var events: [EDLEvent] = []
        let binItems = flattenBin(bin)

        // Export video clips
        if let track = videoTrack {
            for clip in track.clips {
                let reelName = reelNameForAsset(clip.sourceAssetID, binItems: binItems)
                let clipName = binItems.first(where: { $0.id == clip.sourceAssetID })?.name

                let event = EDLEvent(
                    reelName: reelName,
                    trackIndicator: "V",
                    editType: .cut,
                    sourceIn: clip.sourceIn,
                    sourceOut: clip.sourceOut,
                    recordIn: clip.startTime,
                    recordOut: clip.startTime + clip.duration,
                    clipName: clipName
                )
                events.append(event)
            }
        }

        // Export audio clips as separate events
        if let track = audioTrack {
            for clip in track.clips {
                let reelName = reelNameForAsset(clip.sourceAssetID, binItems: binItems)
                let clipName = binItems.first(where: { $0.id == clip.sourceAssetID })?.name

                let event = EDLEvent(
                    reelName: reelName,
                    trackIndicator: "A",
                    editType: .cut,
                    sourceIn: clip.sourceIn,
                    sourceOut: clip.sourceOut,
                    recordIn: clip.startTime,
                    recordOut: clip.startTime + clip.duration,
                    clipName: clipName
                )
                events.append(event)
            }
        }

        // Sort events by record in-point
        events.sort { $0.recordIn < $1.recordIn }

        return formatEDL(title: edlTitle, events: events)
    }

    /// Export individual events for custom EDL construction.
    public func formatEDL(title: String, events: [EDLEvent]) -> String {
        var lines: [String] = []
        lines.append("TITLE: \(sanitizeEDLString(title))")
        lines.append(dropFrame ? "FCM: DROP FRAME" : "FCM: NON-DROP FRAME")
        lines.append("")

        let fps = frameRateAsDouble()
        for (index, event) in events.enumerated() {
            let eventNum = String(format: "%03d", index + 1)
            let reel = String(event.reelName.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
            let track = event.trackIndicator.padding(toLength: 5, withPad: " ", startingAt: 0)
            let editStr = event.editType.edlString

            let srcIn = rationalToTimecode(event.sourceIn, fps: fps)
            let srcOut = rationalToTimecode(event.sourceOut, fps: fps)
            let recIn = rationalToTimecode(event.recordIn, fps: fps)
            let recOut = rationalToTimecode(event.recordOut, fps: fps)

            var line = "\(eventNum)  \(reel) \(track) \(editStr)"
            if case .dissolve(let frames) = event.editType {
                line += " \(String(format: "%03d", frames))"
            } else if case .wipe(let code, let frames) = event.editType {
                _ = code
                line += " \(String(format: "%03d", frames))"
            }
            line += " \(srcIn) \(srcOut) \(recIn) \(recOut)"
            lines.append(line)

            if let name = event.clipName {
                lines.append("* FROM CLIP NAME: \(name)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Types

    /// A single edit event in an EDL.
    public struct EDLEvent: Sendable {
        public var reelName: String
        public var trackIndicator: String
        public var editType: EDLEditType
        public var sourceIn: Rational
        public var sourceOut: Rational
        public var recordIn: Rational
        public var recordOut: Rational
        public var clipName: String?

        public init(reelName: String, trackIndicator: String = "V",
                    editType: EDLEditType = .cut,
                    sourceIn: Rational = .zero, sourceOut: Rational = .zero,
                    recordIn: Rational = .zero, recordOut: Rational = .zero,
                    clipName: String? = nil) {
            self.reelName = reelName
            self.trackIndicator = trackIndicator
            self.editType = editType
            self.sourceIn = sourceIn
            self.sourceOut = sourceOut
            self.recordIn = recordIn
            self.recordOut = recordOut
            self.clipName = clipName
        }
    }

    /// EDL edit types.
    public enum EDLEditType: Sendable {
        case cut
        case dissolve(frames: Int)
        case wipe(code: Int, frames: Int)

        var edlString: String {
            switch self {
            case .cut: return "C   "
            case .dissolve: return "D   "
            case .wipe(let code, _): return String(format: "W%03d", code)
            }
        }
    }

    // MARK: - Private

    private func frameRateAsDouble() -> Double {
        guard frameRate.isValid, frameRate.denominator != 0 else { return 24.0 }
        return Double(frameRate.numerator) / Double(frameRate.denominator)
    }

    private func reelNameForAsset(_ assetID: UUID, binItems: [BinItemData]) -> String {
        if let item = binItems.first(where: { $0.id == assetID }) {
            // Use first 8 chars of the file name (without extension)
            let name = (item.name as NSString).deletingPathExtension
            let cleaned = name.replacingOccurrences(of: " ", with: "_")
            return String(cleaned.prefix(8))
        }
        // Generate a reel name from the UUID
        return String(assetID.uuidString.prefix(8))
    }

    private func flattenBin(_ bin: MediaBinModel) -> [BinItemData] {
        var items = bin.items
        for subfolder in bin.subfolders {
            items.append(contentsOf: flattenBin(subfolder))
        }
        return items
    }

    private func sanitizeEDLString(_ string: String) -> String {
        // EDL titles should be plain ASCII, no special characters
        string.replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "\r", with: "")
    }
}

// MARK: - Timecode Formatting

/// Convert a Rational time to SMPTE timecode string "HH:MM:SS:FF".
public func rationalToTimecode(_ time: Rational, fps: Double) -> String {
    guard time.isValid else { return "00:00:00:00" }

    let totalSeconds = time.seconds
    let totalFrames = Int(totalSeconds * fps + 0.5)

    let framesPerSecond = Int(fps.rounded())
    guard framesPerSecond > 0 else { return "00:00:00:00" }

    let ff = totalFrames % framesPerSecond
    let totalSecondsInt = totalFrames / framesPerSecond
    let ss = totalSecondsInt % 60
    let mm = (totalSecondsInt / 60) % 60
    let hh = totalSecondsInt / 3600

    return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
}

/// Format the EDL header lines.
func formatHeader(title: String) -> String {
    "TITLE: \(title)\nFCM: NON-DROP FRAME\n"
}
