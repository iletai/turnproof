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
                ContentUnavailableView("Room not found", systemImage: "camera")
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
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
        return VStack(spacing: 12) {
            topBar(room, count: findings.count)
            Spacer(minLength: 0)
            if !findings.isEmpty {
                recordedStrip(findings)
            }
            panel(inspection, room: room, findings: findings)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background {
            // Intentional full-bleed media: the latest photo sits under the controls like a camera preview.
            if let last = findings.last, let image = UIImage(data: last.photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityLabel("Latest photo in this room")
            }
        }
    }

    private func topBar(_ room: Room, count: Int) -> some View {
        HStack(alignment: .top) {
            Button {
                if isSheet { dismiss() } else { router.pop() }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .floatingControl(in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("nav.back")

            Spacer()
            VStack(spacing: 2) {
                Text(room.name).font(.title3.weight(.semibold))
                Text("Photo \(count + 1) of \(InspectionService.photoLimit)")
                    .font(.footnote)
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .floatingControl(in: Capsule())
            Spacer()

            PhotosPicker(selection: $libraryItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .floatingControl(in: Circle())
            .accessibilityLabel("Library")
            .accessibilityIdentifier("capture.library")
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private func recordedStrip(_ findings: [Finding]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    FindingThumbnail(finding: finding)
                        .frame(width: 72)
                        .overlay(alignment: .topLeading) {
                            Button {
                                model.deleteFinding(finding)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, TPColor.damage)
                                    .frame(width: 44, height: 44, alignment: .topLeading)
                            }
                            .accessibilityLabel("Delete photo \(index + 1)")
                            .accessibilityIdentifier("finding.delete.\(index + 1)")
                        }
                }
            }
            .padding(8)
        }
        .floatingControl(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func panel(_ inspection: Inspection, room: Room, findings: [Finding]) -> some View {
        VStack(spacing: 12) {
            conditionControl
            TextField("What the photo shows", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("capture.note")
            Toggle("Flag as damage", isOn: $flagged)
                .tint(TPColor.tint)
                .accessibilityHint("Damage needs a note before the report can be sealed.")
                .accessibilityIdentifier("capture.damageFlag")
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(TPColor.damage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("capture.error")
            }
            HStack {
                lastThumbnail(findings.last)
                Spacer()
                Button {
                    capturePhoto(inspection, room: room)
                } label: {
                    Circle()
                        .fill(.white)
                        .padding(6)
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .frame(width: 72, height: 72)
                }
                .disabled(isSaving || findings.count >= InspectionService.photoLimit)
                .accessibilityLabel("Take photo")
                .accessibilityIdentifier("capture.shutter")
                Spacer()
                Button("Done") {
                    if isSheet { dismiss() } else { router.pop() }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(minWidth: 72)
            }
        }
        .padding(16)
        .floatingControl(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Segmented look, but real buttons so each condition keeps its own identifier.
    private var conditionControl: some View {
        HStack(spacing: 2) {
            ForEach(Condition.allCases, id: \.self) { candidate in
                let selected = condition == candidate
                Button {
                    condition = candidate
                } label: {
                    Label(candidate.title, systemImage: candidate.symbol)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(selected ? Color.black : Color.white)
                        .background(selected ? Color.white : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture.condition.\(candidate.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private func lastThumbnail(_ finding: Finding?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let finding, let image = UIImage(data: finding.photoData)?.preparingThumbnail(of: CGSize(width: 132, height: 132)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.12)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.4), lineWidth: 1))
        .frame(minWidth: 72, alignment: .leading)
        .accessibilityHidden(true)
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
