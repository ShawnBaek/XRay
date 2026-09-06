import SwiftUI
import XRay

struct UsernameRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = "Taylor"

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("swiftui.username")
                        .xrayView()
                }
                Section("Inspect this screen") {
                    InspectionControls()
                }
                Section {
                    Text("XRay shows UIKit class names and registered SwiftUI view types. These controls inherit XRay through the environment.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("SwiftUI example")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("swiftui.done")
                }
            }
        }
    }
}

// Deliberately nested inside a Form and NavigationStack to demonstrate trait/environment bridging.
private struct InspectionControls: View {
    @Environment(\.xray) private var xray
    @State private var snapshot: XRaySnapshot?
    @State private var showingCapture = false
    @State private var status = "Ready to inspect"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Show annotations") {
                xray.show()
                status = "Annotations shown"
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("swiftui.show")
            Button("Hide annotations") {
                xray.hide()
                status = "Annotations hidden"
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("swiftui.hide")
            Button("Capture annotated image") { capture() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("swiftui.capture")
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("swiftui.status")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-xray-ui-testing") {
                Button("Simulate screenshot") {
                    NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
                    status = "Screenshot notification sent"
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("swiftui.screenshot")
            }
            #endif
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingCapture) {
            if let snapshot { SnapshotPreview(snapshot: snapshot) }
        }
        .xrayView(Self.self)
    }

    private func capture() {
        do {
            snapshot = try xray.capture()
            xray.hide()
            showingCapture = true
            status = "Capture complete"
        } catch {
            status = error.localizedDescription
        }
    }
}

struct SnapshotPreview: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: XRaySnapshot

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: snapshot.image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Captured screen with XRay annotations")
                Text("\(snapshot.hierarchy.nodes.count) views · \(swiftUITypeNames.count) SwiftUI view types")
                    .font(.footnote)
                    .accessibilityIdentifier("capture.summary")
                    .accessibilityValue("\(swiftUITypeNames.count)")
                if !swiftUITypeNames.isEmpty {
                    Text(swiftUITypeNames.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("capture.swiftUITypes")
                }
            }
            .padding()
            .navigationTitle("XRay capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("capture.done")
                }
            }
        }
    }

    private var swiftUITypeNames: [String] {
        Array(Set(snapshot.hierarchy.nodes.filter { $0.kind == .swiftUI }.map(\.name))).sorted()
    }
}

#Preview("Profile") { UsernameRegistrationView().xray() }
#Preview("Dark, large text") {
    UsernameRegistrationView().xray().preferredColorScheme(.dark).dynamicTypeSize(.accessibility2)
}
