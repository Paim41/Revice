import XCTest

final class AgentUITests: XCTestCase {
    func testWelcomePairingSettingsAndCredits() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pair This iPhone"].waitForExistence(timeout: 15))
        app.buttons["Pair This iPhone"].tap()
        XCTAssertTrue(app.textFields["Six-digit Pairing Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Request Pairing"].exists)
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Agent Settings"].waitForExistence(timeout: 5))
        let credits = app.buttons["About & Developer Credits"]
        for _ in 0..<5 { if credits.isHittable { break }; app.swipeUp() }
        credits.tap()
        XCTAssertTrue(app.staticTexts["Developed by Paim41"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Revice Credits"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
