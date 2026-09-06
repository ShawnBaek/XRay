import UIKit

/// A visible UIKit view or an instrumented SwiftUI view.
public struct XRayNode: Identifiable, Sendable {
    /// The kind of element represented by this node.
    public enum Kind: String, Sendable { case view, viewController, swiftUI }

    /// An identifier valid for the lifetime of the inspected element.
    public let id: String
    /// The nearest included ancestor, if there is one.
    public let parentID: String?
    /// The actual UIView class or the SwiftUI type captured by an inspection modifier.
    public let name: String
    /// An optional developer-supplied caption, separate from the type name.
    public let label: String?
    /// The controller that owns this root UIView, when present.
    public let viewControllerName: String?
    /// The element's framework role.
    public let kind: Kind
    /// The bounding rectangle in the inspected root's coordinate space.
    public let frame: CGRect
    /// The transformed corners in the inspected root's coordinate space.
    public let corners: [CGPoint]
    /// The visible rectangular clipping region inherited from ancestors.
    public let clipRect: CGRect
    /// The depth within the inspected hierarchy.
    public let depth: Int

    init(id: String, parentID: String?, name: String, kind: Kind, frame: CGRect,
         corners: [CGPoint], clipRect: CGRect, depth: Int, label: String? = nil,
         viewControllerName: String? = nil) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.kind = kind
        self.frame = frame
        self.corners = corners
        self.clipRect = clipRect
        self.depth = depth
        self.label = label
        self.viewControllerName = viewControllerName
    }
}

/// An immutable description of the visible hierarchy.
public struct XRayHierarchy: Sendable, CustomStringConvertible {
    /// Nodes in deterministic parent-before-child traversal order.
    public let nodes: [XRayNode]
    /// Whether a traversal limit prevented inspecting additional elements.
    public let isTruncated: Bool

    /// A readable hierarchy suitable for logging or LLDB.
    public var description: String {
        let lines = nodes.map { node in
            let frame = node.frame
            let caption = node.label.map { " — \($0)" } ?? ""
            let owner = node.viewControllerName.map { " (controller: \($0))" } ?? ""
            return String(repeating: "  ", count: min(node.depth, 64))
                + "\(node.name)\(caption) [\(node.kind.rawValue)]\(owner) "
                + "(\(frame.minX.rounded()), \(frame.minY.rounded()), \(frame.width.rounded()), \(frame.height.rounded()))"
        }
        return (lines + (isTruncated ? ["… inspection limit reached"] : [])).joined(separator: "\n")
    }
}

/// An annotated image and the hierarchy used to draw it.
@MainActor
public struct XRaySnapshot {
    /// The captured image, including XRay annotations.
    public let image: UIImage
    /// The immutable hierarchy represented in the image.
    public let hierarchy: XRayHierarchy
}

/// Errors that can prevent an explicit capture or hierarchy query.
public enum XRayError: Error, LocalizedError {
    case disabled
    case targetUnavailable
    case invalidBounds
    case renderingFailed
    case ambiguousWindow

    public var errorDescription: String? {
        switch self {
        case .disabled: "XRay is disabled in Release builds. Run a Debug build."
        case .targetUnavailable: "The inspected view is no longer available."
        case .invalidBounds: "The view must have finite, nonempty bounds within the capture limit."
        case .renderingFailed: "UIKit could not capture this view at the current execution point."
        case .ambiguousWindow: "Choose a window explicitly; XRay requires exactly one active content window."
        }
    }
}

#if DEBUG
@MainActor
protocol XRayOwnedView: AnyObject {}

extension CGRect {
    var xrayIsFinite: Bool {
        [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite)
    }
}

@MainActor
enum XRayTraversal {
    static func collect(root: UIView, configuration: XRay.Configuration) -> XRayHierarchy {
        struct Entry {
            let view: UIView
            let parentID: String?
            let depth: Int
            let clip: CGRect
        }
        var stack = [Entry(view: root, parentID: nil, depth: 0, clip: root.bounds)]
        var nodes: [XRayNode] = []
        var visited = 0
        var truncated = false
        let limit = max(1, min(configuration.maximumViews, 10_000))
        let depthLimit = max(0, min(configuration.maximumDepth, 128))
        while let entry = stack.popLast() {
            let view = entry.view
            guard !(view is any XRayOwnedView), !view.isHidden, view.alpha > 0.01 else { continue }
            guard visited < limit else { truncated = true; break }
            visited += 1
            let frame = view.convert(view.bounds, to: root)
            guard frame.xrayIsFinite else { continue }
            let clip = entry.clip.intersection(frame)
            let visible = !clip.isNull && !clip.isEmpty
            // A nonclipping parent may be empty or offscreen while its children are visible.
            if !visible && view.clipsToBounds { continue }
            let controller = (view.next as? UIViewController).flatMap { $0.viewIfLoaded === view ? $0 : nil }
            let name = String(describing: type(of: view))
            let bundleID = Bundle(for: type(of: view)).bundleIdentifier ?? ""
            let included = visible && (configuration.filter == .all || !bundleID.hasPrefix("com.apple."))
            let id = String(describing: ObjectIdentifier(view))
            if included {
                let b = view.bounds
                let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                               CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
                    .map { view.convert($0, to: root) }
                nodes.append(XRayNode(id: id, parentID: entry.parentID, name: name,
                    kind: controller == nil ? .view : .viewController, frame: frame, corners: corners,
                    clipRect: entry.clip, depth: entry.depth,
                    viewControllerName: controller.map { String(describing: type(of: $0)) }))
            }
            // Do not retain/enqueue an unbounded number of children of a very wide view.
            let children = view.subviews.filter { !($0 is any XRayOwnedView) }
            if entry.depth >= depthLimit {
                truncated = truncated || !children.isEmpty
                continue
            }
            let capacity = max(0, limit - visited - stack.count)
            if children.count > capacity { truncated = true }
            let childClip = view.clipsToBounds ? clip : entry.clip
            for child in children.prefix(capacity).reversed() {
                stack.append(Entry(view: child, parentID: included ? id : entry.parentID,
                                   depth: entry.depth + 1, clip: childClip))
            }
        }
        return XRayHierarchy(nodes: nodes, isTruncated: truncated)
    }
}
#endif
