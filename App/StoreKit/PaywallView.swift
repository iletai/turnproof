import StoreKit
import SwiftUI

/// Apple's paywall: subscriptions of the group + restore button, lifetime unlock underneath.
struct PaywallView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Compact picker: the default list is squeezed under the lifetime row and hides the monthly plan.
            SubscriptionStoreView(groupID: Store.groupID) {
                marketing
            }
            .subscriptionStoreControlStyle(.compactPicker)
            .storeButton(.visible, for: .restorePurchases)
            // PaywallScreen owns the close button (and its onUnlocked hand-off).
            .storeButton(.hidden, for: .cancellation)
            .subscriptionStorePolicyDestination(url: Self.termsURL, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: Self.privacyURL, for: .privacyPolicy)
            ProductView(id: Store.lifetimeID)
                .productViewStyle(.compact)
                .padding()
        }
        .tint(TPColor.tint)
    }

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://apps-site-six.vercel.app/apps/turnproof/privacy")!

    private var marketing: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(TPColor.tint)
                .accessibilityHidden(true)
            Text("Unlimited condition reports")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Your first report was free. Subscribe to seal and share every inspection.")
                .font(.callout)
                .foregroundStyle(TPColor.textSecondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                benefit("Seal and share unlimited reports", symbol: "doc.badge.plus")
                benefit("Move-in, move-out and periodic inspections", symbol: "arrow.left.arrow.right")
                benefit("Everything stays on this iPhone", symbol: "iphone")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func benefit(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(TPColor.tint)
        }
    }
}

#Preview {
    PaywallView()
}
