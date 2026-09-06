import XCTest
@testable import XRayExample

@MainActor
final class XRayExampleTests: XCTestCase {
    func testStoryboardConnectsTheSwiftUIAction() throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: XRayRootViewController.self))
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController() as? XRayRootViewController)
        controller.loadViewIfNeeded()
        let button = try XCTUnwrap(controller.swiftUIButton)
        XCTAssertEqual(button.accessibilityIdentifier, "uikit.openSwiftUI")
        XCTAssertEqual(button.actions(forTarget: controller, forControlEvent: .touchUpInside), ["presentUsernameRegistration:"])
    }
}
