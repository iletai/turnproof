import Foundation
import Testing
@testable import Turnproof

struct InspectionServiceTests {
    private let clock = Date(timeIntervalSince1970: 1_760_000_000)
    private var service: InspectionService { InspectionService(clock: { self.clock }) }

    private func draft() -> (Inspection, Room) {
        let inspection = Inspection(propertyID: UUID(), kind: .moveOut, startedAt: clock)
        let room = Room(inspectionID: inspection.id, templateKey: "kitchen", name: "Kitchen", order: 0)
        return (inspection, room)
    }

    private func finding(in room: Room, condition: Condition, flag: Bool, note: String,
                         order: Int = 0, inspection: Inspection) -> Finding {
        Finding(inspectionID: inspection.id, roomID: room.id, order: order,
                photoData: Data([0x01]), condition: condition, note: note,
                isDamageFlagged: flag, capturedAt: clock)
    }

    @Test func damageWithoutNoteIsUnresolved() {
        let (inspection, room) = draft()
        let damage = finding(in: room, condition: .damaged, flag: true, note: "  ", inspection: inspection)
        let issues = service.validation(rooms: [room], findings: [damage], signatures: [])
        #expect(issues.contains(.unresolvedDamage(room: "Kitchen")))
        #expect(throws: InspectionError.emptyNote) {
            try service.seal(inspection, rooms: [room], findings: [damage], signatures: [])
        }
    }

    @Test func emptyRoomIsReportedInOrder() {
        let (_, room) = draft()
        let issues = service.validation(rooms: [room], findings: [], signatures: [])
        #expect(issues.contains(.noFindings(room: "Kitchen")))
        #expect(issues.filter { if case .missingSignature = $0 { true } else { false } }.count == 2)
    }

    @Test func photoLimitBlocksSeal() {
        let (inspection, room) = draft()
        let findings = (0...InspectionService.photoLimit).map {
            finding(in: room, condition: .good, flag: false, note: "", order: $0, inspection: inspection)
        }
        let signatures = [
            Signature(inspectionID: inspection.id, role: .tenant, pngData: Data([0x01]), signedAt: clock),
            Signature(inspectionID: inspection.id, role: .landlord, pngData: Data([0x02]), signedAt: clock),
        ]
        #expect(throws: InspectionError.photoLimit) {
            try service.seal(inspection, rooms: [room], findings: findings, signatures: signatures)
        }
    }

    @Test func sealNeedsBothSignatures() {
        let (inspection, room) = draft()
        let findings = [finding(in: room, condition: .good, flag: false, note: "", inspection: inspection)]
        let tenant = [Signature(inspectionID: inspection.id, role: .tenant, pngData: Data([0x01]), signedAt: clock)]
        #expect(throws: InspectionError.blocked) {
            try service.seal(inspection, rooms: [room], findings: findings, signatures: tenant)
        }
        #expect(inspection.status == .draft)
    }

    @Test func validPacketSealsAtClockTime() throws {
        let (inspection, room) = draft()
        let findings = [
            finding(in: room, condition: .damaged, flag: true, note: "Scuff on cabinet", inspection: inspection)
        ]
        let signatures = [
            Signature(inspectionID: inspection.id, role: .tenant, pngData: Data([0x01]), signedAt: clock),
            Signature(inspectionID: inspection.id, role: .landlord, pngData: Data([0x02]), signedAt: clock),
        ]
        let sealedAt = try service.seal(inspection, rooms: [room], findings: findings, signatures: signatures)
        #expect(inspection.status == .sealed)
        #expect(inspection.sealedAt == clock)
        #expect(sealedAt == clock)
    }

    @Test func sealedInspectionRejectsNewFindings() {
        let (inspection, room) = draft()
        inspection.status = .sealed
        #expect(throws: InspectionError.sealed) {
            try service.capture(in: inspection, roomID: room.id, order: 0,
                                photo: IngestedPhoto(jpeg: Data([0x01]), exifTakenAt: nil),
                                condition: .good, note: "", isDamageFlagged: false)
        }
    }

    @Test func draftCaptureKeepsFlaggedFindingWithoutNote() throws {
        let (inspection, room) = draft()
        let captured = try service.capture(in: inspection, roomID: room.id, order: 0,
                                           photo: IngestedPhoto(jpeg: Data([0x01]), exifTakenAt: nil),
                                           condition: .damaged, note: "  scratched door ",
                                           isDamageFlagged: true)
        #expect(captured.note == "scratched door")
        #expect(captured.capturedAt == clock)

        let flaggedEmpty = try service.capture(in: inspection, roomID: room.id, order: 1,
                                               photo: IngestedPhoto(jpeg: Data([0x02]), exifTakenAt: nil),
                                               condition: .damaged, note: " ", isDamageFlagged: true)
        #expect(flaggedEmpty.note.isEmpty)
    }
}
