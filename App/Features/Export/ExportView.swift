import PDFKit
import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.isPro) private var isPro
    let inspectionID: UUID

    @State private var artifact: ExportArtifact?
    @State private var shareURL: URL?
    @State private var copied = false
    @State private var showPaywall = false
    @State private var preview: UIImage?

    var body: some View {
        _ = model.revision
        return Group {
            if let inspection = model.inspection(id: inspectionID),
               let report = model.latestReport(for: inspection) {
                content(inspection, report)
            } else {
                ContentUnavailableView("No sealed report yet", systemImage: "doc")
            }
        }
        .background(TPColor.background)
        .task {
            guard let inspection = model.inspection(id: inspectionID),
                  let report = model.latestReport(for: inspection) else { return }
            let built = model.exportArtifact(for: report)
            artifact = built
            shareURL = built.fileURL
            preview = PDFDocument(data: built.pdfData)?.page(at: 0)?.thumbnail(of: CGSize(width: 240, height: 320), for: .mediaBox)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallScreen {
                showPaywall = false
                if let report = currentReport { model.unlock(report) }
            }
        }
    }

    private var currentReport: SealedReport? {
        guard let inspection = model.inspection(id: inspectionID) else { return nil }
        return model.latestReport(for: inspection)
    }

    private func content(_ inspection: Inspection, _ report: SealedReport) -> some View {
        let shortCode = model.integrity.shortCode(report.sha256)
        let unlocked = isPro || model.isUnlocked(report)
        let property = model.property(id: inspection.propertyID)
        return List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(TPColor.tint)
                        .accessibilityHidden(true)
                    Text("Report sealed")
                        .font(.title2.bold())
                    Text("\(inspection.kind.title) · \(property?.label ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(TPColor.textSecondary)
                    Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(TPColor.textSecondary)
                    pagePreview
                        .padding(.top, 8)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Pages") { Text("\(report.pageCount)").monospacedDigit() }
                LabeledContent("Photos") {
                    Text("\(model.findings(for: inspection).count) in \(model.rooms(for: inspection).count) rooms")
                        .monospacedDigit()
                }
                LabeledContent("Signed by", value: signers(inspection, property))
                if let artifact {
                    LabeledContent("File size", value: artifact.sizeDescription)
                }
            }

            if !unlocked {
                Section {
                    Label {
                        Text("Read-only until this report is unlocked. The packet is already sealed; verifying it stays free.")
                            .accessibilityIdentifier("export.locked")
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(TPColor.textSecondary)
                    }
                }
            }

            if let artifact, artifact.pdfData.count > 20_000_000 {
                Section {
                    Label {
                        Text("This packet is over 20 MB. Mail providers may reject it; AirDrop or Files works.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TPColor.fair)
                    }
                }
            }

            Section {
                HStack {
                    Text(shortCode)
                        .font(.body.monospaced().weight(.medium))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("export.shortCode")
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = shortCode
                        copied = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("export.copyHash")
                }
                Button {
                    router.push(.verify(inspection.id))
                } label: {
                    HStack {
                        Text("Verify Report").foregroundStyle(TPColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("export.verify")
            } header: {
                Text("Verification code")
            } footer: {
                Text("Verify rechecks this report against the records stored on this iPhone.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    router.popToRoot()
                }
                .accessibilityIdentifier("export.done")
            }
        }
        .bottomActionBar {
            if let shareURL, unlocked {
                ShareLink(item: shareURL) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .primaryActionStyle()
                .accessibilityIdentifier("export.share")
            } else if !unlocked {
                Button("Unlock Sharing") {
                    showPaywall = true
                }
                .primaryActionStyle()
                .accessibilityIdentifier("export.unlock")
            }
        }
    }

    private var pagePreview: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Group {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit()
            } else {
                TPColor.plainBackground
            }
        }
        .frame(width: 120, height: 160)
        .background(TPColor.plainBackground)
        .clipShape(shape)
        .overlay(shape.stroke(TPColor.separator, lineWidth: 1))
        .accessibilityLabel("First page of the report")
    }

    private func signers(_ inspection: Inspection, _ property: Property?) -> String {
        [inspection.tenantName, property?.landlordName ?? ""]
            .filter { !$0.isEmpty }
            .formatted(.list(type: .and))
    }
}
