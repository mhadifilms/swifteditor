import Testing
import Foundation
@testable import InterchangeKit
@testable import CoreMediaPlus
@testable import ProjectModel

@Suite("InterchangeKit Tests")
struct InterchangeKitTests {

    // MARK: - FCPXML Time Helpers

    @Test("rationalToFCPXML formats time strings correctly")
    func testRationalToFCPXML() {
        #expect(rationalToFCPXML(Rational.zero) == "0s")
        #expect(rationalToFCPXML(Rational(100, 24)) == "25/6s")  // reduced
        #expect(rationalToFCPXML(Rational(5, 1)) == "5s")
        #expect(rationalToFCPXML(Rational(1001, 24000)) == "1001/24000s")
    }

    @Test("parseFCPXMLTime parses rational time strings")
    func testParseFCPXMLTime() {
        let zero = parseFCPXMLTime("0s")
        #expect(zero == Rational.zero)

        let rational = parseFCPXMLTime("1001/24000s")
        #expect(rational.numerator == 1001)
        #expect(rational.denominator == 24000)

        let intSeconds = parseFCPXMLTime("5s")
        #expect(intSeconds == Rational(5, 1))
    }

    // MARK: - FCPXML Export

    @Test("FCPXMLExporter exports a valid FCPXML document")
    func testFCPXMLExport() {
        let project = sampleProject()
        let exporter = FCPXMLExporter()
        let xml = exporter.export(project)

        #expect(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<!DOCTYPE fcpxml>"))
        #expect(xml.contains("<fcpxml version=\"1.11\">"))
        #expect(xml.contains("<resources>"))
        #expect(xml.contains("<format id="))
        #expect(xml.contains("<library>"))
        #expect(xml.contains("<event name="))
        #expect(xml.contains("<project name="))
        #expect(xml.contains("<sequence format="))
        #expect(xml.contains("<spine>"))
        #expect(xml.contains("<asset-clip ref="))
        #expect(xml.contains("</spine>"))
        #expect(xml.contains("</fcpxml>"))
    }

    @Test("FCPXMLExporter exports correct time format")
    func testFCPXMLTimeExport() {
        let project = sampleProject()
        let exporter = FCPXMLExporter()
        let xml = exporter.export(project)

        // The clip starts at 0s with sourceIn 0s and duration = sourceOut - sourceIn
        #expect(xml.contains("offset=\"0s\""))
        // Source in is 0s
        #expect(xml.contains("start=\"0s\""))
    }

    @Test("FCPXMLExporter exports both video and audio tracks")
    func testFCPXMLExportMultipleTracks() {
        let project = sampleProjectWithAudio()
        let exporter = FCPXMLExporter()
        let xml = exporter.export(project)

        // Audio tracks get negative lane numbers
        #expect(xml.contains("lane=\"-1\""))
    }

    // MARK: - FCPXML Import

    @Test("FCPXMLImporter parses a basic FCPXML document")
    func testFCPXMLImport() throws {
        let xml = sampleFCPXML()
        let importer = FCPXMLImporter()
        let imported = try importer.parse(string: xml)

        #expect(imported.name == "Test Edit")
        #expect(imported.formatWidth == 1920)
        #expect(imported.formatHeight == 1080)
        #expect(!imported.assets.isEmpty)
        #expect(!imported.tracks.isEmpty)
    }

    @Test("FCPXMLImporter parses asset references")
    func testFCPXMLImportAssets() throws {
        let xml = sampleFCPXML()
        let importer = FCPXMLImporter()
        let imported = try importer.parse(string: xml)

        let asset = imported.assets.first(where: { $0.id == "r2" })
        #expect(asset != nil)
        #expect(asset?.name == "Interview_A")
        #expect(asset?.hasVideo == true)
        #expect(asset?.hasAudio == true)
    }

    @Test("FCPXMLImporter parses clips from spine")
    func testFCPXMLImportClips() throws {
        let xml = sampleFCPXML()
        let importer = FCPXMLImporter()
        let imported = try importer.parse(string: xml)

        let videoTrack = imported.tracks.first(where: { $0.trackType == .video })
        #expect(videoTrack != nil)

        let clips = videoTrack?.clips.filter { !$0.isTransition } ?? []
        #expect(clips.count == 2)

        let firstClip = clips[0]
        #expect(firstClip.assetRef == "r2")
        #expect(firstClip.offset == parseFCPXMLTime("0s"))
    }

