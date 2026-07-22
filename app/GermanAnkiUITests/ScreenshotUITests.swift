import XCTest

/// Captures each page as an attachment for visual review; not a functional test.
final class ScreenshotUITests: XCTestCase {

    func testCapturePages() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Good"].waitForExistence(timeout: 15))

        app.buttons["Good"].tap()
        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 5))
        attach("reveal")
        app.buttons["continueButton"].tap()

        app.swipeRight()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 5))
        attach("progress")

        app.swipeLeft()
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        attach("settings")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
