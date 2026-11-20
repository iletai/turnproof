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
                ContentUnavailableView("Inspection not found", systemImage: "doc.questionmark")
            }
        }
        .background(TPColor.background)
    }

    private func content(_ inspection: Inspection, _ property: Property) -> some View {
        let rooms = model.rooms(for: inspection)
        let done = rooms.filter { !model.findings(room: $0).isEmpty }.count
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("\(done) of \(rooms.count) rooms").font(.headline).monospacedDigit()
                            Spacer()
                            photoCount(inspection)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(done) of \(rooms.count) rooms").font(.headline).monospacedDigit()
                            photoCount(inspection)
                        }
                    }
                    ProgressView(value: Double(done), total: Double(max(rooms.count, 1)))
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(rooms, id: \.id) { room in
                    roomRow(room, inspection: inspection)
                }
            } header: {
                Text("Rooms")
            } footer: {
                Text("Tap a room to take photos. Every room needs at least one photo.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(inspection.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.pop()
                } label: {
                    Label(property.label, systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("nav.back")
            }
        }
        .bottomActionBar {
            Button("Review & Sign") {
                router.push(.review(inspection.id))
            }
            .primaryActionStyle()
            .accessibilityIdentifier("review.next")
        }
    }

    private func photoCount(_ inspection: Inspection) -> some View {
        Text("\(model.findings(for: inspection).count) photos")
            .font(.subheadline)
            .foregroundStyle(TPColor.textSecondary)
            .monospacedDigit()
    }

    private func roomRow(_ room: Room, inspection: Inspection) -> some View {
        let findings = model.findings(room: room)
        let needsNote = findings.contains { $0.isDamageFlagged && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Button {
            router.push(.capture(inspection: inspection.id, room: room.id))
        } label: {
            HStack(spacing: 12) {
                statusGlyph(isEmpty: findings.isEmpty, needsNote: needsNote)
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .foregroundStyle(TPColor.textPrimary)
                    if needsNote {
                        Text("Damaged item needs a note")
                            .font(.footnote)
                            .foregroundStyle(TPColor.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Text(findings.isEmpty ? "No photos" : "\(findings.count) photos")
                    .font(.footnote)
                    .foregroundStyle(TPColor.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("room.\(room.templateKey)")
    }

    @ViewBuilder private func statusGlyph(isEmpty: Bool, needsNote: Bool) -> some View {
        Group {
            if needsNote {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TPColor.fair)
            } else if isEmpty {
                Image(systemName: "circle").foregroundStyle(TPColor.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(TPColor.good)
            }
        }
        .font(.title3)
        .accessibilityHidden(true)
    }
}
