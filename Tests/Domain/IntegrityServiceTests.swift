import Foundation
import Testing
@testable import Turnproof

struct IntegrityServiceTests {
    private let integrity = IntegrityService()
    private let clock = Date(timeIntervalSince1970: 1_760_000_000)

    private struct Fixture {
        let property: Property
        let inspection: Inspection
        let rooms: [Room]
        let findings: [Finding]
        let signatures: [Signature]
    }

    private func fixture(note: String = "Scuff on door", reversedRoomOrder: Bool = false) -> Fixture {
        let property = Property(label: "Unit A", addressLine: "1 Main St", unit: "2",
                                landlordName: "Lee", createdAt: clock)
        var inspection = Inspection(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                                    propertyID: property.id, kind: .moveOut, startedAt: clock,
                                    tenantName: "Ana", inspectorName: "Lee")
        inspection.sealedAt = clock.addingTimeInterval(600)

        let kitchen = Room(inspectionID: inspection.id, templateKey: "kitchen",
                           name: "Kitchen", order: reversedRoomOrder ? 1 : 0)
        let bath = Room(inspectionID: inspection.id, templateKey: "bath",
                        name: "Bathroom", order: reversedRoomOrder ? 0 : 1)
        let findings = [
            Finding(inspectionID: inspection.id, roomID: kitchen.id, order: 0,
                    photoData: Data([0xAA]), condition: .damaged, note: note,
                    isDamageFlagged: true, capturedAt: clock),
            Finding(inspectionID: inspection.id, roomID: bath.id, order: 0,
                    photoData: Data([0xBB]), condition: .good, note: "",
                    isDamageFlagged: false, capturedAt: clock),
        ]
        let signatures = [
            Signature(inspectionID: inspection.id, role: .tenant, pngData: Data([0x01]), signedAt: clock),
            Signature(inspectionID: inspection.id, role: .landlord, pngData: Data([0x02]), signedAt: clock),
        ]
        return Fixture(property: property, inspection: inspection,
                       rooms: [kitchen, bath], findings: findings, signatures: signatures)
    }

    private func packet(_ fixture: Fixture) -> ReportPacket {
        integrity.packet(property: fixture.property, inspection: fixture.inspection,
                         rooms: fixture.rooms, findings: fixture.findings,
                         signatures: fixture.signatures)
    }

    @Test func manifestIsByteIdenticalForTheSamePacket() throws {
        let fixture = fixture()
        let first = try integrity.manifest(for: packet(fixture))
        let second = try integrity.manifest(for: packet(fixture))
        #expect(first == second)
        #expect(String(decoding: first, as: UTF8.self).hasPrefix("{\"inspection\":"))
    }

    @Test func editingANoteChangesTheDigest() throws {
        let original = try integrity.digest(packet(fixture()))
        let edited = try integrity.digest(packet(fixture(note: "Scuff on door, 3 cm")))
        #expect(original != edited)
    }

    @Test func roomOrderIsPartOfTheEvidence() throws {
        let ordered = try integrity.digest(packet(fixture()))
        let reordered = try integrity.digest(packet(fixture(reversedRoomOrder: true)))
        #expect(ordered != reordered)
    }

    @Test func shortCodeGroupsTwelveCharacters() {
        let digest = "a1b2c3d4e5f67890"
        #expect(integrity.shortCode(digest) == "A1B2-C3D4-E5F6")
        #expect(integrity.shortCode("abc") == "ABC")
    }

    @Test func verifyDetectsChangedRecords() throws {
        let base = fixture()
        let digest = try integrity.digest(packet(base))
        let report = SealedReport(inspectionID: base.inspection.id, revision: 1,
                                  generatedAt: clock, sha256: digest, pageCount: 6, pdfData: Data())
        #expect(integrity.verify(report, packet: packet(base)))
        #expect(!integrity.verify(report, packet: packet(fixture(note: "changed"))))
    }

    @Test func packetRecordsEveryPhotoHashAndCount() throws {
        let fixture = fixture()
        let result = packet(fixture)
        #expect(result.totalPhotos == 2)
        #expect(result.rooms.count == 2)
        #expect(result.rooms[0].findings[0].photoSHA256 == IntegrityService.sha256(Data([0xAA])))
        #expect(result.signatures.map(\.role) == ["landlord", "tenant"])
    }
}
