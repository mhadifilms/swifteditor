import Testing
import Foundation
import CoreMediaPlus
@testable import CollaborationKit

@Suite("CollaborationKit Tests")
struct CollaborationKitTests {

    // MARK: - LamportClock Tests

    @Suite("LamportClock")
    struct LamportClockTests {
        @Test("tick increments counter and returns identifier with correct siteID")
        func tickIncrementsAndReturnsSiteID() async {
            let siteID = UUID()
            let clock = LamportClock(siteID: siteID)

            let id1 = await clock.tick()
            #expect(id1.siteID == siteID)
            #expect(id1.clock == 1)

            let id2 = await clock.tick()
            #expect(id2.clock == 2)

            let value = await clock.value
            #expect(value == 2)
        }

        @Test("merge advances clock past remote value")
        func mergeAdvancesClock() async {
            let clock = LamportClock(siteID: UUID())

            let _ = await clock.tick() // 1
            await clock.merge(remoteClock: 10)

            let value = await clock.value
            #expect(value == 11)

            let id = await clock.tick()
            #expect(id.clock == 12)
        }

        @Test("merge with lower remote value still increments")
        func mergeWithLowerRemote() async {
            let clock = LamportClock(siteID: UUID())
            let _ = await clock.tick() // 1
            let _ = await clock.tick() // 2
            let _ = await clock.tick() // 3

            await clock.merge(remoteClock: 1)
            // max(3, 1) + 1 = 4
            let value = await clock.value
            #expect(value == 4)
        }
    }

    // MARK: - LWWRegister Tests

    @Suite("LWWRegister")
    struct LWWRegisterTests {
        @Test("set with higher timestamp succeeds")
        func setWithHigherTimestamp() {
            let ts1 = CRDTIdentifier(siteID: UUID(), clock: 1)
            let ts2 = CRDTIdentifier(siteID: UUID(), clock: 2)
            var reg = LWWRegister(value: "hello", timestamp: ts1)

            let result = reg.set("world", at: ts2)
            #expect(result == true)
            #expect(reg.value == "world")
        }

        @Test("set with lower timestamp is rejected")
        func setWithLowerTimestamp() {
            let ts1 = CRDTIdentifier(siteID: UUID(), clock: 5)
            let ts2 = CRDTIdentifier(siteID: UUID(), clock: 2)
            var reg = LWWRegister(value: "hello", timestamp: ts1)

            let result = reg.set("world", at: ts2)
            #expect(result == false)
            #expect(reg.value == "hello")
        }

        @Test("merge keeps the value with the higher timestamp")
        func mergeKeepsHigher() {
            let siteA = UUID()
            let siteB = UUID()
            let tsA = CRDTIdentifier(siteID: siteA, clock: 3)
            let tsB = CRDTIdentifier(siteID: siteB, clock: 5)

            var regA = LWWRegister(value: 42, timestamp: tsA)
            let regB = LWWRegister(value: 99, timestamp: tsB)

            regA.merge(with: regB)
            #expect(regA.value == 99)
            #expect(regA.timestamp == tsB)
        }

        @Test("concurrent writes with same clock break tie by siteID")
        func tieBreakBySiteID() {
            let siteA = UUID()
            let siteB = UUID()
            let tsA = CRDTIdentifier(siteID: siteA, clock: 1)
            let tsB = CRDTIdentifier(siteID: siteB, clock: 1)

            // Determine which site wins the tie
            let winnerTimestamp = max(tsA, tsB)
            let loserTimestamp = min(tsA, tsB)
            let winnerValue = (winnerTimestamp == tsA) ? "A" : "B"

            var reg = LWWRegister(value: "initial", timestamp: loserTimestamp)
            reg.set(winnerValue, at: winnerTimestamp)
            #expect(reg.value == winnerValue)
        }
    }

    // MARK: - RGASequence Tests

    @Suite("RGASequence")
    struct RGASequenceTests {
        @Test("insert at head and retrieve elements in order")
        func insertAtHead() {
            let seq = RGASequence<String>()
            let id1 = CRDTIdentifier(siteID: UUID(), clock: 1)
            let id2 = CRDTIdentifier(siteID: UUID(), clock: 2)

            seq.insert(id: id1, afterID: nil, value: "first")
            seq.insert(id: id2, afterID: id1, value: "second")

            let live = seq.liveElements
            #expect(live.count == 2)
            #expect(live[0].value == "first")
            #expect(live[1].value == "second")
        }

        @Test("delete tombstones a node and hides it from liveElements")
        func deleteCreatesTombstone() {
            let seq = RGASequence<String>()
            let id1 = CRDTIdentifier(siteID: UUID(), clock: 1)
            let id2 = CRDTIdentifier(siteID: UUID(), clock: 2)
            let id3 = CRDTIdentifier(siteID: UUID(), clock: 3)

            seq.insert(id: id1, afterID: nil, value: "A")
            seq.insert(id: id2, afterID: id1, value: "B")
            seq.insert(id: id3, afterID: id2, value: "C")

            seq.delete(id: id2)

            let live = seq.liveElements
            #expect(live.count == 2)
            #expect(live[0].value == "A")
            #expect(live[1].value == "C")
            // Tombstone still exists in total count
            #expect(seq.totalCount == 3)
        }

