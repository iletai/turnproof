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
            UserDefaults.standard.removeObject(forKey: AppModel.unlockedKey)
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
    var renderer: any PDFRendering

    /// Reports whose export was paid for (or took the free slot). Survives relaunch.
    static let unlockedKey = "turnproof.unlocked_reports.v1"
    private(set) var unlockedReportIDs: Set<UUID>

    /// Bumped by every mutation so SwiftData-backed screens re-read their fetches.
    var revision = 0

    init(store: TurnproofStore, container: ModelContainer? = nil,
         clock: @escaping @Sendable () -> Date = { Date() },
         photoSource: PhotoSource = UITestPhotoSource(), usesFixturePhotos: Bool = false,
         counter: FreeReportCounter = FreeReportCounter(),
         renderer: any PDFRendering = ReportPDFRenderer { IntegrityService().shortCode($0) }) {
        self.store = store
        self.container = container
        self.clock = clock
        self.photoSource = photoSource
        self.usesFixturePhotos = usesFixturePhotos
        self.counter = counter
        self.renderer = renderer
        self.unlockedReportIDs = Set(
            (UserDefaults.standard.stringArray(forKey: Self.unlockedKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    // MARK: Export access

    func isUnlocked(_ report: SealedReport) -> Bool { unlockedReportIDs.contains(report.id) }

    func unlock(_ report: SealedReport) {
        unlockedReportIDs.insert(report.id)
        UserDefaults.standard.set(unlockedReportIDs.map(\.uuidString), forKey: Self.unlockedKey)
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
        guard inspection.status == .draft else { throw InspectionError.sealed }
        guard findings(for: inspection).count < InspectionService.photoLimit else {
            throw InspectionError.photoLimit
        }
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
        guard inspection.status == .draft else { return }
        store.upsertSignature(inspectionID: inspection.id, role: role, png: png, now: clock())
        revision &+= 1
    }

    func deleteFinding(_ finding: Finding) {
        // Sealed records are immutable: the stored digest must keep describing what exists.
        guard inspection(id: finding.inspectionID)?.status == .draft else { return }
        store.deleteFinding(finding)
        revision &+= 1
    }

    /// Validates, renders, then seals. The inspection stays a draft until the PDF exists, so a
    /// crash mid-render can never leave a sealed inspection with no report behind it.
    func sealAndRender(inspection: Inspection) throws -> ExportArtifact {
        let property = properties.first(where: { $0.id == inspection.propertyID })
        guard let property else { throw RepositoryError.invalidLabel }
        let rooms = rooms(for: inspection)
        let findings = findings(for: inspection)
        let signatures = signatures(for: inspection)
        let service = InspectionService(clock: clock)
        try service.validateSeal(inspection, rooms: rooms, findings: findings, signatures: signatures)

        let sealedAt = clock()
        inspection.sealedAt = sealedAt
        let packet = integrity.packet(property: property, inspection: inspection, rooms: rooms,
                                      findings: findings, signatures: signatures)
        let digest = try integrity.digest(packet)

        var photos: [String: Data] = [:]
        for finding in findings {
            photos[IntegrityService.sha256(finding.photoData)] = finding.photoData
        }
        var signaturePayloads: [String: Data] = [:]
        for signature in signatures {
            signaturePayloads[IntegrityService.sha256(signature.pngData)] = signature.pngData
        }

        let pdf: Data
        do {
            pdf = try renderer.render(packet: packet, digest: digest, photos: photos,
                                      signatures: signaturePayloads)
        } catch {
            inspection.sealedAt = nil
            throw error
        }
        let pages = renderer.layout(for: packet, digest: digest, pageCount: 0,
                                    signatures: signaturePayloads).count

        inspection.status = .sealed
        store.save()
        let report = SealedReport(inspectionID: inspection.id, revision: inspection.revision,
                                  generatedAt: sealedAt, sha256: digest,
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
