import XCTest

final class StudyFlowUITests: XCTestCase {

    func testBrowseGradeSessionFlow() {
        let app = XCUIApplication()
        app.launch()

        // Opens on the study page with a word already shown.
        let good = app.buttons["Good"]
        XCTAssertTrue(good.waitForExistence(timeout: 15))

        // Tap the word: cycles to a sentence and eventually back (4 taps = full cycle).
        let front = app.descendants(matching: .any).matching(identifier: "cardFront").firstMatch
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        for _ in 0..<4 { front.tap() }

        // Grade -> reveal with Continue; change grade; continue to next card.
        good.tap()
        let continueButton = app.buttons["continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        app.buttons["Hard"].tap()   // change the pending grade on the reveal view
        continueButton.tap()
        XCTAssertTrue(app.buttons["Good"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["sessionCounter"].exists)

        // Swipe to the progress page and start the default goal session.
        app.swipeRight()
        let start = app.buttons["startSession"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Back on the study page, in-session UI shows the counter.
        let counter = app.staticTexts["sessionCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "0/20")

        // Grade one card with Easy: graduates instantly -> counts as completed.
        XCTAssertTrue(app.buttons["Easy"].waitForExistence(timeout: 5))
        app.buttons["Easy"].tap()
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "1/20")

        // End the session; back to free browsing.
        app.buttons["endSession"].tap()
        XCTAssertFalse(app.staticTexts["sessionCounter"].exists)
        XCTAssertTrue(app.buttons["Good"].waitForExistence(timeout: 5))
    }
}
