import SwiftUI

struct RoomChecklistView: View {
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
        let done = rooms.filter { !model.findings(room: $0).isEmpty }.count
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                    Text("\(inspection.kind.title) inspection")
                        .font(TPType.display())
                        .foregroundStyle(TPColor.ink)
                    Text("\(done) of \(rooms.count) rooms recorded · \(model.findings(for: inspection).count) photos")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)
                        .padding(.top, 4)

                    progress(done: done, total: rooms.count)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(rooms, id: \.id) { room in
                        roomRow(room, inspection: inspection)
                        Hairline()
                    }
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            BottomBar {
                Button("Review & sign") {
                    router.push(.review(inspection.id))
                }
                .buttonStyle(TPPrimaryButtonStyle())
                .accessibilityIdentifier("review.next")
            }
        }
    }

    private func progress(done: Int, total: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(TPColor.hairline)
                Rectangle().fill(TPColor.ink)
                    .frame(width: total == 0 ? 0 : proxy.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 4)
    }

    private func roomRow(_ room: Room, inspection: Inspection) -> some View {
        let findings = model.findings(room: room)
        let damaged = findings.filter { $0.isDamageFlagged }.count
        return Button {
            router.push(.capture(inspection: inspection.id, room: room.id))
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", room.order + 1))
                    .font(TPType.mono())
                    .foregroundStyle(TPColor.inkTertiary)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(TPType.heading(17))
                        .foregroundStyle(TPColor.ink)
                    Text(findings.isEmpty ? "No photos yet" : "\(findings.count) photos")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)
                }
                Spacer()
                if damaged > 0 {
                    StatusChip(text: "\(damaged) damage", color: TPColor.damage, background: TPColor.damageSoft)
                } else if !findings.isEmpty {
                    StatusChip(text: "Recorded", color: TPColor.good, background: TPColor.goodSoft)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(TPColor.inkTertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room.\(room.templateKey)")
    }
}
