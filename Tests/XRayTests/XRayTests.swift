import XCTest
import UIKit
import SwiftUI
#if DEBUG
@testable import XRay
#else
import XRay
#endif

#if DEBUG
@MainActor
final class XRayTests: XCTestCase {
    func testRepeatedCaptureDoesNotInspectItsOwnOverlays() {
        let controller = UIViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        controller.view.addSubview(UILabel())
        let inspector = XRay(rootViewController: controller)
        inspector.captureXray(classNameOption: .all)
        let firstCount = descendantCount(controller.view)
        inspector.captureXray(classNameOption: .all)
        XCTAssertEqual(descendantCount(controller.view), firstCount)
        inspector.removeXray()
    }

    func testRemovalPreservesApplicationViewWithLegacyTag() {
        let controller = UIViewController()
        let applicationView = UIView()
        applicationView.tag = 20_220_522
        controller.view.addSubview(applicationView)
        let inspector = XRay(rootViewController: controller)
        inspector.captureXray(classNameOption: .all)
        inspector.removeXray()
        XCTAssertTrue(applicationView.superview === controller.view)
    }

    private func descendantCount(_ view: UIView) -> Int {
        view.subviews.reduce(0) { $0 + 1 + descendantCount($1) }
    }

    func testDeallocatedTargetIsSafeDuringCaptureCleanupAndDeinit() {
        weak var weakView: UIView?
        var inspector: XRay?
        autoreleasepool {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            weakView = view
            inspector = XRay(view: view)
            inspector?.show()
        }
        XCTAssertNil(weakView)
        inspector?.hide()
        XCTAssertThrowsError(try inspector?.capture()) { error in
            XCTAssertEqual(error as? XRayError, .targetUnavailable)
        }
        inspector = nil
    }

