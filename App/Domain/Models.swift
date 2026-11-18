import Foundation
import SwiftData

enum InspectionKind: String, Codable, CaseIterable, Sendable {
    case moveIn, moveOut, periodic

    var title: String {
        switch self {
        case .moveIn: "Move-in"
        case .moveOut: "Move-out"
        case .periodic: "Periodic"
        }
    }
}

enum InspectionStatus: String, Codable, Sendable {
    case draft, sealed
}

enum Condition: String, Codable, CaseIterable, Sendable {
    case good, fair, damaged
}

enum SignatureRole: String, Codable, CaseIterable, Sendable {
    case tenant, landlord
}

@Model
final class Property {
    @Attribute(.unique) var id: UUID
    var label: String
    var addressLine: String
    var unit: String
    var landlordName: String
    var createdAt: Date

    init(id: UUID = UUID(), label: String, addressLine: String, unit: String,
         landlordName: String, createdAt: Date) {
        self.id = id
        self.label = label
        self.addressLine = addressLine
        self.unit = unit
        self.landlordName = landlordName
        self.createdAt = createdAt
    }
}

@Model
final class Inspection {
    @Attribute(.unique) var id: UUID
    var propertyID: UUID
    var kindRaw: String
    var statusRaw: String
    var startedAt: Date
    var sealedAt: Date?
    var tenantName: String
    var inspectorName: String
    var revision: Int

    init(id: UUID = UUID(), propertyID: UUID, kind: InspectionKind, status: InspectionStatus = .draft,
         startedAt: Date, sealedAt: Date? = nil, tenantName: String = "",
         inspectorName: String = "", revision: Int = 1) {
        self.id = id
        self.propertyID = propertyID
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.sealedAt = sealedAt
        self.tenantName = tenantName
        self.inspectorName = inspectorName
        self.revision = revision
    }

    var kind: InspectionKind {
        get { InspectionKind(rawValue: kindRaw) ?? .periodic }
        set { kindRaw = newValue.rawValue }
    }

    var status: InspectionStatus {
        get { InspectionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var inspectionID: UUID
    var templateKey: String
    var name: String
    var order: Int

    init(id: UUID = UUID(), inspectionID: UUID, templateKey: String, name: String, order: Int) {
        self.id = id
        self.inspectionID = inspectionID
        self.templateKey = templateKey
        self.name = name
        self.order = order
    }
}

@Model
final class Finding {
    @Attribute(.unique) var id: UUID
    var inspectionID: UUID
    var roomID: UUID
    var order: Int
    @Attribute(.externalStorage) var photoData: Data
    var conditionRaw: String
    var note: String
    var isDamageFlagged: Bool
    var capturedAt: Date
    var exifTakenAt: Date?

    init(id: UUID = UUID(), inspectionID: UUID, roomID: UUID, order: Int, photoData: Data,
         condition: Condition, note: String, isDamageFlagged: Bool,
         capturedAt: Date, exifTakenAt: Date? = nil) {
        self.id = id
        self.inspectionID = inspectionID
        self.roomID = roomID
        self.order = order
        self.photoData = photoData
        self.conditionRaw = condition.rawValue
        self.note = note
        self.isDamageFlagged = isDamageFlagged
        self.capturedAt = capturedAt
        self.exifTakenAt = exifTakenAt
    }

    var condition: Condition {
        get { Condition(rawValue: conditionRaw) ?? .good }
        set { conditionRaw = newValue.rawValue }
    }
}

@Model
final class Signature {
    @Attribute(.unique) var id: UUID
    var inspectionID: UUID
    var roleRaw: String
    @Attribute(.externalStorage) var pngData: Data
    var signedAt: Date

    init(id: UUID = UUID(), inspectionID: UUID, role: SignatureRole, pngData: Data, signedAt: Date) {
        self.id = id
        self.inspectionID = inspectionID
        self.roleRaw = role.rawValue
        self.pngData = pngData
        self.signedAt = signedAt
    }

    var role: SignatureRole {
        get { SignatureRole(rawValue: roleRaw) ?? .tenant }
        set { roleRaw = newValue.rawValue }
    }
}

@Model
final class SealedReport {
    @Attribute(.unique) var id: UUID
    var inspectionID: UUID
    var revision: Int
    var generatedAt: Date
    var sha256: String
    var pageCount: Int
    @Attribute(.externalStorage) var pdfData: Data
    var supersedesID: UUID?

    init(id: UUID = UUID(), inspectionID: UUID, revision: Int, generatedAt: Date,
         sha256: String, pageCount: Int, pdfData: Data, supersedesID: UUID? = nil) {
        self.id = id
        self.inspectionID = inspectionID
        self.revision = revision
        self.generatedAt = generatedAt
        self.sha256 = sha256
        self.pageCount = pageCount
        self.pdfData = pdfData
        self.supersedesID = supersedesID
    }
}

enum RoomTemplate {
    static let keys = ["kitchen", "living", "bedroom", "bath", "hall", "exterior"]

    static func name(for key: String) -> String {
        switch key {
        case "kitchen": String(localized: "Kitchen")
        case "living": String(localized: "Living room")
        case "bedroom": String(localized: "Bedroom")
        case "bath": String(localized: "Bathroom")
        case "hall": String(localized: "Hall")
        case "exterior": String(localized: "Exterior")
        default: key.capitalized
        }
    }
}
