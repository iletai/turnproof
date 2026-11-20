import SwiftUI

/// "Maple Court · Unit 2B"; file-private so parallel lanes can format the same fields their own way.
private func detailTitle(_ property: Property) -> String {
    [property.label, property.unit].filter { !$0.isEmpty }.joined(separator: " · ")
}

struct PropertyDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let propertyID: UUID

    @State private var pendingKind: InspectionKind = .moveOut

    var body: some View {
        _ = model.revision
        return Group {
            if let property = model.property(id: propertyID) {
                content(property)
            } else {
                ContentUnavailableView("Unit not found", systemImage: "building.2")
            }
        }
    }

    private func content(_ property: Property) -> some View {
        let inspections = model.inspections(for: property)
        let active = inspections.first { $0.status == .draft }
        let reports = sealedReports(for: inspections)
        return List {
            Section {
                LabeledContent("Address", value: property.addressLine)
                LabeledContent("Landlord", value: property.landlordName)
            }

            if let active {
                Section("In progress") {
                    Button {
                        router.push(.rooms(active.id))
                    } label: {
                        activeRow(active)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inspection.continue")
                }
            }

            Section("Reports") {
                if reports.isEmpty {
                    Text("No sealed reports yet.")
                        .font(.footnote)
                        .foregroundStyle(TPColor.textSecondary)
                } else {
                    ForEach(reports, id: \.id) { report in
                        Button {
                            router.push(.export(report.inspectionID))
                        } label: {
                            reportRow(report)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history.report.\(report.id.uuidString)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detailTitle(property))
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            VStack(spacing: 8) {
                Picker("Inspection", selection: $pendingKind) {
                    ForEach(InspectionKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("inspection.kind")

                Button(active == nil ? "Start new inspection" : "Continue inspection") {
                    if let active {
                        router.push(.rooms(active.id))
                    } else {
                        let inspection = model.startInspection(for: property, kind: pendingKind,
                                                               tenant: "")
                        router.push(.rooms(inspection.id))
                    }
                }
                .primaryActionStyle()
                .accessibilityIdentifier("inspection.new")
            }
        }
    }

    private func activeRow(_ inspection: Inspection) -> some View {
        let rooms = model.rooms(for: inspection)
        let done = rooms.filter { !model.findings(room: $0).isEmpty }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(inspection.kind.title) inspection")
                    .font(.headline)
                    .foregroundStyle(TPColor.textPrimary)
                Text("Started \(Self.date(inspection.startedAt))")
                    .font(.subheadline)
                    .foregroundStyle(TPColor.textSecondary)
                HStack(spacing: 8) {
                    ProgressView(value: Double(done), total: Double(max(rooms.count, 1)))
                        .progressViewStyle(.linear)
                        .tint(TPColor.tint)
                    Text("\(done) of \(rooms.count) rooms")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(TPColor.textSecondary)
                }
                .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func reportRow(_ report: SealedReport) -> some View {
        let kind = model.inspection(id: report.inspectionID)?.kind
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(TPColor.good)
                .font(.body)
            VStack(alignment: .leading, spacing: 3) {
                if let kind {
                    Text("\(kind.title) report")
                        .font(.headline)
                        .foregroundStyle(TPColor.textPrimary)
                } else {
                    Text("Sealed report")
                        .font(.headline)
                        .foregroundStyle(TPColor.textPrimary)
                }
                Text("Sealed \(Self.date(report.generatedAt))")
                    .font(.subheadline)
                    .foregroundStyle(TPColor.textSecondary)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func sealedReports(for inspections: [Inspection]) -> [SealedReport] {
        inspections.flatMap { model.reports(for: $0) }.sorted { $0.generatedAt > $1.generatedAt }
    }

    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
}
