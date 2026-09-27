import CryptoKit
import SwiftUI
import UIKit
import XCTest

#if DEBUG
@testable import XRay

@MainActor
final class XRayPreviewTests: XCTestCase {
    func testSiblingHostsKeepActionsAndMarkersSeparateFromWindowInstallation() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let parent = UIViewController()
        window.rootViewController = parent
        let outer = XRay.install(in: window, configuration: .init(maximumViews: 123))
        var environment = EnvironmentValues()
        environment.xrayContext = XRayContext(sessionID: outer.id, parentID: UUID())
        let firstProbe = PreviewProbeRecorder()
        let secondProbe = PreviewProbeRecorder()
        let first = XRayPreviewHostController(
            content: PreviewProbe(recorder: firstProbe).xrayView(), environment: environment,
            visible: false, configuration: .init(maximumViews: 31)
        )
        let second = XRayPreviewHostController(
            content: PreviewProbe(recorder: secondProbe).xrayView(), environment: environment,
            visible: false, configuration: .init(maximumViews: 47)
        )
        mount(first, in: parent, frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        mount(second, in: parent, frame: CGRect(x: 320, y: 0, width: 320, height: 480))
        window.makeKeyAndVisible()
        defer {
            first.stopInspection()
            second.stopInspection()
            window.isHidden = true
            window.rootViewController = nil
            XRay.uninstall(from: window)
        }
        let firstID = try XCTUnwrap(first.inspection?.id)
        let secondID = try XCTUnwrap(second.inspection?.id)
        try await waitUntil {
            window.layoutIfNeeded()
            return firstProbe.actions?.sessionID == firstID
                && secondProbe.actions?.sessionID == secondID
                && (try? first.inspection?.hierarchy().nodes.contains { $0.kind == .swiftUI }) == true
                && (try? second.inspection?.hierarchy().nodes.contains { $0.kind == .swiftUI }) == true
        }
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertNotEqual(firstID, outer.id)
        XCTAssertNotEqual(secondID, outer.id)
        XCTAssertEqual(firstProbe.textField.traitCollection.xrayContext.sessionID, firstID)
        XCTAssertEqual(secondProbe.textField.traitCollection.xrayContext.sessionID, secondID)
        let firstNodes = try XCTUnwrap(first.inspection).hierarchy().nodes.filter { $0.kind == .swiftUI }
        let secondNodes = try XCTUnwrap(second.inspection).hierarchy().nodes.filter { $0.kind == .swiftUI }
        XCTAssertEqual(firstNodes.map(\.name), ["PreviewProbe"])
        XCTAssertEqual(secondNodes.map(\.name), ["PreviewProbe"])
        XCTAssertNil(firstNodes.first?.parentID)
        XCTAssertNil(secondNodes.first?.parentID)
        XCTAssertTrue(Set(firstNodes.map(\.id)).isDisjoint(with: secondNodes.map(\.id)))

        firstProbe.actions?.show()
        XCTAssertEqual(first.inspection?.isVisible, true)
        XCTAssertEqual(second.inspection?.isVisible, false)
        XCTAssertFalse(outer.isVisible)
        XCTAssertEqual(outer.configuration.maximumViews, 123)
        XCTAssertEqual(window.traitCollection.xrayContext.sessionID, outer.id)

        first.stopInspection()
        XCTAssertNil(XRay.session(for: firstID))
        XCTAssertEqual(second.inspection?.id, secondID)
        secondProbe.actions?.show()
        XCTAssertEqual(second.inspection?.isVisible, true)
        XCTAssertEqual(window.traitCollection.xrayContext.sessionID, outer.id)
    }

