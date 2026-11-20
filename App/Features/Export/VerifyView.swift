import SwiftUI

struct VerifyView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let inspectionID: UUID

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
    }

    private func content(_ inspection: Inspection, _ report: SealedReport) -> some View {
        let matches = model.verify(report)
        return List {
            Section {
                Label {
                    Text(matches
                         ? "The records on this device still produce the sealed digest."
                         : "The records on this device no longer produce the sealed digest. The stored PDF is unchanged.")
                        .accessibilityIdentifier("verify.result")
                } icon: {
                    Image(systemName: matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(matches ? TPColor.good : TPColor.damage)
                }
                LabeledContent("Verification code") {
                    Text(model.integrity.shortCode(report.sha256)).monospaced()
                }
            } footer: {
                Text("Verification runs locally. Turnproof cannot prove the record to a third party on its own; the code lets anyone compare the PDF against the original packet.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Verify Report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.pop()
                } label: {
                    Label("Report", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("nav.back")
            }
        }
    }
}