    func testRepeatedInstallationReturnsOneSessionAndUninstallPreservesHostSubviews() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        let first = XRay.install(in: window)
        let second = XRay.install(in: window, configuration: .init(filter: .application))
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.configuration.filter, .application)
        first.show()
        XCTAssertTrue(first.isVisible)
        XRay.uninstall(from: window)
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(host.superview === window)
        XCTAssertNil(window.traitCollection.xrayContext.sessionID)
    }

    func testTraversalLimitsAndHiddenSubtree() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        for _ in 0..<100 { root.addSubview(UIView(frame: root.bounds)) }
        let inspector = XRay(view: root, configuration: .init(maximumViews: 8))
        let hierarchy = try inspector.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 8)
        XCTAssertTrue(hierarchy.isTruncated)
        inspector.configuration.maximumViews = 200
        root.subviews.forEach { $0.isHidden = true }
        XCTAssertEqual(try inspector.hierarchy().nodes.count, 1)
        inspector.configuration.maximumDepth = 0
        root.subviews[0].isHidden = false
        XCTAssertTrue(try inspector.hierarchy().isTruncated)
    }

    func testPatternAndDynamicColorsDoNotRequireRGBConversion() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        root.backgroundColor = UIColor(patternImage: tile)
        let child = UIView(frame: CGRect(x: 5, y: 5, width: 50, height: 50))
        child.backgroundColor = .secondarySystemBackground
        root.addSubview(child)
        let inspector = XRay(view: root)
        inspector.show()
        XCTAssertEqual(try inspector.hierarchy().nodes.count, 2)
        inspector.hide()
    }

    func testCaptureRejectsZeroAndOversizedBounds() {
        let root = UIView()
        let inspector = XRay(view: root)
        XCTAssertThrowsError(try inspector.capture()) { XCTAssertEqual($0 as? XRayError, .invalidBounds) }
        root.bounds.size = CGSize(width: 100_000, height: 100_000)
        XCTAssertThrowsError(try inspector.capture()) { XCTAssertEqual($0 as? XRayError, .invalidBounds) }
        root.bounds.size = CGSize(width: 1_000_000_000, height: 0.001)
        XCTAssertThrowsError(try inspector.capture()) { XCTAssertEqual($0 as? XRayError, .invalidBounds) }
    }

    func testTransformedGeometryUsesFourConvertedCorners() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let child = UIView(frame: CGRect(x: 50, y: 50, width: 100, height: 60))
        child.transform = CGAffineTransform(rotationAngle: .pi / 6)
        root.addSubview(child)
        let node = try XCTUnwrap(XRay(view: root).hierarchy().nodes.last)
        XCTAssertEqual(node.corners.count, 4)
        XCTAssertNotEqual(node.corners[0].y, node.corners[1].y)
        XCTAssertEqual(node.frame, child.convert(child.bounds, to: root))
    }

    func testTraitContextIsInheritedAndInactiveActionsAreSafe() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let child = UIView(frame: window.bounds)
        window.addSubview(child)
        let session = XRay.install(in: window)
        window.layoutIfNeeded()
        XCTAssertEqual(child.traitCollection.xrayContext.sessionID, session.id)
        child.traitCollection.xray.show()
        XCTAssertTrue(session.isVisible)
        XRay.uninstall(from: window)
        let actions = XRayActions(sessionID: nil)
        actions.show()
        actions.hide()
        XCTAssertThrowsError(try actions.capture())
    }

    func testManualShowCancelsScreenshotExpiry() async throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let session = XRay(view: root, configuration: .init(screenshotDuration: 0.01))
        session.showAfterScreenshot()
        session.show()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(session.isVisible)
        session.hide()
    }

    func testScreenshotExpiryAfterTargetDeallocationIsSafe() async throws {
        var target: UIView? = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let session = XRay(view: try XCTUnwrap(target), configuration: .init(screenshotDuration: 0.01))
        session.showAfterScreenshot()
        target = nil
        // Advance past the actual scheduled cleanup, even though UIKit detached the overlay already.
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(session.isVisible)
        XCTAssertThrowsError(try session.capture()) { XCTAssertEqual($0 as? XRayError, .targetUnavailable) }
    }

    func testSwiftUIRootInfersTypeAndPropagatesActionsToModifiedChild() async throws {
        var actions: XRayActions?
        let nativeView = UIView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let host = UIHostingController(rootView: SemanticFixture(nativeView: nativeView) { actions = $0 }.xray())
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; XRay.uninstall(from: window) }
        try await waitUntil {
            window.layoutIfNeeded()
            guard let session = XRay.session(for: window.traitCollection.xrayContext.sessionID),
                  let nodes = try? session.hierarchy().nodes else { return false }
            return nodes.filter { $0.kind == .swiftUI }.count == 2 && actions?.sessionID != nil
        }
        let session = try XCTUnwrap(XRay.session(for: window.traitCollection.xrayContext.sessionID))
        let nodes = try session.hierarchy().nodes.filter { $0.kind == .swiftUI }
        let parent = try XCTUnwrap(nodes.first { $0.name == "SemanticFixture" })
        let child = try XCTUnwrap(nodes.first { $0.name == "SemanticRow" })
        XCTAssertNil(parent.label)
        XCTAssertNil(child.label)
        XCTAssertFalse(nodes.contains { $0.name.contains("ModifiedContent") })
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertGreaterThan(child.depth, parent.depth)
        XCTAssertGreaterThan(child.frame.width, 0)
        XCTAssertEqual(nativeView.traitCollection.xrayContext.sessionID, session.id)
        XCTAssertEqual(nativeView.traitCollection.xrayContext.parentID?.uuidString, child.id)
        actions?.show()
        XCTAssertTrue(session.isVisible)
        let subtree = XRay(view: host.view)
        XCTAssertEqual(try subtree.hierarchy().nodes.filter { $0.kind == .swiftUI }.count, 2)
        session.configuration.maximumDepth = 0
        let limited = try session.hierarchy()
        XCTAssertTrue(limited.isTruncated)
        XCTAssertEqual(limited.nodes.filter { $0.kind == .swiftUI }.map(\.name), ["SemanticFixture"])
        actions?.hide()
        XCTAssertFalse(session.isVisible)
        nativeView.traitCollection.xray.show()
        XCTAssertTrue(session.isVisible)
        nativeView.traitCollection.xray.hide()
        window.rootViewController = UIViewController()
        try await waitUntil { window.traitCollection.xrayContext.sessionID == nil }
    }

    func testIndependentWindowsAndSwiftUIOwnersHaveSeparateLifetimes() {
        let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let second = UIWindow(frame: first.frame)
        let firstOwner = UUID(), secondOwner = UUID()
        XRay.attachSwiftUIRoot(in: first, owner: firstOwner, configuration: .init())
        XRay.attachSwiftUIRoot(in: first, owner: secondOwner, configuration: .init())
        let firstSession = XRay.session(for: first.traitCollection.xrayContext.sessionID)
        let secondSession = XRay.install(in: second)
        XCTAssertNotEqual(firstSession?.id, secondSession.id)
        XRay.detachSwiftUIRoot(from: first, owner: firstOwner)
        XCTAssertNotNil(first.traitCollection.xrayContext.sessionID)
        XRay.detachSwiftUIRoot(from: first, owner: secondOwner)
        XCTAssertNil(first.traitCollection.xrayContext.sessionID)
        XCTAssertEqual(second.traitCollection.xrayContext.sessionID, secondSession.id)
        XRay.uninstall(from: second)
    }

    func testVisibleChildrenSurviveOffscreenAndEmptyNonclippingParents() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let parent = UIView(frame: CGRect(x: 400, y: 0, width: 100, height: 100))
        let child = UILabel(frame: CGRect(x: -350, y: 0, width: 100, height: 100))
        root.addSubview(parent)
        parent.addSubview(child)
        let inspector = XRay(view: root)
        XCTAssertEqual(try inspector.hierarchy().nodes.count, 2)
        parent.bounds.size = .zero
        XCTAssertEqual(try inspector.hierarchy().nodes.count, 2)
        parent.clipsToBounds = true
        XCTAssertEqual(try inspector.hierarchy().nodes.count, 1)
    }

    func testHierarchyTextDoesNotConvertUnboundedCoordinatesToIntegers() {
        let node = XRayNode(id: "large", parentID: nil, name: "Large view", kind: .view,
            frame: CGRect(x: -1e30, y: 0, width: 2e30, height: 10), corners: [],
            clipRect: CGRect(x: 0, y: 0, width: 100, height: 100), depth: 0)
        XCTAssertTrue(XRayHierarchy(nodes: [node], isTruncated: false).description.contains("Large view"))
    }

    func testUIKitReportsActualViewSubclassAndKeepsControllerSeparate() throws {
        let controller = NamedController()
        let root = NamedRootView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        controller.view = root
        let child = NamedChildView(frame: CGRect(x: 10, y: 10, width: 100, height: 50))
        root.addSubview(child)
        let hierarchy = try XRay(rootViewController: controller).hierarchy()
        let rootNode = try XCTUnwrap(hierarchy.nodes.first)
        XCTAssertEqual(rootNode.name, "NamedRootView")
        XCTAssertEqual(rootNode.kind, .viewController)
        XCTAssertEqual(rootNode.viewControllerName, "NamedController")
        XCTAssertNil(rootNode.label)
        XCTAssertEqual(hierarchy.nodes.last?.name, "NamedChildView")
        XCTAssertTrue(hierarchy.description.contains("NamedRootView"))
    }

    func testSwiftUITypedBodyNamesCaptionsAndTypeErasure() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = UIHostingController(rootView: TypeNameFixture().xray())
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; XRay.uninstall(from: window) }
        try await waitUntil {
            window.layoutIfNeeded()
            guard let session = XRay.session(for: window.traitCollection.xrayContext.sessionID) else { return false }
            return (try? session.hierarchy().nodes.filter { $0.kind == .swiftUI }.count) == 4
        }
        let session = try XCTUnwrap(XRay.session(for: window.traitCollection.xrayContext.sessionID))
        let hierarchy = try session.hierarchy()
        let nodes = hierarchy.nodes.filter { $0.kind == .swiftUI }
        XCTAssertEqual(Set(nodes.map(\.name)), ["TypeNameFixture", "TypedBodyFixture", "Text", "AnyView"])
        let captioned = try XCTUnwrap(nodes.first { $0.label == "Account title" })
        XCTAssertEqual(captioned.name, "Text", "A custom caption must not replace the actual type")
        XCTAssertTrue(hierarchy.description.contains("Text — Account title"))
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("The expected hierarchy or installation state did not arrive")
                throw XRayError.targetUnavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private struct SemanticFixture: View {
    let nativeView: UIView
    let receive: (XRayActions) -> Void
    var body: some View {
        VStack {
            Text("Profile")
            SemanticRow(nativeView: nativeView, receive: receive)
                .padding(4)
                .background(Color.clear)
                .xrayView()
        }
        .padding()
    }
}

