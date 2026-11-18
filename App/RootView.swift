import BaseNavigationStack
import SwiftUI

/// One router per navigation stack; screens read it with `@Environment(AppRouter.self)`.
struct RootView: View {
    @State private var router = AppRouter()

    var body: some View {
        BaseNavigationContainer(
            router: router,
            content: { ContentView() },
            destination: { AppRouteView(route: $0) },
            sheet: { AppSheetView(sheet: $0) },
            cover: { _ in EmptyView() }
        )
    }
}
