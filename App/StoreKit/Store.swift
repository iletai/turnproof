import StoreKit
import SwiftUI

/// Native StoreKit 2 only (no wrapper). Product ids are "<bundle id of this environment>.pro.*",
/// so Dev/Staging/Prod ASC records never share ids; the subscription group id comes from the xcconfig.
enum Store {
    static let groupID = AppConfiguration.string("SUBSCRIPTION_GROUP_ID") ?? ""
    static let lifetimeID = "\(AppConfiguration.bundleIdentifier).pro.lifetime"

    /// For gates outside SwiftUI (widgets, background work). Views read `\.isPro` instead.
    static func hasPro() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == lifetimeID || transaction.subscriptionGroupID == groupID { return true }
        }
        return false
    }
}

extension EnvironmentValues {
    @Entry var isPro = false
}
