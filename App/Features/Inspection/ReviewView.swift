import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let inspectionID: UUID

    var body: some View {
        _ = model.revision
        return Group {
            if let inspection = model.inspection(id: inspectionID) {
                content(inspection)
            } else {
                ContentUnavailableView("Inspection not found", systemImage: "doc.questionmark")
            }
        }
        .background(TPColor.background)
    }

    private func content(_ inspection: Inspection) -> some View {
        let rooms = model.rooms(for: inspection)
        let issues = model.validation(for: inspection)
        // Missing signatures are collected on the next screen, so they never block the way there.
        let blocking = issues.filter { if case .missingSignature = $0 { false } else { true } }
        return List {
            if !issues.isEmpty {
                Section("Needs attention") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                        Label {
                            Text(issue.message)
                                .accessibilityIdentifier("review.issue.\(index + 1)")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TPColor.fair)
                        }
                    }
                }
            }
            ForEach(rooms, id: \.id) { room in
                roomSection(room)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.pop()
                } label: {
                    Label(inspection.kind.title, systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("nav.back")
            }
        }
        .bottomActionBar {
            VStack(spacing: 8) {
                if !blocking.isEmpty {
                    Text("Resolve \(blocking.count) issues to continue.")
                        .font(.footnote)
                        .foregroundStyle(TPColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button("Continue to Sign") {
                    router.push(.sign(inspection.id))
                }
                .primaryActionStyle()
                .disabled(!blocking.isEmpty)
                .accessibilityIdentifier("review.next")
            }
        }
    }

    private func roomSection(_ room: Room) -> some View {
        let findings = model.findings(room: room)
        return Section("\(room.name) · \(findings.count) photos") {
            if findings.isEmpty {
                Text("No photos")
                    .foregroundStyle(TPColor.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(findings, id: \.id) { finding in
                        FindingThumbnail(finding: finding)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

/// Square photo with its condition glyph and label underneath, never on top of the photo.
struct FindingThumbnail: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // shortcut: decodes the stored photo per cell; add a thumbnail cache if rooms grow past ~20 photos.
                    if let image = UIImage(data: finding.photoData)?.preparingThumbnail(of: CGSize(width: 240, height: 240)) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(TPColor.separator, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if finding.isDamageFlagged {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.title3)
                            .foregroundStyle(TPColor.damage)
                            .background(Circle().fill(TPColor.surface).padding(-2))
                            .padding(4)
                    }
                }
            Label(finding.condition.title, systemImage: finding.condition.symbol)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(TPColor.textSecondary)
                .labelStyle(ConditionLabelStyle(color: TPColor.tint(for: finding.condition)))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConditionLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
