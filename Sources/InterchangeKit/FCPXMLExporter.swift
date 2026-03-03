// InterchangeKit — FCPXML Export
import Foundation
import CoreMediaPlus
import ProjectModel

/// Generates valid FCPXML documents from a Project model.
///
/// FCPXML uses a `<library> > <event> > <project> > <sequence> > <spine>` hierarchy
/// with rational time strings (e.g. "123/600s").
public struct FCPXMLExporter: Sendable {

    public init() {}

    /// Export a full project to FCPXML 1.11 format.
    public func export(_ project: Project) -> String {
        var resourceID = 1
        var xml = header()

        // Resources section
        xml += "    <resources>\n"

        // Format resource
        let formatID = "r\(resourceID)"
        resourceID += 1
        let settings = project.settings
        let frameDuration = Rational(1, 1) / settings.frameRate
        xml += "        <format id=\"\(formatID)\" name=\"FFVideoFormat\""
        xml += " frameDuration=\"\(rationalToFCPXML(frameDuration))\""
        xml += " width=\"\(settings.videoParams.width)\""
        xml += " height=\"\(settings.videoParams.height)\"/>\n"

        // Collect all unique asset IDs across all sequences
        var assetIDMap: [UUID: String] = [:]
        for sequence in project.sequences {
            for track in sequence.tracks {
                for clip in track.clips {
                    if assetIDMap[clip.sourceAssetID] == nil {
                        let rid = "r\(resourceID)"
                        resourceID += 1
                        assetIDMap[clip.sourceAssetID] = rid
                    }
                }
            }
        }

        // Look up asset metadata from bin
        let binItems = flattenBin(project.bin)
        for (assetUUID, rid) in assetIDMap.sorted(by: { $0.value < $1.value }) {
            let item = binItems.first(where: { $0.id == assetUUID })
            let name = item?.name ?? assetUUID.uuidString
            let src = item?.originalPath ?? ""
            let hasVideo = item?.videoParams != nil ? "1" : "1"
            let hasAudio = item?.audioParams != nil ? "1" : "1"
            var durationAttr = ""
            if let dur = item?.duration {
                durationAttr = " duration=\"\(rationalToFCPXML(dur))\""
            }
            xml += "        <asset id=\"\(rid)\" name=\"\(escapeXML(name))\""
            xml += " src=\"\(escapeXML(src))\""
            xml += " start=\"0s\"\(durationAttr)"
            xml += " hasVideo=\"\(hasVideo)\" hasAudio=\"\(hasAudio)\"/>\n"
        }

        xml += "    </resources>\n"

        // Library > Event > Project
        xml += "    <library>\n"
        xml += "        <event name=\"\(escapeXML(project.name))\">\n"

        for sequence in project.sequences {
            xml += exportSequence(sequence, formatID: formatID, assetIDMap: assetIDMap)
        }

        xml += "        </event>\n"
        xml += "    </library>\n"
        xml += "</fcpxml>\n"

        return xml
    }

    /// Export a single sequence (useful for exporting just the active timeline).
    public func exportSequence(_ sequence: ProjectModel.Sequence,
                               settings: ProjectSettings = .defaultHD,
                               bin: MediaBinModel = MediaBinModel()) -> String {
        var resourceID = 1
        var xml = header()

        xml += "    <resources>\n"

        let formatID = "r\(resourceID)"
        resourceID += 1
        let frameDuration = Rational(1, 1) / settings.frameRate
        xml += "        <format id=\"\(formatID)\" name=\"FFVideoFormat\""
        xml += " frameDuration=\"\(rationalToFCPXML(frameDuration))\""
        xml += " width=\"\(settings.videoParams.width)\""
        xml += " height=\"\(settings.videoParams.height)\"/>\n"

        var assetIDMap: [UUID: String] = [:]
        for track in sequence.tracks {
            for clip in track.clips {
                if assetIDMap[clip.sourceAssetID] == nil {
                    let rid = "r\(resourceID)"
                    resourceID += 1
                    assetIDMap[clip.sourceAssetID] = rid
                }
            }
        }

        let binItems = flattenBin(bin)
        for (assetUUID, rid) in assetIDMap.sorted(by: { $0.value < $1.value }) {
            let item = binItems.first(where: { $0.id == assetUUID })
            let name = item?.name ?? assetUUID.uuidString
            let src = item?.originalPath ?? ""
            xml += "        <asset id=\"\(rid)\" name=\"\(escapeXML(name))\""
            xml += " src=\"\(escapeXML(src))\" start=\"0s\""
            xml += " hasVideo=\"1\" hasAudio=\"1\"/>\n"
        }

        xml += "    </resources>\n"
        xml += "    <library>\n"
        xml += "        <event name=\"Export\">\n"
        xml += exportSequence(sequence, formatID: formatID, assetIDMap: assetIDMap)
        xml += "        </event>\n"
        xml += "    </library>\n"
        xml += "</fcpxml>\n"

        return xml
    }

    // MARK: - Private

