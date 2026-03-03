import Foundation
import CoreMediaPlus
import InterchangeKit
import TimelineKit
import ProjectModel

/// Facade for project interchange (FCPXML and EDL import/export).
public final class InterchangeAPI: @unchecked Sendable {
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    // MARK: - FCPXML Export

    /// Export the current timeline as FCPXML string.
    public func exportFCPXML(projectName: String, frameRate: Double) -> String {
        let sequence = timeline.exportToSequence()
        let exporter = FCPXMLExporter()
        let fr = Rational(Int64(frameRate * 1000), 1000)
        let settings = ProjectSettings(
            videoParams: VideoParams(width: 1920, height: 1080),
            audioParams: AudioParams(),
            frameRate: fr
        )
        return exporter.exportSequence(sequence, settings: settings)
    }

    /// Export the current timeline as FCPXML and write to a file.
    public func exportFCPXMLToFile(url: URL, projectName: String, frameRate: Double) throws {
        let xml = exportFCPXML(projectName: projectName, frameRate: frameRate)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - FCPXML Import

    /// Parse an FCPXML string and return the imported project data.
    public func importFCPXML(xmlString: String) throws -> ImportedProject {
        let importer = FCPXMLImporter()
        return try importer.parse(string: xmlString)
    }

    /// Read an FCPXML file and return the imported project data.
    public func importFCPXMLFromFile(url: URL) throws -> ImportedProject {
        let data = try Data(contentsOf: url)
        let importer = FCPXMLImporter()
        return try importer.parse(data: data)
    }

    // MARK: - EDL Export

    /// Export the current timeline as a CMX3600 EDL string.
    public func exportEDL(title: String, frameRate: Double, dropFrame: Bool) -> String {
        let sequence = timeline.exportToSequence()
        let fr = Rational(Int64(frameRate * 1000), 1000)
        let exporter = EDLExporter(frameRate: fr, dropFrame: dropFrame)
        return exporter.exportSequence(sequence, title: title)
    }

    /// Export the current timeline as a CMX3600 EDL and write to a file.
    public func exportEDLToFile(url: URL, title: String, frameRate: Double, dropFrame: Bool) throws {
        let edl = exportEDL(title: title, frameRate: frameRate, dropFrame: dropFrame)
        try edl.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - EDL Import

    /// Parse an EDL string and return the parsed document.
    public func importEDL(edlString: String, frameRate: Double, dropFrame: Bool) throws -> EDLDocument {
        let fr = Rational(Int64(frameRate * 1000), 1000)
        let importer = EDLImporter(frameRate: fr)
        return try importer.parse(text: edlString)
    }

    /// Read an EDL file and return the parsed document.
    public func importEDLFromFile(url: URL, frameRate: Double, dropFrame: Bool) throws -> EDLDocument {
        let data = try Data(contentsOf: url)
        let fr = Rational(Int64(frameRate * 1000), 1000)
        let importer = EDLImporter(frameRate: fr)
        return try importer.parse(data: data)
    }
}
