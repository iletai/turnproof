import Foundation

enum InspectionError: Error, Equatable {
    case sealed
    case photoLimit
    case emptyNote
    case notFound
    case blocked
}

enum ValidationIssue: Equatable, Sendable {
    case noRooms
    case noFindings(room: String)
    case missingSignature(SignatureRole)
    case unresolvedDamage(room: String)
    case tooManyPhotos(Int)

    var message: String {
        switch self {
        case .noRooms:
            String(localized: "Add at least one room.")
        case .noFindings(let room):
            String(localized: "\(room) has no photos.")
        case .missingSignature(let role):
            role == .tenant
                ? String(localized: "The tenant has not signed.")
                : String(localized: "The landlord has not signed.")
        case .unresolvedDamage(let room):
            String(localized: "\(room) has damage without a note.")
        case .tooManyPhotos(let count):
            String(localized: "\(count) photos. Limit is \(InspectionService.photoLimit).")
        }
    }
}

/// Pure rules for a report: what is allowed, what blocks the seal, how a finding is recorded.
struct InspectionService: Sendable {
    static let photoLimit = 40

    let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    func validation(rooms: [Room], findings: [Finding], signatures: [Signature]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if rooms.isEmpty { issues.append(.noRooms) }
        if findings.count > Self.photoLimit { issues.append(.tooManyPhotos(findings.count)) }

        for room in rooms.sorted(by: { $0.order < $1.order }) {
            let roomFindings = findings.filter { $0.roomID == room.id }
            if roomFindings.isEmpty { issues.append(.noFindings(room: room.name)) }
            if roomFindings.contains(where: { $0.isDamageFlagged && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                issues.append(.unresolvedDamage(room: room.name))
            }
        }
        for role in SignatureRole.allCases where !signatures.contains(where: { $0.role == role }) {
            issues.append(.missingSignature(role))
        }
        return issues
    }

    func capture(in inspection: Inspection, roomID: UUID, order: Int,
                 photo: IngestedPhoto, condition: Condition, note: String,
                 isDamageFlagged: Bool) throws -> Finding {
        guard inspection.status == .draft else { throw InspectionError.sealed }
        // An empty note is allowed while drafting: review lists it as unresolved damage and the
        // seal step is what refuses it. Blocking here would make the review screen unreachable.
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Finding(
            inspectionID: inspection.id,
            roomID: roomID,
            order: order,
            photoData: photo.jpeg,
            condition: condition,
            note: trimmed,
            isDamageFlagged: isDamageFlagged,
            capturedAt: clock(),
            exifTakenAt: photo.exifTakenAt
        )
    }

    func seal(_ inspection: Inspection, rooms: [Room], findings: [Finding],
              signatures: [Signature]) throws -> Date {
        guard inspection.status == .draft else { throw InspectionError.sealed }
        let issues = validation(rooms: rooms, findings: findings, signatures: signatures)
        if issues.contains(where: { if case .tooManyPhotos = $0 { true } else { false } }) {
            throw InspectionError.photoLimit
        }
        if findings.contains(where: { $0.isDamageFlagged && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw InspectionError.emptyNote
        }
        if issues.contains(where: { if case .missingSignature = $0 { true } else { false } }) {
            throw InspectionError.blocked
        }
        guard issues.isEmpty else { throw InspectionError.blocked }
        let sealedAt = clock()
        inspection.status = .sealed
        inspection.sealedAt = sealedAt
        return sealedAt
    }
}
