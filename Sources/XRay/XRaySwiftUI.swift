import SwiftUI
import UIKit

/// Inspection actions inherited from the nearest installed window.
/// An absent installation is safe: actions do nothing and capture reports an unavailable target.
public struct XRayActions: Sendable {
    let sessionID: UUID?

    @MainActor public func show() {
        #if DEBUG
        XRay.session(for: sessionID)?.show()
        #endif
    }

    @MainActor public func hide() {
        #if DEBUG
        XRay.session(for: sessionID)?.hide()
        #endif
    }

    @MainActor public func capture() throws -> XRaySnapshot {
        #if DEBUG
        guard let session = XRay.session(for: sessionID) else { throw XRayError.targetUnavailable }
        return try session.capture()
        #else
        throw XRayError.disabled
        #endif
    }
}

extension EnvironmentValues {
    /// Access XRay in a deeply nested SwiftUI view with `@Environment(\.xray)`.
    public var xray: XRayActions { XRayActions(sessionID: xrayContext.sessionID) }
}

extension UITraitCollection {
    /// Access the inherited inspection actions from a UIKit view or controller.
    public var xray: XRayActions { XRayActions(sessionID: xrayContext.sessionID) }
}

extension View {
    /// Installs screenshot activation and records this SwiftUI root's concrete type name.
    /// Apply this to each independently hosted root that should own an installation.
    @MainActor public func xray(configuration: XRay.Configuration = .init()) -> some View {
        #if DEBUG
        modifier(XRayLabelModifier(name: xrayTypeName(Self.self), label: nil))
            .background(XRayInstaller(configuration: configuration).allowsHitTesting(false).accessibilityHidden(true))
        #else
        self
        #endif
    }

    /// Records this view's inferred type name and live bounds in the installed window.
    /// Apply to a custom view's callsite, such as `ProfileHeader().xrayView()`.
    @MainActor public func xrayView() -> some View {
        xrayView(Self.self)
    }

    /// Records the enclosing view type when used inside its body: `.xrayView(Self.self)`.
    @MainActor public func xrayView<Inspected: View>(_ type: Inspected.Type) -> some View {
        #if DEBUG
        modifier(XRayLabelModifier(name: xrayTypeName(type), label: nil))
        #else
        self
        #endif
    }

    /// Records this view's inferred type name with an optional descriptive caption.
    @MainActor public func xrayLabel(_ label: String) -> some View {
        #if DEBUG
        modifier(XRayLabelModifier(name: xrayTypeName(Self.self), label: label))
        #else
        self
        #endif
    }
}

// Only value IDs cross UIKit/SwiftUI boundaries. Sessions and view references stay on the main actor.
struct XRayContext: Hashable, Sendable {
    var sessionID: UUID?
    var parentID: UUID?
    static let inactive = XRayContext()
}

enum XRayContextKey: UITraitDefinition, UITraitBridgedEnvironmentKey {
    static let defaultValue = XRayContext.inactive
    static let name = "XRay context"
    static func read(from traitCollection: UITraitCollection) -> XRayContext { traitCollection[Self.self] }
    static func write(to mutableTraits: inout any UIMutableTraits, value: XRayContext) {
        mutableTraits[Self.self] = value
    }
}

extension UITraitCollection {
    var xrayContext: XRayContext { self[XRayContextKey.self] }
}

