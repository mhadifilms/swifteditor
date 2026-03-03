import Foundation
import CoreMediaPlus

/// Manages SRT subtitle file import and export.
public struct SRTManager: Sendable {

    public init() {}

    // MARK: - Import

    /// Parse an SRT file into subtitle cues.
    public func importSRT(from url: URL) throws -> [SubtitleCue] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseSRT(content)
    }

    /// Parse SRT-formatted text into subtitle cues.
    public func parseSRT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            // Line 0: sequence number (ignored, we use UUID)
            // Line 1: timecodes  "00:00:01,000 --> 00:00:04,000"
            // Line 2+: text content
            let timecodeComponents = lines[1].components(separatedBy: " --> ")
            guard timecodeComponents.count == 2,
                  let startTime = parseSRTTimecode(timecodeComponents[0].trimmingCharacters(in: .whitespaces)),
                  let endTime = parseSRTTimecode(timecodeComponents[1].trimmingCharacters(in: .whitespaces))
            else { continue }

            let textContent = lines[2...].joined(separator: "\n")
            guard !textContent.isEmpty else { continue }

            let cue = SubtitleCue(
                text: textContent,
                startTime: startTime,
                endTime: endTime,
                style: .default
            )
            cues.append(cue)
        }

        return cues
    }

    // MARK: - Export

    /// Export subtitle cues to an SRT file.
    public func exportSRT(cues: [SubtitleCue], to url: URL) throws {
        let content = formatSRT(cues)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Format subtitle cues as an SRT string.
    public func formatSRT(_ cues: [SubtitleCue]) -> String {
        let sorted = cues.sorted { $0.startTime < $1.startTime }
        var result = ""

        for (index, cue) in sorted.enumerated() {
            if index > 0 { result += "\n" }
            result += "\(index + 1)\n"
            result += "\(formatSRTTimecode(cue.startTime)) --> \(formatSRTTimecode(cue.endTime))\n"
            result += "\(cue.text)\n"
        }

        return result
    }

    // MARK: - Timecode Parsing

    /// Parse "HH:MM:SS,mmm" into a Rational.
    private func parseSRTTimecode(_ text: String) -> Rational? {
        // Format: HH:MM:SS,mmm or HH:MM:SS.mmm
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }

        guard let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }

        let secondsParts = parts[2].components(separatedBy: ".")
        guard let wholeSeconds = Int(secondsParts[0]) else { return nil }

        let milliseconds: Int
        if secondsParts.count > 1, let ms = Int(secondsParts[1].padding(toLength: 3, withPad: "0", startingAt: 0)) {
            milliseconds = ms
        } else {
            milliseconds = 0
        }

        let totalMilliseconds = Int64(hours * 3600000 + minutes * 60000 + wholeSeconds * 1000 + milliseconds)
        return Rational(totalMilliseconds, 1000)
    }

    /// Format a Rational time as "HH:MM:SS,mmm".
    private func formatSRTTimecode(_ time: Rational) -> String {
        let totalMs = Int(time.seconds * 1000)
        let hours = totalMs / 3600000
        let minutes = (totalMs % 3600000) / 60000
        let seconds = (totalMs % 60000) / 1000
        let ms = totalMs % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
    }
}
