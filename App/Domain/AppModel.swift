import Foundation
import SwiftData
import UIKit

@Observable
@MainActor
final class AppModel {
    static let shared: AppModel = {
        if Launch.flags.contains(.resetState) {
            TurnproofStore.resetStore()
            FreeReportCounter().reset()
        }
        do {
            let container = try TurnproofStore.container()
            return AppModel(store: TurnproofStore(context: container.mainContext),
                            container: container,
                            clock: Launch.clock,
                            photoSource: UITestPhotoSource(),
                            usesFixturePhotos: Launch.flags.contains(.uiTestMode))
        } catch {
            fatalError("Model container failed: \(error)")
        }
    }()

    /// The container must outlive every fetch; ModelContext does not own its store coordinator.
    private let container: ModelContainer?
    let store: TurnproofStore
    var clock: @Sendable () -> Date
    var photoSource: PhotoSource
    var usesFixturePhotos: Bool
    let ingest = PhotoIngest()
    let integrity = IntegrityService()
    let counter: FreeReportCounter
    var lastError: String?

    /// Bumped by every mutation so SwiftData-backed screens re-read their fetches.
    var revision = 0

    init(store: TurnproofStore, container: ModelContainer? = nil,
         clock: @escaping @Sendable () -> Date = { Date() },
         photoSource: PhotoSource = UITestPhotoSource(), usesFixturePhotos: Bool = false,
         counter: FreeReportCounter = FreeReportCounter()) {
        self.store = store
        self.container = container
        self.clock = clock
        self.photoSource = photoSource
        self.usesFixturePhotos = usesFixturePhotos
        self.counter = counter
    }

    // MARK: Properties

    var properties: [Property] { store.properties() }

    func addProperty(label: String, address: String, unit: String, landlord: String) throws {
        _ = try store.addProperty(label: label, addressLine: address, unit: unit, landlordName: landlord,
                                  now: clock())
        revision &+= 1
    }

    // MARK: Inspections

    func startInspection(for property: Property, kind: InspectionKind, tenant: String) -> Inspection {
        let inspection = store.startInspection(property: property, kind: kind, tenantName: tenant, now: clock())
        revision &+= 1
        return inspection
    }

    func inspections(for property: Property) -> [Inspection] { store.inspections(for: property.id) }
    func rooms(for inspection: Inspection) -> [Room] { store.rooms(inspectionID: inspection.id) }
    func findings(for inspection: Inspection) -> [Finding] { store.findings(inspectionID: inspection.id) }
    func findings(room: Room) -> [Finding] { store.findings(roomID: room.id) }
    func signatures(for inspection: Inspection) -> [Signature] { store.signatures(inspectionID: inspection.id) }
    func reports(for inspection: Inspection) -> [SealedReport] { store.reports(inspectionID: inspection.id) }

    func validation(for inspection: Inspection) -> [ValidationIssue] {
        InspectionService(clock: clock).validation(
            rooms: rooms(for: inspection),
            findings: findings(for: inspection),
            signatures: signatures(for: inspection)
        )
    }

    func capture(room: Room, inspection: Inspection, rawPhoto: Data, condition: Condition,
                 note: String, flagged: Bool) throws {
        let ingested = try ingest.ingest(rawPhoto)
        let service = InspectionService(clock: clock)
        let finding = try service.capture(
            in: inspection, roomID: room.id, order: findings(room: room).count,
            photo: ingested, condition: condition, note: note, isDamageFlagged: flagged
        )
        store.insert(finding)
        revision &+= 1
    }

    func sign(inspection: Inspection, role: SignatureRole, png: Data) {
        store.upsertSignature(inspectionID: inspection.id, role: role, png: png, now: clock())
        revision &+= 1
    }

    func deleteFinding(_ finding: Finding) {
        store.deleteFinding(finding)
        revision &+= 1
    }

