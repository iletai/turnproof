import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let inspectionID: UUID

    @State private var artifact: ExportArtifact?
    @State private var shareURL: URL?
    @State private var copied = false
    @State private var showPaywall = false

    var body: some View {
        _ = model.revision
        return Group {
            if let inspection = model.inspection(id: inspectionID),
               let report = model.latestReport(for: inspection) {
                content(inspection, report)
            } else {
                Text("No sealed report yet")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard let inspection = model.inspection(id: inspectionID),
                  let report = model.latestReport(for: inspection) else { return }
            let built = model.exportArtifact(for: report)
            artifact = built
            shareURL = built.fileURL
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
        let digest = report.sha256
        let shortCode = model.integrity.shortCode(digest)
        let unlocked = model.isUnlocked(report)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "Sealed")
                    Text("Report ready")
                        .font(TPType.display())
                        .foregroundStyle(TPColor.ink)
                    Text("The PDF is stored on this device and never uploaded. Share it with the tenant or keep it with your lease.")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)

                    TPCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Eyebrow(text: "Packet")
                                Spacer()
                                StatusChip(text: "rev \(report.revision)",
                                           color: TPColor.inkSecondary, background: TPColor.paper)
                            }
                            Text(shortCode)
                                .font(TPType.mono(20))
                                .foregroundStyle(TPColor.ink)
                                .accessibilityIdentifier("export.shortCode")
                            HStack(spacing: 16) {
                                Text("\(report.pageCount) pages").font(TPType.mono(12))
                                Text(artifact?.sizeDescription ?? "—").font(TPType.mono(12))
                                Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(TPType.mono(12))
                            }
                            .foregroundStyle(TPColor.inkSecondary)
                        }
                    }

                    if !unlocked {
                        Text("Read-only until this report is unlocked. The packet is already sealed; verifying it stays free.")
                            .font(TPType.small())
                            .foregroundStyle(TPColor.warning)
                            .accessibilityIdentifier("export.locked")
                    }

                    if let artifact, artifact.pdfData.count > 20_000_000 {
                        Text("This packet is over 20 MB. Mail providers may reject it; AirDrop or Files works.")
                            .font(TPType.small())
                            .foregroundStyle(TPColor.warning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "SHA-256")
                        Text(digest)
                            .font(TPType.mono(12))
                            .foregroundStyle(TPColor.inkSecondary)
                            .textSelection(.enabled)
                    }

                    Button {
                        UIPasteboard.general.string = digest
                        copied = true
                    } label: {
                        Text(copied ? "Digest copied" : "Copy digest")
                    }
                    .buttonStyle(TPSecondaryButtonStyle())
                    .accessibilityIdentifier("export.copyHash")

                    Button("Verify this report") {
                        router.push(.verify(inspection.id))
                    }
                    .buttonStyle(TPSecondaryButtonStyle())
                    .accessibilityIdentifier("export.verify")
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.bottom, 24)
            }
            BottomBar {
                VStack(spacing: 8) {
                    if let shareURL, unlocked {
                        ShareLink(item: shareURL) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                                .font(TPType.bodyStrong())
                                .foregroundStyle(TPColor.paperRaised)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(TPColor.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .accessibilityIdentifier("export.share")
                    } else if !unlocked {
                        Button("Unlock sharing") {
                            showPaywall = true
                        }
                        .buttonStyle(TPPrimaryButtonStyle())
                        .accessibilityIdentifier("export.unlock")
                    }
                    Button("Done") {
                        router.popToRoot()
                    }
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkSecondary)
                    .accessibilityIdentifier("export.done")
                }
            }
        }
    }
}
