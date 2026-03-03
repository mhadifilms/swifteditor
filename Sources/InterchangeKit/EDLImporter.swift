// InterchangeKit — CMX3600 EDL Import
import Foundation
import CoreMediaPlus
import ProjectModel

/// Parses CMX3600 Edit Decision List files line by line.
///
/// EDL format:
/// ```
/// TITLE: MY_EDIT
/// FCM: NON-DROP FRAME
///
/// 001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
/// * FROM CLIP NAME: MyClip.mov
/// ```
public struct EDLImporter: Sendable {

    /// Frame rate for timecode parsing. Defaults to 24 fps.
    public var frameRate: Rational

    public init(frameRate: Rational = Rational(24, 1)) {
        self.frameRate = frameRate
    }

    /// Parse EDL text content.
    public func parse(text: String) throws -> EDLDocument {
        var document = EDLDocument()
        let lines = text.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // TITLE line
            if trimmed.hasPrefix("TITLE:") {
                document.title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // FCM line
            if trimmed.hasPrefix("FCM:") {
                let mode = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                document.dropFrame = mode.contains("DROP") && !mode.contains("NON")
                continue
            }

            // Comment lines
            if trimmed.hasPrefix("*") {
                let comment = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                // Apply comment to the most recently parsed event
                if !document.events.isEmpty {
                    if comment.hasPrefix("FROM CLIP NAME:") {
                        let clipName = String(comment.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                        document.events[document.events.count - 1].clipName = clipName
                    }
                    document.events[document.events.count - 1].comments.append(comment)
                }
                continue
            }

            // Event line: starts with a number
            if let event = parseEventLine(trimmed, lineNumber: lineIndex + 1) {
                document.events.append(event)
            }
        }

        return document
    }

    /// Parse EDL from file data.
    public func parse(data: Data) throws -> EDLDocument {
        guard let text = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .ascii) else {
            throw EDLImportError.invalidEncoding
        }
        return try parse(text: text)
    }

    // MARK: - Private

    private func parseEventLine(_ line: String, lineNumber: Int) -> EDLEditEvent? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8 else { return nil }

        // First field must be an event number
        guard let eventNumber = Int(parts[0]) else { return nil }

        let reelName = parts[1]
        let trackStr = parts[2]
        let editStr = parts[3]

        // Parse track indicator
        let trackIndicator: EDLTrackType
        if trackStr == "V" {
            trackIndicator = .video
        } else if trackStr.hasPrefix("A") {
            let channel = Int(trackStr.dropFirst()) ?? 1
            trackIndicator = .audio(channel: channel)
        } else if trackStr.contains("V") && trackStr.contains("A") {
            trackIndicator = .videoAndAudio
        } else if trackStr == "B" {
            trackIndicator = .videoAndAudio
        } else {
            trackIndicator = .video
        }

        // Parse edit type
        let editType: EDLTransitionType
        var transitionFrames: Int = 0
        if editStr == "C" {
            editType = .cut
        } else if editStr == "D" {
            editType = .dissolve
            // The next field may be transition duration in frames
            if parts.count > 4, let frames = Int(parts[4]) {
                transitionFrames = frames
            }
        } else if editStr.hasPrefix("W") {
            let wipeCode = Int(editStr.dropFirst()) ?? 0
            editType = .wipe(code: wipeCode)
            if parts.count > 4, let frames = Int(parts[4]) {
                transitionFrames = frames
            }
        } else {
            editType = .cut
        }

        // Timecodes are always the last 4 fields
        let tcStartIndex = parts.count - 4
        guard tcStartIndex >= 4 else { return nil }

        let fps = frameRateAsDouble()
        guard let sourceIn = parseTimecode(parts[tcStartIndex], fps: fps),
              let sourceOut = parseTimecode(parts[tcStartIndex + 1], fps: fps),
              let recordIn = parseTimecode(parts[tcStartIndex + 2], fps: fps),
              let recordOut = parseTimecode(parts[tcStartIndex + 3], fps: fps) else {
            return nil
        }

        return EDLEditEvent(
            eventNumber: eventNumber,
            reelName: reelName,
            trackType: trackIndicator,
            transitionType: editType,
            transitionDuration: transitionFrames,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            recordIn: recordIn,
            recordOut: recordOut
        )
    }

    private func frameRateAsDouble() -> Double {
        guard frameRate.isValid, frameRate.denominator != 0 else { return 24.0 }
        return Double(frameRate.numerator) / Double(frameRate.denominator)
    }
}

// MARK: - EDL Data Types

/// Represents a parsed EDL document.
public struct EDLDocument: Sendable {
    public var title: String = ""
    public var dropFrame: Bool = false
    public var events: [EDLEditEvent] = []