    func testHostUpdatesKeepStateAndUIKitInstanceWhileForwardingEnvironment() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let recorder = PreviewProbeRecorder()
        let content = PreviewProbe(recorder: recorder).xrayView()
        var environment = EnvironmentValues()
        environment.previewTestValue = "first"
        let host = XRayPreviewHostController(
            content: content, environment: environment, visible: false, configuration: .init()
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            recorder.advance = nil
            host.stopInspection()
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitUntil {
            window.layoutIfNeeded()
            return recorder.observedValue == "first" && recorder.advance != nil && recorder.nativeMakes == 1
        }
        let sessionID = try XCTUnwrap(host.inspection?.id)
        recorder.textField.text = "Unsaved local edit"
        recorder.advance?()
        try await waitUntil { recorder.counter == 1 }

        environment.previewTestValue = "second"
        for visible in [true, false, true] {
            host.update(content: content, environment: environment, visible: visible, configuration: .init())
            window.layoutIfNeeded()
        }
        try await waitUntil { recorder.observedValue == "second" }
        XCTAssertEqual(recorder.counter, 1)
        XCTAssertEqual(recorder.nativeMakes, 1)
        XCTAssertEqual(recorder.textField.text, "Unsaved local edit")
        XCTAssertEqual(recorder.actions?.sessionID, sessionID)
        XCTAssertEqual(host.inspection?.id, sessionID)
        XCTAssertEqual(host.inspection?.isVisible, true)
        XCTAssertNil(window.traitCollection.xrayContext.sessionID)
    }

    func testPublicControllerPreviewContainsAndReleasesItsSession() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        weak var weakController: UIViewController?
        weak var weakSession: XRay?
        var sessionID: UUID?
        do {
            let controller = UIViewController()
            controller.view = UITextField()
            weakController = controller
            let host = UIHostingController(rootView: controller.preview(xray: true)
                .environment(\.layoutDirection, .rightToLeft))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await waitUntil {
                window.layoutIfNeeded()
                return controller.parent != nil && controller.view.traitCollection.xrayContext.sessionID != nil
            }
            sessionID = try XCTUnwrap(controller.view.traitCollection.xrayContext.sessionID)
            weakSession = XRay.session(for: try XCTUnwrap(sessionID))
            XCTAssertEqual(weakSession?.isVisible, true)
            XCTAssertEqual(controller.view.effectiveUserInterfaceLayoutDirection, .rightToLeft)
            XCTAssertNil(window.traitCollection.xrayContext.sessionID)
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitUntil { weakController == nil && weakSession == nil }
        XCTAssertNil(XRay.session(for: try XCTUnwrap(sessionID)))
    }

