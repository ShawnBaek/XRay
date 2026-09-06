import UIKit

/// A visual inspection session scoped to one view or window.
///
/// Use `install(in:configuration:)` once per window for screenshot activation.
/// All UI work is confined to the main actor. Release builds remain inactive.
@MainActor
public final class XRay: NSObject {
    /// Selects which UIKit classes appear; semantic SwiftUI labels are always included.
    public enum Filter: Sendable { case all, application }

    /// Options shared by UIKit and SwiftUI inspection.
    public struct Configuration: Sendable, Equatable {
        public var filter: Filter
        public var showsLabels: Bool
        public var maximumViews: Int
        public var maximumDepth: Int
        /// Seconds to display after a screenshot. A nonpositive value keeps it visible until hidden.
        public var screenshotDuration: TimeInterval

        public init(filter: Filter = .all, showsLabels: Bool = true, maximumViews: Int = 2_000,
                    maximumDepth: Int = 64, screenshotDuration: TimeInterval = 5) {
            self.filter = filter
            self.showsLabels = showsLabels
            self.maximumViews = maximumViews
            self.maximumDepth = maximumDepth
            self.screenshotDuration = screenshotDuration
        }
    }

    /// Configuration applied by subsequent refreshes and captures.
    public var configuration: Configuration
    private weak var rootView: UIView?
    let id = UUID()

    #if DEBUG
    private var overlay: XRayOverlay?
    private var displayLink: CADisplayLink?
    private var hideTask: Task<Void, Never>?
    private static var installationKey: UInt8 = 0
    private static var sessions: [UUID: WeakSession] = [:]
    var semanticMarkers: [UUID: WeakSemanticMarker] = [:]
    private var swiftUIOwners: Set<UUID> = []
    private var manuallyInstalled = false
    #endif

    /// Creates a manually owned session. The view is weakly held.
    public init(view: UIView, configuration: Configuration = .init()) {
        rootView = view
        self.configuration = configuration
        super.init()
        #if DEBUG
        Self.sessions = Self.sessions.filter { $0.value.value != nil }
        Self.sessions[id] = WeakSession(self)
        #endif
    }

    /// Creates a manually owned session for a controller's loaded view.
    public convenience init(rootViewController: UIViewController, configuration: Configuration = .init()) {
        self.init(view: rootViewController.view, configuration: configuration)
    }

    deinit {
        #if DEBUG
        hideTask?.cancel()
        let oldOverlay = overlay
        Task { @MainActor in
            oldOverlay?.removeFromSuperview()
        }
        #endif
    }

    /// Installs screenshot activation once in this window and returns its retained session.
    /// Calling this again updates configuration and returns the same session.
    @discardableResult
    public static func install(in window: UIWindow, configuration: Configuration = .init()) -> XRay {
        #if DEBUG
        let session = obtainInstallation(in: window, configuration: configuration)
        session.manuallyInstalled = true
        return session
        #else
        return XRay(view: window, configuration: configuration)
        #endif
    }

