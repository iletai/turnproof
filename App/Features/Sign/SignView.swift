import SwiftUI

struct SignView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.isPro) private var isPro

    let inspectionID: UUID

    @State private var tenantPNG: Data?
    @State private var landlordPNG: Data?
    @State private var errorText: String?
    @State private var isSealing = false
    @State private var showPaywall = false
    @State private var sealedReport: SealedReport?
    @State private var tenantCanvas = 0
    @State private var landlordCanvas = 0

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
        .sheet(isPresented: $showPaywall) {
            PaywallScreen {
                showPaywall = false
                if let sealedReport { model.unlock(sealedReport) }
                router.push(.export(inspectionID))
            }
        }
    }

    private func content(_ inspection: Inspection) -> some View {
        let sealed = inspection.status == .sealed
        let signed = model.signatures(for: inspection)
        return List {
            Section {
                Text(attestation(inspection))
            } header: {
                Text("What you are signing")
            } footer: {
                Text("This is a record of condition, not legal advice.")
            }

            if sealed {
                sealedNotice(inspection)
            } else {
                signatureSection(title: inspection.tenantName.isEmpty ? String(localized: "Tenant")
                                     : String(localized: "Tenant · \(inspection.tenantName)"),
                                 identifier: "sign.tenant", value: $tenantPNG, reset: $tenantCanvas,
                                 existing: signed.first { $0.role == .tenant })
                signatureSection(title: landlordTitle(inspection),
                                 identifier: "sign.landlord", value: $landlordPNG, reset: $landlordCanvas,
                                 existing: signed.first { $0.role == .landlord })

                if let errorText {
                    Section {
                        Label {
                            Text(errorText).accessibilityIdentifier("sign.error")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TPColor.damage)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sign")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.pop()
                } label: {
                    Label("Review", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("nav.back")
            }
        }
        .bottomActionBar {
            Button {
                if sealed {
                    router.push(.export(inspection.id))
                } else {
                    seal(inspection)
                }
            } label: {
                Label(sealed ? "View Sealed Report" : "Seal Report", systemImage: "checkmark.seal")
            }
            .primaryActionStyle()
            .disabled(isSealing || (!sealed && (tenantPNG == nil || landlordPNG == nil)))
            .accessibilityIdentifier("sign.seal")
        }
    }

    private func attestation(_ inspection: Inspection) -> String {
        let place = model.property(id: inspection.propertyID)?.label ?? ""
        let date = inspection.startedAt.formatted(date: .abbreviated, time: .omitted)
        let photos = model.findings(for: inspection).count
        let rooms = model.rooms(for: inspection).count
        return String(localized: "We walked through \(place) together on \(date) and reviewed \(photos) photos across \(rooms) rooms. This report records the condition we observed.")
    }

    private func landlordTitle(_ inspection: Inspection) -> String {
        guard let name = model.property(id: inspection.propertyID)?.landlordName, !name.isEmpty else {
            return String(localized: "Landlord")
        }
        return String(localized: "Landlord · \(name)")
    }

    private func sealedNotice(_ inspection: Inspection) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This report was sealed and cannot be edited.")
                    Text("Corrections create a new revision instead of changing this one.")
                        .font(.footnote)
                        .foregroundStyle(TPColor.textSecondary)
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(TPColor.good)
            }
            if let report = model.latestReport(for: inspection) {
                LabeledContent("Verification code") {
                    Text(model.integrity.shortCode(report.sha256)).monospaced()
                }
            }
        }
    }

    private func signatureSection(title: String, identifier: String,
                                  value: Binding<Data?>, reset: Binding<Int>,
                                  existing: Signature?) -> some View {
        Section {
            SignatureCanvas { data in value.wrappedValue = data }
                .id(reset.wrappedValue)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("\(title) signature")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Clear") {
                    reset.wrappedValue += 1
                    value.wrappedValue = nil
                }
                .font(.footnote)
                .textCase(nil)
                .disabled(value.wrappedValue == nil && existing == nil)
                .accessibilityIdentifier("\(identifier).clear")
            }
        } footer: {
            if let existing {
                Text("Signed \(existing.signedAt.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    private func seal(_ inspection: Inspection) {
        guard let tenantPNG, let landlordPNG else {
            errorText = String(localized: "Both signatures are required.")
            return
        }
        isSealing = true
        defer { isSealing = false }
        model.sign(inspection: inspection, role: .tenant, png: tenantPNG)
        model.sign(inspection: inspection, role: .landlord, png: landlordPNG)
        do {
            let artifact = try model.sealAndRender(inspection: inspection)
            sealedReport = artifact.report
        } catch InspectionError.blocked {
            errorText = String(localized: "Some checks are still open. Go back to Review.")
            return
        } catch InspectionError.photoLimit {
            errorText = String(localized: "Too many photos for one report.")
            return
        } catch InspectionError.emptyNote {
            errorText = String(localized: "A damage flag is missing its note.")
            return
        } catch {
            errorText = String(localized: "The report could not be sealed.")
            return
        }
        errorText = nil
        if ExportGate.allowsExport(isPro: isPro, counter: model.counter) {
            ExportGate.recordExport(counter: model.counter, isPro: isPro)
            if let sealedReport { model.unlock(sealedReport) }
            router.push(.export(inspection.id))
        } else {
            showPaywall = true
        }
    }
}
