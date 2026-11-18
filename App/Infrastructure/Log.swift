import Foundation
import os

/// One logger per area: `Log.app.info("...")`. Shows in Console.app filtered by the bundle id.
/// `nonisolated` + `Bundle.main` so actors and background queues can log (default isolation is MainActor).
enum Log {
    private nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? ""
    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let network = Logger(subsystem: subsystem, category: "network")
    nonisolated static let store = Logger(subsystem: subsystem, category: "store")
}
