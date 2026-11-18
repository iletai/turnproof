import Foundation
import SwiftData
import Testing
@testable import Turnproof

/// Exercises the AppModel-level rules the screens rely on: what reaches the renderer, what stays
/// committed when rendering fails, and which edits a sealed record refuses.
@MainActor
@Suite(.serialized)
struct AppModelSealTests {
    private let clock = Date(timeIntervalSince1970: 1_760_000_000)
    private let tenantPNG = Data([0x89, 0x50, 0x4e, 0x47, 0x01])
    private let landlordPNG = Data([0x89, 0x50, 0x4e, 0x47, 0x02])

    /// SwiftData traps if a container is released while its context is still alive.
    @MainActor private final class Keeper {
        static var containers: [ModelContainer] = []
    }

    private final class MemoryKeychain: KeychainStoring, @unchecked Sendable {
        private var storage: [String: Data] = [:]
        func read(_ key: String) -> Data? { storage[key] }
        func write(_ data: Data?, _ key: String) { storage[key] = data }
    }

    private final class SpyRenderer: PDFRendering, @unchecked Sendable {
        var failure: Error?
        var renderedPhotos: [String: Data] = [:]
        var renderedSignatures: [String: Data] = [:]
        var layoutSignatures: [String: Data] = [:]
        var pageCount = 4

        func layout(for packet: ReportPacket, digest: String, pageCount: Int,
                    signatures: [String: Data]) -> [PageLayout] {
            layoutSignatures = signatures
            return (0..<self.pageCount).map { PageLayout(index: $0, blocks: []) }
        }

        func render(packet: ReportPacket, digest: String, photos: [String: Data],
                    signatures: [String: Data]) throws -> Data {
            renderedPhotos = photos
            renderedSignatures = signatures
            if let failure { throw failure }
            return Data("PDF".utf8)
        }
    }

    private func makeModel(renderer: any PDFRendering) throws -> AppModel {
        let container = try TurnproofStore.container(inMemory: true)
        Keeper.containers.append(container)
        return AppModel(
            store: TurnproofStore(context: container.mainContext),
            container: container,
            clock: { self.clock },
            usesFixturePhotos: true,
            counter: FreeReportCounter(keychain: MemoryKeychain()),
            renderer: renderer
        )
    }

    /// One finding in every template room so the inspection can seal.
    @discardableResult
    private func seeded(_ model: AppModel) throws -> (Inspection, [Room]) {
        try model.addProperty(label: "Unit A", address: "1 Main St", unit: "", landlord: "Lee")
        let property = try #require(model.properties.first)
        let inspection = model.startInspection(for: property, kind: .moveOut, tenant: "Ana")
        let rooms = model.rooms(for: inspection)
        for (index, room) in rooms.enumerated() {
            model.store.insert(Finding(inspectionID: inspection.id, roomID: room.id, order: 0,
                                       photoData: Data([UInt8(index + 1)]), condition: .good,
                                       note: "", isDamageFlagged: false, capturedAt: clock))
        }
        return (inspection, rooms)
    }

    private func signBoth(_ model: AppModel, _ inspection: Inspection) {
        model.sign(inspection: inspection, role: .tenant, png: tenantPNG)
        model.sign(inspection: inspection, role: .landlord, png: landlordPNG)
    }

    @Test func sealPassesPhotosAndSignatureImagesToTheRenderer() throws {
        let spy = SpyRenderer()
        let model = try makeModel(renderer: spy)
        let (inspection, _) = try seeded(model)
        signBoth(model, inspection)

        let artifact = try model.sealAndRender(inspection: inspection)

        #expect(spy.renderedSignatures.count == 2)
        #expect(spy.renderedSignatures[IntegrityService.sha256(tenantPNG)] == tenantPNG)
        #expect(spy.renderedSignatures[IntegrityService.sha256(landlordPNG)] == landlordPNG)
        #expect(spy.renderedPhotos.count == 6)
        #expect(spy.layoutSignatures.count == 2)
        #expect(artifact.pageCount == spy.pageCount)
        #expect(artifact.report.pageCount == spy.pageCount)
    }

    @Test func renderFailureLeavesTheInspectionDraft() throws {
        let spy = SpyRenderer()
        spy.failure = PDFError.contextUnavailable
        let model = try makeModel(renderer: spy)
        let (inspection, _) = try seeded(model)
        signBoth(model, inspection)

        #expect(throws: PDFError.self) {
            try model.sealAndRender(inspection: inspection)
        }

        #expect(inspection.status == .draft)
        #expect(inspection.sealedAt == nil)
        #expect(model.reports(for: inspection).isEmpty)

        // The rollback must leave a retry possible.
        spy.failure = nil
        let artifact = try model.sealAndRender(inspection: inspection)
        #expect(inspection.status == .sealed)
        #expect(artifact.report.revision == 1)
    }

    @Test func sealedInspectionRejectsCaptureDeleteAndSignature() throws {
        let model = try makeModel(renderer: SpyRenderer())
        let (inspection, rooms) = try seeded(model)
        signBoth(model, inspection)
        _ = try model.sealAndRender(inspection: inspection)

        let before = model.findings(for: inspection)

        #expect(throws: InspectionError.sealed) {
            try model.capture(room: rooms[0], inspection: inspection, rawPhoto: Data([0x00]),
                              condition: .good, note: "", flagged: false)
        }
        #expect(model.findings(for: inspection).count == before.count)

        model.deleteFinding(before[0])
        #expect(model.findings(for: inspection).count == before.count)

        model.sign(inspection: inspection, role: .tenant, png: Data([0x99]))
        let tenant = model.signatures(for: inspection).first { $0.role == .tenant }
        #expect(tenant?.pngData == tenantPNG)
    }

    @Test func captureStopsAtThePhotoLimit() throws {
        let model = try makeModel(renderer: SpyRenderer())
        try model.addProperty(label: "Unit A", address: "1 Main St", unit: "", landlord: "Lee")
        let property = try #require(model.properties.first)
        let inspection = model.startInspection(for: property, kind: .moveOut, tenant: "")
        let room = try #require(model.rooms(for: inspection).first)

        for index in 0..<InspectionService.photoLimit {
            model.store.insert(Finding(inspectionID: inspection.id, roomID: room.id, order: index,
                                       photoData: Data([UInt8(index % 255)]), condition: .good,
                                       note: "", isDamageFlagged: false, capturedAt: clock))
        }

        #expect(throws: InspectionError.photoLimit) {
            try model.capture(room: room, inspection: inspection, rawPhoto: Data([0x00]),
                              condition: .good, note: "", flagged: false)
        }
        #expect(model.findings(for: inspection).count == InspectionService.photoLimit)
    }

    @Test func unlockedReportsSurviveANewModel() throws {
        UserDefaults.standard.removeObject(forKey: AppModel.unlockedKey)
        defer { UserDefaults.standard.removeObject(forKey: AppModel.unlockedKey) }

        let report = SealedReport(inspectionID: UUID(), revision: 1, generatedAt: clock,
                                  sha256: "abc", pageCount: 1, pdfData: Data([0x01]))

        let model = try makeModel(renderer: SpyRenderer())
        #expect(model.isUnlocked(report) == false)

        model.unlock(report)
        #expect(model.isUnlocked(report))

        let reloaded = try makeModel(renderer: SpyRenderer())
        #expect(reloaded.isUnlocked(report))
    }
}
