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
        let introduction = label("Inspect UIKit and SwiftUI in the same window. Take a screenshot to show annotations for five seconds.", style: .body)
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
        if ProcessInfo.processInfo.arguments.contains("-xray-ui-testing") {
            stack.addArrangedSubview(button("Simulate screenshot", id: "uikit.screenshot", action: #selector(simulateScreenshot)))
        }
        #endif
    }

    @IBAction func presentUsernameRegistration(_ sender: Any) {
        present(UIHostingController(rootView: UsernameRegistrationView()), animated: true)
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
