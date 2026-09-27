import SwiftUI
import UIKit
import XRay

final class XRayRootViewController: UIViewController {
    // This button and its action are connected in Main.storyboard.
    @IBOutlet private(set) var swiftUIButton: UIButton!
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let title = label("XRay", style: .largeTitle)
        let introduction = label("See UIKit class names and SwiftUI view types. Take a screenshot to show annotations for five seconds.", style: .body)
        introduction.textColor = .secondaryLabel
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "uikit.status"
        statusLabel.text = "Ready to inspect"

        swiftUIButton.configuration = .filled()
        swiftUIButton.configuration?.title = "Open SwiftUI example"
        swiftUIButton.accessibilityIdentifier = "uikit.openSwiftUI"
        swiftUIButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [title, introduction,
            button("Show annotations", id: "uikit.show", action: #selector(showAnnotations)),
            button("Hide annotations", id: "uikit.hide", action: #selector(hideAnnotations)),
            button("Capture annotated image", id: "uikit.capture", action: #selector(captureImage)),
            swiftUIButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        #if DEBUG
        stack.addArrangedSubview(button("Open preview comparison", id: "uikit.openPreview", action: #selector(presentPreview)))
        if ProcessInfo.processInfo.arguments.contains("-xray-ui-testing") {
            stack.addArrangedSubview(button("Simulate screenshot", id: "uikit.screenshot", action: #selector(simulateScreenshot)))
        }
        #endif
    }

    @IBAction func presentUsernameRegistration(_ sender: Any) {
        present(UIHostingController(rootView: UsernameRegistrationView().xrayView()), animated: true)
    }

    @objc private func showAnnotations() {
        traitCollection.xray.show()
        statusLabel.text = "Annotations shown"
    }

    @objc private func hideAnnotations() {
        traitCollection.xray.hide()
        statusLabel.text = "Annotations hidden"
    }

    @objc private func captureImage() {
        do {
            let snapshot = try traitCollection.xray.capture()
            traitCollection.xray.hide()
            present(UIHostingController(rootView: SnapshotPreview(snapshot: snapshot)), animated: true)
            statusLabel.text = "Capture complete"
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    #if DEBUG
    @objc private func presentPreview() {
        let direction: LayoutDirection = ProcessInfo.processInfo.arguments.contains("-xray-preview-rtl") ? .rightToLeft : .leftToRight
        let preview = PreviewExampleFixture()
            .preview(xray: true, reference: .image(PreviewExampleFixture.reference, logicalSize: CGSize(width: 320, height: 480)))
            .environment(\.layoutDirection, direction)
        present(UIHostingController(rootView: preview), animated: true)
    }

    @objc private func simulateScreenshot() {
        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        statusLabel.text = "Screenshot notification sent"
    }
    #endif

    private func button(_ title: String, id: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.accessibilityIdentifier = id
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func label(_ title: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
}

#if DEBUG
private struct PreviewExampleFixture: View {
    @State private var note = "Synthetic note"
    @State private var count = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Preview fixture").font(.title)
            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("preview.note")
            Button("Count: \(count)") { count += 1 }
                .accessibilityIdentifier("preview.counter")
            Spacer()
        }
        .padding()
        .background(.background)
    }

    // A synthetic reference keeps the public example independent of private designs.
    static var reference: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 480)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
            NSString(string: "Sample reference").draw(
                at: CGPoint(x: 20, y: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white]
            )
        }
    }
}
#endif
