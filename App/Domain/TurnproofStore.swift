import Foundation
import SwiftData

enum RepositoryError: Error, Equatable {
    case invalidLabel
    case invalidAddress
    case saveFailed
}

@MainActor
final class TurnproofStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    static let schema = Schema([
        Property.self, Inspection.self, Room.self, Finding.self,
        Signature.self, SealedReport.self,
    ])

    /// Explicit on-disk location so UI tests can reset state and so a kill/relaunch keeps drafts.
    static func storeURL() throws -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Turnproof", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "turnproof.store")
    }

    static func resetStore() {
        guard let url = try? storeURL() else { return }
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: try storeURL())
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Returns false (and logs) when the write fails; callers that must not lie to the user check it.
    @discardableResult
    func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Log.store.error("Save failed: \(error)")
            return false
        }
    }

    // MARK: Properties

    func properties() -> [Property] {
        let descriptor = FetchDescriptor<Property>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addProperty(label: String, addressLine: String, unit: String, landlordName: String,
                     now: Date = Date()) throws -> Property {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw RepositoryError.invalidLabel }
        guard !address.isEmpty else { throw RepositoryError.invalidAddress }
        let property = Property(label: label, addressLine: address,
                                unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
                                landlordName: landlordName.trimmingCharacters(in: .whitespacesAndNewlines),
                                createdAt: now)
        context.insert(property)
        save()
        return property
    }

    func delete(_ property: Property) {
        let inspections = inspections(for: property.id)
        for inspection in inspections {
            for room in rooms(inspectionID: inspection.id) { context.delete(room) }
            for finding in findings(inspectionID: inspection.id) { context.delete(finding) }
            for signature in signatures(inspectionID: inspection.id) { context.delete(signature) }
            for report in reports(inspectionID: inspection.id) { context.delete(report) }
            context.delete(inspection)
        }
        context.delete(property)
        save()
    }

    // MARK: Inspections

    func inspections(for propertyID: UUID) -> [Inspection] {
        let descriptor = FetchDescriptor<Inspection>(
            predicate: #Predicate { $0.propertyID == propertyID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func startInspection(property: Property, kind: InspectionKind, tenantName: String,
                         now: Date) -> Inspection {
        let inspection = Inspection(propertyID: property.id, kind: kind, startedAt: now,
                                    tenantName: tenantName, inspectorName: property.landlordName)
        context.insert(inspection)
        for (index, key) in RoomTemplate.keys.enumerated() {
            context.insert(Room(inspectionID: inspection.id, templateKey: key,
                                name: RoomTemplate.name(for: key), order: index))
        }
        save()
        return inspection
    }

    func rooms(inspectionID: UUID) -> [Room] {
        let descriptor = FetchDescriptor<Room>(
            predicate: #Predicate { $0.inspectionID == inspectionID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func findings(inspectionID: UUID) -> [Finding] {
        let descriptor = FetchDescriptor<Finding>(
            predicate: #Predicate { $0.inspectionID == inspectionID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func findings(roomID: UUID) -> [Finding] {
        let descriptor = FetchDescriptor<Finding>(
            predicate: #Predicate { $0.roomID == roomID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func signatures(inspectionID: UUID) -> [Signature] {
        let descriptor = FetchDescriptor<Signature>(
            predicate: #Predicate { $0.inspectionID == inspectionID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func reports(inspectionID: UUID) -> [SealedReport] {
        let descriptor = FetchDescriptor<SealedReport>(
            predicate: #Predicate { $0.inspectionID == inspectionID },
            sortBy: [SortDescriptor(\.revision, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func insert(_ finding: Finding) {
        context.insert(finding)
        save()
    }

    func upsertSignature(inspectionID: UUID, role: SignatureRole, png: Data, now: Date) {
        if let existing = signatures(inspectionID: inspectionID).first(where: { $0.role == role }) {
            existing.pngData = png
            existing.signedAt = now
        } else {
            context.insert(Signature(inspectionID: inspectionID, role: role, pngData: png, signedAt: now))
        }
        save()
    }

    func deleteFinding(_ finding: Finding) {
        context.delete(finding)
        save()
    }

    func insert(_ report: SealedReport) {
        context.insert(report)
        save()
    }
}
