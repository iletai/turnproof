import PhotosUI
import SwiftUI

struct CaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let inspectionID: UUID
    let roomID: UUID
    var isSheet = false

    @State private var condition: Condition = .good
    @State private var note = ""
    @State private var flagged = false
    @State private var errorText: String?
    @State private var isCameraPresented = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isSaving = false

    var body: some View {
        _ = model.revision
        return Group {
            if let inspection = model.inspection(id: inspectionID),
               let room = model.room(id: roomID) {
                content(inspection, room)
            } else {
                Text("Room not found")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { data in save(data, inspection: model.inspection(id: inspectionID),
                                        room: model.room(id: roomID)) }
                .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    errorText = String(localized: "That photo could not be read.")
                    return
                }
                save(data, inspection: model.inspection(id: inspectionID), room: model.room(id: roomID))
                libraryItem = nil
            }
        }
    }

    private func content(_ inspection: Inspection, _ room: Room) -> some View {
        let findings = model.findings(room: room)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(room, findings: findings)
                    if let last = findings.last, let image = UIImage(data: last.photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .overlay(Rectangle().stroke(TPColor.hairline, lineWidth: 1))
                            .accessibilityLabel("Latest photo in this room")
                    }
                    conditionControl
                    noteField
                    damageToggle
                    if let errorText {
                        Text(errorText)
                            .font(TPType.small())
                            .foregroundStyle(TPColor.damage)
                            .accessibilityIdentifier("capture.error")
                    }
                    if !findings.isEmpty {
                        Hairline()
                        Eyebrow(text: "Recorded in this room")
                        ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                            findingRow(finding, index: index)
                            Hairline()
                        }
                    }
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            bottomBar(inspection, room: room, count: findings.count)
        }
    }

    private func header(_ room: Room, findings: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if isSheet { dismiss() } else { router.pop() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(TPColor.ink)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityIdentifier("nav.back")

            Eyebrow(text: "Room \(room.order + 1) of \(RoomTemplate.keys.count)")
            Text(room.name)
                .font(TPType.display())
                .foregroundStyle(TPColor.ink)
            Text("\(findings.count) of \(InspectionService.photoLimit) photos · one photo per finding")
                .font(TPType.small())
                .foregroundStyle(TPColor.inkSecondary)
        }
    }

    private var conditionControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Condition")
            HStack(spacing: 8) {
                ForEach(Condition.allCases, id: \.self) { candidate in
                    Button {
                        condition = candidate
                    } label: {
                        ConditionChip(condition: candidate, isSelected: condition == candidate)
                            .overlay(Rectangle().stroke(condition == candidate
                                                        ? TPColor.tint(for: candidate)
                                                        : TPColor.hairline,
                                                        lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Note")
            TextField("What the photo shows", text: $note, axis: .vertical)
                .font(TPType.body())
                .lineLimit(3, reservesSpace: true)
                .padding(12)
                .background(TPColor.paperRaised)
                .overlay(Rectangle().stroke(TPColor.hairline, lineWidth: 1))
                .accessibilityIdentifier("capture.note")
        }
    }

    private var damageToggle: some View {
        Toggle(isOn: $flagged) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Flag as damage")
                    .font(TPType.bodyStrong())
                    .foregroundStyle(TPColor.ink)
                Text("Damage needs a note before the report can be sealed.")
                    .font(TPType.caption())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .tint(TPColor.damage)
        .accessibilityIdentifier("capture.damageFlag")
    }

    private func findingRow(_ finding: Finding, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(TPType.mono())
                .foregroundStyle(TPColor.inkTertiary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusChip(text: finding.condition.rawValue,
                               color: TPColor.tint(for: finding.condition),
                               background: TPColor.soft(for: finding.condition))
                    if finding.isDamageFlagged {
                        StatusChip(text: "damage", color: TPColor.damage, background: TPColor.damageSoft)
                    }
                }
                Text(finding.note.isEmpty ? "No note" : finding.note)
                    .font(TPType.small())
                    .foregroundStyle(finding.note.isEmpty ? TPColor.inkTertiary : TPColor.inkSecondary)
            }
            Spacer()
            Button {
                model.deleteFinding(finding)
            } label: {
                Image(systemName: "trash")
                    .font(.system(.subheadline))
                    .foregroundStyle(TPColor.inkTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("finding.delete.\(index + 1)")
        }
        .padding(.vertical, 8)
    }

    private func bottomBar(_ inspection: Inspection, room: Room, count: Int) -> some View {
        BottomBar {
            HStack(spacing: 8) {
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(TPType.bodyStrong())
                        .foregroundStyle(TPColor.ink)
                        .frame(minWidth: 112, minHeight: 52)
                        .overlay(Rectangle().stroke(TPColor.ink, lineWidth: 1))
                }
                .accessibilityIdentifier("capture.library")

                Button {
                    capturePhoto(inspection, room: room)
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
                .buttonStyle(TPPrimaryButtonStyle())
                .disabled(isSaving || count >= InspectionService.photoLimit)
                .accessibilityIdentifier("capture.shutter")
            }
        }
    }

    private func capturePhoto(_ inspection: Inspection, room: Room) {
        if model.usesFixturePhotos {
            isSaving = true
            Task {
                let data = try? await model.photoSource.capturePhoto()
                isSaving = false
                if let data { save(data, inspection: inspection, room: room) }
            }
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            isCameraPresented = true
        } else {
            errorText = String(localized: "This device has no camera. Use Library instead.")
        }
    }

    private func save(_ raw: Data, inspection: Inspection?, room: Room?) {
        guard let inspection, let room else { return }
        do {
            try model.capture(room: room, inspection: inspection, rawPhoto: raw,
                              condition: condition, note: note, flagged: flagged)
            note = ""
            flagged = false
            condition = .good
            errorText = nil
            if isSheet { dismiss() }
        } catch PhotoIngestError.undecodable {
            errorText = String(localized: "That photo could not be read.")
        } catch PhotoIngestError.tooLargeAfterDownscale {
            errorText = String(localized: "That photo is too large to store.")
        } catch InspectionError.sealed {
            errorText = String(localized: "This report is already sealed.")
        } catch {
            errorText = String(localized: "The photo was not saved.")
        }
    }
}
