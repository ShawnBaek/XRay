import XCTest

@MainActor
final class XRayExampleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPreviewControlsPreserveEditsAndDragInBothDirections() {
        for rtl in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-xray-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (rtl ? ["-xray-preview-rtl"] : [])
            app.launch()
            let open = app.buttons["uikit.openPreview"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            open.tap()
            let compare = app.switches["xray.preview.compare"]
            let xray = app.switches["xray.preview.toggle"]
            XCTAssertTrue(compare.waitForExistence(timeout: 5))
            tapSwitch(compare, rtl: rtl)
            XCTAssertEqual(compare.value as? String, "0")
            tapSwitch(xray, rtl: rtl)
            XCTAssertEqual(xray.value as? String, "0")
            let field = app.textFields["preview.note"]
            field.tap()
            field.typeText(" edited")
            let editedValue = field.value as? String
            XCTAssertTrue(editedValue?.contains("edited") == true)
            let counter = app.buttons["preview.counter"]
            counter.tap()
            XCTAssertEqual(counter.label, "Count: 1")
            tapSwitch(xray, rtl: rtl)
            XCTAssertEqual(xray.value as? String, "1")
            XCTAssertEqual(field.value as? String, editedValue)
            XCTAssertEqual(counter.label, "Count: 1")
            app.buttons["xray.preview.controls"].tap()
            XCTAssertFalse(compare.exists)
            XCTAssertEqual(field.value as? String, editedValue)
            app.buttons["xray.preview.controls"].tap()
            XCTAssertTrue(compare.waitForExistence(timeout: 5))
            tapSwitch(compare, rtl: rtl)
            XCTAssertEqual(compare.value as? String, "1")
            let divider = app.otherElements["xray.preview.divider"]
            XCTAssertTrue(divider.waitForExistence(timeout: 5))
            let initialDividerX = divider.frame.midX
            let origin = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: -60, dy: 0)))
            let value = Double((divider.value as? String ?? "").replacingOccurrences(of: "%", with: ""))
            XCTAssertNotNil(value)
            XCTAssertLessThan(value ?? 100, 45, "Dragging physically left must reduce the reference fraction, including in RTL")
            XCTAssertLessThan(divider.frame.midX, initialDividerX - 20,
                              "The rendered divider must follow the physical drag, including in RTL")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = rtl ? "Preview RTL after drag" : "Preview LTR after drag"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

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

    private func tapSwitch(_ control: XCUIElement, rtl: Bool) {
        // SwiftUI exposes the label and switch as one element; target the thumb.
        control.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.1 : 0.9, dy: 0.5)).tap()
    }

    private func assertLabel(_ label: String, on element: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: expected, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
}
