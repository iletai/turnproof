import CoreGraphics
import Foundation
import Testing
import UIKit
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

    @Test func signaturePageCarriesTheDrawnImages() {
        let packet = packet(rooms: [("kitchen", 1)])
        let payload = Data([0x89, 0x50, 0x4e, 0x47])
        let layout = renderer.layout(for: packet, digest: "digest", pageCount: 0,
                                     signatures: ["c": payload])
        let tenant = layout.flatMap(\.blocks).first {
            $0.kind == .signature && $0.text == "c"
        }
        #expect(tenant?.payload == payload)
    }

    @Test func datesPrintInUTC() {
        #expect(ReportPDFRenderer.date(clock) == "9 Oct 2025, 08:53 UTC")
    }

    @Test func footerShowsShortCodeAndPageNumbers() {
        let layout = renderer.layout(for: packet(rooms: [("kitchen", 1)]), digest: "a1b2c3d4e5f6",
                                     pageCount: 3)
        #expect(layout.last?.blocks.contains { $0.text.contains("PAGES 3") } == true)
    }

    /// Reads the page into a bitmap and returns the RGB of the pixel `rowFromTop` rows below the page top.
    private func pixel(of pdf: Data, page index: Int, x: Int, rowFromTop: Int) throws -> (r: Int, g: Int, b: Int) {
        let document = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        let page = try #require(document.page(at: index + 1))
        let size = ReportPDFRenderer.pageSize
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.drawPDFPage(page)
        }
        let offset = (rowFromTop * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    @Test func photosKeepTheirOrientationInThePDF() throws {
        let size = CGSize(width: 100, height: 100)
        let jpeg = UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).jpegData(
            withCompressionQuality: 1
        ) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        }
        let packet = packet(rooms: [("kitchen", 1)])
        let layout = renderer.layout(for: packet, digest: "digest", pageCount: 0)
        let photo = try #require(layout[1].blocks.first { $0.kind == .photo })
        let pdf = try renderer.render(packet: packet, digest: "digest",
                                      photos: [photo.text: jpeg])

        let x = Int(photo.rect.midX)
        let top = try pixel(of: pdf, page: 1, x: x, rowFromTop: Int(photo.rect.minY) + 8)
        let bottom = try pixel(of: pdf, page: 1, x: x, rowFromTop: Int(photo.rect.maxY) - 8)
        #expect(top.r > 150 && top.b < 100, "top of the photo should stay red, got \(top)")
        #expect(bottom.b > 150 && bottom.r < 100, "bottom of the photo should stay blue, got \(bottom)")
    }
}
