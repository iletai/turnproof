import XCTest

extension XCUIApplication {
    /// The app's launch contract: fixture photos, a fixed clock, and an optional state reset.
    static func turnproof(resetState: Bool = true, clock: TimeInterval = 1_760_000_000) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "-UITestClock=\(clock)"]
        if resetState { app.launchArguments.append("-UITestResetState") }
        return app
    }
}
