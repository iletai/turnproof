import StoreKit
import SwiftUI

/// Apple's paywall: subscriptions of the group + restore button, lifetime unlock underneath.
struct PaywallView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Compact picker: the default list is squeezed under the lifetime row and hides the monthly plan.
            SubscriptionStoreView(groupID: Store.groupID)
                .subscriptionStoreControlStyle(.compactPicker)
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
