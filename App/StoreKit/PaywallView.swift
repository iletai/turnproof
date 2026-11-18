import StoreKit
import SwiftUI

/// Apple's paywall: subscriptions of the group + restore button, lifetime unlock underneath.
struct PaywallView: View {
    var body: some View {
        VStack(spacing: 0) {
            SubscriptionStoreView(groupID: Store.groupID)
                .storeButton(.visible, for: .restorePurchases)
            ProductView(id: Store.lifetimeID)
                .productViewStyle(.compact)
                .padding()
        }
    }
}

#Preview {
    PaywallView()
}
