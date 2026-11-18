import CoreGraphics
import Foundation
import Testing
@testable import Turnproof

struct PDFLayoutTests {
    private let clock = Date(timeIntervalSince1970: 1_760_000_000)
    private let renderer = ReportPDFRenderer { IntegrityService().shortCode($0) }

    private func finding(order: Int, note: String = "Scuff on cabinet door") -> ReportPacket.FindingInfo {
        .init(order: order, condition: "damaged", note: note, isDamageFlagged: true,
              capturedAt: clock, exifTakenAt: nil, photoSHA256: String(repeating: "a", count: 64))
    }

    private func packet(rooms: [(String, Int)], note: String = "Scuff on cabinet door") -> ReportPacket {
        ReportPacket(
            reportID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            property: .init(label: "Unit A", addressLine: "1 Main St", unit: "2", landlordName: "Lee"),
            inspection: .init(kind: "moveOut", startedAt: clock, sealedAt: clock,
                              tenantName: "Ana", inspectorName: "Lee", revision: 1),
            rooms: rooms.enumerated().map { index, room in
                .init(templateKey: room.0, name: room.0.capitalized, order: index,
                      findings: (0..<room.1).map { finding(order: $0, note: note) })
            },
            signatures: [
                .init(role: "landlord", signedAt: clock, pngSHA256: "b"),
                .init(role: "tenant", signedAt: clock, pngSHA256: "c"),
            ]
        )
    }

    @Test func threeRoomsNinePhotosProduceSixPages() {
        let layout = renderer.layout(
            for: packet(rooms: [("kitchen", 3), ("living", 3), ("bath", 3)]),
            digest: "digest", pageCount: 0
        )
        #expect(layout.count == 6)
        #expect(layout.first?.blocks.first?.kind == .eyebrow)
        #expect(layout.last?.blocks.first?.text == "INTEGRITY")
    }

    @Test func roomWithFivePhotosContinuesOnASecondPage() {
        let layout = renderer.layout(for: packet(rooms: [("kitchen", 5)]), digest: "digest", pageCount: 0)
        #expect(layout.count == 5)
        #expect(layout[1].blocks.first?.text == "ROOM")
        #expect(layout[2].blocks.first?.text == "ROOM · CONTINUED")
    }

    @Test func emptyRoomStillGetsAPage() {
        let layout = renderer.layout(for: packet(rooms: [("hall", 0)]), digest: "digest", pageCount: 0)
        #expect(layout.count == 4)
        #expect(layout[1].blocks.contains { $0.text == "No photos recorded for this room." })
    }

    @Test func longNoteStaysInsideItsCaptionBox() {
        let long = String(repeating: "Cabinet door scratched along the lower hinge, 12 cm. ", count: 4)
        let layout = renderer.layout(for: packet(rooms: [("kitchen", 1)], note: long), digest: "digest", pageCount: 0)
        let caption = layout[1].blocks.first { $0.kind == .body }
        #expect(caption?.text.contains(long) == true)
        #expect(caption?.rect.height == 44)
    }

    @Test func vietnameseTextKeepsTheSameGeometry() {
        let ascii = renderer.layout(for: packet(rooms: [("kitchen", 2)], note: "Ong", ),
                                    digest: "digest", pageCount: 0)
        let vietnamese = renderer.layout(for: packet(rooms: [("kitchen", 2)], note: "Ống"),
                                         digest: "digest", pageCount: 0)
        #expect(ascii.count == vietnamese.count)
        #expect(ascii[1].blocks.map(\.rect) == vietnamese[1].blocks.map(\.rect))
    }

    @Test func renderedPDFHasOnePagePerLayoutPage() throws {
        let packet = packet(rooms: [("kitchen", 2), ("bath", 1)])
        let expected = renderer.layout(for: packet, digest: "digest", pageCount: 0).count
        let data = try renderer.render(packet: packet, digest: "digest")

        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == expected)
        #expect(data.count > 1_000)
    }

    @Test func footerShowsShortCodeAndPageNumbers() {
        let layout = renderer.layout(for: packet(rooms: [("kitchen", 1)]), digest: "a1b2c3d4e5f6",
                                     pageCount: 3)
        #expect(layout.last?.blocks.contains { $0.text.contains("PAGES 3") } == true)
    }
}