    private func header() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n<fcpxml version=\"1.11\">\n"
    }

    private func exportSequence(_ sequence: ProjectModel.Sequence,
                                formatID: String,
                                assetIDMap: [UUID: String]) -> String {
        let totalDuration = computeSequenceDuration(sequence)
        var xml = ""
        xml += "            <project name=\"\(escapeXML(sequence.name))\">\n"
        xml += "                <sequence format=\"\(formatID)\""
        xml += " duration=\"\(rationalToFCPXML(totalDuration))\""
        xml += " tcStart=\"0s\" tcFormat=\"NDF\">\n"

        // Video tracks go into the spine; audio tracks as separate lanes
        let videoTracks = sequence.tracks.filter { $0.trackType == .video }
        let audioTracks = sequence.tracks.filter { $0.trackType == .audio }

        xml += "                    <spine>\n"

        // Primary video storyline (first video track)
        if let primaryTrack = videoTracks.first {
            for clip in primaryTrack.clips {
                let ref = assetIDMap[clip.sourceAssetID] ?? "r0"
                let offset = rationalToFCPXML(clip.startTime)
                let start = rationalToFCPXML(clip.sourceIn)
                let duration = rationalToFCPXML(clip.sourceOut - clip.sourceIn)
                xml += "                        <asset-clip ref=\"\(ref)\""
                xml += " offset=\"\(offset)\""
                xml += " start=\"\(start)\""
                xml += " duration=\"\(duration)\""
                if !clip.isEnabled {
                    xml += " enabled=\"0\""
                }
                xml += "/>\n"
            }
        }

        // Additional video tracks as connected clips in lanes
        for (laneIndex, track) in videoTracks.dropFirst().enumerated() {
            let lane = laneIndex + 1
            for clip in track.clips {
                let ref = assetIDMap[clip.sourceAssetID] ?? "r0"
                let offset = rationalToFCPXML(clip.startTime)
                let start = rationalToFCPXML(clip.sourceIn)
                let duration = rationalToFCPXML(clip.sourceOut - clip.sourceIn)
                xml += "                        <asset-clip ref=\"\(ref)\""
                xml += " lane=\"\(lane)\""
                xml += " offset=\"\(offset)\""
                xml += " start=\"\(start)\""
                xml += " duration=\"\(duration)\"/>\n"
            }
        }

        // Audio tracks
        for (audioIndex, track) in audioTracks.enumerated() {
            let lane = -(audioIndex + 1)
            for clip in track.clips {
                let ref = assetIDMap[clip.sourceAssetID] ?? "r0"
                let offset = rationalToFCPXML(clip.startTime)
                let start = rationalToFCPXML(clip.sourceIn)
                let duration = rationalToFCPXML(clip.sourceOut - clip.sourceIn)
                xml += "                        <asset-clip ref=\"\(ref)\""
                xml += " lane=\"\(lane)\""
                xml += " offset=\"\(offset)\""
                xml += " start=\"\(start)\""
                xml += " duration=\"\(duration)\""
                if track.isMuted {
                    xml += " enabled=\"0\""
                }
                xml += "/>\n"
            }
        }

        xml += "                    </spine>\n"
        xml += "                </sequence>\n"
        xml += "            </project>\n"

        return xml
    }

    private func computeSequenceDuration(_ sequence: ProjectModel.Sequence) -> Rational {
        var maxEnd = Rational.zero
        for track in sequence.tracks {
            for clip in track.clips {
                let clipEnd = clip.startTime + clip.duration
                if clipEnd > maxEnd { maxEnd = clipEnd }
            }
        }
        return maxEnd
    }

    private func flattenBin(_ bin: MediaBinModel) -> [BinItemData] {
        var items = bin.items
        for subfolder in bin.subfolders {
            items.append(contentsOf: flattenBin(subfolder))
        }
        return items
    }
}

// MARK: - FCPXML Time Formatting

/// Convert a Rational time to FCPXML format string.
/// Examples: "0s", "100/24s", "1001/24000s"
public func rationalToFCPXML(_ time: Rational) -> String {
    guard time.isValid else { return "0s" }
    if time.numerator == 0 { return "0s" }
    if time.denominator == 1 { return "\(time.numerator)s" }
    return "\(time.numerator)/\(time.denominator)s"
}

/// Parse an FCPXML time string to a Rational.
/// Handles "numerator/denominators", "Xs" (integer seconds), and "X.Ys" (decimal seconds).
public func parseFCPXMLTime(_ string: String) -> Rational {
    let cleaned = string.hasSuffix("s")
        ? String(string.dropLast())
        : string

    if cleaned.contains("/") {
        let parts = cleaned.split(separator: "/")
        guard parts.count == 2,
              let numerator = Int64(parts[0]),
              let denominator = Int64(parts[1]) else {
            return .invalid
        }
        return Rational(numerator, denominator)
    } else if let intVal = Int64(cleaned) {
        return Rational(intVal, 1)
    } else if let seconds = Double(cleaned) {
        return Rational(seconds: seconds, preferredTimescale: 600)
    }
    return .invalid
}

/// Escape special XML characters.
func escapeXML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
