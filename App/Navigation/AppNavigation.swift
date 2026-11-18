import BaseNavigationStack
import SwiftUI

/// Pushed screens.
enum AppRoute: Hashable, Sendable {
    case property(UUID)
    case rooms(UUID)
    case capture(inspection: UUID, room: UUID)
    case review(UUID)
    case sign(UUID)
    case export(UUID)
    case verify(UUID)
}

/// Sheets.
enum AppSheet: Identifiable, Hashable, Sendable {
    case addProperty
    case paywall
    case addFinding(inspection: UUID, room: UUID)

    var id: String {
        switch self {
        case .addProperty: "addProperty"
        case .paywall: "paywall"
        case .addFinding(let inspection, let room): "addFinding-\(inspection)-\(room)"
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
    @Environment(AppModel.self) private var model
    let route: AppRoute

    var body: some View {
        switch route {
        case .property(let id):
            PropertyDetailView(propertyID: id)
        case .rooms(let id):
            RoomChecklistView(inspectionID: id)
        case .capture(let inspection, let room):
            CaptureView(inspectionID: inspection, roomID: room)
        case .review(let id):
            ReviewView(inspectionID: id)
        case .sign(let id):
            SignView(inspectionID: id)
        case .export(let id):
            ExportView(inspectionID: id)
        case .verify(let id):
            VerifyView(inspectionID: id)
        }
    }
}

struct AppSheetView: View {
    @Environment(AppModel.self) private var model
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .addProperty:
            AddPropertySheet()
        case .paywall:
            PaywallScreen()
        case .addFinding(let inspection, let room):
            CaptureView(inspectionID: inspection, roomID: room, isSheet: true)
        }
    }
}
