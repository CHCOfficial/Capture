import XCTest

final class CaptureUITests: XCTestCase {
    func testRecorderWindowLaunchesWithRecordButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }
}

