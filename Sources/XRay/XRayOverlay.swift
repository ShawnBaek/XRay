import UIKit

#if DEBUG
@MainActor
final class XRayOverlay: UIView, XRayOwnedView {
    var hierarchy = XRayHierarchy(nodes: [], isTruncated: false)
    var showsLabels = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        Self.draw(hierarchy, in: context, bounds: bounds, showsLabels: showsLabels, labelInsets: safeAreaInsets)
    }

    struct Caption {
        let text: String
        let frame: CGRect
        let font: UIFont
        let kind: XRayNode.Kind
        let clip: CGRect
    }

    private static func color(for kind: XRayNode.Kind) -> UIColor {
        switch kind {
        case .viewController: .systemRed
        case .swiftUI: .systemPurple
        case .view: .systemBlue
        }
    }

    static func draw(_ hierarchy: XRayHierarchy, in context: CGContext, bounds: CGRect,
                     showsLabels: Bool, labelInsets: UIEdgeInsets = .zero) {
        // Draw every outline first, so later outlines cannot strike through captions.
        for node in hierarchy.nodes {
            context.saveGState()
            context.clip(to: node.clipRect.intersection(bounds))
            context.setStrokeColor(color(for: node.kind).cgColor)
            context.setLineWidth(1)
            if let first = node.corners.first {
                context.beginPath()
                context.move(to: first)
                node.corners.dropFirst().forEach { context.addLine(to: $0) }
                context.closePath()
                context.strokePath()
            }
            context.restoreGState()
        }
        guard showsLabels else { return }
        for caption in captions(for: hierarchy, bounds: bounds.inset(by: labelInsets)) {
            context.saveGState()
            context.clip(to: caption.clip)
            color(for: caption.kind).setFill()
            UIBezierPath(roundedRect: caption.frame, cornerRadius: 3).fill()
            (caption.text as NSString).draw(
                with: caption.frame.insetBy(dx: 4, dy: 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes(font: caption.font), context: nil
            )
            context.restoreGState()
        }
    }

    private static func attributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        return [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
    }

    static func captions(for hierarchy: XRayHierarchy, bounds: CGRect) -> [Caption] {
        // Semantic names and controller owners take priority over backing UIKit views.
        // Preserve traversal order within a priority for stable layout between frames.
        func priority(_ node: XRayNode) -> Int {
            switch node.kind {
            case .swiftUI: 0
            case .viewController: 1
            case .view: 2
            }
        }
        let candidates = hierarchy.nodes.enumerated().filter { _, node in
            let name = node.viewControllerName ?? node.name
            let implementationPrefixes = ["UIHostingController<", "_UIHosting", "UIHostingView<",
                                          "XRayPreviewHostController<", "UIKitPlatformViewHost<"]
            return !implementationPrefixes.contains(where: { name.hasPrefix($0) })
        }.sorted {
            let lhs = priority($0.element), rhs = priority($1.element)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }
        var result: [Caption] = []
        // Bound collision work independently of the hierarchy traversal limit.
        for (_, node) in candidates.prefix(256) {
            let clip = node.clipRect.intersection(bounds)
            let visible = node.frame.intersection(clip)
            guard !visible.isNull, !visible.isEmpty, clip.width > 16 else { continue }
            let text = (node.viewControllerName ?? node.name) + (node.label.map { " — \($0)" } ?? "")
            let string = text as NSString
            let regularFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            let naturalWidth = string.size(withAttributes: attributes(font: regularFont)).width
            let available = clip.width - 8
            let font = UIFont.monospacedSystemFont(
                ofSize: max(8, min(10, 10 * available / max(1, naturalWidth))), weight: .medium
            )
            let measured = string.boundingRect(
                with: CGSize(width: available, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes(font: font), context: nil
            )
            let size = CGSize(width: min(clip.width, ceil(measured.width) + 8),
                              height: ceil(measured.height) + 4)
            guard size.height <= clip.height else { continue }
            let x = min(max(visible.minX, clip.minX), clip.maxX - size.width)
            var box = CGRect(origin: CGPoint(x: x, y: visible.minY), size: size)
            // Keep the caption attached to the visible element. If it cannot fit
            // without covering another caption, leave its outline and hierarchy intact.
            let bottom = min(clip.maxY, max(visible.maxY, visible.minY + size.height))
            for _ in 0..<32 {
                let collisions = result.filter { $0.frame.insetBy(dx: -1, dy: -1).intersects(box) }
                guard let nextY = collisions.map({ $0.frame.maxY + 2 }).max() else { break }
                box.origin.y = nextY
            }
            guard box.maxY <= bottom,
                  !result.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).intersects(box) })
            else { continue }
            result.append(Caption(text: text, frame: box, font: font, kind: node.kind, clip: clip))
            if result.count == 128 { break }
        }
        return result
    }
}

@MainActor
final class XRayDisplayLinkTarget: NSObject {
    weak var session: XRay?
    init(session: XRay) { self.session = session }
    @objc func update(_ link: CADisplayLink) {
        guard let session else { link.invalidate(); return }
        session.refresh()
    }
}
#endif
