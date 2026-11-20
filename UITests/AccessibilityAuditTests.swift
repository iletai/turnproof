import XCTest

/// Audits the screens the store gallery shows with a focused set: text has to survive the largest
/// Dynamic Type size, every control needs a real hit area, and every element needs a description.
/// Contrast is left out on purpose — hairlines and chips make it noisy on this layout.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoreScreensPassAccessibilityAudit() throws {
        let app = XCUIApplication.turnproof()
        app.launch()

        addProperty(app, label: "Riverside Apartments", address: "12 Nguyen Hue", unit: "Unit 4B")
        try audit(app) // properties list

        startInspection(app)
        recordRoom(app, key: "kitchen", condition: "damaged", flagged: true, note: "Scuff")
        try audit(app) // room checklist with progress

        app.buttons["room.kitchen"].tap()
        XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 5))
        try audit(app) // capture with a saved finding
        app.buttons["nav.back"].tap()

        for key in ["living", "bedroom", "bath", "hall", "exterior"] {
            recordRoom(app, key: key)
        }

        openReview(app)
        openSign(app)
        sign(app, identifier: "sign.tenant")
        sign(app, identifier: "sign.landlord")
        app.buttons["sign.seal"].tap()

        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 20), app.debugDescription)
        try audit(app) // export with the short code
    }

    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        let bar = app.navigationBars.firstMatch
        let navigationBar = bar.exists ? bar.frame : .zero
        try app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription]) { issue in
            // System bar buttons stay fixed and show the Large Content Viewer instead of growing.
            guard issue.auditType == .dynamicType, let element = issue.element else { return false }
            return navigationBar.contains(element.frame)
        }
    }
}
