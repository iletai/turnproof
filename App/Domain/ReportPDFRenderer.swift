import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

struct LayoutBlock: Equatable, Sendable {
    enum Kind: String, Sendable {
        case eyebrow, title, subtitle, body, meta, rule, photo, signature, qr
    }

    let kind: Kind
    let rect: CGRect
    let text: String
    var payload: Data? = nil
}

struct PageLayout: Equatable, Sendable {
    let index: Int
    let blocks: [LayoutBlock]

    var description: String {
        let header = "page \(index)"
        let body = blocks.map { block in
            let r = block.rect
            return "\(block.kind.rawValue) \(r.minX.rounded()) \(r.minY.rounded()) \(r.width.rounded()) \(r.height.rounded()) \(block.text)"
        }
        return ([header] + body).joined(separator: "\n")
    }
}

enum PDFError: Error {
    case contextUnavailable
}

/// Injected so tests can prove the seal is not committed when rendering fails.
protocol PDFRendering: Sendable {
    func layout(for packet: ReportPacket, digest: String, pageCount: Int,
                signatures: [String: Data]) -> [PageLayout]
    func render(packet: ReportPacket, digest: String, photos: [String: Data],
                signatures: [String: Data]) throws -> Data
}

struct ReportPDFRenderer: PDFRendering, Sendable {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 48
    static let photosPerPage = 4

    let shortCode: @Sendable (String) -> String

    init(shortCode: @escaping @Sendable (String) -> String) {
        self.shortCode = shortCode
    }

    func layout(for packet: ReportPacket, digest: String, pageCount: Int,
                signatures: [String: Data] = [:]) -> [PageLayout] {
        var pages: [PageLayout] = []
        pages.append(cover(packet: packet, digest: digest, index: 0))

        for room in packet.rooms {
            let chunks = room.findings.chunked(into: Self.photosPerPage)
            for (chunkIndex, chunk) in chunks.enumerated() {
                pages.append(roomPage(room: room, findings: chunk, continued: chunkIndex > 0,
                                      index: pages.count))
            }
            if room.findings.isEmpty {
                pages.append(roomPage(room: room, findings: [], continued: false, index: pages.count))
            }
        }

        pages.append(signaturePage(packet: packet, signatures: signatures, index: pages.count))
        pages.append(integrityPage(packet: packet, digest: digest, pageCount: pageCount,
                                   index: pages.count))
        return pages
    }

