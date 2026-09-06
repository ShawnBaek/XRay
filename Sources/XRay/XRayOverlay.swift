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
        Self.draw(hierarchy, in: context, bounds: bounds, showsLabels: showsLabels)
    }

    static func draw(_ hierarchy: XRayHierarchy, in context: CGContext, bounds: CGRect, showsLabels: Bool) {
        for node in hierarchy.nodes {
            let color: UIColor = switch node.kind {
            case .viewController: .systemRed
            case .swiftUI: .systemPurple
            case .view: .systemBlue
            }
            context.saveGState()
            context.clip(to: node.clipRect.intersection(bounds))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1)
            if let first = node.corners.first {
                context.beginPath()
                context.move(to: first)
                node.corners.dropFirst().forEach { context.addLine(to: $0) }
                context.closePath()
                context.strokePath()
            }
            if showsLabels {
                let caption = node.label.map { " — \($0)" } ?? ""
                let text = (node.name + caption) as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: UIColor.white,
                ]
                let visible = node.frame.intersection(node.clipRect).intersection(bounds)
                let size = text.size(withAttributes: attributes)
                let width = min(size.width + 8, min(240, visible.width))
                if width > 8, visible.height > 12 {
                    let box = CGRect(x: visible.minX, y: visible.minY, width: width, height: 16)
                    color.setFill()
                    UIBezierPath(roundedRect: box, cornerRadius: 3).fill()
                    text.draw(in: box.insetBy(dx: 4, dy: 1), withAttributes: attributes)
                }
            }
            context.restoreGState()
        }
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
