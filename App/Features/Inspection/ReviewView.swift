import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let inspectionID: UUID

    var body: some View {
        _ = model.revision
        return Group {
            if let inspection = model.inspection(id: inspectionID),
               let property = model.property(id: inspection.propertyID) {
                content(inspection, property)
            } else {
                Text("Inspection not found")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ inspection: Inspection, _ property: Property) -> some View {
        let rooms = model.rooms(for: inspection)
        let issues = model.validation(for: inspection)
        // Missing signatures are collected on the next screen, so they never block the way there.
        let blocking = issues.filter { if case .missingSignature = $0 { false } else { true } }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        router.pop()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(TPColor.ink)
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("nav.back")

                    Eyebrow(text: property.label)
                    Text("Review before signing")
                        .font(TPType.display())
                        .foregroundStyle(TPColor.ink)
                    Text("\(model.findings(for: inspection).count) photos across \(rooms.count) rooms. Everything below is hashed into the sealed packet.")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)

                    issueSection(issues)
                    roomSection(rooms)
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            BottomBar {
                Button(blocking.isEmpty ? "Sign both parties" : "Resolve \(blocking.count) issue\(blocking.count == 1 ? "" : "s")") {
                    router.push(.sign(inspection.id))
                }
                .buttonStyle(TPPrimaryButtonStyle())
                .disabled(!blocking.isEmpty)
                .accessibilityIdentifier("review.next")
            }
        }
    }

    private func issueSection(_ issues: [ValidationIssue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack {
                Text("Checks").font(TPType.heading(17))
                Spacer()
                StatusChip(text: issues.isEmpty ? "ready" : "\(issues.count) open",
                           color: issues.isEmpty ? TPColor.good : TPColor.warning,
                           background: issues.isEmpty ? TPColor.goodSoft : TPColor.warningSoft)
            }
            .padding(.vertical, 12)

            if issues.isEmpty {
                Text("Every room has a photo, every damage flag has a note, and both signatures are recorded after you sign.")
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkSecondary)
                    .padding(.bottom, 12)
            } else {
                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(TPType.mono())
                            .foregroundStyle(TPColor.warning)
                        Text(issue.message)
                            .font(TPType.body(15))
                            .foregroundStyle(TPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("review.issue.\(index + 1)")
                    Hairline()
                }
            }
        }
    }

    private func roomSection(_ rooms: [Room]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Rooms")
            ForEach(rooms, id: \.id) { room in
                let findings = model.findings(room: room)
                HStack {
                    Text(room.name).font(TPType.body(15)).foregroundStyle(TPColor.ink)
                    Spacer()
                    Text("\(findings.count) photos")
                        .font(TPType.mono())
                        .foregroundStyle(findings.isEmpty ? TPColor.warning : TPColor.inkSecondary)
                }
                .padding(.vertical, 8)
                Hairline()
            }
        }
    }
}