extension UIMutableTraits {
    var xrayContext: XRayContext {
        get { self[XRayContextKey.self] }
        set { self[XRayContextKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var xrayContext: XRayContext {
        get { self[XRayContextKey.self] }
        set { self[XRayContextKey.self] = newValue }
    }
}

#if DEBUG
// ModifiedContent exposes Content as a public generic parameter. Resolve that type
// without evaluating body, reflecting stored values, or inspecting private SwiftUI state.
private protocol XRayModifiedViewType {
    static var xrayContentTypeName: String { get }
}

extension ModifiedContent: XRayModifiedViewType where Content: View, Modifier: ViewModifier {
    nonisolated static var xrayContentTypeName: String { xrayTypeName(Content.self) }
}

private func xrayTypeName<T>(_ type: T.Type) -> String {
    if let modified = type as? any XRayModifiedViewType.Type {
        return modified.xrayContentTypeName
    }
    return String(describing: type)
}

@MainActor
private struct XRayInstaller: UIViewRepresentable {
    let configuration: XRay.Configuration
    func makeUIView(context: Context) -> InstallationView { InstallationView(configuration: configuration) }
    func updateUIView(_ view: InstallationView, context: Context) {
        view.configuration = configuration
        view.synchronize()
    }
    static func dismantleUIView(_ view: InstallationView, coordinator: ()) { view.detach() }

    final class InstallationView: UIView, XRayOwnedView {
        let ownerID = UUID()
        weak var installedWindow: UIWindow?
        var configuration: XRay.Configuration
        init(configuration: XRay.Configuration) {
            self.configuration = configuration
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); synchronize() }
        func synchronize() {
            guard installedWindow !== window else {
                if let window { XRay.updateInstallation(in: window, configuration: configuration) }
                return
            }
            detach()
            guard let window else { return }
            installedWindow = window
            XRay.attachSwiftUIRoot(in: window, owner: ownerID, configuration: configuration)
        }
        func detach() {
            if let installedWindow { XRay.detachSwiftUIRoot(from: installedWindow, owner: ownerID) }
            installedWindow = nil
        }
    }
}

@MainActor
private struct XRayLabelModifier: ViewModifier {
    @Environment(\.xrayContext) private var inherited
    @State private var id = UUID()
    let name: String
    let label: String?

    func body(content: Content) -> some View {
        content
            .environment(\.xrayContext, XRayContext(sessionID: inherited.sessionID, parentID: id))
            .background(XRayLabelLocator(id: id, name: name, label: label, inherited: inherited)
                .allowsHitTesting(false).accessibilityHidden(true))
    }
}

@MainActor
private struct XRayLabelLocator: UIViewRepresentable {
    let id: UUID
    let name: String
    let label: String?
    let inherited: XRayContext
    func makeUIView(context: Context) -> XRaySemanticMarker { XRaySemanticMarker(id: id) }
    func updateUIView(_ view: XRaySemanticMarker, context: Context) {
        view.name = name
        view.label = label
        view.inherited = inherited
        view.synchronize()
    }
    static func dismantleUIView(_ view: XRaySemanticMarker, coordinator: ()) { view.detach() }
}

@MainActor
final class XRaySemanticMarker: UIView, XRayOwnedView {
    let nodeID: UUID
    var name = ""
    var label: String?
    var inherited = XRayContext.inactive
    weak var session: XRay?

    init(id: UUID) {
        nodeID = id
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        registerForTraitChanges([XRayContextKey.self]) { (view: XRaySemanticMarker, _: UITraitCollection) in
            view.synchronize()
        }
    }
    required init?(coder: NSCoder) { nil }
    override func didMoveToWindow() { super.didMoveToWindow(); synchronize() }
    func synchronize() {
        let context = inherited.sessionID == nil ? traitCollection.xrayContext : inherited
        let next = window == nil ? nil : XRay.session(for: context.sessionID)
        if next !== session {
            detach()
            session = next
            next?.semanticMarkers[nodeID] = WeakSemanticMarker(self)
        }
    }
    func detach() {
        session?.semanticMarkers.removeValue(forKey: nodeID)
        session = nil
    }
}

@MainActor
final class WeakSemanticMarker {
    weak var value: XRaySemanticMarker?
    init(_ value: XRaySemanticMarker) { self.value = value }
}

extension XRay {
    func semanticHierarchy(in root: UIView, configuration: Configuration) -> XRayHierarchy {
        semanticMarkers = semanticMarkers.filter { $0.value.value != nil }
        let markers = semanticMarkers.values.compactMap(\.value)
            .filter { $0.isDescendant(of: root) && !$0.isHidden && !$0.name.isEmpty }
        let parents = Dictionary(uniqueKeysWithValues: markers.map { ($0.nodeID, $0.inherited.parentID) })
        let depthLimit = max(0, min(configuration.maximumDepth, 128))
        var truncated = false
        func depth(of marker: XRaySemanticMarker) -> Int {
            var parent = marker.inherited.parentID
            var seen: Set<UUID> = [marker.nodeID]
            var result = 0
            while let id = parent, parents.index(forKey: id) != nil, seen.insert(id).inserted, result < 128 {
                result += 1
                parent = parents[id] ?? nil
            }
            return result
        }
        let nodes = markers.compactMap { marker -> XRayNode? in
            let nodeDepth = depth(of: marker)
            guard nodeDepth <= depthLimit else { truncated = true; return nil }
            let frame = marker.convert(marker.bounds, to: root)
            guard frame.xrayIsFinite, !frame.isEmpty else { return nil }
            var clip = root.bounds
            var ancestor = marker.superview
            while let view = ancestor {
                if view.isHidden || view.alpha <= 0.01 { return nil }
                if view.clipsToBounds { clip = clip.intersection(view.convert(view.bounds, to: root)) }
                if view === root { break }
                ancestor = view.superview
            }
            guard frame.intersects(clip) else { return nil }
            let b = marker.bounds
            let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
                .map { marker.convert($0, to: root) }
            let parentID = marker.inherited.parentID.flatMap { parents.index(forKey: $0) != nil ? $0.uuidString : nil }
            return XRayNode(id: marker.nodeID.uuidString, parentID: parentID,
                name: marker.name, kind: .swiftUI, frame: frame, corners: corners, clipRect: clip,
                depth: nodeDepth, label: marker.label)
        }.sorted { ($0.depth, $0.id) < ($1.depth, $1.id) }
        return XRayHierarchy(nodes: nodes, isTruncated: truncated)
    }
}
#endif
