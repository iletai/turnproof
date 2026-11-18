import SwiftUI

/// Presented at the seal → export transition only. Entry and capture stay free and offline.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPro) private var isPro

    var onUnlocked: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PaywallView()
                if !isPro {
                    Text("One report is free. A subscription covers every unit and every inspection.")
                        .font(TPType.small())
                        .foregroundStyle(TPColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TPSpacing.gutter)
                        .padding(.bottom, 8)
                }
                Button(isPro ? "Continue" : "Not now") {
                    dismiss()
                    if isPro { onUnlocked?() }
                }
                .font(TPType.small())
                .foregroundStyle(TPColor.inkSecondary)
                .padding(.bottom, 12)
                .accessibilityIdentifier("paywall.dismiss")
            }
            .background(TPColor.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Eyebrow(text: "Turnproof Pro")
                }
            }
        }
        .onChange(of: isPro) { _, pro in
            if pro {
                dismiss()
                onUnlocked?()
            }
        }
    }
}
