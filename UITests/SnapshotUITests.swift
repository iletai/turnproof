import XCTest

/// App Store screenshots (`bundle exec fastlane screenshots`); devices/languages in fastlane/Snapfile.
/// Not MainActor: default isolation would change the XCTestCase inits, which are nonisolated.
final nonisolated class SnapshotUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        snapshot("01-home")
        // Add one snapshot("NN-name") per store screenshot; drive tabs by index so every language works.
    }
}