    #if DEBUG
    private static func obtainInstallation(in window: UIWindow, configuration: Configuration) -> XRay {
        if let existing = objc_getAssociatedObject(window, &installationKey) as? XRay {
            existing.configuration = configuration
            return existing
        }
        // Reference the bridge from a live entry point so LLDB can discover it in Debug builds.
        _ = XRayDebugBridge.self
        let session = XRay(view: window, configuration: configuration)
        objc_setAssociatedObject(window, &installationKey, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.traitOverrides.xrayContext = XRayContext(sessionID: session.id, parentID: nil)
        NotificationCenter.default.addObserver(session, selector: #selector(screenshotTaken),
            name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        return session
    }

    static func attachSwiftUIRoot(in window: UIWindow, owner: UUID, configuration: Configuration) {
        obtainInstallation(in: window, configuration: configuration).swiftUIOwners.insert(owner)
    }

    static func updateInstallation(in window: UIWindow, configuration: Configuration) {
        session(for: window.traitCollection.xrayContext.sessionID)?.configuration = configuration
    }

    static func detachSwiftUIRoot(from window: UIWindow, owner: UUID) {
        guard let session = session(for: window.traitCollection.xrayContext.sessionID) else { return }
        session.swiftUIOwners.remove(owner)
        if session.swiftUIOwners.isEmpty && !session.manuallyInstalled { uninstall(from: window) }
    }
    #endif

    /// Removes this window's installation and all of its owned annotations.
    public static func uninstall(from window: UIWindow) {
        #if DEBUG
        guard let session = objc_getAssociatedObject(window, &installationKey) as? XRay else { return }
        session.hide()
        NotificationCenter.default.removeObserver(session)
        if window.traitCollection.xrayContext.sessionID == session.id {
            window.traitOverrides.remove(XRayContextKey.self)
        }
        objc_setAssociatedObject(window, &installationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #endif
    }

    /// Whether the live annotation overlay is attached.
    public var isVisible: Bool {
        #if DEBUG
        overlay?.superview != nil
        #else
        false
        #endif
    }

    /// Shows annotations until hidden, refreshing their geometry while visible.
    public func show() {
        #if DEBUG
        hideTask?.cancel()
        hideTask = nil
        guard let rootView else { hide(); return }
        if overlay == nil {
            let newOverlay = XRayOverlay(frame: rootView.bounds)
            overlay = newOverlay
            rootView.addSubview(newOverlay)
        }
        refresh()
        if displayLink == nil {
            let link = CADisplayLink(target: XRayDisplayLinkTarget(session: self), selector: #selector(XRayDisplayLinkTarget.update(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        #endif
    }

    /// Hides annotations. Repeated calls and a deallocated target are safe.
    public func hide() {
        #if DEBUG
        hideTask?.cancel()
        hideTask = nil
        displayLink?.invalidate()
        displayLink = nil
        overlay?.removeFromSuperview()
        overlay = nil
        #endif
    }

    /// Updates an already visible overlay after layout or configuration changes.
    public func refresh() {
        #if DEBUG
        guard let rootView else { hide(); return }
        guard let overlay, let hierarchy = try? hierarchy() else { return }
        overlay.frame = rootView.bounds
        overlay.bounds = rootView.bounds
        overlay.hierarchy = hierarchy
        overlay.showsLabels = configuration.showsLabels
        rootView.bringSubviewToFront(overlay)
        overlay.setNeedsDisplay()
        #endif
    }

    /// Returns visible UIKit nodes and registered SwiftUI semantic nodes without showing an overlay.
    public func hierarchy() throws -> XRayHierarchy {
        #if DEBUG
        guard let rootView else { throw XRayError.targetUnavailable }
        let native = XRayTraversal.collect(root: rootView, configuration: configuration)
        let markerSession = Self.session(for: rootView.traitCollection.xrayContext.sessionID) ?? self
        let semantic = markerSession.semanticHierarchy(in: rootView, configuration: configuration)
        let maximum = max(1, min(configuration.maximumViews, 10_000))
        let nodes = Array((native.nodes + semantic.nodes).prefix(maximum))
        return XRayHierarchy(nodes: nodes, isTruncated: native.isTruncated || semantic.isTruncated
            || native.nodes.count + semantic.nodes.count > maximum)
        #else
        throw XRayError.disabled
        #endif
    }

    /// Captures an annotated image without changing the overlay's visible state.
    /// GPU-backed or protected content may not be included by UIKit's snapshot APIs.
    public func capture() throws -> XRaySnapshot {
        #if DEBUG
        guard let rootView else { throw XRayError.targetUnavailable }
        let bounds = rootView.bounds
        let scale = rootView.window?.screen.scale ?? (rootView as? UIWindow)?.screen.scale ?? 2
        let pixelWidth = ceil(bounds.width * scale)
        let pixelHeight = ceil(bounds.height * scale)
        guard bounds.xrayIsFinite, bounds.width > 0, bounds.height > 0,
              (1...16_384).contains(pixelWidth), (1...16_384).contains(pixelHeight),
              pixelWidth * pixelHeight <= 16_000_000 else { throw XRayError.invalidBounds }
        let snapshot = try hierarchy()
        let wasHidden = overlay?.isHidden
        overlay?.isHidden = true
        defer { if let wasHidden { overlay?.isHidden = wasHidden } }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .standard
        var rendered = false
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            rendered = rootView.drawHierarchy(in: bounds, afterScreenUpdates: false)
            XRayOverlay.draw(snapshot, in: context.cgContext, bounds: bounds, showsLabels: configuration.showsLabels)
        }
        guard rendered else { throw XRayError.renderingFailed }
        return XRaySnapshot(image: image, hierarchy: snapshot)
        #else
        throw XRayError.disabled
        #endif
    }

    #if DEBUG
    @objc private func screenshotTaken() {
        guard let window = rootView as? UIWindow, !window.isHidden,
              window.windowScene?.activationState == .foregroundActive else { return }
        showAfterScreenshot()
    }

    func showAfterScreenshot() {
        show()
        let seconds = configuration.screenshotDuration
        guard seconds.isFinite, seconds > 0 else { return }
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(min(seconds, 86_400))) }
            catch { return }
            self?.hide()
        }
    }

    static func session(for id: UUID?) -> XRay? { id.flatMap { sessions[$0]?.value } }

    private final class WeakSession {
        weak var value: XRay?
        init(_ value: XRay) { self.value = value }
    }
    #endif
}

extension XRay {
    /// Compatibility with XRay 1.x. Prefer `Configuration.filter`.
    @available(*, deprecated, message: "Use XRay.Configuration.filter.")
    public enum ClassNameOption { case all, customClass }

    @available(*, deprecated, message: "Use show(); capture() now returns an annotated image.")
    public func captureXray(classNameOption: ClassNameOption) {
        configuration.filter = classNameOption == .all ? .all : .application
        show()
    }

    @available(*, deprecated, message: "Set configuration.filter, then call refresh().")
    public func refresh(classNameOption: ClassNameOption) {
        configuration.filter = classNameOption == .all ? .all : .application
        show()
    }

    @available(*, deprecated, renamed: "hide()")
    public func removeXray() { hide() }
}
