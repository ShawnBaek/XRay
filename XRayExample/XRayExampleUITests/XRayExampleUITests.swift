import XCTest

@MainActor
final class XRayExampleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeepSwiftUICaptureAndDismissAfterScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-xray-ui-testing"]
        app.launch()

        for iteration in 1...2 {
            let open = app.buttons["uikit.openSwiftUI"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            open.tap()
            let field = app.textFields["swiftui.username"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, "Taylor")

            app.buttons["swiftui.show"].tap()
            assertLabel("Annotations shown", on: app.staticTexts["swiftui.status"])
            app.buttons["swiftui.capture"].tap()
            let summary = app.staticTexts["capture.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            let typeNames = app.staticTexts["capture.swiftUITypes"]
            XCTAssertTrue(typeNames.waitForExistence(timeout: 5))
            let capturedTypes = Set(typeNames.label.split(separator: "\n").map(String.init))
            XCTAssertTrue(capturedTypes.contains("UsernameRegistrationView"), "Capture must show the actual screen type")
            XCTAssertTrue(capturedTypes.contains("InspectionControls"), "Capture must show the actual nested view type")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "SwiftUI annotated capture \(iteration)"
            capture.lifetime = .keepAlways
            add(capture)
            app.buttons["capture.done"].tap()
            XCTAssertTrue(app.buttons["swiftui.screenshot"].waitForExistence(timeout: 5))
            app.buttons["swiftui.screenshot"].tap()
            assertLabel("Screenshot notification sent", on: app.staticTexts["swiftui.status"])
            app.buttons["swiftui.done"].tap()
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            app.buttons["uikit.hide"].tap()
            assertLabel("Annotations hidden", on: app.staticTexts["uikit.status"])
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func assertLabel(_ label: String, on element: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: expected, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
}