        @Test("concurrent inserts after same anchor are ordered by identifier")
        func concurrentInsertOrdering() {
            let seq = RGASequence<String>()
            let anchor = CRDTIdentifier(siteID: UUID(), clock: 1)
            seq.insert(id: anchor, afterID: nil, value: "anchor")

            // Two sites concurrently insert after the anchor
            let siteA = UUID()
            let siteB = UUID()
            let idA = CRDTIdentifier(siteID: siteA, clock: 2)
            let idB = CRDTIdentifier(siteID: siteB, clock: 2)

            // Insert in arbitrary order — result should be deterministic
            seq.insert(id: idA, afterID: anchor, value: "from A")
            seq.insert(id: idB, afterID: anchor, value: "from B")

            let live = seq.liveElements
            #expect(live.count == 3)
            #expect(live[0].value == "anchor")

            // The one with the higher CRDTIdentifier should be first (closer to anchor)
            let higherID = max(idA, idB)
            #expect(live[1].id == higherID)
        }

        @Test("element(at:) returns correct logical index")
        func elementAtLogicalIndex() {
            let seq = RGASequence<String>()
            let id1 = CRDTIdentifier(siteID: UUID(), clock: 1)
            let id2 = CRDTIdentifier(siteID: UUID(), clock: 2)
            let id3 = CRDTIdentifier(siteID: UUID(), clock: 3)

            seq.insert(id: id1, afterID: nil, value: "X")
            seq.insert(id: id2, afterID: id1, value: "Y")
            seq.insert(id: id3, afterID: id2, value: "Z")

            // Delete the middle element
            seq.delete(id: id2)

            let elem0 = seq.element(at: 0)
            let elem1 = seq.element(at: 1)
            let elem2 = seq.element(at: 2)
            #expect(elem0?.value == "X")
            #expect(elem1?.value == "Z")
            #expect(elem2 == nil)
        }

        @Test("duplicate insert is idempotent")
        func duplicateInsertIdempotent() {
            let seq = RGASequence<String>()
            let id1 = CRDTIdentifier(siteID: UUID(), clock: 1)

            seq.insert(id: id1, afterID: nil, value: "A")
            seq.insert(id: id1, afterID: nil, value: "A") // duplicate

            #expect(seq.count == 1)
            #expect(seq.totalCount == 1)
        }
    }

    // MARK: - TimelineOperation Serialization Tests

    @Suite("TimelineOperation Codable")
    struct TimelineOperationCodableTests {
        @Test("insertClip round-trips through JSON")
        func insertClipRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 1)
            let trackID = CRDTIdentifier(siteID: UUID(), clock: 2)
            let clip = ClipPayload(
                assetID: UUID(),
                sourceIn: Rational(0, 1),
                sourceOut: Rational(300, 1),
                speed: 1.0
            )
            let op = TimelineOperation.insertClip(
                id: id, afterID: nil, trackID: trackID, clip: clip
            )

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("deleteClip round-trips through JSON")
        func deleteClipRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 5)
            let op = TimelineOperation.deleteClip(id: id)

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("moveClip round-trips through JSON")
        func moveClipRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 3)
            let afterID = CRDTIdentifier(siteID: UUID(), clock: 1)
            let toTrackID = CRDTIdentifier(siteID: UUID(), clock: 2)
            let op = TimelineOperation.moveClip(id: id, afterID: afterID, toTrackID: toTrackID)

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("setClipProperty round-trips through JSON")
        func setClipPropertyRoundTrip() throws {
            let clipID = CRDTIdentifier(siteID: UUID(), clock: 1)
            let ts = CRDTIdentifier(siteID: UUID(), clock: 2)
            let op = TimelineOperation.setClipProperty(
                clipID: clipID, key: "opacity",
                value: .double(0.75), timestamp: ts
            )

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("trimClipStart round-trips through JSON")
        func trimClipStartRoundTrip() throws {
            let clipID = CRDTIdentifier(siteID: UUID(), clock: 1)
            let ts = CRDTIdentifier(siteID: UUID(), clock: 3)
            let op = TimelineOperation.trimClipStart(
                clipID: clipID, newInPoint: Rational(10, 600), timestamp: ts
            )

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("trimClipEnd round-trips through JSON")
        func trimClipEndRoundTrip() throws {
            let clipID = CRDTIdentifier(siteID: UUID(), clock: 1)
            let ts = CRDTIdentifier(siteID: UUID(), clock: 4)
            let op = TimelineOperation.trimClipEnd(
                clipID: clipID, newOutPoint: Rational(500, 600), timestamp: ts
            )

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("insertTrack round-trips through JSON")
        func insertTrackRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 1)
            let op = TimelineOperation.insertTrack(id: id, afterID: nil, kind: .video)

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("deleteTrack round-trips through JSON")
        func deleteTrackRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 7)
            let op = TimelineOperation.deleteTrack(id: id)

            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(TimelineOperation.self, from: data)
            #expect(decoded == op)
        }

        @Test("OperationEnvelope round-trips through JSON")
        func envelopeRoundTrip() throws {
            let id = CRDTIdentifier(siteID: UUID(), clock: 1)
            let op = TimelineOperation.deleteClip(id: id)
            let envelope = OperationEnvelope(
                senderID: UUID(), sequenceNumber: 42, operation: op
            )

            let data = try JSONEncoder().encode(envelope)
            let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
            #expect(decoded.sequenceNumber == 42)
            #expect(decoded.operation == op)
        }
    }

    // MARK: - PropertyValue Tests

    @Suite("PropertyValue Codable")
    struct PropertyValueCodableTests {
        @Test("all property value variants round-trip")
        func allVariantsRoundTrip() throws {
            let cases: [PropertyValue] = [
                .double(3.14),
                .string("test"),
                .bool(true),
                .rational(Rational(24, 1)),
            ]

            for pv in cases {
                let data = try JSONEncoder().encode(pv)
                let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
                #expect(decoded == pv)
            }
        }
    }
}
