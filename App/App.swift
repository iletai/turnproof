import SwiftUI

@main
struct TurnproofApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared
    @State private var hasSubscription = false
    @State private var hasLifetime = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.isPro, hasSubscription || hasLifetime)
                .subscriptionStatusTask(for: Store.groupID) { state in
                    guard case .success(let statuses) = state else { return }
                    hasSubscription = statuses.contains { $0.state == .subscribed || $0.state == .inGracePeriod }
                }
                .currentEntitlementTask(for: Store.lifetimeID) { state in
                    guard case .success(let result) = state else { return }
                    if case .verified(let transaction)? = result {
                        hasLifetime = transaction.revocationDate == nil
                    } else {
                        hasLifetime = false
                    }
                }
        }
    }
}
