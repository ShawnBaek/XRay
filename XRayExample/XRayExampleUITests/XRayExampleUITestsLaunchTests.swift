import XCTest

@MainActor
final class XRayExampleUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUIKitScreenshotAndRepeatedCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["-xray-ui-testing"]
        app.launch()
        let screenshotButton = app.buttons["uikit.screenshot"]
        XCTAssertTrue(screenshotButton.waitForExistence(timeout: 5))
        screenshotButton.tap()
        let overlay = XCTAttachment(screenshot: app.screenshot())
        overlay.name = "UIKit screenshot activation"
        overlay.lifetime = .keepAlways
        add(overlay)

        var firstSummary: String?
        for _ in 0..<2 {
            app.buttons["uikit.show"].tap()
            app.buttons["uikit.capture"].tap()
            let summary = app.staticTexts["capture.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertEqual(summary.value as? String, "0")
            if let firstSummary {
                XCTAssertEqual(summary.label, firstSummary, "Repeated inspection must not add XRay's own views")
            } else {
                firstSummary = summary.label
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "UIKit annotated image"
            capture.lifetime = .keepAlways
            add(capture)
            app.buttons["capture.done"].tap()
            XCTAssertTrue(screenshotButton.waitForExistence(timeout: 5))
        }
        app.buttons["uikit.hide"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
