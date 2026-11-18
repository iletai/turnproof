import SwiftUI

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
                Text("Unit not found").foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ property: Property) -> some View {
        let inspections = model.inspections(for: property)
        let active = inspections.first(where: { $0.status == .draft })
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        router.pop()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TPColor.ink)
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("nav.back")

                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: property.addressLine)
                        Text(property.unit.isEmpty ? property.label : property.unit)
                            .font(TPType.display())
                            .foregroundStyle(TPColor.ink)
                        Text("Landlord: \(property.landlordName)")
                            .font(TPType.small())
                            .foregroundStyle(TPColor.inkSecondary)
                    }

                    if let active {
                        activeCard(active)
                    }

                    Hairline()
                    HStack {
                        Text("History").font(TPType.heading())
                        Spacer()
                        Text("\(sealedReports(for: inspections).count) SEALED")
                            .font(TPType.eyebrow()).foregroundStyle(TPColor.inkTertiary)
                    }
                    if sealedReports(for: inspections).isEmpty {
                        Text("No sealed reports yet.")
                            .font(TPType.small())
                            .foregroundStyle(TPColor.inkTertiary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sealedReports(for: inspections), id: \.id) { report in
                                historyRow(report)
                                Hairline()
                            }
                        }
                    }
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            BottomBar {
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
                    .buttonStyle(TPPrimaryButtonStyle())
                    .accessibilityIdentifier("inspection.new")
                }
            }
        }
    }

    private func activeCard(_ inspection: Inspection) -> some View {
        let rooms = model.rooms(for: inspection)
        let done = rooms.filter { !model.findings(room: $0).isEmpty }.count
        return TPCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "In progress")
                    Spacer()
                    Text("\(done) of \(rooms.count) rooms")
                        .font(TPType.mono())
                        .foregroundStyle(TPColor.inkSecondary)
                }
                Text("\(inspection.kind.title) inspection")
                    .font(TPType.heading())
                    .foregroundStyle(TPColor.ink)
                Text("Started \(Self.date(inspection.startedAt))")
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkSecondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(TPColor.hairline)
                        Rectangle().fill(TPColor.ink)
                            .frame(width: rooms.isEmpty ? 0 : proxy.size.width * CGFloat(done) / CGFloat(rooms.count))
                    }
                }
                .frame(height: 4)
                Button {
                    router.push(.rooms(inspection.id))
                } label: {
                    Text("Continue inspection")
                }
                .buttonStyle(TPSecondaryButtonStyle())
                .accessibilityIdentifier("inspection.continue")
            }
        }
    }

    private func sealedReports(for inspections: [Inspection]) -> [SealedReport] {
        inspections.flatMap { model.reports(for: $0) }.sorted { $0.generatedAt > $1.generatedAt }
    }

    private func historyRow(_ report: SealedReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(TPColor.inkSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sealed report").font(TPType.bodyStrong()).foregroundStyle(TPColor.ink)
                Text(Self.date(report.generatedAt))
                    .font(TPType.small()).foregroundStyle(TPColor.inkSecondary)
                HStack(spacing: 8) {
                    StatusChip(text: "rev \(report.revision)", color: TPColor.inkSecondary, background: TPColor.paper)
                    Text(report.sha256.uppercased().prefix(12))
                        .font(TPType.mono())
                        .foregroundStyle(TPColor.inkTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
