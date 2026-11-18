import Foundation
import SwiftData
import Testing
@testable import Turnproof

@MainActor
@Suite(.serialized)
struct RepositoryTests {
    /// SwiftData traps if the container backing a context is released before the context.
    @MainActor private final class Keeper {
        static var containers: [ModelContainer] = []
    }

    private func store() throws -> TurnproofStore {
        let container = try TurnproofStore.container(inMemory: true)
        Keeper.containers.append(container)
        return TurnproofStore(context: container.mainContext)
    }

    @Test func blankLabelIsRejected() throws {
        let store = try store()
        #expect(throws: RepositoryError.invalidLabel) {
            try store.addProperty(label: "   ", addressLine: "1 Main St", unit: "", landlordName: "Lee")
        }
        #expect(store.properties().isEmpty)
    }

    @Test func blankAddressIsRejected() throws {
        let store = try store()
        #expect(throws: RepositoryError.invalidAddress) {
            try store.addProperty(label: "Unit A", addressLine: "\n ", unit: "", landlordName: "Lee")
        }
    }

    @Test func newInspectionStartsAsDraftWithTemplateRooms() throws {
        let store = try store()
        let property = try store.addProperty(label: " Unit A ", addressLine: " 1 Main St ",
                                             unit: "2", landlordName: "Lee", now: .epoch)
        #expect(property.label == "Unit A")
        #expect(property.addressLine == "1 Main St")

        let inspection = store.startInspection(property: property, kind: .moveOut, tenantName: "Ana", now: .epoch)
        #expect(inspection.status == .draft)
        #expect(inspection.revision == 1)
        let rooms = store.rooms(inspectionID: inspection.id)
        #expect(rooms.map(\.templateKey) == RoomTemplate.keys)
        #expect(rooms.map(\.order) == Array(0..<RoomTemplate.keys.count))
    }

    @Test func deletingPropertyCascades() throws {
        let store = try store()
        let property = try store.addProperty(label: "Unit A", addressLine: "1 Main St",
                                             unit: "", landlordName: "Lee", now: .epoch)
        let inspection = store.startInspection(property: property, kind: .moveIn, tenantName: "Ana", now: .epoch)
        let room = store.rooms(inspectionID: inspection.id)[0]
        store.insert(Finding(inspectionID: inspection.id, roomID: room.id, order: 0,
                             photoData: Data([0x01]), condition: .good, note: "",
                             isDamageFlagged: false, capturedAt: .epoch))
        store.upsertSignature(inspectionID: inspection.id, role: .tenant, png: Data([0x02]), now: .epoch)
        store.insert(SealedReport(inspectionID: inspection.id, revision: 1, generatedAt: .epoch,
                                  sha256: "abc", pageCount: 1, pdfData: Data([0x03])))

        store.delete(property)

        #expect(store.properties().isEmpty)
        #expect(store.inspections(for: property.id).isEmpty)
        #expect(store.rooms(inspectionID: inspection.id).isEmpty)
        #expect(store.findings(inspectionID: inspection.id).isEmpty)
        #expect(store.signatures(inspectionID: inspection.id).isEmpty)
        #expect(store.reports(inspectionID: inspection.id).isEmpty)
    }

    @Test func inspectionsAreNewestFirst() throws {
        let store = try store()
        let property = try store.addProperty(label: "Unit A", addressLine: "1 Main St",
                                             unit: "", landlordName: "Lee", now: .epoch)
        let older = store.startInspection(property: property, kind: .moveIn, tenantName: "", now: .epoch)
        let newer = store.startInspection(property: property, kind: .moveOut, tenantName: "",
                                          now: .epoch.addingTimeInterval(3600))
        #expect(store.inspections(for: property.id).map(\.id) == [newer.id, older.id])
    }
}

extension Date {
    static let epoch = Date(timeIntervalSince1970: 1_760_000_000)
}
