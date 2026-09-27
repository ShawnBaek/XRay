import SwiftUI
import UIKit

extension View {
    /// Adds XRay controls and an optional offline design comparison to an Xcode preview.
    ///
    /// `xray` sets the initial toggle state. Subsequent changes belong to this preview.
    /// Inject synthetic data into the view before calling this method. Nested custom
    /// SwiftUI types can register themselves with `xrayView()`.
    @MainActor public func preview(
        xray: Bool = false,
        reference: XRayPreviewReference? = nil,
        configuration: XRay.Configuration = .init()
    ) -> some View {
        #if DEBUG
        XRayPreviewSurface(
            content: self.xrayView(Self.self), initiallyVisible: xray,
            reference: reference, configuration: configuration
        )
        #else
        self
        #endif
    }
}

extension UIView {
    /// Previews this view with the same controls offered to SwiftUI and view controllers.
    /// Give each preview its own view instance.
    @MainActor public func preview(
        xray: Bool = false,
        reference: XRayPreviewReference? = nil,
        configuration: XRay.Configuration = .init()
    ) -> some View {
        #if DEBUG
        XRayPreviewSurface(content: XRayUIKitView(view: self).ignoresSafeArea(.container), initiallyVisible: xray,
                           reference: reference, configuration: configuration)
        #else
        XRayUIKitView(view: self)
        #endif
    }
}

extension UIViewController {
    /// Previews this controller with normal representable containment and XRay controls.
    /// Give each preview its own controller instance. Control changes retain that instance.
    @MainActor public func preview(
        xray: Bool = false,
        reference: XRayPreviewReference? = nil,
        configuration: XRay.Configuration = .init()
    ) -> some View {
        #if DEBUG
        XRayPreviewSurface(content: XRayUIKitController(controller: self).ignoresSafeArea(.container), initiallyVisible: xray,
                           reference: reference, configuration: configuration)
        #else
        XRayUIKitController(controller: self)
        #endif
    }
}

@MainActor
private struct XRayUIKitView: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
private struct XRayUIKitController: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#if DEBUG
@MainActor
struct XRayPreviewSurface<Content: View>: View {
    let content: Content
    let reference: XRayPreviewReference?
    let configuration: XRay.Configuration
    @Environment(\.layoutDirection) private var contentLayoutDirection
    @State private var visible: Bool
    @State private var compares = true
    @State private var controlsVisible = true
    @State private var fraction = 0.5
    @State private var loaded: XRayLoadedReference?
    @State private var loadError: String?
    @State private var coordinateSpace = UUID()

    init(
        content: Content, initiallyVisible: Bool,
        reference: XRayPreviewReference?, configuration: XRay.Configuration
    ) {
        self.content = content
        self.reference = reference
        self.configuration = configuration
        _visible = State(initialValue: initiallyVisible)
    }

    private var inspectionToggle: some View {
        Toggle("XRay", isOn: $visible)
            .accessibilityIdentifier("xray.preview.toggle")
    }

    @ViewBuilder private var comparisonToggle: some View {
        if loaded != nil {
            Toggle("Compare", isOn: $compares)
                .accessibilityIdentifier("xray.preview.compare")
        }
    }

    @ViewBuilder private var designLink: some View {
        if let url = loaded?.sourceURL, url.scheme == "https" {
            Link("Design", destination: url)
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 8) {
            if controlsVisible {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            inspectionToggle.fixedSize()
                            comparisonToggle.fixedSize()
                            designLink
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            inspectionToggle
                            comparisonToggle
                            designLink
                        }
                    }
                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("xray.preview.referenceError")
                    }
                }
                .font(.callout)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                controlsVisible.toggle()
            } label: {
                Image(systemName: controlsVisible ? "chevron.up" : "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controlsVisible ? "Hide preview controls" : "Show preview controls")
            .accessibilityIdentifier("xray.preview.controls")
        }
        .padding(8)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                let logicalSize = loaded?.logicalSize ?? geometry.size
                let scale = XRayPreviewGeometry.scale(canvas: logicalSize, available: geometry.size)
                ZStack(alignment: .topLeading) {
                    XRayPreviewHost(
                        content: content, visible: visible, configuration: configuration
                    )
                    .environment(\.layoutDirection, contentLayoutDirection)
                    if let loaded, compares {
                        Image(uiImage: loaded.image)
                            .resizable()
                            .frame(width: logicalSize.width, height: logicalSize.height)
                            .mask {
                                Path(CGRect(x: 0, y: 0, width: logicalSize.width * fraction,
                                            height: logicalSize.height))
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        XRayComparisonDivider(
                            fraction: $fraction, size: logicalSize, coordinateSpace: coordinateSpace
                        )
                    }
                }
                .frame(width: logicalSize.width, height: logicalSize.height)
                .coordinateSpace(name: coordinateSpace)
                .clipped()
                .scaleEffect(scale)
                .frame(width: logicalSize.width * scale, height: logicalSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(white: 0.08))
            .ignoresSafeArea(.container)
            // Comparison measures physical left-to-right coordinates in every locale.
            // The hosted content keeps its own inherited layout direction above.
            .environment(\.layoutDirection, .leftToRight)
            controls
        }
        .task(id: reference?.identity) {
            do {
                loaded = try reference?.load()
                loadError = nil
            } catch {
                loaded = nil
                loadError = error.localizedDescription
            }
        }
    }
}