    public init() {}
}

/// A single edit event from an EDL.
public struct EDLEditEvent: Sendable {
    public var eventNumber: Int
    public var reelName: String
    public var trackType: EDLTrackType
    public var transitionType: EDLTransitionType
    public var transitionDuration: Int
    public var sourceIn: Rational
    public var sourceOut: Rational
    public var recordIn: Rational
    public var recordOut: Rational
    public var clipName: String?
    public var comments: [String] = []

    public init(eventNumber: Int = 0, reelName: String = "",
                trackType: EDLTrackType = .video,
                transitionType: EDLTransitionType = .cut,
                transitionDuration: Int = 0,
                sourceIn: Rational = .zero, sourceOut: Rational = .zero,
                recordIn: Rational = .zero, recordOut: Rational = .zero,
                clipName: String? = nil, comments: [String] = []) {
        self.eventNumber = eventNumber
        self.reelName = reelName
        self.trackType = trackType
        self.transitionType = transitionType
        self.transitionDuration = transitionDuration
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.recordIn = recordIn
        self.recordOut = recordOut
        self.clipName = clipName
        self.comments = comments
    }
}

/// Track types in EDL format.
public enum EDLTrackType: Sendable, Equatable {
    case video
    case audio(channel: Int)
    case videoAndAudio
}

/// Transition types in EDL format.
public enum EDLTransitionType: Sendable, Equatable {
    case cut
    case dissolve
    case wipe(code: Int)
}

/// EDL import errors.
public enum EDLImportError: Error, Sendable {
    case invalidEncoding
    case invalidFormat(line: Int, detail: String)
}

// MARK: - Timecode Parsing

/// Parse a SMPTE timecode string "HH:MM:SS:FF" or "HH;MM;SS;FF" to a Rational.
public func parseTimecode(_ string: String, fps: Double) -> Rational? {
    let separators = CharacterSet(charactersIn: ":;")
    let parts = string.components(separatedBy: separators)
    guard parts.count == 4,
          let h = Int(parts[0]),
          let m = Int(parts[1]),
          let s = Int(parts[2]),
          let f = Int(parts[3]) else {
        return nil
    }

    let framesPerSecond = Int(fps.rounded())
    guard framesPerSecond > 0 else { return nil }

    let totalFrames = h * 3600 * framesPerSecond
                    + m * 60 * framesPerSecond
                    + s * framesPerSecond
                    + f

    // Convert frame count to rational time
    // For integer frame rates: totalFrames / fps
    // For NTSC: totalFrames * 1001 / (fps_rounded * 1000)
    if fps > 29.9 && fps < 30.1 {
        // 29.97 fps: timescale 30000
        return Rational(Int64(totalFrames) * 1001, 30000)
    } else if fps > 23.9 && fps < 24.0 {
        // 23.976 fps: timescale 24000
        return Rational(Int64(totalFrames) * 1001, 24000)
    } else {
        return Rational(Int64(totalFrames), Int64(framesPerSecond))
    }
}

// MARK: - Conversion to ProjectModel

extension EDLDocument {
    /// Convert the parsed EDL to a ProjectModel.Sequence.
    /// EDL is single-track, so we create one video track.
    public func toSequence() -> ProjectModel.Sequence {
        var videoClips: [ClipData] = []
        var audioClips: [ClipData] = []

        for event in events {
            // Create a deterministic asset UUID from the reel name
            let assetID = deterministicUUID(from: event.reelName)

            let clipData = ClipData(
                sourceAssetID: assetID,
                startTime: event.recordIn,
                sourceIn: event.sourceIn,
                sourceOut: event.sourceOut
            )

            switch event.trackType {
            case .video:
                videoClips.append(clipData)
            case .audio:
                audioClips.append(clipData)
            case .videoAndAudio:
                videoClips.append(clipData)
                audioClips.append(clipData)
            }
        }

        var tracks: [TrackData] = []

        if !videoClips.isEmpty {
            var videoTrack = TrackData(name: "V1", trackType: .video)
            videoTrack.clips = videoClips
            tracks.append(videoTrack)
        }

        if !audioClips.isEmpty {
            var audioTrack = TrackData(name: "A1", trackType: .audio)
            audioTrack.clips = audioClips
            tracks.append(audioTrack)
        }

        return ProjectModel.Sequence(
            name: title.isEmpty ? "Imported EDL" : title,
            tracks: tracks
        )
    }

    private func deterministicUUID(from string: String) -> UUID {
        let bytes = Array(string.utf8)
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        for (i, byte) in bytes.enumerated() {
            hash[i % 16] ^= byte
        }
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}
