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
                Text("No sealed report yet")
                    .font(TPType.body())
                    .foregroundStyle(TPColor.inkSecondary)
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ inspection: Inspection, _ report: SealedReport) -> some View {
        let matches = model.verify(report)
        return ScrollView {
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

                Eyebrow(text: "Integrity")
                Text("Verify packet")
                    .font(TPType.display())
                    .foregroundStyle(TPColor.ink)

                TPCard {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusChip(text: matches ? "matches" : "changed",
                                   color: matches ? TPColor.good : TPColor.damage,
                                   background: matches ? TPColor.goodSoft : TPColor.damageSoft)
                        Text(matches
                             ? "The records on this device still produce the sealed digest."
                             : "The records on this device no longer produce the sealed digest. The stored PDF is unchanged.")
                            .font(TPType.body(15))
                            .foregroundStyle(TPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("verify.result")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Stored digest")
                    Text(report.sha256)
                        .font(TPType.mono(12))
                        .foregroundStyle(TPColor.inkSecondary)
                        .textSelection(.enabled)
                }

                Text("Verification runs locally. Turnproof cannot prove the record to a third party on its own; the digest lets anyone compare the PDF against the original packet.")
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkTertiary)
            }
            .padding(.horizontal, TPSpacing.gutter)
            .padding(.bottom, 24)
        }
    }
}
