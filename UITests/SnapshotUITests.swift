import XCTest

/// App Store gallery: one demo inspection, captured screen by screen (`fastlane screenshots`).
///
/// These are raw captures only — captions, gradients and device frames are a separate composition
/// step. PNGs land in the simulator's fastlane cache, which the repo does not contain, so after a
/// run copy them into the repo:
///
///     xcodebuild test -scheme Turnproof-Dev -destination 'platform=iOS Simulator,id=<UDID>' \
///       -only-testing:TurnproofUITests/SnapshotUITests
///     mkdir -p fastlane/screenshots/en-US
///     cp "$HOME/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Caches/tools.fastlane/screenshots/"*.png \
///        fastlane/screenshots/en-US/
///
/// Not MainActor: default isolation would change the XCTestCase inits, which are nonisolated.
final nonisolated class SnapshotUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        // The helper only logs when its directory is missing, so the test creates it.
        SnapshotFiles.prepareDirectory()
    }

    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication.turnproof()
        setupSnapshot(app)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        addProperty(app, label: "Riverside Apartments", address: "12 Nguyen Hue",
                    unit: "Unit 4B", landlord: "Le")
        capture("01-properties")

        startInspection(app)
        // Record most rooms first so the checklist progress bar is visible.
        recordRoom(app, key: "living")
        recordRoom(app, key: "bedroom")
        recordRoom(app, key: "bath")
        recordRoom(app, key: "hall")
        capture("02-rooms")

        recordRoom(app, key: "kitchen", condition: "damaged", flagged: true,
                   note: "Scuff on cabinet door")
        // Reopen the room so the saved photo and its damage note are on screen.
        app.buttons["room.kitchen"].tap()
        XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 5))
        capture("03-capture")
        app.buttons["nav.back"].tap()

        recordRoom(app, key: "exterior")
        openReview(app)
        capture("04-review")

        openSign(app)
        sign(app, identifier: "sign.tenant")
        sign(app, identifier: "sign.landlord")
        let seal = app.buttons["sign.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 5))
        XCTAssertTrue(seal.isEnabled, app.debugDescription)
        capture("05-sign")

        seal.tap()
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["export.shortCode"].exists)
        capture("06-export")

        app.buttons["export.verify"].tap()
        XCTAssertTrue(app.staticTexts["verify.result"].waitForExistence(timeout: 5))
        capture("07-verify")
    }

    /// The paywall is only reachable by sealing a second report; its capture feeds the ASC purchase review screenshot.
    @MainActor
    func testCapturePaywall() throws {
        let app = XCUIApplication.turnproof()
        setupSnapshot(app)
        app.launch()
        addProperty(app)
        for report in 1 ... 2 {
            if report == 2 {
                propertyRow(app).tap()
                app.buttons["inspection.new"].tap()
            } else {
                startInspection(app)
            }
            recordAllRooms(app)
            openReview(app)
            openSign(app)
            sign(app, identifier: "sign.tenant")
            sign(app, identifier: "sign.landlord")
            app.buttons["sign.seal"].tap()
            if report == 1 {
                XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 20))
                app.buttons["export.done"].tap()
            }
        }
        XCTAssertTrue(app.buttons["paywall.dismiss"].waitForExistence(timeout: 10))
        // Give StoreKit time to load the plans before the capture.
        sleep(5)
        capture("08-paywall")
    }

    /// Clears any PNG from an earlier run so the assertions prove this run wrote the file.
    @MainActor
    private func capture(_ name: String) {
        SnapshotFiles.removeStale(name)
        snapshot(name)
        SnapshotFiles.assertCaptured(name)
    }
}

/// `SnapshotHelper` writes `$SIMULATOR_HOST_HOME/Library/Caches/tools.fastlane/screenshots/
/// <device>-<name>.png` and only logs its failures, so the test checks the file itself.
private nonisolated enum SnapshotFiles {
    private static let cachePath = "Library/Caches/tools.fastlane/screenshots"
    private static let minimumBytes = 20_000

    static var directory: URL? {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        return URL(fileURLWithPath: home).appendingPathComponent(cachePath, isDirectory: true)
    }

    /// Simulator name without the "Clone N of " prefix parallel runners add.
    static var deviceName: String {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        return name.replacingOccurrences(of: "Clone [0-9]+ of ", with: "", options: .regularExpression)
    }

    static func url(for name: String) -> URL? {
        directory?.appendingPathComponent("\(deviceName)-\(name).png")
    }

    static func prepareDirectory() {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func removeStale(_ name: String) {
        guard let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func assertCaptured(_ name: String) {
        guard let url = url(for: name) else {
            XCTFail("SIMULATOR_HOST_HOME is unset; snapshots need a simulator host")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("fastlane wrote no PNG at \(url.path)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, minimumBytes,
                             "\(name) is \(size) bytes, too small to be a real screen")
    }
}
