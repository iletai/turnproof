import BaseNavigationStack
import SwiftUI

/// Pushed screens. Recipes (tabs, deep links): skill `iletai-libs` references/navigation.md.
enum AppRoute: Hashable, Sendable {
    case settings
}

/// Sheets. Hash by `id` if a payload is not Hashable.
enum AppSheet: Identifiable, Hashable, Sendable {
    case paywall
    var id: String {
        switch self {
        case .paywall: "paywall"
        }
    }
}

/// Full-screen covers; keep the placeholder until the app needs one.
enum AppCover: Identifiable, Hashable, Sendable {
    case unused
    var id: String { "unused" }
}

typealias AppRouter = NavigationRouter<AppRoute, AppSheet, AppCover>

struct AppRouteView: View {
    let route: AppRoute
    var body: some View {
        switch route {
        case .settings: Text("Settings")
        }
    }
}

struct AppSheetView: View {
    let sheet: AppSheet
    var body: some View {
        switch sheet {
        case .paywall: Text("Paywall")
        }
    }
}