    func render(packet: ReportPacket, digest: String, photos: [String: Data] = [:],
                signatures: [String: Data] = [:]) throws -> Data {
        let provisional = layout(for: packet, digest: digest, pageCount: 0, signatures: signatures)
        let pages = layout(for: packet, digest: digest, pageCount: provisional.count,
                           signatures: signatures)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Turnproof",
            kCGPDFContextTitle as String: "\(packet.property.label) · \(packet.inspection.kind)",
            kCGPDFContextSubject as String: digest,
            kCGPDFContextAuthor as String: packet.inspection.inspectorName,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize),
                                             format: format)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                draw(page: page, photos: photos, in: context.cgContext)
                drawFooter(pageIndex: page.index + 1, total: pages.count, packet: packet,
                           digest: digest)
            }
        }
    }

    // MARK: Pages

    private func cover(packet: ReportPacket, digest: String, index: Int) -> PageLayout {
        var blocks: [LayoutBlock] = []
        let width = Self.pageSize.width - Self.margin * 2
        var y = Self.margin

        blocks.append(.init(kind: .eyebrow, rect: CGRect(x: Self.margin, y: y, width: width, height: 14),
                            text: "TURNPROOF · CONDITION REPORT"))
        y += 28
        blocks.append(.init(kind: .title, rect: CGRect(x: Self.margin, y: y, width: width, height: 84),
                            text: packet.property.label))
        y += 88
        blocks.append(.init(kind: .subtitle, rect: CGRect(x: Self.margin, y: y, width: width, height: 20),
                            text: packet.property.unit))
        y += 36
        blocks.append(.init(kind: .rule, rect: CGRect(x: Self.margin, y: y, width: width, height: 1), text: ""))
        y += 24

        let rows: [(String, String)] = [
            ("Address", packet.property.addressLine),
            ("Inspection", packet.inspection.kind.capitalized),
            ("Started", Self.date(packet.inspection.startedAt)),
            ("Sealed", packet.inspection.sealedAt.map(Self.date) ?? "—"),
            ("Tenant", packet.inspection.tenantName),
            ("Landlord", packet.property.landlordName),
            ("Report ID", packet.reportID.uuidString.prefix(8).uppercased()),
            ("Short code", shortCode(digest)),
        ]
        for (label, value) in rows {
            blocks.append(.init(kind: .meta, rect: CGRect(x: Self.margin, y: y, width: 140, height: 20),
                                text: label.uppercased()))
            blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin + 150, y: y, width: width - 150, height: 20),
                                text: value))
            y += 26
        }
        return PageLayout(index: index, blocks: blocks)
    }

    private func roomPage(room: ReportPacket.RoomInfo, findings: [ReportPacket.FindingInfo],
                          continued: Bool, index: Int) -> PageLayout {
        var blocks: [LayoutBlock] = []
        let width = Self.pageSize.width - Self.margin * 2
        blocks.append(.init(kind: .eyebrow, rect: CGRect(x: Self.margin, y: Self.margin, width: width, height: 14),
                            text: continued ? "ROOM · CONTINUED" : "ROOM"))
        blocks.append(.init(kind: .title, rect: CGRect(x: Self.margin, y: Self.margin + 24, width: width, height: 40),
                            text: room.name))
        blocks.append(.init(kind: .rule, rect: CGRect(x: Self.margin, y: Self.margin + 72, width: width, height: 1), text: ""))

        let columnWidth = (width - 16) / 2
        let tileHeight: CGFloat = 196
        for (position, finding) in findings.enumerated() {
            let column = position % 2
            let row = position / 2
            let x = Self.margin + CGFloat(column) * (columnWidth + 16)
            let y = Self.margin + 92 + CGFloat(row) * (tileHeight + 56)
            blocks.append(.init(kind: .photo, rect: CGRect(x: x, y: y, width: columnWidth, height: tileHeight),
                                text: finding.photoSHA256))
            let caption = Self.caption(for: finding)
            blocks.append(.init(kind: .body, rect: CGRect(x: x, y: y + tileHeight + 6, width: columnWidth, height: 44),
                                text: caption))
        }
        if findings.isEmpty {
            blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin, y: Self.margin + 92, width: width, height: 20),
                                text: "No photos recorded for this room."))
        }
        return PageLayout(index: index, blocks: blocks)
    }

    private func signaturePage(packet: ReportPacket, signatures: [String: Data],
                               index: Int) -> PageLayout {
        var blocks: [LayoutBlock] = []
        let width = Self.pageSize.width - Self.margin * 2
        blocks.append(.init(kind: .eyebrow, rect: CGRect(x: Self.margin, y: Self.margin, width: width, height: 14),
                            text: "SIGNED ON THIS DEVICE"))
        blocks.append(.init(kind: .title, rect: CGRect(x: Self.margin, y: Self.margin + 24, width: width, height: 40),
                            text: "Signatures"))
        blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin, y: Self.margin + 76, width: width, height: 66),
                            text: "Both parties signed on this device in each other's presence. The photos and notes above describe the unit at the time shown."))

        var y = Self.margin + 160
        for signature in packet.signatures {
            blocks.append(.init(kind: .meta, rect: CGRect(x: Self.margin, y: y, width: width, height: 16),
                                text: signature.role.uppercased()))
            blocks.append(.init(kind: .signature, rect: CGRect(x: Self.margin, y: y + 20, width: width, height: 120),
                                text: signature.pngSHA256, payload: signatures[signature.pngSHA256]))
            blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin, y: y + 146, width: width, height: 18),
                                text: Self.date(signature.signedAt)))
            y += 190
        }
        return PageLayout(index: index, blocks: blocks)
    }

    private func integrityPage(packet: ReportPacket, digest: String, pageCount: Int, index: Int) -> PageLayout {
        var blocks: [LayoutBlock] = []
        let width = Self.pageSize.width - Self.margin * 2
        blocks.append(.init(kind: .eyebrow, rect: CGRect(x: Self.margin, y: Self.margin, width: width, height: 14),
                            text: "INTEGRITY"))
        blocks.append(.init(kind: .title, rect: CGRect(x: Self.margin, y: Self.margin + 24, width: width, height: 40),
                            text: "Sealed record"))
        blocks.append(.init(kind: .qr, rect: CGRect(x: Self.margin, y: Self.margin + 92, width: 120, height: 120),
                            text: digest))
        blocks.append(.init(kind: .meta, rect: CGRect(x: Self.margin + 140, y: Self.margin + 96, width: width - 140, height: 16),
                            text: "SHA-256"))
        blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin + 140, y: Self.margin + 118, width: width - 140, height: 72),
                            text: digest))
        blocks.append(.init(kind: .body, rect: CGRect(x: Self.margin, y: Self.margin + 240, width: width, height: 96),
                            text: "This code is a SHA-256 digest of the report's records and photo hashes. Anyone can read it. Turnproof recomputes it from the original records on the device that sealed it; this packet does not prove the records to a third party on its own."))
        blocks.append(.init(kind: .meta, rect: CGRect(x: Self.margin, y: Self.margin + 352, width: width, height: 16),
                            text: "PAGES \(pageCount) · REVISION \(packet.inspection.revision)"))
        return PageLayout(index: index, blocks: blocks)
    }

    // MARK: Drawing

    private func draw(page: PageLayout, photos: [String: Data], in context: CGContext) {
        UIColor(red: 0.965, green: 0.949, blue: 0.918, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: Self.pageSize))
        for block in page.blocks {
            switch block.kind {
            case .rule:
                UIColor(red: 0.87, green: 0.84, blue: 0.79, alpha: 1).setFill()
                context.fill(block.rect)
            case .photo:
                drawImage(photos[block.text], in: block.rect, context: context)
            case .signature:
                drawSignature(block.payload, in: block.rect, context: context)
            case .qr:
                drawQR(block.text, in: block.rect, context: context)
            default:
                drawText(block)
            }
        }
    }

    private func drawText(_ block: LayoutBlock) {
        let ink = UIColor(red: 0.063, green: 0.137, blue: 0.231, alpha: 1)
        let secondary = UIColor(red: 0.29, green: 0.35, blue: 0.42, alpha: 1)
        let font: UIFont
        let color: UIColor
        switch block.kind {
        case .eyebrow, .meta:
            font = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            color = secondary
        case .title:
            font = UIFont.systemFont(ofSize: 30, weight: .semibold)
            color = ink
        case .subtitle:
            font = UIFont.systemFont(ofSize: 17, weight: .regular)
            color = secondary
        default:
            font = UIFont.systemFont(ofSize: 11, weight: .regular)
            color = ink
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = block.kind == .body ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        (block.text as NSString).draw(with: block.rect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
    }

    private func drawImage(_ data: Data?, in rect: CGRect, context: CGContext) {
        guard let data, let uiImage = UIImage(data: data), let image = uiImage.cgImage else {
            drawPlaceholderPhoto(in: rect, context: context)
            return
        }
        context.saveGState()
        context.interpolationQuality = .high
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        context.addRect(rect)
        context.clip()
        // UIImage.draw honours the UIKit-flipped PDF context; CGContext.draw would mirror the image vertically.
        uiImage.draw(in: CGRect(origin: origin, size: size))
        context.restoreGState()
        UIColor(red: 0.87, green: 0.84, blue: 0.79, alpha: 1).setStroke()
        context.setLineWidth(1)
        context.stroke(rect)
    }

    private func drawPlaceholderPhoto(in rect: CGRect, context: CGContext) {
        UIColor(red: 0.85, green: 0.83, blue: 0.79, alpha: 1).setFill()
        context.fill(rect)
        UIColor(red: 0.55, green: 0.58, blue: 0.6, alpha: 1).setStroke()
        context.setLineWidth(1)
        context.stroke(rect)
    }

    private func drawSignature(_ data: Data?, in rect: CGRect, context: CGContext) {
        UIColor.white.setFill()
        context.fill(rect)
        if let data, let image = UIImage(data: data)?.cgImage {
            context.saveGState()
            context.interpolationQuality = .high
            UIImage(cgImage: image).draw(in: rect.insetBy(dx: 12, dy: 8))
            context.restoreGState()
        }
        UIColor(red: 0.87, green: 0.84, blue: 0.79, alpha: 1).setStroke()
        context.setLineWidth(1)
        context.stroke(rect)
        let baseline = CGRect(x: rect.minX + 24, y: rect.maxY - 24, width: rect.width - 48, height: 1)
        UIColor(red: 0.29, green: 0.35, blue: 0.42, alpha: 1).setFill()
        context.fill(baseline)
    }

    private func drawQR(_ digest: String, in rect: CGRect, context: CGContext) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(digest.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return }
        context.saveGState()
        context.interpolationQuality = .none
        UIImage(cgImage: cgImage).draw(in: rect)
        context.restoreGState()
    }

    private func drawFooter(pageIndex: Int, total: Int, packet: ReportPacket, digest: String) {
        let text = "\(packet.reportID.uuidString.prefix(8).uppercased()) · \(shortCode(digest)) · \(pageIndex)/\(total)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor(red: 0.45, green: 0.5, blue: 0.55, alpha: 1),
        ]
        (text as NSString).draw(at: CGPoint(x: Self.margin, y: Self.pageSize.height - 32), withAttributes: attributes)
    }

    private static func caption(for finding: ReportPacket.FindingInfo) -> String {
        var parts = [finding.condition.uppercased()]
        if !finding.note.isEmpty { parts.append(finding.note) }
        parts.append(Self.date(finding.capturedAt))
        return parts.joined(separator: " · ")
    }

    /// UTC so a packet printed after travelling still shows the instant the digest hashed.
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy, HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
