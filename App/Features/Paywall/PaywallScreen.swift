import SwiftUI

/// Presented at the seal → export transition only. Entry and capture stay free and offline.
struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPro) private var isPro

    var onUnlocked: (() -> Void)?

    var body: some View {
        NavigationStack {
            PaywallView()
                .background(TPColor.background)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                            if isPro { onUnlocked?() }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(isPro ? "Continue" : "Not now")
                        .accessibilityIdentifier("paywall.dismiss")
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
