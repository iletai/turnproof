import XCTest

/// Walks the inspection flow. Shared by `EndToEndTests` and `SnapshotUITests` so a screen change
/// breaks one place; every step keys off accessibility identifiers, never user-visible copy.
@MainActor
extension XCTestCase {
    // MARK: Properties

    func addProperty(_ app: XCUIApplication, label: String = "Unit A", address: String = "1 Main St",
                     unit: String = "", landlord: String = "Lee") {
        let start = app.buttons["inspection.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // Landlord is the lowest field: fill it before any keyboard is up. In the vi run the taller keyboard
        // hid it and it dropped out of the hierarchy when tapped after the other fields.
        let landlordField = app.textFields["property.field.landlord"]
        XCTAssertTrue(landlordField.waitForExistence(timeout: 5))
        landlordField.tap()
        landlordField.typeText(landlord)

        let labelField = app.textFields["property.field.label"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 5))
        labelField.tap()
        labelField.typeText(label)
        app.textFields["property.field.address"].tap()
        app.textFields["property.field.address"].typeText(address)
        if !unit.isEmpty {
            app.textFields["property.field.unit"].tap()
            app.textFields["property.field.unit"].typeText(unit)
        }
        app.buttons["property.save"].tap()

        XCTAssertTrue(propertyRow(app).waitForExistence(timeout: 5))
    }

    func propertyRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'property.row.'")).firstMatch
    }

    // MARK: Inspection

    func startInspection(_ app: XCUIApplication) {
        propertyRow(app).tap()
        let new = app.buttons["inspection.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        XCTAssertTrue(app.buttons["room.kitchen"].waitForExistence(timeout: 5))
    }

    /// Captures one photo in `key`, optionally damaged and noted, then returns to the checklist.
    func recordRoom(_ app: XCUIApplication, key: String, condition: String? = nil,
                    flagged: Bool = false, note: String? = nil) {
        app.buttons["room.\(key)"].tap()
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        if let condition {
            app.buttons["capture.condition.\(condition)"].tap()
        }
        if flagged {
            app.switches["capture.damageFlag"].tap()
        }
        if let note {
            let field = app.textFields["capture.note"]
            field.tap()
            field.typeText(note)
        }
        shutter.tap()
        XCTAssertTrue(app.buttons["finding.delete.1"].waitForExistence(timeout: 10))
        app.buttons["nav.back"].tap()
        XCTAssertTrue(app.buttons["review.next"].waitForExistence(timeout: 5))
    }

    func recordAllRooms(_ app: XCUIApplication, damagedNote: String? = nil) {
        for key in ["kitchen", "living", "bedroom", "bath", "hall", "exterior"] {
            let damaged = key == "kitchen" && damagedNote != nil
            recordRoom(app, key: key, condition: damaged ? "damaged" : nil,
                       flagged: damaged, note: damaged ? damagedNote : nil)
        }
    }

    func openReview(_ app: XCUIApplication) {
        let next = app.buttons["review.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["review.issue.1"].waitForExistence(timeout: 5),
                      app.debugDescription)
    }

    func openSign(_ app: XCUIApplication) {
        let next = app.buttons["review.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isEnabled, app.debugDescription)
        next.tap()
        XCTAssertTrue(app.buttons["sign.seal"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func sign(_ app: XCUIApplication, identifier: String) {
        let canvas = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