enum XRayPreviewGeometry {
    static func scale(canvas: CGSize, available: CGSize) -> CGFloat {
        guard canvas.width > 0, canvas.height > 0,
            available.width > 0, available.height > 0
        else { return 1 }
        return min(available.width / canvas.width, available.height / canvas.height)
    }

    static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard x.isFinite, width.isFinite, width > 0 else { return 0.5 }
        return min(1, max(0, Double(x / width)))
    }
}

private struct XRayComparisonDivider: View {
    @Binding var fraction: Double
    let size: CGSize
    let coordinateSpace: UUID

    var body: some View {
        Rectangle()
            .fill(.tint)
            .frame(width: 2, height: size.height)
            .overlay {
                Text("↔")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .frame(width: 44, height: size.height)
            .contentShape(Rectangle())
            .position(x: size.width * fraction, y: size.height / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
                    .onChanged { value in
                        fraction = XRayPreviewGeometry.fraction(x: value.location.x, width: size.width)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Design comparison")
            .accessibilityValue(Text(fraction, format: .percent))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = min(1, fraction + 0.1)
                case .decrement: fraction = max(0, fraction - 0.1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("xray.preview.divider")
    }
}

@MainActor
struct XRayPreviewHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let visible: Bool
    let configuration: XRay.Configuration

    func makeUIViewController(context: Context) -> XRayPreviewHostController<Content> {
        XRayPreviewHostController(
            content: content, environment: context.environment,
            visible: visible, configuration: configuration
        )
    }

    func updateUIViewController(_ controller: XRayPreviewHostController<Content>, context: Context) {
        controller.update(
            content: content, environment: context.environment,
            visible: visible, configuration: configuration
        )
    }

    static func dismantleUIViewController(
        _ controller: XRayPreviewHostController<Content>, coordinator: ()
    ) {
        controller.stopInspection()
    }
}

struct XRayHostedPreviewContent<Content: View>: View {
    let content: Content
    let inherited: EnvironmentValues
    let localContext: XRayContext

    var body: some View {
        content
            .environment(\.xrayContext, localContext)
            .environment(\.self, inherited)
    }
}

@MainActor
final class XRayPreviewHostController<Content: View>: UIViewController {
    private let hosting: UIHostingController<XRayHostedPreviewContent<Content>>
    private(set) var inspection: XRay?

    init(
        content: Content, environment: EnvironmentValues,
        visible: Bool, configuration: XRay.Configuration
    ) {
        hosting = UIHostingController(
            rootView: .init(content: content, inherited: environment, localContext: .inactive)
        )
        super.init(nibName: nil, bundle: nil)
        let session = XRay(view: view, configuration: configuration)
        inspection = session
        view.traitOverrides.xrayContext = XRayContext(sessionID: session.id, parentID: nil)
        update(content: content, environment: environment, visible: visible, configuration: configuration)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) { nil }

    override func loadView() { view = UIView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        inspection?.refresh()
    }

    func update(
        content: Content, environment: EnvironmentValues,
        visible: Bool, configuration: XRay.Configuration
    ) {
        guard let inspection else { return }
        hosting.rootView = .init(
            content: content, inherited: environment,
            localContext: XRayContext(sessionID: inspection.id, parentID: nil)
        )
        inspection.configuration = configuration
        if visible { inspection.show() } else { inspection.hide() }
    }

    func stopInspection() {
        guard let inspection else { return }
        inspection.hide()
        if view.traitCollection.xrayContext.sessionID == inspection.id {
            view.traitOverrides.remove(XRayContextKey.self)
        }
        self.inspection = nil
    }
}
#endif