    func testPublicSwiftUIPreviewPreservesRTLInsidePhysicalComparisonCanvas() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let recorder = PreviewProbeRecorder()
        let host = UIHostingController(rootView: PreviewProbe(recorder: recorder)
            .preview().environment(\.layoutDirection, .rightToLeft))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            recorder.advance = nil
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitUntil {
            window.layoutIfNeeded()
            return recorder.observedLayoutDirection == .rightToLeft && recorder.nativeMakes == 1
        }
        XCTAssertEqual(recorder.textField.effectiveUserInterfaceLayoutDirection, .rightToLeft)
    }

    func testReferenceLoadsFromConsumerBundleAndRejectsChecksumOrDimensions() throws {
        let fixture = try makeResourceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }
        XCTAssertNotEqual(fixture.bundle.bundleURL, Bundle.main.bundleURL)
        let reference = XRayPreviewReference.resource("noteInput", bundle: fixture.bundle)
        let loaded = try reference.load()
        XCTAssertEqual(loaded.logicalSize, CGSize(width: 8, height: 8))
        XCTAssertEqual(loaded.image.cgImage?.width, 8)
        XCTAssertEqual(loaded.image.cgImage?.height, 8)
        XCTAssertEqual(loaded.sourceURL?.host, "www.figma.com")

        var metadata = fixture.metadata
        metadata.removeValue(forKey: "version")
        try write(metadata, to: fixture.metadataURL)
        XCTAssertNoThrow(try reference.load(), "Desktop MCP snapshots do not require a REST file version")

        metadata["sha256"] = String(repeating: "0", count: 64)
        try write(metadata, to: fixture.metadataURL)
        assertInvalidImage(reference)

        metadata = fixture.metadata
        metadata["pixelWidth"] = 9
        try write(metadata, to: fixture.metadataURL)
        assertInvalidImage(reference)
    }

    func testComparisonGeometryClampsAtEdgesAndPreservesCanvasAspect() {
        XCTAssertEqual(XRayPreviewGeometry.fraction(x: -20, width: 375), 0)
        XCTAssertEqual(XRayPreviewGeometry.fraction(x: 375 * 0.25, width: 375), 0.25)
        XCTAssertEqual(XRayPreviewGeometry.fraction(x: 400, width: 375), 1)
        XCTAssertEqual(
            XRayPreviewGeometry.scale(canvas: CGSize(width: 375, height: 812), available: CGSize(width: 300, height: 650)),
            0.8, accuracy: 0.0001
        )
        // Still manually exercise the actual divider at 25% in RTL and a scaled
        // Canvas. Pure geometry tests do not cover SwiftUI mask/gesture layout.
    }

    private func mount(_ child: UIViewController, in parent: UIViewController, frame: CGRect) {
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.view.frame = frame
        child.didMove(toParent: parent)
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("The expected preview state did not arrive")
                throw XRayError.targetUnavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func assertInvalidImage(_ reference: XRayPreviewReference, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try reference.load(), file: file, line: line) { error in
            guard case .some(.invalidImage) = error as? XRayReferenceError else {
                XCTFail("Expected invalidImage; received \(error)", file: file, line: line)
                return
            }
        }
    }

    private func write(_ metadata: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: url)
    }

    private func makeResourceFixture() throws -> PreviewResourceFixture {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("XRayPreview-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.xray.preview.fixture", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleURL.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let directory = try XCTUnwrap(bundle.resourceURL)
            .appendingPathComponent("XRayReferences/noteInput", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try image.write(to: directory.appendingPathComponent("reference.png"))
        let metadata: [String: Any] = [
            "schemaVersion": 1,
            "sourceURL": "https://www.figma.com/design/fixtureFileKey/?node-id=1-2",
            "fileKey": "fixtureFileKey", "nodeID": "1:2", "version": "fixture-version",
            "provenance": "figma-desktop-mcp", "capturedAt": "2026-09-27T00:00:00Z",
            "logicalWidth": 8, "logicalHeight": 8, "pixelWidth": 8, "pixelHeight": 8,
            "exportScale": 1,
            "sha256": SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined(),
        ]
        let metadataURL = directory.appendingPathComponent("metadata.json")
        try write(metadata, to: metadataURL)
        return PreviewResourceFixture(bundleURL: bundleURL, bundle: bundle, metadataURL: metadataURL, metadata: metadata)
    }
}

@MainActor
private final class PreviewProbeRecorder {
    let textField = UITextField()
    var actions: XRayActions?
    var advance: (() -> Void)?
    var observedValue = ""
    var observedLayoutDirection: LayoutDirection?
    var counter = -1
    var nativeMakes = 0
}

private struct PreviewTestValueKey: EnvironmentKey {
    static let defaultValue = "unspecified"
}

private extension EnvironmentValues {
    var previewTestValue: String {
        get { self[PreviewTestValueKey.self] }
        set { self[PreviewTestValueKey.self] = newValue }
    }
}

@MainActor
private struct PreviewProbe: View {
    @Environment(\.xray) private var actions
    @Environment(\.previewTestValue) private var value
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var counter = 0
    let recorder: PreviewProbeRecorder

    var body: some View {
        VStack {
            Text("Count: \(counter)")
            PreviewNativeField(recorder: recorder).frame(width: 180, height: 44)
        }
        .onAppear {
            recorder.actions = actions
            recorder.observedValue = value
            recorder.observedLayoutDirection = layoutDirection
            recorder.counter = counter
            recorder.advance = { counter += 1 }
        }
        .onChange(of: actions.sessionID) { _, _ in recorder.actions = actions }
        .onChange(of: value) { _, _ in recorder.observedValue = value }
        .onChange(of: counter) { _, _ in recorder.counter = counter }
        .onDisappear { recorder.advance = nil }
    }
}

@MainActor
private struct PreviewNativeField: UIViewRepresentable {
    let recorder: PreviewProbeRecorder
    func makeUIView(context: Context) -> UITextField {
        recorder.nativeMakes += 1
        return recorder.textField
    }
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

private struct PreviewResourceFixture {
    let bundleURL: URL
    let bundle: Bundle
    let metadataURL: URL
    let metadata: [String: Any]
}
#endif
