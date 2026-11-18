import XCTest

final class EndToEndTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Happy path

    @MainActor
    func testInspectionSealsAndExports() {
        let app = XCUIApplication.turnproof()
        app.launch()

        addProperty(app)
        startInspection(app)
        recordAllRooms(app, damagedNote: "Scuff on cabinet door")

        openReview(app)
        openSign(app)

        sign(app, identifier: "sign.tenant")
        sign(app, identifier: "sign.landlord")
        let seal = app.buttons["sign.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 5))
        XCTAssertTrue(seal.isEnabled)
        seal.tap()

        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["export.shortCode"].exists)
        XCTAssertEqual(app.staticTexts["export.shortCode"].label.count, 14)

        app.buttons["export.verify"].tap()
        XCTAssertTrue(app.staticTexts["verify.result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["verify.result"].label.contains("still produce the sealed digest"))
    }

    // MARK: Negatives

    @MainActor
    func testSealIsDisabledUntilBothPartiesDraw() {
        let app = XCUIApplication.turnproof()
        app.launch()

        addProperty(app)
        startInspection(app)
        recordAllRooms(app)
        openReview(app)
        openSign(app)

        let seal = app.buttons["sign.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 5))
        XCTAssertFalse(seal.isEnabled)

        sign(app, identifier: "sign.tenant")
        XCTAssertFalse(seal.isEnabled)

        sign(app, identifier: "sign.landlord")
        XCTAssertTrue(seal.isEnabled)
    }

    @MainActor
    func testDamageWithoutNoteBlocksReview() {
        let app = XCUIApplication.turnproof()
        app.launch()

        addProperty(app)
        startInspection(app)

        app.buttons["room.kitchen"].tap()
        app.buttons["capture.condition.damaged"].tap()
        app.switches["capture.damageFlag"].tap()
        app.buttons["capture.shutter"].tap()
        XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 10))
        app.buttons["nav.back"].tap()

        app.buttons["review.next"].tap()
        XCTAssertTrue(app.staticTexts["review.issue.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.next"].isEnabled)
    }

    @MainActor
    func testSecondReportHitsPaywallAndKeepsSealedReport() {
        let app = XCUIApplication.turnproof()
        app.launch()

        // First report consumes the single free slot.
        addProperty(app)
        startInspection(app)
        recordAllRooms(app, damagedNote: "Scuff")
        openReview(app)
        openSign(app)
        sign(app, identifier: "sign.tenant")
        sign(app, identifier: "sign.landlord")
        app.buttons["sign.seal"].tap()
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 10))
        app.buttons["export.done"].tap()

        // Second report is sealed but export is gated.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'property.row.'")).firstMatch.tap()
        app.buttons["inspection.new"].tap()
        recordAllRooms(app)
        openReview(app)
        openSign(app)
        sign(app, identifier: "sign.tenant")
        sign(app, identifier: "sign.landlord")
        app.buttons["sign.seal"].tap()

        let dismiss = app.buttons["paywall.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()

        XCTAssertTrue(app.staticTexts["This report was sealed and cannot be edited."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export.share"].exists)
    }

    @MainActor
    func testDraftSurvivesRelaunch() {
        let app = XCUIApplication.turnproof()
        app.launch()

        addProperty(app)
        startInspection(app)
        app.buttons["room.kitchen"].tap()
        app.buttons["capture.shutter"].tap()
        XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 10))

        app.terminate()
        let relaunched = XCUIApplication.turnproof(resetState: false)
        relaunched.launch()

        let row = relaunched.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'property.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(relaunched.buttons["inspection.continue"].waitForExistence(timeout: 5))
        relaunched.buttons["inspection.continue"].tap()
        XCTAssertTrue(relaunched.buttons["room.kitchen"].waitForExistence(timeout: 5))
        relaunched.buttons["room.kitchen"].tap()
        XCTAssertTrue(relaunched.buttons["finding.delete.1"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    @MainActor
    private func openReview(_ app: XCUIApplication) {
        let next = app.buttons["review.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["Review before signing"].waitForExistence(timeout: 5),
                      app.debugDescription)
    }

    @MainActor
    private func openSign(_ app: XCUIApplication) {
        let next = app.buttons["review.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isEnabled, app.debugDescription)
        next.tap()
        XCTAssertTrue(app.buttons["sign.seal"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func addProperty(_ app: XCUIApplication, label: String = "Unit A") {
        let start = app.buttons["inspection.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let labelField = app.textFields["property.field.label"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 5))
        labelField.tap()
        labelField.typeText(label)
        app.textFields["property.field.address"].tap()
        app.textFields["property.field.address"].typeText("1 Main St")
        app.textFields["property.field.landlord"].tap()
        app.textFields["property.field.landlord"].typeText("Lee")
        app.buttons["property.save"].tap()

        XCTAssertTrue(propertyRow(app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func propertyRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'property.row.'")).firstMatch
    }

    @MainActor
    private func startInspection(_ app: XCUIApplication) {
        propertyRow(app).tap()
        let new = app.buttons["inspection.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(app.buttons["room.kitchen"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func recordAllRooms(_ app: XCUIApplication, damagedNote: String? = nil) {
        for key in ["kitchen", "living", "bedroom", "bath", "hall", "exterior"] {
            app.buttons["room.\(key)"].tap()
            let shutter = app.buttons["capture.shutter"]
            XCTAssertTrue(shutter.waitForExistence(timeout: 5))
            if key == "kitchen", let damagedNote {
                app.buttons["capture.condition.damaged"].tap()
                app.switches["capture.damageFlag"].tap()
                let note = app.textFields["capture.note"]
                note.tap()
                note.typeText(damagedNote)
            }
            shutter.tap()
            XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 10))
            app.buttons["nav.back"].tap()
            XCTAssertTrue(app.buttons["review.next"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func sign(_ app: XCUIApplication, identifier: String) {
        let canvas = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
