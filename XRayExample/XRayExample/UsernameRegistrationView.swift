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
                        .xrayLabel("Username field")
                }
                Section("Inspect this screen") {
                    InspectionControls()
                }
                Section {
                    Text("These controls find XRay through the environment, across UIKit and SwiftUI. No session is passed through view initializers.")
                        .foregroundStyle(.secondary)
                }
            }
            .xrayLabel("Profile form")
            .navigationTitle("SwiftUI example")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("swiftui.done")
                }
            }
        }
        .xrayLabel("Profile screen")
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
        .xrayLabel("Inspection controls")
        .sheet(isPresented: $showingCapture) {
            if let snapshot { SnapshotPreview(snapshot: snapshot) }
        }
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
                Text("\(snapshot.hierarchy.nodes.count) views · \(semanticCount) SwiftUI labels")
                    .font(.footnote)
                    .accessibilityIdentifier("capture.summary")
                    .accessibilityValue("\(semanticCount)")
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

    private var semanticCount: Int { snapshot.hierarchy.nodes.filter { $0.kind == .swiftUI }.count }
}

#Preview("Profile") { UsernameRegistrationView().xray() }
#Preview("Dark, large text") {
    UsernameRegistrationView().xray().preferredColorScheme(.dark).dynamicTypeSize(.accessibility2)
}