    /// Validates, seals, renders and stores the report. Returns the artifact to share.
    func sealAndRender(inspection: Inspection) throws -> ExportArtifact {
        let property = properties.first(where: { $0.id == inspection.propertyID })
        guard let property else { throw RepositoryError.invalidLabel }
        let rooms = rooms(for: inspection)
        let findings = findings(for: inspection)
        let signatures = signatures(for: inspection)
        let service = InspectionService(clock: clock)
        _ = try service.seal(inspection, rooms: rooms, findings: findings, signatures: signatures)
        store.save()

        let packet = integrity.packet(property: property, inspection: inspection, rooms: rooms,
                                      findings: findings, signatures: signatures)
        let digest = try integrity.digest(packet)
        var photoMap: [String: Data] = [:]
        for finding in findings {
            photoMap[IntegrityService.sha256(finding.photoData)] = finding.photoData
        }
        let renderer = ReportPDFRenderer(shortCode: integrity.shortCode)
        let pdf = try renderer.render(packet: packet, digest: digest, photos: photoMap)
        let pages = renderer.layout(for: packet, digest: digest, pageCount: 0).count
        let report = SealedReport(inspectionID: inspection.id, revision: inspection.revision,
                                  generatedAt: inspection.sealedAt ?? clock(), sha256: digest,
                                  pageCount: pages, pdfData: pdf,
                                  supersedesID: reports(for: inspection).first?.id)
        store.insert(report)
        revision &+= 1
        return ExportArtifact(report: report, pdfData: pdf, digest: digest,
                              shortCode: integrity.shortCode(digest), pageCount: pages)
    }

    /// Latest stored report for an inspection, if the packet was already sealed.
    func latestReport(for inspection: Inspection) -> SealedReport? {
        reports(for: inspection).first
    }

    func verify(_ report: SealedReport) -> Bool {
        guard let inspection = inspection(id: report.inspectionID),
              let property = properties.first(where: { $0.id == inspection.propertyID })
        else { return false }
        let packet = integrity.packet(property: property, inspection: inspection,
                                      rooms: rooms(for: inspection), findings: findings(for: inspection),
                                      signatures: signatures(for: inspection))
        return integrity.verify(report, packet: packet)
    }

    func inspection(id: UUID) -> Inspection? {
        let descriptor = FetchDescriptor<Inspection>(predicate: #Predicate { $0.id == id })
        return try? store.context.fetch(descriptor).first
    }

    func property(id: UUID) -> Property? {
        let descriptor = FetchDescriptor<Property>(predicate: #Predicate { $0.id == id })
        return try? store.context.fetch(descriptor).first
    }

    func room(id: UUID) -> Room? {
        let descriptor = FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })
        return try? store.context.fetch(descriptor).first
    }

    func exportArtifact(for report: SealedReport) -> ExportArtifact {
        ExportArtifact(report: report, pdfData: report.pdfData, digest: report.sha256,
                       shortCode: integrity.shortCode(report.sha256), pageCount: report.pageCount)
    }
}

struct ExportArtifact {
    let report: SealedReport
    let pdfData: Data
    let digest: String
    let shortCode: String
    let pageCount: Int

    var fileURL: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Turnproof-\(shortCode).pdf")
        try? pdfData.write(to: url, options: .atomic)
        return url
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .file)
    }
}

/// Launch-argument contract used by UI tests; production runs with none of these.
enum Launch {
    enum Flag: String {
        case uiTestMode = "-UITestMode"
        case resetState = "-UITestResetState"
        case resumeDraft = "-UITestResumeDraft"
    }

    private static let arguments = ProcessInfo.processInfo.arguments

    static let flags: Set<Flag> = Set(arguments.compactMap(Flag.init(rawValue:)))

    /// `-UITestClock=<unix seconds>` pins time so sealed digests are reproducible.
    static var clock: @Sendable () -> Date {
        for argument in arguments where argument.hasPrefix("-UITestClock=") {
            if let seconds = TimeInterval(argument.dropFirst("-UITestClock=".count)) {
                let fixed = Date(timeIntervalSince1970: seconds)
                return { fixed }
            }
        }
        return { Date() }
    }
}

/// Fixture source for UI tests and previews; camera capture is unavailable in CI.
struct UITestPhotoSource: PhotoSource {
    func capturePhoto() async throws -> Data { Self.fixtureData() }
    func pickFromLibrary() async throws -> Data { Self.fixtureData() }

    static func fixtureData() -> Data {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.78, green: 0.76, blue: 0.72, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.35, green: 0.33, blue: 0.3, alpha: 1).setStroke()
            context.cgContext.setLineWidth(6)
            context.cgContext.move(to: CGPoint(x: 300, y: 200))
            context.cgContext.addLine(to: CGPoint(x: 520, y: 640))
            context.cgContext.strokePath()
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