@MainActor
private struct SemanticRow: View {
    let nativeView: UIView
    let receive: (XRayActions) -> Void
    var body: some View {
        VStack {
            SemanticChild(receive: receive)
            NativeFixture(view: nativeView).frame(width: 100, height: 30)
        }
    }
}

@MainActor
private struct TypeNameFixture: View {
    var body: some View {
        VStack {
            Text("Account").font(.headline).xrayLabel("Account title")
            TypedBodyFixture()
            AnyView(Text("Erased content")).xrayView()
        }
    }
}

@MainActor
private struct TypedBodyFixture: View {
    var body: some View {
        VStack { Text("Typed body") }
            .padding()
            .xrayView(Self.self)
    }
}

@MainActor private final class NamedController: UIViewController {}
@MainActor private final class NamedRootView: UIView {}
@MainActor private class NamedBaseView: UIView {}
@MainActor private final class NamedChildView: NamedBaseView {}

@MainActor
private struct NativeFixture: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
private struct SemanticChild: View {
    @Environment(\.xray) private var xray
    let receive: (XRayActions) -> Void
    var body: some View {
        Text("Taylor").onAppear { receive(xray) }
            .onChange(of: xray.sessionID) { _, _ in receive(xray) }
    }
}
#else
@MainActor
final class XRayReleaseTests: XCTestCase {
    func testReleaseRemainsInactive() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let child = UIView(frame: window.bounds)
        window.addSubview(child)
        let traits = window.traitCollection
        let session = XRay.install(in: window)
        session.show()
        session.refresh()
        XCTAssertFalse(session.isVisible)
        XCTAssertEqual(window.subviews, [child])
        XCTAssertEqual(window.traitCollection, traits)
        XCTAssertNil(NSClassFromString("XRayDebugBridge"))
        XCTAssertThrowsError(try session.capture()) { XCTAssertEqual($0 as? XRayError, .disabled) }
        XCTAssertThrowsError(try session.hierarchy()) { XCTAssertEqual($0 as? XRayError, .disabled) }
        XRay.uninstall(from: window)
    }
}
#endif
