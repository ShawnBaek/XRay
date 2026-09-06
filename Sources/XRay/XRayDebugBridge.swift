import UIKit

#if DEBUG
/// The stable Objective-C entry point used by `Tools/xray_lldb.py`.
/// Link XRay by installing it in a Debug build before using LLDB commands.
@objc(XRayDebugBridge)
@MainActor
public final class XRayDebugBridge: NSObject {
    private static var errorMessage = ""

    @objc nonisolated public static func show() -> String {
        guard Thread.isMainThread else { return "XRay requires the main thread." }
        return MainActor.assumeIsolated {
            do { try activeSession().show(); return "XRay shown. Continue execution to display the overlay." }
            catch { errorMessage = error.localizedDescription; return errorMessage }
        }
    }

    @objc nonisolated public static func hide() -> String {
        guard Thread.isMainThread else { return "XRay requires the main thread." }
        return MainActor.assumeIsolated {
            do { try activeSession().hide(); return "XRay hidden. Continue execution to update the screen." }
            catch { errorMessage = error.localizedDescription; return errorMessage }
        }
    }

    @objc nonisolated public static func hierarchyDescription() -> String {
        guard Thread.isMainThread else { return "XRay requires the main thread." }
        return MainActor.assumeIsolated {
            do { return try activeSession().hierarchy().description }
            catch { errorMessage = error.localizedDescription; return errorMessage }
        }
    }

    @objc nonisolated public static func capturePNG() -> NSData? {
        guard Thread.isMainThread else { return nil }
        let data: Data? = MainActor.assumeIsolated {
            do {
                guard let data = try activeSession().capture().image.pngData() else { throw XRayError.renderingFailed }
                errorMessage = ""
                return data
            } catch { errorMessage = error.localizedDescription; return nil }
        }
        return data.map { $0 as NSData }
    }

    @objc nonisolated public static func lastError() -> String {
        guard Thread.isMainThread else { return "XRay requires the main thread." }
        return MainActor.assumeIsolated { errorMessage }
    }

    private static func activeSession() throws -> XRay {
        #if DEBUG
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter { $0.isKeyWindow && !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil }
        guard windows.count == 1, let window = windows.first else { throw XRayError.ambiguousWindow }
        if let session = XRay.session(for: window.traitCollection.xrayContext.sessionID) { return session }
        return XRay.install(in: window)
        #else
        throw XRayError.disabled
        #endif
    }
}
#endif
