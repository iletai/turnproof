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
                Text("Inspection not found")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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

                    Eyebrow(text: "On this device")
                    Text("Both parties sign")
                        .font(TPType.display())
                        .foregroundStyle(TPColor.ink)
                    Text("Sign with a finger inside each box. The signatures are drawn at \(inspection.kind.title.lowercased()) and hashed into the packet.")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)

                    if sealed {
                        sealedNotice(inspection)
                    } else {
                        signatureBlock(title: "Tenant", identifier: "sign.tenant",
                                       role: .tenant, value: $tenantPNG, reset: $tenantCanvas,
                                       existing: signed.first { $0.role == .tenant })
                        signatureBlock(title: "Landlord", identifier: "sign.landlord",
                                       role: .landlord, value: $landlordPNG, reset: $landlordCanvas,
                                       existing: signed.first { $0.role == .landlord })

                        if let errorText {
                            Text(errorText)
                                .font(TPType.small())
                                .foregroundStyle(TPColor.damage)
                                .accessibilityIdentifier("sign.error")
                        }
                    }
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            BottomBar {
                Button(sealed ? "View sealed report" : "Seal report") {
                    if sealed {
                        router.push(.export(inspection.id))
                    } else {
                        seal(inspection)
                    }
                }
                .buttonStyle(TPPrimaryButtonStyle())
                .disabled(isSealing || (!sealed && (tenantPNG == nil || landlordPNG == nil)))
                .accessibilityIdentifier("sign.seal")
            }
        }
    }

    private func sealedNotice(_ inspection: Inspection) -> some View {
        TPCard {
            VStack(alignment: .leading, spacing: 8) {
                StatusChip(text: "sealed", color: TPColor.good, background: TPColor.goodSoft)
                Text("This report was sealed and cannot be edited.")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.ink)
                if let report = model.latestReport(for: inspection) {
                    Text(model.integrity.shortCode(report.sha256))
                        .font(TPType.mono(13))
                        .foregroundStyle(TPColor.inkSecondary)
                }
                Text("Corrections create a new revision instead of changing this one.")
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
    }

    private func signatureBlock(title: String, identifier: String, role: SignatureRole,
                                value: Binding<Data?>, reset: Binding<Int>,
                                existing: Signature?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: title)
                Spacer()
                if existing != nil {
                    StatusChip(text: "signed", color: TPColor.good, background: TPColor.goodSoft)
                } else if value.wrappedValue != nil {
                    Text("Drawn").font(TPType.eyebrow()).foregroundStyle(TPColor.inkSecondary)
                }
            }
            SignatureCanvas { data in value.wrappedValue = data }
                .id(reset.wrappedValue)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("\(title) signature")
            HStack {
                Button("Clear") {
                    reset.wrappedValue += 1
                    value.wrappedValue = nil
                }
                .font(TPType.small())
                .foregroundStyle(TPColor.inkSecondary)
                .disabled(value.wrappedValue == nil && existing == nil)
                .accessibilityIdentifier("\(identifier).clear")
                Spacer()
                Text(role == .tenant ? "Tenant signs first" : "Landlord countersigns")
                    .font(TPType.caption())
                    .foregroundStyle(TPColor.inkTertiary)
            }
        }
        .padding(.bottom, 8)
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
