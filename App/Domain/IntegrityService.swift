import CryptoKit
import Foundation

struct ReportPacket: Sendable, Equatable, Codable {
    struct PropertyInfo: Codable, Sendable, Equatable {
        var label: String
        var addressLine: String
        var unit: String
        var landlordName: String
    }

    struct InspectionInfo: Codable, Sendable, Equatable {
        var kind: String
        var startedAt: Date
        var sealedAt: Date?
        var tenantName: String
        var inspectorName: String
        var revision: Int
    }

    struct FindingInfo: Codable, Sendable, Equatable {
        var order: Int
        var condition: String
        var note: String
        var isDamageFlagged: Bool
        var capturedAt: Date
        var exifTakenAt: Date?
        var photoSHA256: String
    }

    struct RoomInfo: Codable, Sendable, Equatable {
        var templateKey: String
        var name: String
        var order: Int
        var findings: [FindingInfo]
    }

    struct SignatureInfo: Codable, Sendable, Equatable {
        var role: String
        var signedAt: Date
        var pngSHA256: String
    }

    var reportID: UUID
    var property: PropertyInfo
    var inspection: InspectionInfo
    var rooms: [RoomInfo]
    var signatures: [SignatureInfo]

    var totalPhotos: Int { rooms.reduce(0) { $0 + $1.findings.count } }
}

struct IntegrityService: Sendable {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoString(date))
        }
        return encoder
    }()

    /// Fresh formatter per call: ISO8601DateFormatter is not Sendable, and manifest encoding is off the hot path.
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    func packet(property: Property, inspection: Inspection, rooms: [Room],
                findings: [Finding], signatures: [Signature]) -> ReportPacket {
        let signatureInfos = signatures
            .sorted { $0.role.rawValue < $1.role.rawValue }
            .map {
                ReportPacket.SignatureInfo(
                    role: $0.role.rawValue,
                    signedAt: $0.signedAt,
                    pngSHA256: Self.sha256($0.pngData)
                )
            }
        let roomInfos = rooms.sorted { $0.order < $1.order }.map { room in
            ReportPacket.RoomInfo(
                templateKey: room.templateKey,
                name: room.name,
                order: room.order,
                findings: findings
                    .filter { $0.roomID == room.id }
                    .sorted { $0.order < $1.order }
                    .map {
                        ReportPacket.FindingInfo(
                            order: $0.order,
                            condition: $0.condition.rawValue,
                            note: $0.note,
                            isDamageFlagged: $0.isDamageFlagged,
                            capturedAt: $0.capturedAt,
                            exifTakenAt: $0.exifTakenAt,
                            photoSHA256: Self.sha256($0.photoData)
                        )
                    }
            )
        }
        return ReportPacket(
            reportID: inspection.id,
            property: .init(label: property.label, addressLine: property.addressLine,
                            unit: property.unit, landlordName: property.landlordName),
            inspection: .init(kind: inspection.kind.rawValue, startedAt: inspection.startedAt,
                              sealedAt: inspection.sealedAt, tenantName: inspection.tenantName,
                              inspectorName: inspection.inspectorName, revision: inspection.revision),
            rooms: roomInfos,
            signatures: signatureInfos
        )
    }

    func manifest(for packet: ReportPacket) throws -> Data {
        try encoder.encode(packet)
    }

    func digest(_ packet: ReportPacket) throws -> String {
        Self.sha256(try manifest(for: packet))
    }

    func shortCode(_ digest: String) -> String {
        var remaining = String(digest.uppercased().prefix(12))
        var chunks: [String] = []
        while !remaining.isEmpty {
            let size = Swift.min(4, remaining.count)
            let end = remaining.index(remaining.startIndex, offsetBy: size)
            chunks.append(String(remaining[remaining.startIndex..<end]))
            remaining = String(remaining[end...])
        }
        return chunks.joined(separator: "-")
    }

    func verify(_ report: SealedReport, packet: ReportPacket) -> Bool {
        guard let recomputed = try? digest(packet) else { return false }
        return recomputed == report.sha256
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