    @Test("FCPXMLImporter handles transitions")
    func testFCPXMLImportTransitions() throws {
        let xml = sampleFCPXMLWithTransition()
        let importer = FCPXMLImporter()
        let imported = try importer.parse(string: xml)

        let videoTrack = imported.tracks.first(where: { $0.trackType == .video })
        let transitions = videoTrack?.clips.filter { $0.isTransition } ?? []
        #expect(transitions.count == 1)
        #expect(transitions.first?.transitionName == "Cross Dissolve")
    }

    // MARK: - FCPXML Round Trip

    @Test("FCPXML export then import preserves project structure")
    func testFCPXMLRoundTrip() throws {
        let original = sampleProject()
        let exporter = FCPXMLExporter()
        let xml = exporter.export(original)

        let importer = FCPXMLImporter()
        let imported = try importer.parse(string: xml)
        let restored = imported.toProject()

        // FCPXML round-trip: the project name comes from the <project name="..."> element,
        // which is the sequence name in our export, not the top-level project name.
        #expect(restored.name == original.sequences[0].name)
        #expect(restored.sequences.count == original.sequences.count)

        let origSeq = original.sequences[0]
        let restoredSeq = restored.sequences[0]

        let origVideoTracks = origSeq.tracks.filter { $0.trackType == .video }
        let restoredVideoTracks = restoredSeq.tracks.filter { $0.trackType == .video }
        #expect(restoredVideoTracks.count == origVideoTracks.count)

        let origClips = origVideoTracks.first?.clips ?? []
        let restoredClips = restoredVideoTracks.first?.clips ?? []
        #expect(restoredClips.count == origClips.count)
    }

    // MARK: - EDL Export

    @Test("EDLExporter produces valid CMX3600 format")
    func testEDLExportFormat() {
        let exporter = EDLExporter(frameRate: Rational(24, 1))
        let events = [
            EDLExporter.EDLEvent(
                reelName: "REEL_01",
                trackIndicator: "V",
                editType: .cut,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(10, 1),
                recordIn: Rational(0, 1),
                recordOut: Rational(10, 1),
                clipName: "MyClip.mov"
            )
        ]

        let edl = exporter.formatEDL(title: "TEST_EDL", events: events)

        #expect(edl.contains("TITLE: TEST_EDL"))
        #expect(edl.contains("FCM: NON-DROP FRAME"))
        #expect(edl.contains("001"))
        #expect(edl.contains("REEL_01"))
        #expect(edl.contains("C   "))
        #expect(edl.contains("00:00:00:00"))
        #expect(edl.contains("00:00:10:00"))
        #expect(edl.contains("* FROM CLIP NAME: MyClip.mov"))
    }

    @Test("EDLExporter handles dissolve transitions")
    func testEDLExportDissolve() {
        let exporter = EDLExporter(frameRate: Rational(24, 1))
        let events = [
            EDLExporter.EDLEvent(
                reelName: "REEL_01",
                editType: .dissolve(frames: 24),
                sourceIn: Rational(0, 1),
                sourceOut: Rational(5, 1),
                recordIn: Rational(0, 1),
                recordOut: Rational(5, 1)
            )
        ]

        let edl = exporter.formatEDL(title: "TEST", events: events)
        #expect(edl.contains("D   "))
        #expect(edl.contains("024"))
    }

    @Test("EDLExporter exports from project")
    func testEDLExportProject() {
        let project = sampleProject()
        let exporter = EDLExporter(frameRate: project.settings.frameRate)
        let edl = exporter.export(project)

        #expect(edl.contains("TITLE:"))
        #expect(edl.contains("FCM:"))
        // Should have at least one event line
        #expect(edl.contains("001"))
    }

    // MARK: - EDL Import

    @Test("EDLImporter parses title and FCM")
    func testEDLImportHeader() throws {
        let edl = """
        TITLE: MY_EDIT
        FCM: NON-DROP FRAME

        001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)

        #expect(doc.title == "MY_EDIT")
        #expect(doc.dropFrame == false)
        #expect(doc.events.count == 1)
    }

    @Test("EDLImporter parses event fields correctly")
    func testEDLImportEventFields() throws {
        let edl = """
        TITLE: TEST
        FCM: NON-DROP FRAME

        001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
        * FROM CLIP NAME: Interview.mov
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)

        let event = doc.events[0]
        #expect(event.eventNumber == 1)
        #expect(event.reelName == "REEL_01")
        #expect(event.trackType == .video)
        #expect(event.transitionType == .cut)
        #expect(event.clipName == "Interview.mov")
    }

    @Test("EDLImporter parses dissolve transitions")
    func testEDLImportDissolve() throws {
        let edl = """
        TITLE: TEST
        FCM: NON-DROP FRAME

        001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
        002  REEL_02  V     D    024 01:00:00:00 01:00:05:00 01:00:09:00 01:00:15:00
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)

        #expect(doc.events.count == 2)
        #expect(doc.events[1].transitionType == .dissolve)
        #expect(doc.events[1].transitionDuration == 24)
    }

    @Test("EDLImporter parses audio-only events")
    func testEDLImportAudio() throws {
        let edl = """
        TITLE: TEST
        FCM: NON-DROP FRAME

        001  REEL_01  A1    C        00:00:00:00 00:00:10:00 00:00:00:00 00:00:10:00
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)

        #expect(doc.events.count == 1)
        #expect(doc.events[0].trackType == .audio(channel: 1))
    }

    @Test("EDLImporter parses wipe transitions")
    func testEDLImportWipe() throws {
        let edl = """
        TITLE: TEST
        FCM: NON-DROP FRAME

        001  REEL_01  V     W001 012 01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)

        #expect(doc.events.count == 1)
        #expect(doc.events[0].transitionType == .wipe(code: 1))
        #expect(doc.events[0].transitionDuration == 12)
    }

    @Test("EDLImporter converts to Sequence")
    func testEDLToSequence() throws {
        let edl = """
        TITLE: MY_EDIT
        FCM: NON-DROP FRAME

        001  REEL_01  V     C        01:00:00:00 01:00:10:00 01:00:00:00 01:00:10:00
        002  REEL_02  V     C        00:05:00:00 00:05:05:00 01:00:10:00 01:00:15:00
        """

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edl)
        let sequence = doc.toSequence()

        #expect(sequence.name == "MY_EDIT")
        let videoTrack = sequence.tracks.first(where: { $0.trackType == .video })
        #expect(videoTrack != nil)
        #expect(videoTrack?.clips.count == 2)
    }

    // MARK: - EDL Round Trip

    @Test("EDL export then import preserves events")
    func testEDLRoundTrip() throws {
        let exporter = EDLExporter(frameRate: Rational(24, 1))
        let events = [
            EDLExporter.EDLEvent(
                reelName: "REEL_01",
                trackIndicator: "V",
                editType: .cut,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(10, 1),
                recordIn: Rational(0, 1),
                recordOut: Rational(10, 1),
                clipName: "Clip1.mov"
            ),
            EDLExporter.EDLEvent(
                reelName: "REEL_02",
                trackIndicator: "V",
                editType: .cut,
                sourceIn: Rational(5, 1),
                sourceOut: Rational(15, 1),
                recordIn: Rational(10, 1),
                recordOut: Rational(20, 1),
                clipName: "Clip2.mov"
            ),
        ]

        let edlText = exporter.formatEDL(title: "ROUNDTRIP", events: events)

        let importer = EDLImporter(frameRate: Rational(24, 1))
        let doc = try importer.parse(text: edlText)

        #expect(doc.title == "ROUNDTRIP")
        #expect(doc.events.count == 2)
        #expect(doc.events[0].reelName == "REEL_01")
        #expect(doc.events[0].clipName == "Clip1.mov")
        #expect(doc.events[1].reelName == "REEL_02")
        #expect(doc.events[1].clipName == "Clip2.mov")
    }

    // MARK: - Timecode Helpers

    @Test("rationalToTimecode formats correctly")
    func testTimecodeFormat() {
        let tc = rationalToTimecode(Rational(240, 24), fps: 24.0)
        #expect(tc == "00:00:10:00")

        let tcZero = rationalToTimecode(Rational.zero, fps: 24.0)
        #expect(tcZero == "00:00:00:00")

        let tcOneFrame = rationalToTimecode(Rational(1, 24), fps: 24.0)
        #expect(tcOneFrame == "00:00:00:01")
    }

    @Test("parseTimecode parses SMPTE timecode")
    func testTimecodeParser() {
        let time = parseTimecode("01:00:00:00", fps: 24.0)
        #expect(time != nil)
        // 1 hour at 24fps = 86400 frames = 3600 seconds
        let expectedSeconds = 3600.0
        if let t = time {
            #expect(abs(t.seconds - expectedSeconds) < 0.01)
        }
    }

    // MARK: - Test Data Helpers

    private func sampleProject() -> Project {
        let assetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let clip = ClipData(
            sourceAssetID: assetID,
            startTime: .zero,
            sourceIn: .zero,
            sourceOut: Rational(240, 24)
        )

        let videoTrack = TrackData(
            name: "V1",
            trackType: .video,
            clips: [clip]
        )

        let sequence = ProjectModel.Sequence(
            name: "Main Sequence",
            tracks: [videoTrack]
        )

        let binItem = BinItemData(
            id: assetID,
            name: "TestClip.mov",
            relativePath: "Media/TestClip.mov",
            originalPath: "file:///Media/TestClip.mov",
            duration: Rational(480, 24)
        )

        return Project(
            name: "Test Project",
            settings: .defaultHD,
            sequences: [sequence],
            bin: MediaBinModel(items: [binItem])
        )
    }

    private func sampleProjectWithAudio() -> Project {
        let videoAssetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let audioAssetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let videoClip = ClipData(
            sourceAssetID: videoAssetID,
            startTime: .zero,
            sourceIn: .zero,
            sourceOut: Rational(240, 24)
        )
        let audioClip = ClipData(
            sourceAssetID: audioAssetID,
            startTime: .zero,
            sourceIn: .zero,
            sourceOut: Rational(240, 24)
        )

        let videoTrack = TrackData(name: "V1", trackType: .video, clips: [videoClip])
        let audioTrack = TrackData(name: "A1", trackType: .audio, clips: [audioClip])

        let sequence = ProjectModel.Sequence(
            name: "AV Sequence",
            tracks: [videoTrack, audioTrack]
        )

        return Project(
            name: "AV Project",
            settings: .defaultHD,
            sequences: [sequence],
            bin: MediaBinModel()
        )
    }

    private func sampleFCPXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
            <resources>
                <format id="r1" name="FFVideoFormat1080p24"
                        frameDuration="1/24s" width="1920" height="1080"/>
                <asset id="r2" name="Interview_A" src="file:///Media/Interview_A.mov"
                       start="0s" duration="3600/24s" hasVideo="1" hasAudio="1"/>
                <asset id="r3" name="BRoll_01" src="file:///Media/BRoll_01.mov"
                       start="0s" duration="1200/24s" hasVideo="1" hasAudio="1"/>
            </resources>
            <library>
                <event name="Test Event">
                    <project name="Test Edit">
                        <sequence format="r1" duration="1800/24s"
                                  tcStart="0s" tcFormat="NDF">
                            <spine>
                                <asset-clip ref="r2" name="Interview_A"
                                            offset="0s" start="100/24s"
                                            duration="600/24s"/>
                                <asset-clip ref="r3" name="BRoll_01"
                                            offset="600/24s" start="0s"
                                            duration="1200/24s"/>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
    }

    private func sampleFCPXMLWithTransition() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
            <resources>
                <format id="r1" name="FFVideoFormat1080p24"
                        frameDuration="1/24s" width="1920" height="1080"/>
                <asset id="r2" name="ClipA" src="file:///Media/ClipA.mov"
                       start="0s" duration="600/24s" hasVideo="1" hasAudio="1"/>
                <asset id="r3" name="ClipB" src="file:///Media/ClipB.mov"
                       start="0s" duration="600/24s" hasVideo="1" hasAudio="1"/>
            </resources>
            <library>
                <event name="Test">
                    <project name="Transition Test">
                        <sequence format="r1" duration="1200/24s"
                                  tcStart="0s" tcFormat="NDF">
                            <spine>
                                <asset-clip ref="r2" name="ClipA"
                                            offset="0s" start="0s"
                                            duration="600/24s"/>
                                <transition name="Cross Dissolve"
                                            offset="576/24s" duration="48/24s"/>
                                <asset-clip ref="r3" name="ClipB"
                                            offset="624/24s" start="0s"
                                            duration="600/24s"/>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
    }
}
